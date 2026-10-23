# Recovery Intelligence — the Recovery Opportunity Engine

**Phase 12 of 20 — Bank Transaction Failure Intelligence & Recovery Optimization**

## 1. Purpose

Master brief Section 17 calls this out as one of the project's distinctive
components: not treating every failed transaction the same, but
classifying failures into action-oriented categories with defined
criteria, a recommended action, expected benefit, risk, owner, and KPI.

The data model has carried a `default_recovery_track` field on every
`failure_reasons` row since Phase 6 (`data-architecture.md`) — a
design-time assumption about how each reason *should* be handled,
documented in `future-state.md` before a single transaction existed. This
phase does something different: it checks that assumption against what
**actually happened** in the dataset (Phase 10's real recovery rates) and
lets the evidence override the assumption where the two disagree. One
reason does disagree — see Section 3.

All figures below come from `sql/09_recovery_opportunity.sql`, a new
query added to the Phase 10 SQL layer and re-run for real into
`sql/query-results.md`, not hand-typed. It classifies every one of the 13
failure reasons into exactly one of 5 categories, in this order of
precedence:

1. **Do Not Retry** — `default_recovery_track = 'Not Applicable'` (retrying
   identical input can't change the outcome) OR `failure_category = 'Policy'`
   (an intentional hold, not a defect)
2. **Immediate Recovery Candidate** — observed recovery rate ≥ 70%,
   checked *before* any category-specific branch, so real evidence can
   promote a reason out of its design-time track
3. **Investigate** — `failure_category = 'Risk'` (a policy/threshold
   question, not something to automate around), OR no recovery data
   exists at all *and* failed value is ≥ $100,000 (a stated materiality
   assumption — worth a closer look before writing the value off)
4. **Customer Intervention** — the design-time track says so, and nothing
   above applied
5. **Engineering Fix** — the design-time track says so, and nothing above
   applied

Everything falls into exactly one bucket; nothing is silently dropped.

## 2. The Recovery Opportunity Matrix

| Category | Reasons (13 total) | Failure events | Associated value | Criteria | Recommended action | Expected benefit | Risk | Owner | KPI |
|---|---|---|---|---|---|---|---|---|---|
| **Immediate Recovery Candidate** | `AUTH_FAILED`, `RAIL_TIMEOUT`, `BALANCE_DECLINED_STALE_READ`, `RISK_ENGINE_TIMEOUT`, `RAIL_OUTAGE` | 2,698 (25.3%) | $570,878 (21.9%) | Observed recovery ≥ 70%; not a Risk/Policy control | Automated retry, minimal human review; tune per-reason backoff to the observed attempt curve (1st try 75.4%, 2nd 79.1%, 3rd 90.7% success — `06_recovery_analysis.sql` Q2) | The bulk of this $571K is plausibly recoverable with no human involvement — Phase 13 sizes this precisely | Low — transient technical conditions, not intentional declines; retry doesn't bypass any control | Operations Manager, Payments (monitoring) + Engineering Lead, Payments Platform (owns the retry mechanism) | Automated recovery rate by reason (sustain 74–92% observed); avg. attempts-to-recovery |
| **Investigate** | `RISK_HELD`, `RAIL_DECLINED_ISSUER` | 3,500 (32.8%) | **$1,092,377 (42.0%)** | `Risk` category (intentional control) OR no recovery data + value ≥ $100K | `RISK_HELD`: review threshold/clearance-SLA with Risk & Fraud. `RAIL_DECLINED_ISSUER`: close the instrumentation gap (Section 4) before concluding it's unrecoverable | **Largest value bucket in this entire matrix** — even a modest improvement here outweighs further-optimizing the already-strong Immediate Recovery bucket | High if mishandled — `RISK_HELD` exists to prevent fraud exposure; a careless auto-retry here risks reopening the exact exposure the control exists for (the Synapse–Evolve pattern cited in `business-case.md`) | Risk & Fraud Team Lead (`RISK_HELD`); Engineering Lead (instrumentation gap); Compliance/Legal informed | Risk-hold median clearance time; % of `RAIL_DECLINED_ISSUER` transactions with a logged recovery attempt (today: 0%) |
| **Customer Intervention** | `BALANCE_DECLINED_INSUFFICIENT_FUNDS` | 2,428 (22.7%) | $516,927 (19.9%) | Design-time track says customer action is required; observed 40.36% recovery is consistent with genuine customer-driven resolution | Proactive, low-balance nudge before a scheduled transaction attempts, rather than a silent retry — ties to the small-business/payroll-timing finding in `root-cause-analysis.md` | The 40.36% recovery observed today happens with **no** explicit nudge mechanism in place; a real product intervention could plausibly lift it (Phase 13/14 sizes this) | Low-medium — messaging that reads as an overdraft offer needs Compliance review | Product Manager, Payments & Transfers; Customer Support Operations Lead informed | Recovery rate for this reason (baseline 40.36%); repeat-failure rate among nudged customers |
| **Engineering Fix** | `PROCESSING_ERROR` | 276 (2.6%) | $42,252 (1.6%) | Design-time track says so; internal `Technology`-category systemic defect, not a per-transaction condition | Extend the same find-fix-verify pattern already proven in this dataset (Section 5) to future stage-6 anomalies | **Already realized, not projected** — the day-55 fix cut the per-day rate ~65% (4.48/day → 1.55/day, `root-cause-analysis.md` Section 8). The one line in this matrix that's a fact, not a forecast | Low — internal code fix, normal release risk only | Engineering Lead, Payments Platform | Stage-6 per-day error rate, sustained post-fix |
| **Do Not Retry** | `CLIENT_INIT_FAILURE`, `VALIDATION_FAILED`, `ACCOUNT_RESTRICTED_DECLINE`, `UNCLASSIFIED` | 1,775 (16.6%) | $380,884 (14.6%) | `Not Applicable` track OR `Policy` category | Do not build retry automation. `CLIENT_INIT_FAILURE`/`VALIDATION_FAILED` point to upstream client/API investment instead; `ACCOUNT_RESTRICTED_DECLINE` stays with Compliance | Avoided cost — prevents building automation where it structurally cannot help | Low for correctly excluding these; the real risk is elsewhere — see Section 6 on `UNCLASSIFIED` | Product/Engineering per reason; Compliance/Legal for `ACCOUNT_RESTRICTED_DECLINE` | Not a recovery KPI — upstream client-crash / API-validation-error rate instead |

Percentages are of the 10,677 total failure events and $2,603,318 in
associated value across all 13 reasons (`sql/09_recovery_opportunity.sql`
totals — slightly below `07_financial_impact.sql` Q1's transaction-level
$2,603,613 because a transaction that failed more than once in its
lifecycle contributes to more than one reason row here; the same
event-level convention `07`'s own Q4 category rollup already uses, kept
consistent rather than reconciled away).

## 3. The one reclassification: RAIL_OUTAGE

This is the headline finding of this phase. `RAIL_OUTAGE` was tagged
`Do Not Retry-Monitor` at design time in Phase 6/8 — a conservative
assumption that an external rail outage needs a human to confirm before
retrying. The real data disagrees: it has the **highest observed recovery
rate of any reason in the dataset, 91.76%**. An outage is binary and
temporary — once the rail is back up, a retry succeeds almost every time,
unlike an issuer decline which reflects a standing judgment that a retry
won't help. This query's precedence order (evidence checked before the
category-specific branch) is exactly what catches this: a
category/origin-only classification would have left `RAIL_OUTAGE` sitting
in the monitored queue it doesn't need to be in.

This is worth stating plainly as the value of building an actual data-driven
engine here instead of just restating the Phase 6 design assumptions
in a nicer table — the assumption was reasonable when it was written
(before any data existed to check it against), and the right response to
new evidence is to update the classification, not defend the original
guess.

## 4. Data limitation carried forward from Phase 11

`RAIL_DECLINED_ISSUER` sits in **Investigate** specifically because no
recovery data exists for it to evaluate — `root-cause-analysis.md`
Section 9 already documented that this reason (and
`ACCOUNT_RESTRICTED_DECLINE`) has zero logged `recovery_attempts` rows
despite sharing a `Do Not Retry-Monitor` design-time track with
`RISK_HELD` and `RAIL_OUTAGE`, which are both well-instrumented. That gap
is exactly why this reason can't be scored on recovery probability the
way the other four "Do Not Retry-Monitor"-track reasons could. Its
$366,742 in associated value earns it a place in Investigate on
materiality alone — but the honest status here is "we don't know how
recoverable this is," not "we've evaluated it and it's uncertain." Closing
this instrumentation gap is a precondition for ever moving
`RAIL_DECLINED_ISSUER` out of Investigate with evidence rather than a
guess.

## 5. What "already proven" looks like here

Every other category's "expected benefit" is necessarily forward-looking
language, deferred to Phase 13's Business Impact Model for actual sizing
(per Section 18's instruction to never present an estimate as a fact).
`PROCESSING_ERROR` is the one exception worth calling out on its own: the
day-55 engineering-fix signal in `root-cause-analysis.md` Section 8 is not
a projection — it is an observed before/after rate change that already
happened in this dataset (4.48 errors/day before, 1.55/day after). It's
included here as a reminder that the "Engineering Fix" category isn't
hypothetical scaffolding; this project's own data contains one real
instance of it working.

## 6. A caution on UNCLASSIFIED

`UNCLASSIFIED` (the FR-00 sentinel added in Phase 9's cleaning step,
`data-quality-report.md`) shows an observed recovery rate of 62.50% in
`sql/09_recovery_opportunity.sql`'s output — high enough that, read
carelessly, it could look like a reasonable Immediate Recovery candidate.
It isn't one. It's a data-quality artifact: transaction_events that
referenced a `failure_reason_id` outside the standard taxonomy at extract
time, not a real, actionable failure cause. Its recovery track is
correctly `Not Applicable` and it lands in **Do Not Retry** in this
matrix — flagged here explicitly so that number never gets quoted in a
leadership deck as "63% of unclassified failures recover automatically."
The actual action item behind `UNCLASSIFIED` is upstream: keep
`data_quality_checks.py`'s taxonomy-completeness check running so this
bucket stays small and gets investigated case-by-case, not treated as a
recovery opportunity.

## 7. Handoff to Phase 13

This phase deliberately stops short of dollar recoverability estimates.
"Expected benefit" above is directional language, not a number, by
design — Section 18 requires observed, estimated, and scenario-assumption
figures to stay visibly separate, and this project's practice throughout
has been to build one layer at a time rather than blend them. Phase 13
(Business Impact Model) is where a stated recovery-rate assumption gets
applied to the Investigate and Customer Intervention buckets specifically
— the two categories where today's *observed* recovery (40.36%
and, for `RISK_HELD`, 40.79%) is well below the Immediate Recovery
bucket's 74–92%, and where the matrix above argues there's real headroom
if `RISK_HELD`'s clearance process and `RAIL_DECLINED_ISSUER`'s
instrumentation gap both get addressed.

## 8. Open items carried forward

1. Close the `RAIL_DECLINED_ISSUER` recovery-instrumentation gap (Section
   4) — a precondition for ever re-scoring it with evidence.
2. `RISK_HELD`'s threshold/SLA review needs Risk & Fraud stakeholder
   input this project's data alone can't supply (same note carried from
   `root-cause-analysis.md` Section 13).
3. Any customer-facing messaging change for `BALANCE_DECLINED_INSUFFICIENT_FUNDS`
   needs a Compliance review pass before Phase 16 turns it into a formal
   recommendation.
