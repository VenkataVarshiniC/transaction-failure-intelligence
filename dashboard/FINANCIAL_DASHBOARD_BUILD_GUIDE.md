# Power BI Financial Dashboard Build Guide

## Status

Power BI Desktop was not present in the available Windows application inventory, so no `.pbix` was created or tested. This package provides reproducible imports, DAX, relationships, expected totals, and a six-page build specification. Do not describe the dashboard as built until the checklist at the end is completed in Power BI Desktop.

## Import

Run `python scripts/run_financial_pipeline.py`, then import every file listed in `dashboard/power-bi-import-manifest.csv`. Preserve the manifest table names. Set month fields to Date, currency fields to Fixed Decimal Number, counts/rates to Decimal or Whole Number as appropriate, and `reconciles`/`selected` to True/False.

Create a calendar table:

```DAX
Calendar =
CALENDAR(
    MIN(transaction_performance[month]),
    MAX(forecast_monthly[forecast_month])
)
```

Add Year, Month Number, Month Label, and Year-Month columns. Mark it as the date table.

## Relationships

Use single-direction one-to-many relationships from `Calendar[Date]` to:

- `transaction_performance[month]`
- `financial_costs[month]`
- `monthly_opex[month]`
- `recovery_performance[month]`
- `budget_vs_actual[month]`
- `forecast_monthly[forecast_month]`

Keep `scenario_comparison`, `net_recovery_benefit`, `financial_kpis`, `forecast_validation`, and `source_to_report_reconciliation` disconnected. The exposure, segment, channel, and category extracts are purpose-built drill tables and do not need relationships to the monthly facts.

Load measures from `dashboard/financial-dashboard-measures.dax` into a dedicated `_Measures` table.

## Page 1 — Financial Operations Overview

Cards: Total Transactions, Not Success Rate, Failed Face Value, Total Modeled OpEx, OpEx per Transaction, Recovery Cost per Successful Recovery.

Visuals: monthly transaction/failure trend; OpEx by cost category; cost-class split; cost by payment channel. Add a persistent subtitle: “Synthetic data; modeled costs; failed face value is not loss.”

Expected unfiltered totals: 180,000 transactions; 5.93% not-success rate; $2,603,613.29 failed face value; $137,142.45 OpEx; $0.7619 per transaction.

## Page 2 — Failure and Recovery Analysis

Use `failed_transaction_exposure` for failure count and face value by reason, category, channel, rail, and segment. Use `recovery_performance` for attempts, recovered transactions, and attempt success rates. Add drill-through from category to reason and transaction ID.

Show pending and unclassified status cards so the 10,681 not-success count is not silently reduced to the 10,643 finalized-failure denominator used for recovery rate.

## Page 3 — Operational Expenditure

Use `financial_costs` and `monthly_opex`. Show monthly OpEx, line-item waterfall, variable versus recurring-fixed cost, intervention cost by failure category, segment allocation, and channel allocation.

Expected total: $137,142.45. Segment and channel allocations should each reconcile within $0.02 because extracts are rounded to cents.

## Page 4 — Recovery Economics

Use `scenario_comparison` as a disconnected slicer. Display the selected-scenario measures for incremental successes, processed value, fee revenue, avoided OpEx, added cost, net benefit, ROI, and break-even conversion. Place processed value in a separate exposure-colored card and label it “principal throughput—not benefit.”

Add a comparison bar for all scenarios by net financial benefit and a scatter plot with effort score versus net benefit from `net_recovery_benefit`, sized by risk score.

Expected combined result: 1,706.2 incremental successes/events, $512,437.23 processed value, $1,793.53 fee revenue, $2,363.68 avoided OpEx, $102,420.68 added cost, and -$98,263.47 net benefit.

## Page 5 — Forecast and Variance Analysis

Use `forecast_monthly` for July–December volume, failure, recovery, and OpEx. Use `budget_vs_actual` for observed-month budget variance. Add the `forecast_validation` table with selected-model conditional formatting and MAE/RMSE/MAPE tooltips.

Expected six-month totals: 367,991 transactions, 20,439 failures, 8,662 recoveries, and $277,269.86 OpEx. Include the annotation “Synthetic scenario projection; holdout accuracy is not production accuracy.”

## Page 6 — Executive Decision Summary

Show ranked interventions, net benefit, ROI, break-even rate, confidence, effort, and risk. Add a reconciliation badge using Reconciliation Pass Count / Reconciliation Check Count; expected value is 6 / 6. Include the four implementation priorities and explicit non-financial risks from `docs/EXECUTIVE_FINANCIAL_REPORT.md`.

## Filters and interaction

Synchronize Calendar Year-Month across pages 1, 3, and 5. Add category, reason, channel, rail, and segment filters where supported by the relevant extract. Enable drill-through to the failed-transaction exposure table. Keep scenario selection isolated to pages 4 and 6.

## Verification checklist

- Refresh completes without type or path errors.
- All expected totals above match the CSV/SQL outputs.
- Six reconciliation checks show True.
- Scenario processed value never appears in a financial-benefit total.
- Recovery rate uses only recovered plus permanently failed transactions.
- Budget variance sign is favorable when budget exceeds modeled actual.
- Forecast page identifies the output as synthetic.
- Screenshots and a tested `.pbix` are added only after an actual Desktop build.
