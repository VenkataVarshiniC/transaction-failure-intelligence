# Financial Scenarios

## Economics framework

Each intervention reports incremental successful transactions, processed value, fee revenue, avoided operating costs, incremental retry/servicing cost, implementation cost, analysis-window recurring cost, net benefit, ROI, and break-even conversion.

Processed value is principal throughput and is excluded from net financial benefit. The combined case sums four non-overlapping reason codes, preventing transaction or cost double counting.

## Results for the 90-day-equivalent analysis window

| Scenario | Incremental successes | Processed value | Fee revenue | Avoided OpEx | Additional cost | Net benefit | ROI | Break-even conversion |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| B: Automated Retry—Issuer Declines | 584.8 | $146,696.61 | $513.44 | $950.30 | $19,593.75 | **-$18,130.01** | -92.53% | 607.03% |
| C: Proactive Low-Balance Nudge | 144.0 | $35,478.21 | $124.17 | $93.60 | $19,940.74 | **-$19,722.96** | -98.91% | 1,598.34% |
| D: Stale-Read Engineering Fix | 375.4 | $80,460.03 | $281.61 | $48.05 | $19,438.36 | **-$19,108.70** | -98.30% | 3,856.29% |
| F: Risk Review Pilot | 602.0 | $249,802.38 | $874.31 | $1,271.73 | $43,447.83 | **-$41,301.80** | -95.06% | 1,463.23% |
| E: Combined | 1,706.2 | $512,437.23 | $1,793.53 | $2,363.68 | $102,420.68 | **-$98,263.47** | -95.94% | Not meaningful as one rate |

## Decision implication

None of the interventions breaks even on direct modeled fee revenue and OpEx in one 90-day-equivalent window. Scenario B has the least-negative net result and the lowest break-even hurdle, but its 607% required conversion is impossible within the current target pool under v1.0 assumptions.

This does not prove the interventions have no business value. Fraud-risk control, customer retention, regulatory service obligations, reputation, and lifetime value are not modeled. It does prove that the existing $262,637 face-value scenario should not be described as savings. Leadership should either reduce implementation scope, extend the benefit horizon, supply defensible retention/revenue benefits, or treat the work as a risk/service investment.

## Priority

1. Instrument `RAIL_DECLINED_ISSUER` first; it closes a measurement gap and is the least-negative direct case.
2. Scope the stale-read fix as a reliability control, with a smaller implementation budget before approval.
3. Pilot low-balance messaging only with Compliance review and measurable customer-behavior attribution.
4. Keep Risk-review changes gated by Risk, Fraud, and Compliance despite the large face-value exposure.

All benefits are hypothetical planning results, not realized savings.
