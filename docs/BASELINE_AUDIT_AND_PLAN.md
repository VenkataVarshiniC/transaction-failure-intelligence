# Baseline Audit and Implementation Plan

## Audit scope and result

The baseline was audited at commit `4408384` before financial-platform files were added. The audit covered data generation, issue injection, cleaning, the 180,000-row analysis dataset, all 36 SQL questions, recovery logic, root-cause work, customer segmentation, the existing scenario model, the financial-impact narrative, dashboard specification, setup instructions, and reproducibility controls.

The seed-42 generator and seed-2026 issue injector were rerun in an isolated directory. Every raw, clean, and exception CSV matched the committed dataset semantically. The DuckDB database rebuilt successfully and all 36 existing SQL questions executed without errors.

## Reproduced baseline

| Metric | Reproduced result | Definition |
|---|---:|---|
| Transactions | 180,000 | Clean transaction rows |
| Direct successes | 169,319 | `final_status = 'success'` |
| Not-success transactions | 10,681 (5.93%) | Every status other than `success`, including 36 pending and 2 unclassified |
| Finalized failures | 10,643 | 4,235 recovered + 6,408 permanently failed |
| Valid transaction value | $38,130,539.17 | Invalid/missing amounts excluded |
| Failed face value | $2,603,613.29 (6.828%) | Exposure, not financial loss |
| Recovered face value | $916,896.23 | Observed `recovered_success` value |
| Finalized-failure recovery rate | 39.79% | 4,235 / 10,643 |
| Affected attributable customers | 5,900 | Customer-linked transactions with non-success status |

## Definition correction

The existing `analysis/business-impact-model.md` reports 10,679 failed transactions by summing the four named status buckets shown there. The clean source contains two additional `unclassified` statuses. The new reporting layer therefore publishes both the named status counts and a transparent `not_success_count = 10,681`. No source data was changed.

## Data-quality and interpretation limits

- Forty-five transactions have invalid amounts and are retained for volume analysis but excluded from value analysis.
- Two statuses remain unclassified; 36 transactions are pending.
- One hundred fourteen transactions sit on quarantined orphan accounts and cannot be attributed to a customer segment.
- Ten recovery outcomes have inconsistent completion timestamps and are excluded from trusted attempt-success rates.
- `RAIL_DECLINED_ISSUER` has no observed recovery instrumentation.
- The 90-day synthetic history includes only two complete calendar months. Forecast validation therefore uses a 14-day daily holdout; future monthly totals are synthetic projections, not real-world forecasts.
- Failed face value and recovered principal are exposure/throughput measures. Neither is treated as expense, loss, savings, or revenue.

## Implementation milestones

| Milestone | Output | Status |
|---|---|---|
| 1. Baseline gate | Reproduction and metric-definition audit | Complete |
| 2. Assumption layer | Versioned cost, scenario, and budget CSVs | Complete |
| 3. Financial cost model | Variable, recurring-fixed, and one-time costs | Complete |
| 4. Recovery economics | Fee revenue, avoided cost, added cost, ROI, break-even | Complete |
| 5. Forecasting | Two-model holdout comparison and six monthly projections | Complete |
| 6. SQL reporting | Twelve financial views plus six reconciliations | Complete |
| 7. Dashboard enablement | Import extracts, DAX, model and six-page build guide | Complete; `.pbix` not created because Power BI Desktop is unavailable |
| 8. QA and evidence | Automated tests and executive/resume evidence | Complete |

## Reproduction commands

```powershell
python scripts/load_database.py
python scripts/run_sql_analysis.py
python scripts/run_financial_pipeline.py
python -m unittest discover -s tests -v
```
