# Forecast Validation

## Method

The synthetic history is aggregated daily. The last 14 days (May 31–June 13, 2026) are held out. Two deterministic models are trained through May 30:

1. Weekday seasonal-naive: mean of prior observations for the same weekday.
2. Linear trend with weekday effects: ordinary least squares using elapsed day and six weekday indicators.

The lower-MAE model is selected separately for transaction, failure, and recovery volume, then refit on all 90 days. Forecast constraints enforce recovery ≤ failure ≤ transaction volume.

## Held-out results

| Target | Selected model | MAE | RMSE | MAPE |
|---|---|---:|---:|---:|
| Transaction volume | Weekday seasonal-naive | 49.26/day | 87.84 | 2.31% |
| Failure volume | Linear trend + weekday | 6.84/day | 9.72 | 6.00% |
| Recovery volume | Weekday seasonal-naive | 7.86/day | 10.50 | 20.76% |

The more complex model only wins for failure volume. That comparison prevents complexity from being treated as automatically superior.

## Six-month projection

For July–December 2026 the model projects 367,991 transactions, 20,439 failures, 8,662 recoveries, and $277,269.86 of modeled OpEx. Monthly OpEx ranges from $45,439.83 to $46,752.26.

## Interpretation limits

These error measures describe a synthetic 14-day holdout. They are not production forecast accuracy, do not establish generalization to a real bank, and do not capture real seasonality, economic cycles, product launches, or outages beyond the generator’s designed patterns. The future output is explicitly labeled `synthetic_scenario_projection`.
