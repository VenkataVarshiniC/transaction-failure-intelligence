"""Build deterministic held-out forecast validation and six monthly projections.

The 90-day synthetic history is split chronologically: the last 14 days are
held out. A weekday seasonal-naive baseline is compared with a linear trend
plus weekday-effects model. The lower-MAE model is selected independently for
transaction, failure, and recovery volume, then refit on all history.

Forecast accuracy is evidence about this synthetic holdout only. It is not a
claim of real-bank forecasting performance.
"""

from __future__ import annotations

from pathlib import Path

import numpy as np
import pandas as pd


PROJECT_ROOT = Path(__file__).resolve().parents[1]
DATA_DIR = PROJECT_ROOT / "data" / "clean"
CONFIG_DIR = PROJECT_ROOT / "config"
OUT_DIR = PROJECT_ROOT / "data" / "reporting"
HOLDOUT_DAYS = 14
FORECAST_MONTHS = 6


def design_matrix(dates: pd.DatetimeIndex, origin: pd.Timestamp) -> np.ndarray:
    day_number = (dates - origin).days.to_numpy(dtype=float)
    weekday = dates.day_of_week.to_numpy()
    weekday_dummies = np.column_stack([(weekday == i).astype(float) for i in range(1, 7)])
    return np.column_stack([np.ones(len(dates)), day_number, weekday_dummies])


def predict_seasonal(train: pd.Series, dates: pd.DatetimeIndex) -> np.ndarray:
    weekday_means = train.groupby(train.index.day_of_week).mean()
    fallback = float(train.mean())
    return np.array([weekday_means.get(day.day_of_week, fallback) for day in dates], dtype=float)


def predict_trend_weekday(train: pd.Series, dates: pd.DatetimeIndex) -> np.ndarray:
    origin = train.index.min()
    x_train = design_matrix(train.index, origin)
    coefficients = np.linalg.lstsq(x_train, train.to_numpy(dtype=float), rcond=None)[0]
    return design_matrix(dates, origin) @ coefficients


def score(actual: np.ndarray, predicted: np.ndarray) -> tuple[float, float, float]:
    predicted = np.clip(predicted, 0, None)
    error = actual - predicted
    mae = float(np.mean(np.abs(error)))
    rmse = float(np.sqrt(np.mean(error**2)))
    nonzero = actual != 0
    mape = float(np.mean(np.abs(error[nonzero] / actual[nonzero])) * 100) if nonzero.any() else np.nan
    return mae, rmse, mape


