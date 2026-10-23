# What-If Simulation

**Phase 14 of 20 — Bank Transaction Failure Intelligence & Recovery Optimization**

## 1. Purpose and how this builds on Phases 12-13

Master brief Section 19: build a scenario model — five named scenarios
(A: No Action, B: Automated Retry, C: Customer Intervention, D:
Engineering Improvements, E: Combined), each estimating failure
reduction, recovered transactions/value, customer impact, and
operational impact, with every estimate clearly labeled.

Per `business-impact-model.md` Section 7's own open item, this phase maps
the brief's generic A-E scenarios onto the category structure Phase 12
already built (`recovery-intelligence.md`) rather than starting from
scratch — so Scenario B targets the specific reasons Phase 12 already
identified as retry-eligible, Scenario C targets the one reason already
tagged customer-driven, and so on. One consistent taxonomy throughout the
project, not two.

**Every dollar figure below is a SCENARIO ASSUMPTION** — the third and
most speculative of the three tiers `business-impact-model.md`
established (Observed → Estimated → Scenario). Where Phase 13 built one
estimate from a benchmark already proven elsewhere in this dataset, this
phase goes a step further and states assumptions that have **no
observed precedent in the data at all** (e.g., "if a nudge lifts recovery
by 10 percentage points"). That is by design — this is what Section 19
asks a what-if model to do — but it means the numbers here carry
correspondingly less certainty than Phase 13's, and every one is labeled
as a stated, named assumption rather than a finding.

## 2. Scenario A — No Action (the baseline every other scenario is measured against)

Purely observed, zero assumption — restated from `business-impact-model.md`:

| Metric | Value |
|---|---|
| Recovered transactions | 4,235 |
| Recovered value | $916,896.23 |
| Still-unrecovered value | $1,686,717.06 |
| Customers affected | 5,900 (49.2% of the base) |
| Operational load (proxy) | 2,418 Customer Intervention attempts; 2,587 repeat-failure customers |

If nothing changes, this is the run rate the next 90-day window would be
expected to resemble, all else equal — a stated assumption in itself
(the dataset covers one window; extrapolating it forward assumes no
seasonal or volume change, which `dataset-design.md`'s stress-day design
already shows isn't always true).

## 3. Scenario B — Automated Retry (expanding an existing, proven mechanism)

**What this targets:** `RAIL_DECLINED_ISSUER` — the one Investigate-category
reason with real dollar exposure but **zero** recovery instrumentation
today (`business-impact-model.md` Section 3). This scenario asks: what if
Kestrel built the same kind of automated retry mechanism already proven
for the five Immediate Recovery Candidate reasons, and pointed it at this
one? (`Immediate Recovery Candidate`'s own $43,167 residual is *not*
modeled further here — Phase 13 already showed that bucket is near its
observed 90.32% ceiling; there's limited headroom left to simulate.)

No observed rate exists for `RAIL_DECLINED_ISSUER` to benchmark from (the
same instrumentation gap flagged in Phases 11-13), so this scenario
states three illustrative rates rather than picking one:

| Assumption | Rate | Recovered value | Recovered transactions |
|---|---|---|---|
| Conservative | 20% | $73,348.30 | ~292 |
| **Moderate (used in Scenario E)** | **40%** (benchmark: `RISK_HELD`'s own observed 40.81% — a comparably uncertain, externally-influenced reason) | **$146,696.61** | **~585** |
| Optimistic | 70% (benchmark: the Immediate Recovery Candidate threshold used throughout this project) | $256,719.06 | ~1,023 |

Base: $366,741.52 still-unrecovered value, 1,462 transactions
(`business-impact-model.md` Section 3, via `10_business_impact.sql` Q3).

- **Customer impact:** touches a subset of the 1,310 distinct customers
  who have hit `RAIL_DECLINED_ISSUER` at least once (`08_prioritization.sql`).
- **Operational impact:** requires an Engineering build (the
  instrumentation gap itself) before any retry can run — not a
  configuration change. This is a one-time build cost this project does
  not size in dollars (outside a BA-level analysis's scope); flagged
  here rather than omitted.

## 4. Scenario C — Customer Intervention (proactive low-balance nudge)

**What this targets:** `BALANCE_DECLINED_INSUFFICIENT_FUNDS`, the one
reason already correctly classified as customer-driven
(`recovery-intelligence.md`). Today it recovers at 40.45% with no active
nudge mechanism. This scenario asks: what if a proactive low-balance
alert, sent before a scheduled transaction attempts, lifted that rate?

Nudge-driven behavior change is inherently harder to predict than a
system fix, so the assumption is kept deliberately modest (a few
percentage points, not tens):

| Assumption | Lift | Recovered value | Recovered transactions |
|---|---|---|---|
| Conservative | +5pp | $17,739.10 | ~72 |
| **Moderate (used in Scenario E)** | **+10pp** | **$35,478.21** | **~144** |
| Optimistic | +15pp | $53,217.31 | ~216 |

Base: $354,782.06 still-unrecovered value, 1,440 transactions
(`business-impact-model.md` Section 3, via `10_business_impact.sql` Q1).

- **Customer impact:** touches a subset of the 2,044 distinct customers
  who have hit this reason at least once, with the small-business
  segment (`root-cause-analysis.md` Section 6: $1,102 avg failed-txn value
  vs. $127 retail) the highest-value slice to reach first.
- **Operational impact:** a notification/messaging feature build, plus a
  mandatory Compliance review pass (`recovery-intelligence.md` Section 2
  already flagged this — messaging that reads like an overdraft offer is
  a regulatory question, not just a product one).

## 5. Scenario D — Engineering Improvements (extending a pattern already proven once)

**What this targets:** `BALANCE_DECLINED_STALE_READ` — root-caused in
Phase 11 as a genuine race condition (a balance check reading stale data
under concurrent load), the same *kind* of fixable internal defect as
`PROCESSING_ERROR`, whose Phase 8 "engineering fix" already produced a
real, observed result: a 65.4% reduction in per-day rate after day 55
((4.48 − 1.55) / 4.48; `root-cause-analysis.md` Section 8).

This scenario is conceptually different from B and C: it doesn't recover
transactions that already failed, it **prevents some from failing at
all** going forward. That's a distinct kind of benefit and is kept in its
own row rather than summed into "recovered value" as if it were the same
thing.

| Assumption | Reduction | Failure events avoided | Value avoided |
|---|---|---|---|
| **Applied (only one modeled — this is a specific proven benchmark, not a range)** | 65.4% (the actual day-55 `PROCESSING_ERROR` result) | ~375 of 574 | **~$80,462** |

Base: 574 failure events, $123,027.57 associated value
(`sql/query-results.md`, `03_failure_analysis.sql` Q1 / `07_financial_impact.sql`
Q4-adjacent per-reason figures). Unlike B and C, only one rate is shown
here because it isn't a guess — it's the one reduction rate this dataset
has already demonstrated actually happening, applied to a second,
structurally similar defect. A range would imply more uncertainty than
this particular assumption actually carries relative to B and C.

- **Customer impact:** reduces failures for a subset of the 558 distinct
  customers who have hit this reason.
- **Operational impact:** one engineering fix, following the same
  find-fix-verify pattern already used once successfully — the lowest
  operational burden of any scenario in this model, precisely because
  it's not new.

## 6. Scenario E — Combined Strategy

Sums the **moderate** case from B and C plus D's applied case. This
addition is valid because the three scenarios touch three non-overlapping
reasons (`RAIL_DECLINED_ISSUER`, `BALANCE_DECLINED_INSUFFICIENT_FUNDS`,
`BALANCE_DECLINED_STALE_READ`) — no transaction is counted in more than
one scenario's benefit.

| Scenario | Recovered / avoided value | Transactions / events |
|---|---|---|
| B (moderate, 40%) | $146,696.61 | ~585 transactions |
| C (moderate, +10pp) | $35,478.21 | ~144 transactions |
| D (applied, 65.4%) | ~$80,462 | ~375 events |
| **Combined (E)** | **~$262,637** | — (different units, not summed) |

- **Customer impact:** touches distinct, mostly non-overlapping customer
  sets across the three reasons (a customer *could* appear in more than
  one, but this model doesn't attempt to de-duplicate across reasons —
  stated as a simplification, not resolved).
- **Operational impact:** the combined build is one Engineering
  instrumentation project (B), one product/Compliance-reviewed messaging
  feature (C), and one code fix (D) — three distinct, modest-scope work
  items rather than one large undertaking, which is itself worth stating
  plainly to whoever scopes this for delivery.

## 7. Side-by-side comparison

| | A: No Action | B: Auto-Retry (moderate) | C: Customer Intervention (moderate) | D: Engineering | E: Combined |
|---|---|---|---|---|---|
| Value recovered/avoided | $0 (baseline) | $146,696.61 | $35,478.21 | ~$80,462 | ~$262,637 |
| Txns/events affected | 0 | ~585 | ~144 | ~375 | ~1,104 |
| New build required | None | Retry instrumentation | Nudge feature + Compliance review | One code fix | All three |
| Confidence relative to others in this model | — (fact, not a scenario) | Medium (benchmarked off a similar reason) | Lower (behavioral, no precedent in data) | **Highest** (proven pattern, applied once already) | Mixed — inherits each component's confidence |

## 8. What this phase deliberately does not do

- **No scenario touches `RISK_HELD`.** Its $499,605 estimate already has
  its own, better-grounded treatment in `business-impact-model.md`
  (a direct benchmark against this dataset's own 90.32% mature-mechanism
  rate) — restating it as a "scenario" here would understate how solid
  that particular number already is relative to B/C/D's more speculative
  assumptions.
- **No dollar figure is put on the Engineering build costs** for B, C, or
  D. Sizing engineering effort (story points, headcount-weeks) is outside
  a Business Analyst-level deliverable and would need Engineering Lead
  input this project's data can't supply — named as a gap, not guessed at.
- **No probability or confidence interval is attached to any number.**
  The Confidence row in Section 7 is qualitative for the same reason —
  assigning a false precision (e.g., "72% confidence") to an assumption
  with no statistical basis would be worse than stating it plainly in
  words.

## 9. Open items carried forward

1. Scenario B and D both depend on Engineering scoping work this project
   hasn't done and can't do from data alone.
2. Scenario C's messaging design needs the Compliance review flagged in
   Phase 12 before it becomes a real recommendation, not just a modeled
   number.
3. Phase 16 (Business Recommendations) should present Scenario E's
   combined case as the primary recommendation, with B/C/D as
   independently adoptable components — not an all-or-nothing package —
   since nothing in this model requires them to ship together.
