# Executive Financial Report

## Executive conclusion

The simulated operation processed 180,000 transactions over 90 days. A total of 10,681 transactions were not in direct-success status (5.93%), representing $2.604M of valid failed face value. That value is exposure, not loss. The operation recovered $916,896.23 of face value across 4,235 finalized recoveries, a 39.79% finalized-failure recovery rate.

The v1.0 cost model estimates $137,142.45 of 90-day OpEx, or $0.7619 per transaction. Platform/processing and recurring fixed allocations represent 81.6% of modeled cost. Risk failures are the most expensive to service because manual review drives $13,543.60 of category intervention cost.

## Management reporting

- The modeled budget is favorable by $14,457.55 overall, although Platform and Processing is modestly unfavorable each month.
- Small-Business represents only 18,766 transactions but $1.410M of failed face value, making it the highest-stakes segment.
- API has the strongest modeled channel contribution; mobile has the largest cost allocation and negative modeled contribution. These are partial contribution views, not full profitability.
- Six source-to-report controls reconcile transaction counts, valid value, failed value, recovery attempts, OpEx, and combined scenario economics exactly.

## Forecast

On the synthetic 14-day holdout, selected-model MAPE is 2.31% for volume, 6.00% for failures, and 20.76% for recoveries. July–December scenario projections total 367,991 transactions and $277,269.86 OpEx. Recovery-volume error is materially higher and should carry wider management tolerance.

## Intervention decision

The old combined scenario described approximately $262,637 of recovered/avoided face value. The extended model shows why that is not savings. Under v1.0 assumptions, the broader four-intervention package processes $512,437.23 of incremental principal but produces only $1,793.53 of fee revenue and $2,363.68 of avoided OpEx against $102,420.68 of added cost, for a net **-$98,263.47**.

Approve instrumentation and tightly scoped pilots only where risk, service, or customer-retention objectives justify the spend. Do not approve the full package on direct 90-day economics alone.

## Priority actions

1. Close issuer-decline instrumentation and establish an observed recovery rate.
2. Obtain Engineering estimates that can replace v1.0 implementation assumptions.
3. Add support-ticket and customer-retention data before valuing service benefits.
4. Require Finance sign-off on fee-rate and budget assumptions; require Compliance sign-off on messaging and risk-policy interventions.
5. Reforecast after at least twelve complete monthly periods before using the model for production budgeting.

## Principal risks

Synthetic data, short history, missing support/retention economics, incomplete pricing detail, orphan customer attribution, and scenario-rate uncertainty are the main limitations. No hypothetical benefit in this report is a realized saving.
