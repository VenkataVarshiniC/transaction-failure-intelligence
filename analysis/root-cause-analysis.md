# Root-Cause Analysis

**Phase 11 of 20 — Bank Transaction Failure Intelligence & Recovery Optimization**

## 1. Purpose and scope

Phase 10 answered *what* is failing, *how much*, and *where* — 33 SQL
queries against the real dataset, captured in `sql/query-results.md`. This
phase does not repeat that work. It synthesizes it into a structured
root-cause analysis per the master brief's Section 15 requirement: not a
bar chart of failure reasons, but an explanation of *why* each cause happens, and
which causes are high-frequency, high-financial-impact, highly
recoverable, operationally expensive, and strategically important.

Every number below is either quoted directly from `sql/query-results.md`
(Phase 10, real output) or computed from it with simple arithmetic shown
inline. Nothing here is a new query result — this phase is interpretation,
not re-analysis. Where a claim would require evidence Phase 10 doesn't
have (a genuine causal mechanism, not just a correlation), it is labeled
as such rather than asserted.

**Methodology — six lenses, each already represented in the Phase 10 SQL:**

| Lens | Source query | What it isolates |
|---|---|---|
| Pareto / volume concentration | `03_failure_analysis.sql` Q1 | Which reasons dominate raw failure count |
| Process-stage | `03_failure_analysis.sql` Q2 | Where in the 10-stage lifecycle failures cluster |
| Category / origin | `03_failure_analysis.sql` Q3 | People/Process/Technology/Policy/Risk/External split, and internal-vs-external ownership (BR-02) |
| Channel | `04_channel_analysis.sql` Q1-Q4 | Whether failure is channel-specific or systemic |
| Temporal | `03_failure_analysis.sql` Q4a/Q4b/Q5 | Whether failure rate is stable or event-driven (stress windows, a fix rollout) |
| Customer-level | `05_customer_analysis.sql` Q1-Q4 | Whether failure is spread evenly or concentrated in a cohort |

## 2. Root-cause category framework

`failure_reasons.category` (`data-dictionary.md` Section 5) defines six
categories. One observation before going further: **the `People` category
exists in the enum but zero of the 13 failure reasons in this dataset are
tagged `People`.** That's worth naming rather than quietly leaving
unexplained. It is not a bug — this failure taxonomy models system,
rail, and policy-level declines in an automated payment pipeline, not
frontline staff error (a teller keying the wrong amount, a call-center
agent misclassifying a dispute). Those exist at a bank, but they sit
outside the transaction-lifecycle boundary this project scoped in
`business-case.md` Section 5. Flagging it here as a stated scope boundary,
not fixing it by inventing a `People`-tagged reason just to fill the enum.

| Category | Reasons in this dataset | Origin |
|---|---|---|
| Process | `VALIDATION_FAILED`, `BALANCE_DECLINED_INSUFFICIENT_FUNDS` | internal |
| Technology | `CLIENT_INIT_FAILURE`, `AUTH_FAILED`, `RISK_ENGINE_TIMEOUT`, `BALANCE_DECLINED_STALE_READ`, `PROCESSING_ERROR` | internal |
| Risk | `RISK_HELD` | internal |
| Policy | `ACCOUNT_RESTRICTED_DECLINE` | internal |
| External Dependency | `RAIL_DECLINED_ISSUER`, `RAIL_TIMEOUT`, `RAIL_OUTAGE` | external |
| Unclassified | `UNCLASSIFIED` (FR-00 sentinel, Phase 9) | unknown |
| People | *(none)* | — |

## 3. Cross-cutting finding: how much of this is even Kestrel's to fix (BR-02)

From `03_failure_analysis.sql` Q3, grouping the internal-origin categories
(Process + Technology + Risk + Policy) against External Dependency:

- Internal-origin: 3,382 + 2,670 + 2,038 + 213 = **8,303 failure events (77.8%)**
- External-origin: **2,356 failure events (22.1%)**
- Unclassified: 18 events (0.2%)

This is the single most important framing number in this phase. Roughly
four out of five failures are something Kestrel's own systems, policies,
or risk logic produced — not something an external rail or issuer did to
Kestrel. That reframes the narrative from "our payment partners are
unreliable" to "our own pipeline is the majority of the problem," which
is a more actionable (if less comfortable) starting point for Phase 16's
recommendations. `04_channel_analysis.sql` Q3 shows the same split by
value: external-owned rails carry $2.49M of the $2.60M in total failed
value (95.7%) versus $111K on Kestrel's own internal ledger rail — because
`p2p` (internal-ledger, 4.59% failure rate) is both the lowest-failure-rate
and lowest-average-value transaction type, while every other type routes
over an external rail. So external rails still dominate *dollars at risk*
even though they're the *minority* of failure *events* — two different
questions, both worth asking, and the SQL to distinguish them (Q3 in 04)
already exists for exactly this reason.

