# Business Impact Model

**Phase 13 of 20 — Bank Transaction Failure Intelligence & Recovery Optimization**

## 1. Purpose and ground rules

Master brief Section 18: quantify the impact, and keep three tiers
visibly separate throughout — **Observed**, **Estimated**, and **Scenario
assumption**. Never present one as another. This document follows that
discipline literally: every number below is labeled with which tier it
belongs to, and the one arithmetic step that turns an observed figure
into an estimate is shown as plain multiplication, not buried in a query.

All figures are drawn from `sql/query-results.md` (Phases 10-12) plus one
new file, `sql/10_business_impact.sql`, added this phase and run for
real. As with every prior phase: **simulated dataset, simulated
financial figures — none of this represents real bank losses or real
customer data** (`business-case.md` Section 6; master brief Section 31).

Phase 14 (What-If Simulation) is where multiple scenarios get built and
compared. This phase deliberately stops at *one* stated, labeled estimate
per figure — building five scenarios here would blur exactly the
distinction Section 18 asks this phase to protect.

## 2. Observed metrics

These are direct aggregations of what happened in the dataset. No
assumption is applied anywhere in this section.

| Metric | Value | Source |
|---|---|---|
| Total transactions | 180,000 | `02_transaction_performance.sql` Q1 |
| Failed transaction volume | 10,679 (5.93%) — success 169,319; recovered_success 4,235; permanently_failed 6,408; pending 36 | `02` Q1 |
| Failed transaction value | $2,603,613.29 of $38,130,539.17 total valid value (6.828%) | `07_financial_impact.sql` Q1 |
| Observed recovered value | $916,896.23, across 4,235 transactions | `07` Q2 |
| Customers affected (1+ failure) | 5,900 of 12,000 (49.2%) | `05_customer_analysis.sql` Q1 |
| Customers with repeat failures (2+) | 2,587 (21.6% of all customers; 43.8% of affected) | `05` Q1 |
| Customers with 4+ failures ("problem cohort") | 525 (4.4% of all customers) | `05` Q1 |
| Small-business vs. retail per-failure stakes | $1,101.72 avg vs. $126.81 avg (8.7x) | `05` Q4 |

### Repeated failure cost — a real dollar figure, not just a customer count

`root-cause-analysis.md` Section 10 already showed repeat-failure
customers are a concentrated cohort. This phase sizes them in dollars for
the first time (`10_business_impact.sql` Q4):

| Cohort | Customers | Failed transactions | Failed value | Avg per failed txn |
|---|---|---|---|---|
| Repeat failure (2+) | 2,587 (43.8% of affected) | 7,362 | **$1,914,257.77 (73.6% of all failed value)** | $260.06 |
| Single failure | 3,313 (56.2% of affected) | 3,313 | $686,813.63 (26.4%) | $207.32 |

This is the clearest "repeated failure cost" finding in the dataset:
**43.8% of affected customers account for nearly three-quarters of all
failed value**, and their average failed transaction is also ~26% larger
than a one-off failure's. A remediation that only reduces the failure
*rate* uniformly misses this — targeting the repeat cohort specifically
(the same cohort `recovery-intelligence.md` and `root-cause-analysis.md`
already flagged) has a structurally larger ceiling than an across-the-board
fix.

### Support workload proxy — explicitly labeled as a proxy

This dataset has no `support_tickets` entity (`data-architecture.md`
Section 6 scoped it out deliberately) — so there is no real support-contact
data to report. Two **proxies** stand in, and are labeled as such rather
than presented as real support-volume figures:

- **Customer Intervention track volume**: 2,418 logged attempts
  (`06_recovery_analysis.sql` Q1) — the recovery track most likely to
  generate an inbound customer contact, since it depends on the customer
  taking action.
- **Repeat-failure customer count**: 2,587 (above) — customers who hit
  the same kind of friction more than once are the most plausible source
  of repeat contacts, independent of which track their failures route to.

Neither is a ticket count. Treat both as directional indicators of where
support burden is *likely* concentrated, not as a support-volume forecast.

## 3. Estimated metrics

Everything in this section applies exactly one stated assumption to an
observed baseline. Each assumption is named explicitly; none is asserted
as fact.

### Potentially recoverable value: $1,264,295.11

**Definition, stated plainly:** the sum of still-unrecovered value sitting
in the three opportunity categories (`recovery-intelligence.md`, Phase 12)
where *some* recovery mechanism is plausible in principle — this is a
statement about which value is in-scope for further recovery work, not a
prediction that all of it converts.

| Category | Still-unrecovered value | Included? |
|---|---|---|
| Investigate | $866,346.28 | Yes |
| Customer Intervention | $354,782.06 | Yes |
| Immediate Recovery Candidate (residual, after existing auto-retry) | $43,166.77 | Yes |
| **Subtotal — potentially recoverable** | **$1,264,295.11** | |
| Do Not Retry | $377,200.66 | No — by definition, no mechanism applies (`recovery-intelligence.md` Section 2) |
| Engineering Fix | $42,252.17 | No — this value isn't "recovered" per transaction, it's prevented going forward once fixed (Section 5 below) |

