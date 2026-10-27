# Financial Operations Model

## Purpose and financial treatment

This model converts operational events into modeled expenses and contribution economics. Observed synthetic transaction metrics are kept separate from v1.0 planning assumptions in `config/financial_assumptions.csv`.

Transaction face value is not a cost. Recovered or prevented principal is reported as incremental processed value only. Direct financial benefit contains modeled fee revenue and avoided operating expense, less incremental servicing, recurring, and one-time implementation costs.

## Cost architecture

| Class | Included items | Treatment |
|---|---|---|
| Variable | Platform usage, processor fixed and value-based charges, retry, support, manual review, notifications, failure investigation | Quantity × configured unit rate |
| Recurring fixed | Engineering reliability, operations platform, other operations | Monthly amount prorated by active days in partial months |
| One-time implementation | Scenario build/pilot costs | Included in intervention economics, not baseline OpEx |
| Modeled revenue | 35 bps on settled or incremental processed value | Contribution input, not a claim about actual bank pricing |

Assumption version v1.0 uses $0.015 per transaction, $0.08 plus 12 bps per settled transaction, $0.04 per retry, $3.25 per customer-intervention attempt, $6.50 per manual review, $0.008 per notification, and $0.12 per failed-transaction investigation. Monthly recurring allocations total $17,500.

## Baseline outputs

| KPI | Result |
|---|---:|
| Total modeled 90-day OpEx | $137,142.45 |
| Variable OpEx | $85,526.87 |
| Recurring fixed OpEx | $51,615.58 |
| OpEx per transaction | $0.7619 |
| Allocated OpEx per not-success transaction | $12.8399 |
| Failure-management cost per not-success transaction | $2.2255 |
| Recovery servicing cost per successful recovery | $5.3102 |

These are modeled results, not observed bank expenses. The 10,681 denominator includes pending and unclassified statuses because the report labels it explicitly as “not success.”

## Reporting implementation

`sql/11_financial_reporting_models.sql` creates views for transaction performance, failed exposure, recovery performance, cost detail, monthly OpEx, financial KPIs, category intervention cost, net recovery economics, segment impact, channel contribution, budget variance, scenario comparison, and reconciliation. `scripts/build_financial_reporting.py` exports each view to `data/reporting/`.

All six reconciliation checks pass at a tolerance below one cent.
