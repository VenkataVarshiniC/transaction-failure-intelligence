# Synthetic Dataset Design

**Phase:** 8 of 20 — Synthetic Dataset Design
**Depends on:** [data-dictionary.md](./data-dictionary.md)

---

## 1. A Note on the Kaggle Search (Carried Over from the Prior Step)

Before designing a synthetic generator, we checked Kaggle for a real dataset that could be used directly. None of the candidates (PaySim, several bank/fraud-detection datasets, several UPI datasets) carry the transaction-*lifecycle*, failure-*reason*, or recovery-*attempt* data this project needs — they are flat, completed-transaction tables with at most a binary fraud label. That's expected: this is internal banking operational data that isn't published.

**What we did take from Kaggle:** [PaySim](https://www.kaggle.com/datasets/ealaxi/paysim1) — a peer-reviewed, widely used synthetic mobile-money simulator — as a **calibration reference**, not a data source. One practical limitation to be upfront about: this environment's network access does not reach kaggle.com, so we could not download the raw file and compute exact statistics from it ourselves. What we used instead is PaySim's publicly documented, citable structural characteristics:
- Five transaction types, with fraud/risk activity concentrated specifically in **transfer-type** transactions, not payment/purchase-type ones.
- Transaction amounts that follow a right-skewed distribution (consistent with financial transaction amounts generally), not a uniform or normal one.

Both facts are used below as **calibration inputs** to our own generation logic — informing *which transaction types get elevated risk-related failure rates* and *what shape the amount distribution takes* — not as literal statistics copied into our dataset. This distinction is deliberately spelled out because it matters for how defensible the "real-world-grounded" claim is if asked about it directly.

If stronger grounding is wanted later, the PaySim CSV (or its documented `value_counts()` output) can be attached to the conversation directly and this design revisited against the real numbers.

---

## 2. Volume Plan

| Entity | Target Row Count | Basis |
|---|---|---|
| Customer Segment | 3 | Retail-Standard, Retail-Premium, Small-Business (fixed lookup) |
| Channel | 4 | mobile_app, web, pos_atm, api (fixed lookup) |
| Payment Rail | 4 | card_network, ach, rtp, internal_ledger (fixed lookup) |
| Failure Reason | 12 | The controlled vocabulary from data-dictionary.md, Section 11 |
| Customer | ~12,000 | A representative analytical sample (business-case.md, Section 5) at roughly Kestrel's real retail:SMB ratio (~92:8) |
| Account | ~16,200 | Retail customers average ~1.3 accounts, small-business customers ~1.8 |
| Transaction | ~180,000 | Midpoint of the 100,000–250,000 target range (business-case.md, Section 4), over a 90-day window (~2,000/day average) |
| Transaction Event | ~640,000 (derived, not fixed) | Average ~3.6 events per transaction; failed/retried transactions generate more |
| Recovery Attempt | Derived from failure volume and recovery-track assignment (Section 5 below) | — |

---

## 3. Why the Data Isn't Purely Random

Section 11 of the master brief is explicit that random, IID failure generation would make the analysis trivial and unrealistic. Five deliberate, documented patterns are built into the generator:

1. **Channel affects failure type, not just failure rate.** `web` sessions get an elevated authentication/validation failure multiplier (older session-management code path); `pos_atm` gets elevated rail-related failures (direct card-network dependency); `api` (small-business integrations) gets elevated risk-screening and processing-error multipliers (newer, less-hardened integration surface).
2. **Transaction type affects risk-hold likelihood** (the PaySim-calibrated pattern): `wire`, `payroll`, `external_transfer`, and `rtp_transfer` carry a 1.6× risk-hold multiplier versus baseline; `card_pos` and `bill_pay` carry a 0.6× multiplier.
3. **A "problem cohort" of customers exists.** ~4% of customers are generated with a 3× multiplier across all failure types — representing (without a dedicated schema field) realistic causes like an outdated app version or a flagged account. This is what makes the repeat-failure customer analysis (BR-04, Phase 11) find a real pattern instead of noise.
4. **Two designed volume/outage events, modeled directly on the real-world inspiration (business-case.md, Section 1).** On three specific days within the 90-day window, transaction volume rises ~20% and, during a multi-hour window on those days, `rail_timeout` and `rail_outage` failures on the `rtp` rail spike 4×–8× — a direct, deliberate echo of the April 2025 UPI volume-driven outage pattern, not a generic random spike.
5. **A mid-window engineering fix.** `PROCESSING_ERROR` (Stage 6 — 100% internally caused, per process-analysis.md) is generated at an elevated rate for the first ~55 days of the window and drops sharply afterward, simulating a bug fix shipping partway through the period. This gives Phase 11's root-cause analysis a genuine before/after pattern to find, rather than a flat rate that has to be explained away as an assumption.

---

## 4. Stage Failure-Probability Model

Baseline probabilities (probability a transaction fails at a given stage, conditional on reaching it), before the multipliers in Section 3 are applied. These sum to an approximate 5% baseline overall failure rate — deliberately labeled as an assumption, not a benchmark, since business-case.md's own rule against inventing unexplained targets applies here too. 5% is set *above* the ~1–2% baseline decline rates commonly reported for mature real-time-payment networks (Paytm/NPCI reporting), because Kestrel is meant to represent the **pre-intervention** state this project exists to diagnose — a mature, well-optimized rate would leave nothing to find.

| Stage | Failure Reason | Baseline Probability |
|---|---|---|
| 1. Initiated | Client-side init failure | 0.30% |
| 2. Authentication | Auth failure | 0.40% |
| 3. Validation | Validation failure | 0.50% |
| 4. Risk Screening | Risk hold | 1.00% |
| 4. Risk Screening | Risk-engine timeout | 0.20% |
| 5. Balance Validation | Insufficient funds | 1.30% |
| 5. Balance Validation | Stale-balance decline | 0.30% |
| 5. Balance Validation | Account restricted | 0.15% |
| 6. Payment Processing | Processing error | 0.25% (pre-day-55) / 0.05% (post-day-55) |
| 7. External Network | Issuer decline | 1.00% |
| 7. External Network | Rail timeout | 0.50% (baseline) |
| 7. External Network | Rail outage | 0.10% (baseline) |

**Total baseline ≈ 5.0%.** Actual generated failure rate will differ slightly once channel, transaction-type, problem-cohort, and spike-day multipliers are applied — the exact realized figure is reported in Section 7 (Generation Output Summary) once the dataset is built, not asserted in advance.

---

## 5. Recovery Track Assignment and Outcome Model

Each `FailureReason` carries a `default_recovery_track` (data-dictionary.md, Section 9), which determines how the failure is handled after it occurs:

| Recovery Track | Applies To | Recovery Probability per Attempt | Typical Attempts | Time to Recovery |
|---|---|---|---|---|
| Auto-Retry | Auth failure, risk-engine timeout, stale-balance decline, rail timeout | 70–85% | 1–3 | Seconds to minutes |
| Customer Intervention | Insufficient funds | 30–50% | 1 (a single proactive nudge) | Hours to days |
| Engineering Fix | Processing error | ~0% until day 55, then treated as already fixed going forward | N/A | N/A — this track's "fix" is a rate change, not a per-transaction retry |
| Do Not Retry / Monitor | Risk hold, account restricted, issuer decline, rail outage | ~0% automated; risk holds get a delayed manual-review outcome (~40% of holds are reviewed and confirmed legitimate within 4–24 hours) | N/A (manual) | Hours (review) to unresolved |
| Not Applicable | Client-side init failure, validation failure | — | — | — (customer corrects and resubmits themselves, outside this dataset's scope, per data-architecture.md Section 5) |

---

## 6. Reproducibility

The generator uses a fixed random seed (`42`). Re-running it against this design produces byte-identical output, satisfying NFR-02 (Reliability) from requirements.md — a requirement that exists specifically so the KPIs computed in later phases don't shift between runs.

---

## 7. Generation Output Summary

The generator (`scripts/generate_dataset.py`, seed `42`) produced:

| File | Rows | Size |
|---|---|---|
| customers.csv | 12,000 | 0.5 MB |
| accounts.csv | 15,323 | 0.8 MB |
| transactions.csv | 180,000 | 22.6 MB |
| transaction_events.csv | 918,963 | 60.9 MB |
| recovery_attempts.csv | 7,607 | 0.8 MB |
| customer_segments.csv / channels.csv / payment_rails.csv / failure_reasons.csv | 3 / 4 / 4 / 12 | lookup tables |

**Overall outcome mix:** 94.07% `success`, 3.56% `permanently_failed`, 2.35% `recovered_success`, 0.02% `pending` — a realized overall failure rate of **5.93%**, close to the ~5% baseline design target in Section 4 once channel/type/problem-cohort multipliers are layered on. Average events per transaction: **5.1**.

**Recovery performance by track** (matches the Section 5 design ranges): Auto-Retry recovered ~78% of attempts, Customer Intervention ~39%, Do Not Retry/Monitor (blended risk-review + rail-outage) ~43%.

**Calibration checks that confirm the intended patterns actually appear in the data, not just in the design intent:**
- **Transaction-type risk gradient (PaySim-informed):** `p2p` (internal-ledger, lowest risk) failed at 4.59%, while `payroll`, `wire`, `rtp_transfer`, and `external_transfer` (transfer-type) failed at 7.0–8.1% — the elevated-risk pattern from Section 3 is visible in the realized data, not just asserted in the generation code.
- **Stress-day/stress-window signal:** measured at the correct granularity (RTP-rail timeout/outage rate *within* the designated stress-day, stress-hour window versus everywhere else), the failure rate is **3.4%** inside the window versus **0.7%** outside it — a genuine ~5× elevation. It is deliberately *not* obvious from a same-day total transaction count alone (a day's overall volume includes 20 non-stress hours), which mirrors how this kind of pattern would actually need to be found in Phase 10/11 — by slicing on hour-of-day and rail, not by eyeballing daily totals.
- **Engineering-fix signal:** `PROCESSING_ERROR` events occurred at ~5.1/day before day 55 and ~1.0/day after — a clear, discoverable before/after break for Phase 11's root-cause analysis to surface.
- **Account-status decline reason:** restricted accounts (2% of accounts, included in the transaction pool at reduced activity weight — Section 3 revision) correctly generate `ACCOUNT_RESTRICTED_DECLINE` events; this was validated after an initial generator bug excluded restricted accounts from transacting entirely, which would have made that failure reason a phantom row in the dictionary with zero real occurrences.

---

## Open Items for Stakeholder Review

- Confirm the ~5% baseline failure rate assumption (Section 4) is a reasonable "pre-intervention" starting point — it is deliberately elevated versus published real-time-payments benchmarks, and that choice is worth a second look before it becomes the number every later phase's finding is measured against.
- Confirm the "problem cohort" (4% of customers, 3× failure multiplier) is a strong enough signal for Phase 11's repeat-failure analysis without being so strong it looks artificially planted.
- Confirm the mid-window "engineering fix" on Processing Error (Section 3, point 5) is a welcome piece of narrative realism rather than an unnecessary scripted event — it can be removed in favor of a flat rate if a simpler story is preferred.