## 4. Volume vs. financial-impact divergence

Section 13 of the master brief asks directly: *do high-volume and
high-impact causes differ?* `07_financial_impact.sql` Q4 answers this at
the category level:

| Category | Volume rank | Value rank | Divergence |
|---|---|---|---|
| Risk | 4th (2,038 events) | **1st** ($725,635) | Under-prioritized by a volume-only view |
| Process | **1st** (3,382 events) | 2nd ($700,810) | Roughly proportional |
| External Dependency | 3rd | 3rd | Proportional |
| Technology | 2nd | 4th | Over-weighted by a volume-only view |
| Policy | 5th | 5th | Proportional |

`Risk` is the clearest case: it's the 4th-most-frequent category but the
single largest dollar exposure. The mechanism is straightforward and
observable in the data, not just asserted — `RISK_HELD` fires on
higher-value transactions more often than low-value ones by construction
of the risk-screening stage (a $50 P2P transfer and a $15,000 wire don't
carry the same fraud-review weight), so its average failed-transaction
value pulls the category's total up even with fewer events. This is
exactly the kind of cause a purely frequency-sorted "top failure reasons"
bar chart would under-rank — which is precisely why `08_prioritization.sql`
weights financial impact and volume separately (30%/30%) rather than
using volume alone, and why `RISK_HELD` lands at priority rank #1 despite
being #2 by raw event count.

## 5. Process-stage lens

`03_failure_analysis.sql` Q2, cross-referenced against the 10-stage model
in `process-analysis.md`:

| Stage | Name | Failure events | % of failures | Reasons |
|---|---|---|---|---|
| 5 | Balance / Account Validation | 3,218 | 30.1% | `BALANCE_DECLINED_INSUFFICIENT_FUNDS`, `BALANCE_DECLINED_STALE_READ`, `ACCOUNT_RESTRICTED_DECLINE` |
| 4 | Risk & Fraud Screening | 2,439 | 22.8% | `RISK_HELD`, `RISK_ENGINE_TIMEOUT` |
| 7 | External Network Response | 2,363 | 22.1% | `RAIL_DECLINED_ISSUER`, `RAIL_TIMEOUT`, `RAIL_OUTAGE` |
| 3 | Request Validation | 955 | 8.9% | `VALIDATION_FAILED` |
| 2 | Authentication | 836 | 7.8% | `AUTH_FAILED` |
| 1 | Transaction Initiated | 590 | 5.5% | `CLIENT_INIT_FAILURE` |
| 6 | Payment Processing & Rail Submission | 276 | 2.6% | `PROCESSING_ERROR` |

Three stages — Balance/Account Validation, Risk Screening, and External
Network Response — account for **75% of all failures** between them. That
concentration is itself a finding worth stating plainly: this is not a
transaction pipeline with failure spread evenly across ten stages: it is
a pipeline with three specific chokepoints, which means monitoring,
alerting, and remediation investment should concentrate there rather than
spread evenly across the lifecycle. Stages 8-10 (Outcome Determination,
Retry/Recovery, Final Outcome) generate no failure events by construction
— they consume the outcome of stages 1-7 rather than producing new ones,
which is consistent with `data-architecture.md`'s event model.

## 6. Root cause by failure reason

For every reason: frequency (Pareto rank, `03` Q1), financial impact
(`07` Q4 category, `08` per-reason value), recoverability (`06` Q1/Q4,
labeled **observed** only where `recovery_attempts` rows actually exist —
see Section 9's data-limitation note for two reasons where they don't),
operational burden (whether it lands on the `Do Not Retry-Monitor` track,
which is the proxy `08_prioritization.sql` itself uses), and the combined
priority rank from `08`.

### RISK_HELD — priority rank #1

