# Business Recommendations

**Phase 16 of 20 — Bank Transaction Failure Intelligence & Recovery Optimization**

Covers master brief Sections 22 (Business Insights), 23 (Recommendation
Framework), and 25 (KPI Framework). Section 24 (Future-State Process) was
already delivered in Phase 5 (`future-state.md`) and isn't repeated here.

Every insight, recommendation, and baseline figure below cites the phase
and query it comes from. Every KPI target is explicitly labeled as a
stated planning assumption — none is presented as something the data
proves will happen (the same Observed/Estimated/Scenario discipline from
Phases 13-14, carried through to target-setting).

## 1. Business Insights

Ten insights, each in the Finding / Evidence / Business Impact /
Recommendation / Owner / KPI format the master brief specifies.

### Insight 1 — A small customer cohort drives most of the dollar problem

**Finding:** 21.6% of all customers (2,587 people) who fail more than
once account for 73.6% of all failed transaction value.
**Evidence:** `10_business_impact.sql` Q4 — $1,914,257.77 of $2,601,071.40
in observed failed value.
**Business Impact:** A uniform, across-the-board fix leaves most of the
dollar problem untouched; a cohort-targeted intervention has a
structurally larger ceiling.
**Recommendation:** Design recovery and outreach interventions to
identify and prioritize repeat-failure customers specifically, not just
failure *reasons*.
**Owner:** Product Manager, Payments & Transfers; Customer Support
Operations Lead.
**KPI:** Repeated Failure Rate (see KPI Framework, Section 3).

### Insight 2 — Most of the failure problem is Kestrel's own, not its rail partners'

**Finding:** ~78% of failure events are internal-origin (Process,
Technology, Risk, Policy); ~22% are external (rail/issuer).
**Evidence:** `03_failure_analysis.sql` Q3 — 8,303 of 10,677 events.
**Business Impact:** Reframes the narrative from "our payment partners
are unreliable" to "our own pipeline is the majority of the problem" —
a less comfortable but more actionable starting point.
**Recommendation:** Weight internal remediation (Insights 4, 7, 9, 10)
ahead of external rail-relationship work in near-term planning.
**Owner:** VP, Digital Operations (sponsor).
**KPI:** Internal-origin failure share (target: trend down as internal
fixes land).

### Insight 3 — The highest-frequency failure category isn't the highest-value one