Source: `10_business_impact.sql` Q1.

### Estimated recovered value — one worked example: ~$451,243 (RISK_HELD)

This is the one place in this project a specific dollar estimate gets
built, and the assumption behind it is named in full:

**Stated assumption:** RISK_HELD's clearance process could reach the
90.32% transaction-level recovery rate this dataset's own
`Immediate Recovery Candidate` category already achieves for reasons with
a mature, well-instrumented recovery mechanism (`10_business_impact.sql`
Q1: 2,417 recovered / 2,676 total for that category). This is a benchmark
drawn from this project's own data — not an industry figure, not a
vendor claim.

**The math, shown so it can be checked by hand:**

```
RISK_HELD still-unrecovered value today:   $499,604.76   (10_business_impact.sql Q3)
RISK_HELD achieved rate today:                  40.81%   (830 recovered / 2,034 total)
Benchmark rate (Immediate Recovery category):   90.32%   (10_business_impact.sql Q1)

Estimated recovered value = $499,604.76 × 90.32%  ≈  $451,243
```

**Why RAIL_DECLINED_ISSUER — the other Investigate reason — gets no
estimate at all:** it has $366,741.52 still unrecovered and **zero**
logged recovery attempts (`10_business_impact.sql` Q3; the same
instrumentation gap `root-cause-analysis.md` Section 9 and
`recovery-intelligence.md` Section 4 already flagged). There is no
observed rate to benchmark from, and inventing one to fill the gap would
violate the entire point of this section. Its value stays labeled "at
stake, recoverability unknown" until that gap is closed.

**Why this estimate isn't extended to Customer Intervention:** the
`BALANCE_DECLINED_INSUFFICIENT_FUNDS` mechanism (a customer adding funds)
is already active and already at 40.45% (`10_business_impact.sql` Q1: 978
recovered / 2,418 total) — there's no equivalent "mature mechanism
elsewhere in this dataset" to benchmark a *customer-driven* recovery rate
against the way RISK_HELD borrows from a *system-driven* one. Sizing a
proactive-nudge intervention for this reason needs its own scenario
assumption (a stated guess at how much a nudge would lift the rate) —
that's exactly the kind of single-variable, clearly-hypothetical number
Phase 14 is built to hold, not this phase.

## 4. Scenario assumptions — none built here, by design

Section 18's third tier is deliberately empty in this document.
`future-state.md`'s four recovery tracks and master brief Section 19 both
already name the shape Phase 14 will take (Scenario A: no action, B:
automated retry, C: customer intervention, D: engineering improvements, E:
combined) — building any of them here, ahead of that phase, would blend
tiers this document exists to keep apart.

## 5. The one already-realized case, restated

`recovery-intelligence.md` Section 5 already made this point for the
Recovery Opportunity Matrix; it belongs here too as a business-impact
fact, because it's the one line in this entire model that isn't a
forecast. The day-55 engineering fix (`root-cause-analysis.md` Section 8)
cut `PROCESSING_ERROR`'s per-day rate from 4.48 to 1.55 — a ~65%
reduction that already happened. Applied to its $42,252.17 in observed
associated value as a rough annualization-free sense of scale: at the
pre-fix rate this reason was on pace for roughly 2.9x the failures it now
generates per day. That's not a number this document is claiming as a
saved dollar figure (no clean "before/after value" query was run for it
specifically, and doing so now would be scope creep for this phase) — it's
included to make the point that "Engineering Fix" isn't a hypothetical
category in this matrix. It has one proven instance already.

## 6. Summary table — the three tiers, side by side

| | Observed | Estimated |
|---|---|---|
| Failed value | $2,603,613.29 | — |
| Recovered value | $916,896.23 | ~$451,243 additional (RISK_HELD only, stated assumption above) |
| Recoverable pool | — | $1,264,295.11 (definition above) |
| Repeat-failure cohort value | $1,914,257.77 (73.6% of failed value) | — |
| RAIL_DECLINED_ISSUER value at stake | $366,741.52 | Not estimated — instrumentation gap (Section 3) |

No scenario-assumption column exists in this table on purpose — that
column is Phase 14's.

## 7. Open items carried forward

1. RAIL_DECLINED_ISSUER's recovery instrumentation gap (repeated from
   Phase 11/12) is now also a business-impact blocker: $366,742 in value
   this document cannot responsibly estimate a recovery figure for until
   it's closed.
2. The repeat-failure cohort's 73.6% share of failed value is the
   strongest single number in this phase for Phase 16's recommendations —
   it argues for a customer-targeted intervention design, not a uniform
   one, more directly than any figure in Phases 10-12.
3. Phase 14 should build its scenarios directly on this phase's category
   structure (Investigate / Customer Intervention / Immediate Recovery /
   Engineering Fix) rather than starting from the master brief's generic
   A-E labels independently — the two map cleanly onto each other and
   keeping one consistent taxonomy avoids the project accumulating two
   incompatible category schemes.
