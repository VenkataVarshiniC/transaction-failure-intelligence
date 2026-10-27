"""Load versioned assumptions, create DuckDB reporting views, and export CSVs."""

from __future__ import annotations

from pathlib import Path

import duckdb


PROJECT_ROOT = Path(__file__).resolve().parents[1]
DB_PATH = PROJECT_ROOT / "sql" / "kestrel.duckdb"
SQL_PATH = PROJECT_ROOT / "sql" / "11_financial_reporting_models.sql"
CONFIG_DIR = PROJECT_ROOT / "config"
REPORTING_DIR = PROJECT_ROOT / "data" / "reporting"

EXPORTS = {
    "transaction_performance": "vw_transaction_performance",
    "failed_transaction_exposure": "vw_failed_transaction_exposure",
    "recovery_performance": "vw_recovery_performance",
    "financial_costs": "vw_financial_costs",
    "monthly_opex": "vw_monthly_opex",
    "financial_kpis": "vw_financial_kpis",
    "intervention_cost_by_failure_category": "vw_intervention_cost_by_failure_category",
    "net_recovery_benefit": "vw_net_recovery_benefit",
    "customer_segment_financial_impact": "vw_customer_segment_financial_impact",
    "payment_channel_profitability": "vw_payment_channel_profitability",
    "budget_vs_actual": "vw_budget_vs_actual",
    "scenario_comparison": "vw_scenario_comparison",
    "source_to_report_reconciliation": "vw_source_to_report_reconciliation",
}


def load_csv_table(con: duckdb.DuckDBPyConnection, table_name: str, path: Path) -> None:
    con.execute(
        f"CREATE OR REPLACE TABLE {table_name} AS "
        f"SELECT * FROM read_csv_auto('{path.as_posix()}', header=true)"
    )


def main() -> None:
    if not DB_PATH.exists():
        raise FileNotFoundError(f"Database not found: {DB_PATH}. Run scripts/load_database.py first.")

    REPORTING_DIR.mkdir(parents=True, exist_ok=True)
    con = duckdb.connect(str(DB_PATH))
    load_csv_table(con, "financial_assumptions", CONFIG_DIR / "financial_assumptions.csv")
    load_csv_table(con, "recovery_scenarios", CONFIG_DIR / "recovery_scenarios.csv")
    load_csv_table(con, "monthly_opex_budget", CONFIG_DIR / "monthly_opex_budget.csv")

    forecast_monthly = REPORTING_DIR / "forecast_monthly.csv"
    forecast_validation = REPORTING_DIR / "forecast_validation.csv"
    if forecast_monthly.exists():
        load_csv_table(con, "forecast_monthly", forecast_monthly)
    if forecast_validation.exists():
        load_csv_table(con, "forecast_validation", forecast_validation)

    con.execute(SQL_PATH.read_text(encoding="utf-8"))

    for output_name, view_name in EXPORTS.items():
        output_path = REPORTING_DIR / f"{output_name}.csv"
        # SQL views do not guarantee row order. Sorting on every projected
        # column keeps committed reporting extracts byte-reproducible across
        # DuckDB executions without changing their grain or calculations.
        con.execute(f"SELECT * FROM {view_name} ORDER BY ALL").fetchdf().to_csv(output_path, index=False)
        count = con.execute(f"SELECT COUNT(*) FROM {view_name}").fetchone()[0]
        print(f"[OK] {view_name}: {count} rows -> {output_path.relative_to(PROJECT_ROOT)}")

    failed_reconciliations = con.execute(
        "SELECT COUNT(*) FROM vw_source_to_report_reconciliation WHERE NOT reconciles"
    ).fetchone()[0]
    con.close()
    if failed_reconciliations:
        raise RuntimeError(f"{failed_reconciliations} source-to-report reconciliation checks failed")


if __name__ == "__main__":
    main()