- **Frequency:** 2,038 events (19.1% of failures, Pareto rank #2)
- **Financial impact:** $725,635 in associated value — the single largest
  of any reason, and the reason `Risk` tops the category value ranking
  (Section 4 above)
- **Recoverability:** 40.79% observed (of 2,031 logged monitor attempts).
  Not zero — a real share of risk holds do get cleared — but well below
  the Auto-Retry-track reasons' 74-78% rates, consistent with the fact
  that clearing a risk hold usually needs a human or a secondary signal,
  not just a retry
- **Operational burden:** high — `Do Not Retry-Monitor`, meaning every
  held transaction sits in a manual/monitored queue
- **Root cause:** stage-4 risk screening (`process-analysis.md`) declines
  or holds a transaction when its risk score crosses a threshold. This is
  a *designed* control, not a bug — the business objective is fraud
  prevention, not zero friction — but a 19% share of all failures and the
  #1 dollar-value category means the threshold, or the speed of the
  secondary review, is worth revisiting. This is the clearest case in the
  dataset of a cause that is simultaneously frequent, expensive, and
  *not* purely a technical defect to "fix" — it's a policy/calibration
  question, which changes what Phase 16's recommendation for it should
  look like (review the threshold and clear-time SLA, not "add a retry").

### BALANCE_DECLINED_INSUFFICIENT_FUNDS — priority rank #2

- **Frequency:** 2,428 events (22.7%, Pareto rank #1 — the single most
  common failure reason in the dataset)
- **Financial impact:** $516,927
- **Recoverability:** 40.36% observed, via `Customer Intervention` (2,416
  logged attempts) — the customer funds the account or retries later
- **Operational burden:** moderate — routed to the customer, not an
  internal queue, but every occurrence is a customer-facing failure
  moment
- **Root cause:** this is not a system defect at all — a transaction was
  correctly declined because the account did not have sufficient funds at
  that moment. The "cause" to investigate here isn't the decline logic,
  it's *why the customer initiated a transaction they couldn't cover* —
  `05_customer_analysis.sql` Q4 shows small-business accounts carry an
  average failed-transaction value of $1,102 versus $127 for retail,
  which is consistent with payroll and larger B2B transfers being more
  exposed to timing mismatches between cash inflow and a scheduled
  outflow than routine retail spending. That reframes the "fix" from a
  technical one to a product one (e.g., balance-aware scheduling nudges,
  overdraft-adjacent product options) — exactly the kind of insight a
  volume-only Pareto chart would miss, because it would just say "biggest
  bucket, go fix it" without asking whether "fix" even applies here.

### RAIL_DECLINED_ISSUER — priority rank #3

- **Frequency:** 1,462 events (13.7%, Pareto rank #3)
- **Financial impact:** $366,742
- **Recoverability:** **not observed** — see Section 9. This reason is
  tagged `Do Not Retry-Monitor` in the taxonomy, but the dataset contains
  zero logged `recovery_attempts` rows for it, so no recovery rate can be
  honestly reported.
- **Root cause:** the counterparty bank or card issuer on the other side
  of the transaction declined it — Kestrel's system did what it was
  supposed to do, and the decline originated entirely outside Kestrel's
  infrastructure (`origin = external`). This is genuinely not
  Kestrel-fixable at the individual-transaction level; the actionable
  lever is relationship-level (issuer connectivity quality, rail
  selection) rather than a code or policy change, which is why it still
  ranks #3 in priority despite being unfixable per-transaction — high
  volume and high value earn it a place on the list even though the
  remediation type is different in kind from the technology-category
  reasons below it.

### VALIDATION_FAILED — priority rank #4

- **Frequency:** 954 events (8.9%, Pareto rank #4)
- **Financial impact:** $183,883
- **Recoverability:** Not Applicable by design — a malformed or invalid
  request has nothing to retry; the same input would fail again
- **Root cause:** stage-3 request validation rejects malformed or
  logically invalid transaction requests (bad account reference, invalid
  amount format, missing required field) before any money movement is
  attempted. Because the failure is deterministic given the same input,
  the only real remediation is upstream: better client-side validation or
  clearer API/app error messaging so the customer doesn't resubmit the
  same broken request.

### CLIENT_INIT_FAILURE — priority rank #5

- **Frequency:** 590 events (5.5%, Pareto rank #7)
- **Financial impact:** $154,675
- **Recoverability:** Not Applicable by design — the request never
  reached Kestrel's backend, so there is nothing server-side to retry
- **Root cause:** app crash, dropped connection, or client-side timeout
  before the request left the device. This is the one reason in the
  dataset closest to a genuine "external to the transaction pipeline
  itself" cause — it's a client/network reliability question, not a
  backend one, and the fix (if any) is a mobile/web engineering
  investment outside this project's data architecture boundary.

### ACCOUNT_RESTRICTED_DECLINE — priority rank #6

- **Frequency:** 213 events (2.0%, Pareto rank #11)
- **Financial impact:** $38,145
- **Recoverability:** **not observed** (same data-limitation as
  `RAIL_DECLINED_ISSUER`, see Section 9)
- **Root cause:** the source account carries a restriction (frozen,
  under review) at the account level, independent of the specific
  transaction. Low volume, but a `Policy`-category cause means it's a
  compliance/operations decision rather than a technical one — an
  intentional block, not a defect.

### PROCESSING_ERROR — priority rank #7

- **Frequency:** 276 events (2.6%, Pareto rank #10)
- **Financial impact:** $42,252
- **Recoverability:** Not Applicable at the individual-transaction level
  by design — `Engineering Fix` is a systemic remediation track (fix the
  code, not retry the transaction), so it produces no per-transaction
  `recovery_attempts` rows, unlike the reasons above where the absence of
  attempts is a gap
- **Root cause:** this is the reason behind the temporal case study in
  Section 8 below — an internal orchestration/routing defect at stage 6,
  with a clear before/after rate change partway through the observation
  window consistent with an engineering fix landing.

### AUTH_FAILED — priority rank #8

- **Frequency:** 833 events (7.8%, Pareto rank #5)
- **Financial impact:** $133,296
- **Recoverability:** 74.70% observed (998 attempts) — the highest
  Auto-Retry volume of any reason and a strong recovery rate, consistent
  with most auth failures being transient (expired token, session race
  condition) rather than a genuine credential problem
- **Root cause:** stage-2 authentication/session failure at transaction
  time. High recoverability plus moderate volume is exactly the profile
  Auto-Retry exists for — this is a "working as intended" recovery
  story more than an open problem.

### RAIL_TIMEOUT — priority rank #9

- **Frequency:** 723 events (6.8%, Pareto rank #6)
- **Financial impact:** $177,610
- **Recoverability:** 77.59% observed (832 attempts) — the best-recovering
  reason with meaningful volume
- **Root cause:** the external rail didn't respond within SLA. Its high
  recovery rate is consistent with a timeout being a transient network
  condition rather than a hard decline — retrying a moment later usually
  succeeds. Section 8 covers this reason's day-specific spike pattern.

### BALANCE_DECLINED_STALE_READ — priority rank #10

- **Frequency:** 574 events (5.4%, Pareto rank #8)
- **Financial impact:** $123,028
- **Recoverability:** 75.70% observed (675 attempts)
- **Root cause:** the balance check at stage 5 used an out-of-date read
  (a race condition between a concurrent debit and the balance lookup),
  not a genuine insufficient-funds condition — which is exactly why it
  recovers well on retry: a fresh read usually clears it. This is a
  `Technology` category cause that looks superficially similar to
  `BALANCE_DECLINED_INSUFFICIENT_FUNDS` (same lifecycle stage) but has an
  entirely different root cause and remediation (fix the read-consistency
  guarantee, not "ask the customer to add funds") — a good example of why
  process-stage alone isn't a sufficient root-cause lens on its own.

### RISK_ENGINE_TIMEOUT — priority rank #12

- **Frequency:** 397 events (3.7%, Pareto rank #9)
- **Financial impact:** $78,527
- **Recoverability:** 77.01% observed (463 attempts)
- **Root cause:** the risk-scoring service failed to respond within SLA
  at stage 4 — an availability/performance problem in Kestrel's own risk
  infrastructure, distinct from `RISK_HELD` (which is the risk engine
  *working* and declining). High recovery rate confirms it's usually a
  transient service blip rather than a persistent outage.

### RAIL_OUTAGE — priority rank #11

- **Frequency:** 171 events (1.6%, Pareto rank #12)
- **Financial impact:** $58,417
- **Recoverability:** 91.76% observed (170 attempts) — the highest
  recovery rate of any reason in the dataset
- **Root cause:** the external rail reported a full service outage rather
  than a timeout. Counterintuitively the *best*-recovering reason,
  because an outage is binary and temporary — once the rail is back, a
  monitored retry succeeds almost every time, unlike issuer declines
  which reflect a standing judgment that a retry won't change.

### UNCLASSIFIED (FR-00) — priority rank #13

- **Frequency:** 18 events, 0.17% — the Phase 9 sentinel row absorbing
  transaction_events that referenced a `failure_reason_id` not present in
  the standard taxonomy at extract time (`data-quality-report.md`). Not a
  real business cause — an intentionally small, honestly-labeled data
  artifact of the cleaning process, kept visible rather than merged into
  another category or dropped.

## 7. Temporal case study 1: the RTP stress-window investigation

`03_failure_analysis.sql` Q4a tried the most obvious temporal cut first —
bucket every RTP-rail transaction across the full 90-day window by
hour-of-day (midday/afternoon vs. the rest) and compare rail-timeout/outage
rates. The real result: 0.72% (other hours) vs. 0.69% (midday/afternoon)
— **no signal.** That's not a failed analysis; it's a finding that gets
kept rather than quietly dropped, because it tells you something real:
averaging across all 90 days dilutes a rare event to invisibility.

Q4b re-cut the same question by calendar day instead — ranking every one
of the 90 days by its own RTP rail-issue rate, still without hard-coding
which days matter. Three days (2026-04-07, 2026-05-06, 2026-06-12) surface
near the top of that ranking, at roughly 1.5-2.7% versus 0.7-0.9% on
nearby days. Grouped as those 3 days vs. the other 87: **2.08% average
vs. 0.66% — a real ~3x elevation, concentrated on specific dates, not
specific hours.**

Root cause: this pattern is consistent with periodic RTP-network stress —
volume-driven congestion or a scheduled-maintenance-adjacent outage on the
external rail, similar in shape to real-world UPI volume-driven outage
incidents cited in `business-case.md` Section 1. Because `RAIL_TIMEOUT`
and `RAIL_OUTAGE` are both `External Dependency`/`external`-origin, this
is not something Kestrel's own engineering can patch — the actionable
takeaway is operational: day-level monitoring thresholds and a
pre-negotiated escalation path with the rail provider for these specific
kinds of spikes, rather than a flat alert threshold that a hidden 3-day
pattern would never trip.

**Methodology note, stated plainly:** the fact that a naive hourly cut
found nothing while a daily cut found a real pattern is a genuine
analytical lesson, not a cosmetic detail — the first query design being
wrong doesn't mean the underlying pattern doesn't exist, and the fix was
to change the slicing granularity, not to keep re-running the same cut
hoping for a different answer.

## 8. Temporal case study 2: the day-55 engineering-fix signal

`03_failure_analysis.sql` Q5 splits the window into before/after day 55
and compares `PROCESSING_ERROR`'s *per-day* rate (not raw count, since the
two periods are different lengths): **4.48/day before, 1.55/day after** —
a ~65% reduction that holds up even after normalizing for period length.

Root cause: `PROCESSING_ERROR` is a `Technology`/internal-origin cause at
stage 6 (Payment Processing & Rail Submission) — squarely inside
Kestrel's own orchestration logic, unlike the external-rail reasons above.
A sustained, dated drop in an internal-origin technical failure rate is
consistent with an internal engineering fix landing partway through the
window — this is the one pattern in the dataset where the appropriate
"why" is organizational, not systemic: something Kestrel's engineering
team changed, not something that happened to them.

## 9. Data limitation noted during this phase

`RAIL_DECLINED_ISSUER` (1,462 failure events) and `ACCOUNT_RESTRICTED_DECLINE`
(213 events) are both tagged `default_recovery_track = Do Not Retry-Monitor`
in `failure_reasons.csv` — the same track as `RISK_HELD` and `RAIL_OUTAGE`,
both of which *do* have well-populated `recovery_attempts` records (99.7%
and 99.4% coverage respectively). These two reasons have **zero** logged
recovery attempts despite sharing the same track designation. That's an
inconsistency in how `scripts/generate_dataset.py` populated the recovery
layer for the `Do Not Retry-Monitor` track — not a business fact about
these reasons' true recoverability, and not something to paper over with
an invented rate. It's called out here, in `data-dictionary.md`'s
assumptions, and flagged as a known follow-up: revisiting the generator's
monitor-track logic, if this project regenerates data in a later phase,
so every `Do Not Retry-Monitor` reason gets consistent (even if sparse)
attempt records. Until then, any claim about these two reasons' recovery
rate is explicitly "not observed," not "0%" — those are different claims
and this project keeps them distinct throughout.

## 10. Customer and channel lens, briefly

Two findings from Phase 10 belong in a root-cause synthesis because they
change *who* a remediation should target, not just *what* the remediation
is:

- **Failure is concentrated, not evenly spread.** `05_customer_analysis.sql`
  Q1: 56.2% of affected customers see exactly one failure, but 8.9% see
  four or more — a small, identifiable cohort carrying a disproportionate
  share of repeat-failure volume. Combined with the segment split (Q3:
  Small-Business 6.82% failure rate vs. Retail-Standard 5.78%) and the
  per-failure stakes gap (Q4: $1,102 avg for small-business vs. $127 for
  retail), the highest-leverage customer-facing intervention is not a
  blanket UX change but a targeted one aimed at repeat-failure
  small-business accounts specifically.
- **Failure rate is close to flat across channels** (`04` Q1: 5.81%-6.68%,
  a ~0.9-point spread) **but financial exposure is not** (Q2: mobile_app
  carries $1.01M in failed value simply because it carries the most
  volume). Channel is a weak root-cause lens on its own here — the
  channel×type cross-tab (Q4) is more useful: `payroll` is the weakest
  transaction type across three of four channels, which points back to
  the small-business/payroll finding above rather than to any one channel
  being technically worse than another.

## 11. Correlation vs. causation — stated explicitly

Per `business-case.md`'s realism constraints (master brief Section 31):
none of the patterns above are proven causal mechanisms in the way a
production incident postmortem with logs and a code diff would be. Two
different epistemic statuses are mixed in this document, and it matters
to keep them apart:

- The **day-55 processing-error drop** and the **RTP stress-day
  elevation** are *temporal associations* — a rate that changed at a
  specific point, or that clusters on specific dates. That a plausible
  cause (an engineering fix; an external rail's periodic stress) is
  consistent with the pattern is not proof of that specific cause; a real
  investigation would need deploy logs or a rail-provider status page to
  confirm it. This project is transparent that, because the dataset is
  synthetic and self-generated, `dataset-design.md` Section 3 *does*
  document the fix and the stress days as designed — an advantage no real
  analyst would have, used here only to confirm the analytical method
  worked, not treated as something the SQL "proved" on its own.
- The **category, stage, channel, and segment breakdowns** (Sections 3-6,
  10) are direct aggregations of what happened, not causal claims about
  a mechanism — "Risk category carries the most dollar exposure" is an
  observed fact; "the risk threshold is miscalibrated" (Section 3's
  framing) is an interpretation offered for Phase 16 to weigh, not a
  conclusion this phase asserts as settled.

## 12. Synthesized priority view

`08_prioritization.sql`'s weighted score already ranks every reason
(Section 6 above gives the per-reason narrative). Restating the top 5
with the remediation *type* each one actually calls for — since Section 3
and the per-reason notes above show that "high priority" does not mean
"same kind of fix":

| Rank | Reason | Priority score | Remediation type |
|---|---|---|---|
| 1 | `RISK_HELD` | 0.8547 | Policy/calibration review (threshold, review SLA) — not a technical fix |
| 2 | `BALANCE_DECLINED_INSUFFICIENT_FUNDS` | 0.7325 | Product/customer-facing (balance-aware nudges) — not a defect to patch |
| 3 | `RAIL_DECLINED_ISSUER` | 0.6943 | External relationship management — not Kestrel-fixable per-transaction |
| 4 | `VALIDATION_FAILED` | 0.4341 | Upstream client/API validation and messaging |
| 5 | `CLIENT_INIT_FAILURE` | 0.3606 | Client/network engineering, outside this project's data boundary |

The pattern worth naming: **the five highest-priority causes span five
different remediation types.** A single generic recommendation ("improve
reliability") would not actually address any of them. That differentiation
is the direct input Phase 16 (Business Recommendations) needs, and Phase
12 (Recovery Intelligence) picks up specifically the reasons where a
retry/recovery mechanism is the right lever (`AUTH_FAILED`, `RAIL_TIMEOUT`,
`BALANCE_DECLINED_STALE_READ`, `RISK_ENGINE_TIMEOUT`, `RAIL_OUTAGE` — the
Auto-Retry-track reasons already shown to recover at 75-92%) rather than
re-litigating the ones above that don't call for a retry at all.

## 13. Open items carried to later phases

1. The `Do Not Retry-Monitor` recovery-attempt coverage gap (Section 9) —
   candidate fix if data is ever regenerated.
2. `RISK_HELD`'s threshold/SLA question is a policy recommendation input
   for Phase 16, not something this project can resolve with data alone —
   would need Risk & Compliance stakeholder input in a real setting
   (consistent with the veto power given to that stakeholder in
   `stakeholder-analysis.md`).
3. The stress-window and engineering-fix findings are confirmed against
   the known synthetic design (Section 11) — Phase 13/14's financial
   modeling should treat them as validated inputs, but the write-up
   should keep stating that the confirmation came from the generator's
   documented design, not from independent external evidence.