def assumption_map() -> dict[str, float]:
    assumptions = pd.read_csv(CONFIG_DIR / "financial_assumptions.csv")
    return dict(zip(assumptions["assumption_id"], assumptions["value"].astype(float)))


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    transactions = pd.read_csv(DATA_DIR / "transactions.csv", parse_dates=["initiated_at"])
    recoveries = pd.read_csv(DATA_DIR / "recovery_attempts.csv")

    transactions["date"] = transactions["initiated_at"].dt.normalize()
    transactions["failure_volume"] = (transactions["final_status"] != "success").astype(int)
    transactions["recovery_volume"] = (transactions["final_status"] == "recovered_success").astype(int)
    daily = transactions.groupby("date").agg(
        transaction_volume=("transaction_id", "count"),
        failure_volume=("failure_volume", "sum"),
        recovery_volume=("recovery_volume", "sum"),
    )
    full_index = pd.date_range(daily.index.min(), daily.index.max(), freq="D")
    daily = daily.reindex(full_index, fill_value=0)
    daily.index.name = "date"

    train = daily.iloc[:-HOLDOUT_DAYS]
    holdout = daily.iloc[-HOLDOUT_DAYS:]
    validation_rows: list[dict[str, object]] = []
    selected_models: dict[str, str] = {}

    for target in daily.columns:
        candidates = {
            "weekday_seasonal_naive": predict_seasonal(train[target], holdout.index),
            "linear_trend_weekday": predict_trend_weekday(train[target], holdout.index),
        }
        scored: list[tuple[str, float]] = []
        for model_name, raw_prediction in candidates.items():
            prediction = np.clip(raw_prediction, 0, None)
            mae, rmse, mape = score(holdout[target].to_numpy(dtype=float), prediction)
            scored.append((model_name, mae))
            validation_rows.append(
                {
                    "target": target,
                    "model": model_name,
                    "train_start": train.index.min().date(),
                    "train_end": train.index.max().date(),
                    "holdout_start": holdout.index.min().date(),
                    "holdout_end": holdout.index.max().date(),
                    "holdout_days": HOLDOUT_DAYS,
                    "mae": round(mae, 4),
                    "rmse": round(rmse, 4),
                    "mape_pct": round(mape, 4),
                    "selected": False,
                    "evidence_scope": "synthetic_14_day_holdout",
                }
            )
        selected_models[target] = min(scored, key=lambda item: (item[1], item[0]))[0]

    validation = pd.DataFrame(validation_rows)
    for target, model_name in selected_models.items():
        validation.loc[(validation["target"] == target) & (validation["model"] == model_name), "selected"] = True
    validation.to_csv(OUT_DIR / "forecast_validation.csv", index=False)

    last_observed = daily.index.max()
    forecast_start = last_observed + pd.offsets.MonthBegin(1)
    forecast_end = forecast_start + pd.offsets.MonthEnd(FORECAST_MONTHS)
    future_dates = pd.date_range(forecast_start, forecast_end, freq="D")
    daily_forecast = pd.DataFrame(index=future_dates)

    for target in daily.columns:
        model_name = selected_models[target]
        if model_name == "weekday_seasonal_naive":
            values = predict_seasonal(daily[target], future_dates)
        else:
            values = predict_trend_weekday(daily[target], future_dates)
        daily_forecast[target] = np.clip(values, 0, None)

    daily_forecast["failure_volume"] = np.minimum(
        daily_forecast["failure_volume"], daily_forecast["transaction_volume"]
    )
    daily_forecast["recovery_volume"] = np.minimum(
        daily_forecast["recovery_volume"], daily_forecast["failure_volume"]
    )
    monthly = daily_forecast.resample("MS").sum()

    assumptions = assumption_map()
    valid_settled = transactions[
        transactions["is_valid_amount"].astype(str).str.lower().eq("true")
        & transactions["final_status"].isin(["success", "recovered_success"])
    ]
    average_settled_value = float(valid_settled["amount"].mean())
    attempts_per_recovery = len(recoveries) / max(
        int((transactions["final_status"] == "recovered_success").sum()), 1
    )
    customer_intervention_share = (
        recoveries["recovery_track"].eq("Customer Intervention").sum()
        / max(int(transactions["failure_volume"].sum()), 1)
    )
    manual_review_share = (
        recoveries["recovery_track"].eq("Do Not Retry-Monitor").sum()
        / max(int(transactions["failure_volume"].sum()), 1)
    )

    monthly["settled_volume"] = (
        monthly["transaction_volume"] - monthly["failure_volume"] + monthly["recovery_volume"]
    )
    monthly["projected_settled_value_usd"] = monthly["settled_volume"] * average_settled_value
    monthly["payment_processing_expense_usd"] = (
        monthly["settled_volume"] * assumptions["payment_processing_fixed_per_settled_transaction"]
        + monthly["projected_settled_value_usd"] * assumptions["payment_processing_bps"] / 10_000
    )
    monthly["recovery_expense_usd"] = (
        monthly["recovery_volume"] * attempts_per_recovery * assumptions["retry_cost_per_attempt"]
        + monthly["failure_volume"] * manual_review_share * assumptions["manual_review_cost_per_attempt"]
    )
    monthly["customer_intervention_expense_usd"] = (
        monthly["failure_volume"]
        * customer_intervention_share
        * assumptions["customer_support_cost_per_intervention_attempt"]
    )
    monthly["platform_expense_usd"] = (
        monthly["transaction_volume"] * assumptions["platform_cost_per_transaction"]
    )
    monthly["notification_and_failure_ops_usd"] = (
        monthly["transaction_volume"] * assumptions["notification_cost_per_notification"]
        + monthly["failure_volume"] * assumptions["failure_investigation_cost_per_failure"]
    )
    monthly["recurring_fixed_expense_usd"] = sum(
        assumptions[key]
        for key in (
            "engineering_remediation_monthly",
            "operations_platform_monthly",
            "other_operations_monthly",
        )
    )
    monthly["total_opex_usd"] = monthly[
        [
            "payment_processing_expense_usd",
            "recovery_expense_usd",
            "customer_intervention_expense_usd",
            "platform_expense_usd",
            "notification_and_failure_ops_usd",
            "recurring_fixed_expense_usd",
        ]
    ].sum(axis=1)

    monthly = monthly.reset_index(names="forecast_month")
    monthly["forecast_type"] = "synthetic_scenario_projection"
    monthly["transaction_model"] = selected_models["transaction_volume"]
    monthly["failure_model"] = selected_models["failure_volume"]
    monthly["recovery_model"] = selected_models["recovery_volume"]
    numeric_columns = monthly.select_dtypes(include=[np.number]).columns
    monthly[numeric_columns] = monthly[numeric_columns].round(2)
    monthly.to_csv(OUT_DIR / "forecast_monthly.csv", index=False)

    print("Forecast validation written to", OUT_DIR / "forecast_validation.csv")
    print("Monthly forecast written to", OUT_DIR / "forecast_monthly.csv")
    print("Selected models:", selected_models)


if __name__ == "__main__":
    main()