**Finding:** the `Risk` category ranks 4th by failure volume but 1st by
associated dollar value ($725,635).
**Evidence:** `07_financial_impact.sql` Q4.
**Business Impact:** A volume-only prioritization (a plain Pareto chart)
would under-rank the single largest financial exposure in the dataset.
**Recommendation:** Keep prioritization scoring weighted by both volume
*and* financial impact (`08_prioritization.sql`'s 30/30/20/10/10 model),
never volume alone.
**Owner:** Risk & Fraud Team Lead; Finance/FP&A.
**KPI:** Financial Exposure by category (KPI Framework, Section 4).

### Insight 4 — Observed data overturned one design-time assumption

**Finding:** `RAIL_OUTAGE` was tagged "Do Not Retry-Monitor" at design
time; its observed recovery rate is 91.76% — the highest of any reason.
**Evidence:** `recovery-intelligence.md` Section 3.
**Business Impact:** A conservative design-time assumption was actively
holding back a near-automatic recovery — a small but real, already-proven
value leak.
**Recommendation:** Reclassify `RAIL_OUTAGE` to auto-retry-eligible in
the live routing logic (not just the analysis) — this is the one
recommendation in this document that requires no new build, only a
configuration change.
**Owner:** Operations Manager, Payments; Engineering Lead, Payments
Platform.
**KPI:** `RAIL_OUTAGE` recovery rate (target: sustain ≥85% once automated).

### Insight 5 — The single largest recovery opportunity is concentrated in just 2 of 13 reasons

**Finding:** `RISK_HELD` and `RAIL_DECLINED_ISSUER` together are only 2
of 13 failure reasons but carry 42% of all associated failed value
($1,092,377).
**Evidence:** `recovery-intelligence.md` Section 2.
**Business Impact:** Two focused workstreams (a Risk process review and
an Engineering instrumentation build) outweigh broad, diffuse effort
spread across all 13 reasons.
**Recommendation:** Sequence Recommendations R4 and R5 (Section 2 below)
ahead of lower-value, higher-effort work.
**Owner:** Risk & Fraud Team Lead; Engineering Lead, Payments Platform.
**KPI:** Potentially Recoverable Value (KPI Framework, Section 4).

### Insight 6 — A real instrumentation gap is quietly capping what this project (and Kestrel) can know

**Finding:** `RAIL_DECLINED_ISSUER` has zero logged recovery attempts
despite carrying $366,742 in value — not because it's unrecoverable, but
because nothing tracks whether it was ever tried.
**Evidence:** `business-impact-model.md` Section 3, `10_business_impact.sql` Q3.
**Business Impact:** No dollar estimate can responsibly be attached to
this reason until this is fixed — it's a data-quality problem blocking a
business decision, not just an analytics footnote.
**Recommendation:** Instrument recovery attempts for this reason before
attempting to size or pilot any recovery mechanism for it.
**Owner:** Engineering Lead, Payments Platform.
**KPI:** % of `RAIL_DECLINED_ISSUER` transactions with a logged recovery
attempt (baseline: 0%; target: fully instrumented).

### Insight 7 — Three process stages account for three-quarters of all failures

**Finding:** Balance/Account Validation (30.1%), Risk & Fraud Screening
(22.8%), and External Network Response (22.1%) together cover 75% of
failures; the other four lifecycle stages cover the remaining 25%.
**Evidence:** `root-cause-analysis.md` Section 5.
**Business Impact:** Monitoring and remediation investment should
concentrate at these three chokepoints, not spread evenly across the
10-stage lifecycle.
**Recommendation:** Any future monitoring/alerting build (Recommendation
R8) should prioritize instrumentation depth at these three stages first.
**Owner:** Engineering Lead, Payments Platform.
**KPI:** Failure share by lifecycle stage (tracked, not targeted to
change directly — this is a diagnostic KPI, not a lever).

### Insight 8 — A failed small-business transaction is worth 8.7x a failed retail one

**Finding:** small-business failed transactions average $1,101.72;
retail failed transactions average $126.81.
**Evidence:** `05_customer_analysis.sql` Q4.
**Business Impact:** Segment-blind prioritization treats a failed $50
P2P transfer the same as a failed payroll run — `stakeholder-analysis.md`
already named this exact gap for the Small-Business Customer segment.
**Recommendation:** Weight the Customer Intervention nudge (Recommendation
R6) toward small-business accounts first.
**Owner:** Product Manager, Payments & Transfers.
**KPI:** Avg. failed-transaction value by segment (tracked as a
prioritization input, not a target to move).

### Insight 9 — External rail risk clusters on specific days, not specific hours

**Finding:** an hour-of-day cut shows no stress-window signal (0.72% vs.
0.69%); a day-level cut shows the 3 highest-risk days run ~2.08% vs.
~0.66% elsewhere — a real ~3x elevation invisible to a flat, hourly
threshold.
**Evidence:** `root-cause-analysis.md` Section 7.
**Business Impact:** A monitoring threshold built on the "obvious" cut
(time-of-day) would never catch this pattern.
**Recommendation:** Build day-level, not just hour-level, alerting
thresholds for external rail risk (part of Recommendation R3).
**Owner:** Engineering Lead, Payments Platform.
**KPI:** RTP rail-issue rate, tracked at daily granularity.

### Insight 10 — An internal engineering fix already worked, once, for real

**Finding:** `PROCESSING_ERROR`'s per-day rate dropped ~65.4% (4.48 → 1.55)
after an internal fix landed around day 55 of the observation window.
**Evidence:** `root-cause-analysis.md` Section 8.
**Business Impact:** This isn't a hypothetical lever — it's the one
result in this entire project that already happened, not a projection.
**Recommendation:** Apply the same find-fix-verify pattern to
`BALANCE_DECLINED_STALE_READ`, the other reason root-caused as a fixable
internal race condition (Recommendation R7).
**Owner:** Engineering Lead, Payments Platform.
**KPI:** Stage-6/Technology-category internal defect rate, per-day trend.

## 2. Recommendation Framework

Nine recommendations across three horizons, each traceable to an insight
above or a Phase 12-14 deliverable.

### Immediate (0-30 days)

| # | Action | Business Rationale | Owner | Effort | Expected Impact | Risk | KPI |
|---|---|---|---|---|---|---|---|
| R1 | Instrument recovery attempts for `RAIL_DECLINED_ISSUER` | Closes the gap blocking any real estimate for $366,742 in value (Insight 6) | Engineering Lead, Payments Platform | Low — telemetry addition, not new business logic | Enables — unlocks future estimation, not itself a dollar recovery | Low | % instrumented (0% → 100%) |
| R2 | Reclassify `RAIL_OUTAGE` to auto-retry-eligible in live routing | Observed 91.76% recovery already proves this; only the design-time tag hasn't caught up (Insight 4) | Operations Manager, Payments + Engineering Lead | Low — config change, mechanism already exists | ~$58,417 in value moves to faster, lower-effort recovery | Low | `RAIL_OUTAGE` recovery rate, resolution time |
| R3 | Build day-level (not just hourly) RTP rail monitoring thresholds | Hourly cuts miss the real stress-day pattern (Insight 9) | Engineering Lead, Payments Platform | Low-Medium | Faster detection of the next stress episode; not itself a recovery | Low | Time-to-detection for a stress day |

### Short-Term (1-3 months)

| # | Action | Business Rationale | Owner | Effort | Expected Impact | Risk | KPI |
|---|---|---|---|---|---|---|---|
| R4 | Review `RISK_HELD`'s clearance threshold and SLA with Risk & Fraud | Largest single dollar lever in this project — ~$451,243 estimated (`business-impact-model.md` Section 3) | Risk & Fraud Team Lead; Compliance/Legal informed | Medium — policy/process review, not a large build | High — ~$451K estimated, benchmarked against this dataset's own proven 90.32% rate | Medium-High if rushed — this control exists to prevent fraud exposure (the Synapse-Evolve pattern cited in `business-case.md`); needs Compliance sign-off, not a fast unilateral change | Risk-hold median clearance time; `RISK_HELD` recovery rate |
| R5 | Build automated retry for `RAIL_DECLINED_ISSUER`; pilot at the moderate (40%) rate | Second-largest lever in the Investigate bucket (Insight 5); Scenario B, `whatif-simulation.md` Section 3 | Engineering Lead, Payments Platform | Medium | Medium-High — ~$146,697 (moderate scenario) | Medium — depends on R1 landing first | `RAIL_DECLINED_ISSUER` recovery rate (baseline: unmeasurable → target: matches pilot rate) |
| R6 | Design and Compliance-review a proactive low-balance nudge, prioritized for small-business accounts | Customer-driven recovery already happens at 40.45% with no active mechanism (Insight 1, 8); Scenario C, `whatif-simulation.md` Section 4 | Product Manager, Payments & Transfers; Compliance/Legal | Medium — feature build + mandatory compliance review | Medium — ~$35,478 (moderate scenario), concentrated in the highest-stakes segment | Medium — messaging that reads like an overdraft offer is a regulatory question (`recovery-intelligence.md` Section 2) | `BALANCE_DECLINED_INSUFFICIENT_FUNDS` recovery rate |

### Medium-Term (3-6 months)

| # | Action | Business Rationale | Owner | Effort | Expected Impact | Risk | KPI |
|---|---|---|---|---|---|---|---|
| R7 | Apply the proven engineering-fix pattern to `BALANCE_DECLINED_STALE_READ` | The one scenario built on an already-proven rate, not a guess (Insight 10); Scenario D, `whatif-simulation.md` Section 5 | Engineering Lead, Payments Platform | Medium — a real code fix + before/after verification cycle | Medium, **highest confidence** of any recommendation — ~$80,462 avoided | Low | Stage-5 stale-read failure rate, per-day trend |
| R8 | Productionize the Recovery Opportunity Engine and Decision Simulator (Phases 12, 15) into a standing operational tool | Turns a one-time analysis into ongoing operating infrastructure — directly addresses the Operations Manager's stated pain point ("reacts to alerts with no way to tell a high-impact failure from a low-impact one," `stakeholder-analysis.md`) | VP, Digital Operations (sponsor); Operations Manager, Payments | High — real engineering build, ongoing maintenance | High — compounding, ongoing value vs. a one-time report | Medium — requires sustained investment, not a one-time win | Dashboard adoption / weekly active use by Operations |
| R9 | Establish the KPI Framework (Section 3 below) as a standing monthly operating review | Prevents the gains from R1-R8 eroding back to reactive, ticket-by-ticket triage | VP, Digital Operations; Senior Management | Low-Medium — a process/cadence change | High — sustains every other recommendation's impact | Low | Review cadence adherence (qualitative) |

### Impact vs. Effort matrix

```
High Impact  |  R2 (quick win)         |  R4, R5, R8  (invest)
             |  R1, R9 (enabling)      |
-------------|-------------------------|---------------------------
Low Impact   |  R3 (do anyway)         |  R6, R7 (worth it, not urgent)
             |
             +-------------------------+---------------------------
               Low Effort                High Effort
```

Reading this matrix plainly: **R2 and R4 are the two recommendations
worth acting on first** — R2 because it's nearly free (a config change)
and R4 because it's the single largest dollar lever in the whole project,
even though it takes more care to execute correctly (Risk/Compliance
sign-off, not a fast unilateral change).

## 3. KPI Framework

Every target below is a **stated planning assumption** — directional,
not a data-derived prediction. None is a mechanical sum of Phase 13/14's
individual scenario estimates (stacking several already-speculative
numbers would manufacture false precision); each is a round, defensible
number chosen to be ambitious but plausible if the Section 2
recommendations are substantially adopted.

### Executive KPIs

| KPI | Formula | Business Meaning | Target | Owner | Frequency |
|---|---|---|---|---|---|
| Transaction Success Rate (ultimate) | (success + recovered_success) / total transactions | Share of all transactions that end in the customer's money moving successfully, including after recovery | Baseline 96.42% → **97.5%** within 6 months | VP, Digital Operations | Monthly |
| Failure Rate | (total − success) / total | Headline "how often does this happen" number | Baseline 5.93% → **<5.5%** within 6 months | VP, Digital Operations | Monthly |
| Failed Transaction Value | Sum of amount where final_status ≠ success | Dollar exposure, not just event count | Baseline 6.83% of total value → **<6.0%** within 6 months | Finance/FP&A | Monthly |
| Recovery Rate | recovered_success / (recovered_success + permanently_failed) | Of transactions that ever entered a failed state, what share was ultimately saved | Baseline 39.79% → **45-48%** within 6 months | Operations Manager, Payments | Monthly |

### Operational KPIs

| KPI | Formula | Business Meaning | Target | Owner | Frequency |
|---|---|---|---|---|---|
| Retry Success Rate (Auto-Retry track) | recovered / total Auto-Retry attempts | Health of the already-mature automated mechanism | Baseline ~90.3% (transaction-level) → **sustain ≥90%** (a maintain, not grow, target) | Engineering Lead, Payments Platform | Weekly |
| Average Recovery Time (Do Not Retry-Monitor track) | AVG(completed_at − initiated_at) | How long a risk-held/monitored transaction sits before resolution | Baseline ~35,832 sec (~10 hrs) → **-20%** within 6 months, tied to R4 | Risk & Fraud Team Lead | Weekly |
| Repeated Failure Rate | Customers with 2+ failures / all customers | Concentration of the repeat-failure cohort (Insight 1) | Baseline 21.6% → **<18%** within 6 months | Operations Manager, Payments | Weekly |
| Failure Rate by Channel | Channel-level failure rate | Detects a channel becoming a new weak point | Baseline range 5.81-6.68% → **narrow the spread**, bring `api` (highest) toward `mobile_app` (lowest) | Engineering Lead, Payments Platform | Weekly |

### Customer KPIs

| KPI | Formula | Business Meaning | Target | Owner | Frequency |
|---|---|---|---|---|---|
| Customers Affected | DISTINCTCOUNT(customer) where any transaction failed | Breadth of the problem | Baseline 49.2% → **<45%** within 6 months | Customer Support Operations Lead | Monthly |
| Repeat Failure Customers | Customers with 2+ failures (count) | The cohort Insight 1 says to target directly | Baseline 2,587 → **<2,200** within 6 months | Product Manager, Payments & Transfers | Monthly |
| Customer Intervention Rate | recovered / total for the Customer Intervention track | Effectiveness of customer-driven recovery, pre/post the R6 nudge | Baseline 40.45% → **50.45%** (Scenario C moderate case) within 6 months | Product Manager, Payments & Transfers | Monthly |

### Financial KPIs

| KPI | Formula | Business Meaning | Target | Owner | Frequency |
|---|---|---|---|---|---|
| Potentially Recoverable Value | Sum of still-unrecovered value in recovery-eligible categories | The size of the addressable opportunity (`business-impact-model.md` Section 3) | Baseline $1,264,295 → **convert ≥35% (~$442K) to Recovered Value** within 6 months | Finance/FP&A | Monthly |
| Recovered Value | Sum of amount where final_status = recovered_success | What's actually been saved | Baseline $916,896 → **+$300K-450K** within 6 months (a range, reflecting R4/R5/R6/R7's differing confidence levels rather than one falsely precise number) | Finance/FP&A | Monthly |
| Financial Exposure | Failed value as $ and % of total transaction value | Overall risk-in-dollars headline for Senior Management | Baseline $2,603,613 (6.83%) → **<6.0%** within 6 months | Senior Management (COO/CEO) | Monthly |

## 4. Open items

1. R4 (the largest single lever) explicitly needs Risk & Fraud and
   Compliance sign-off before execution — this document recommends the
   review happen, not a specific threshold change, consistent with this
   project's data alone being insufficient to set fraud-control policy.
2. Every KPI target above assumes "substantial adoption" of the paired
   recommendation — none accounts for partial adoption, and a future
   monthly review (R9) is exactly where that gets recalibrated with real
   post-launch data instead of this document's planning assumptions.
3. Recovered Value's $300K-450K range roughly brackets R4+R5+R6+R7's
   individual estimates/scenarios summed (~$451K + $147K + $35K + $80K ≈
   $713K at the high end) discounted for partial adoption and execution
   risk — stated here explicitly as a judgment call, not a formula, so a
   future reviewer can see the reasoning rather than just the number.
