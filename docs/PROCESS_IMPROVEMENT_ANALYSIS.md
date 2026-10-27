# Process Improvement Analysis

## Baseline versus intervention model

Only the stale-read engineering scenario prevents an initial failure. Its 375.4 modeled avoided events reduce the overall not-success rate from 5.9339% to approximately 5.7253%, a 0.2086 percentage-point improvement. Automated retry, customer messaging, and risk review occur after an initial failure; they improve final recovery, not the initial failure rate.

The three recovery interventions model 1,330.8 incremental recoveries. Holding the finalized-failure denominator constant, the recovery rate would rise from 39.79% to approximately 52.29% (+12.50 percentage points). If the 375.4 prevented stale-read failures are also removed from the finalized-failure denominator, the modeled recovery rate is approximately 54.21%. These are scenario calculations, not observed changes.

## Operational and customer impact

| Intervention | Primary operational change | Target customers observed | Incremental successes/events | Added cost | Direct net benefit |
|---|---|---:|---:|---:|---:|
| Issuer-decline retry | Instrument and retry eligible declines | 1,310 | 584.8 | $19,593.75 | -$18,130.01 |
| Low-balance nudge | Proactive customer message | 2,044 | 144.0 | $19,940.74 | -$19,722.96 |
| Stale-read fix | Prevent internal race-condition failures | 558 | 375.4 | $19,438.36 | -$19,108.70 |
| Risk review pilot | Faster review under controlled policy | 1,736 | 602.0 | $43,447.83 | -$41,301.80 |

Customer counts overlap and therefore are not summed. Additional processing expense is included in each scenario’s retry and servicing cost. The combined case avoids $2,363.68 of modeled operating cost but adds $102,420.68 of implementation, recurring, retry, and servicing cost in the analysis window.

## Priority by benefit, effort, and risk

1. **Issuer-decline instrumentation** — best direct economics of the modeled set, medium confidence, low-to-medium effort, and closes a material observability gap.
2. **Stale-read engineering fix** — highest evidence confidence and directly improves failure rate, but requires a materially smaller delivery estimate to become economic.
3. **Low-balance nudge pilot** — low evidence confidence; test on a limited customer cohort only after Compliance review.
4. **Risk review pilot** — high face-value exposure but highest effort/risk; Risk, Fraud, and Compliance retain veto authority.

Financial approval should not rely on processed principal. If leadership proceeds for service, fraud-control, or retention reasons, those objectives and measures should be stated separately from direct ROI.
