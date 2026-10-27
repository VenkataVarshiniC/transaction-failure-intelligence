# OpEx Analysis

## Ninety-day operating expense

| Cost category | Modeled cost | Share of total |
|---|---:|---:|
| Platform and Processing | $60,316.91 | 44.0% |
| Recurring Fixed | $51,615.58 | 37.6% |
| Recovery and Manual Review | $14,630.04 | 10.7% |
| Customer Intervention | $7,858.50 | 5.7% |
| Notification and Failure Operations | $2,721.42 | 2.0% |
| **Total** | **$137,142.45** | **100.0%** |

Monthly modeled OpEx is $24,276.89 in partial March, $46,046.93 in April, $46,671.79 in May, and $20,146.84 in partial June. Fixed costs are prorated for the partial months.

## Failure-category intervention cost

Risk failures carry the largest modeled intervention cost at $13,543.60, or $6.6455 per affected transaction, because monitored attempts receive the $6.50 manual-review allocation. Process failures cost $8,381.54 ($2.4783 each), while External Dependency failures cost $1,446.65 ($0.6140 each).

## Segment and channel allocation

Retail-Standard receives $82,586.05 of modeled cost because it drives 127,527 transactions. Small-Business receives $32,386.30 but accounts for $1.410M of failed face value, confirming that operational cost and exposure should be managed as separate lenses.

Mobile app carries $75,862.48 of modeled cost and a negative modeled contribution of $23,494.83 after shared fixed-cost allocation. API shows the strongest modeled contribution at $13,884.22. These are incomplete contribution views—not product profitability—because credit losses, interchange detail, deposits, capital, and customer lifetime value are outside the dataset.

## Budget variance

The v1.0 synthetic budget is $151,600 versus $137,142.45 modeled actual, a favorable $14,457.55 variance. The largest favorable category is Recovery and Manual Review because its budget was deliberately conservative. Platform and Processing is slightly unfavorable in every observed month, including $575.15 in partial June.

Budgets are planning assumptions, not historical finance-system records.
