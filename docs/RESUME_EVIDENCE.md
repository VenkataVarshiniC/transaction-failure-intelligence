# Resume Evidence

## Verified project evidence

| Evidence area | Verified result |
|---|---|
| Transaction volume analyzed | 180,000 synthetic transactions; $38.131M valid value |
| Financial exposure identified | $2.604M failed face value; explicitly not treated as loss |
| Operational costs modeled | $137,142.45 across variable and recurring-fixed categories; $0.7619 per transaction |
| Net benefit by intervention | B -$18,130.01; C -$19,722.96; D -$19,108.70; F -$41,301.80; combined -$98,263.47 |
| Potential cost reductions | $2,363.68 combined avoided OpEx under assumptions; hypothetical, not realized |
| Forecast accuracy | Synthetic 14-day holdout MAPE: 2.31% volume, 6.00% failures, 20.76% recoveries |
| SQL reporting coverage | 12 financial/management views plus existing 36 business queries |
| Reconciliation | 6 of 6 source-to-report checks pass; segment and channel allocations reconcile within rounding |
| Dashboard verification | Import-ready extracts, DAX, relationships, and six-page specification complete; `.pbix` not created because Power BI Desktop is unavailable |
| Automated QA | 10 tests pass, including duplicate handling, cost allocation, scenario consistency, double counting, forecast constraints, variance math, and reproducibility |

## Metric-first resume bullets

- Built a DuckDB/Python financial-operations platform over **180K transactions and $38.1M in simulated value**, translating failure and recovery events into **12 management-reporting views**, versioned assumptions, and **6/6 source-to-report reconciliations**.
- Modeled **$137.1K of 90-day OpEx ($0.76/transaction)** across processing, retry, support, review, notification, and fixed-cost drivers; corrected a **$262.6K face-value scenario** by separating principal from revenue and showing **-$98.3K direct net benefit** under fully costed assumptions.
- Benchmarked seasonal-naive and trend/weekday forecasts on a **14-day synthetic holdout**, achieving **2.31% volume and 6.00% failure MAPE**, and produced six-month volume, recovery, OpEx, budget-variance, and Power BI-ready reporting outputs backed by **10 passing automated tests**.

All metrics are from synthetic data and modeled assumptions. No savings or business results are presented as realized.
