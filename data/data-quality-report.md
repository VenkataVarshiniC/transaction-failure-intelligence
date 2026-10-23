# Data Quality Report

**Phase:** 9 of 20 — Data Quality
**Depends on:** [dataset-design.md](./dataset-design.md)
**Scans:** the Phase 8 extract as received — `transactions.csv` (180,015 rows), `accounts.csv` (15,323), `customers.csv` (12,000), `transaction_events.csv` (918,993), `failure_reasons.csv` (12), `recovery_attempts.csv` (7,607)

---

## 1. Methodology

Every check below is a query run against the extract, documented in `scripts/data_quality_checks.py` — nothing here is asserted without a reproducible query behind it. One internal-consistency check was run alongside the checklist items specifically to validate Phase 8's own generation logic: whether any transaction marked `success` also carries a failure event attached to it. It found zero such cases, which confirms the lifecycle simulation's success/failure branching was implemented consistently — worth stating explicitly, since a data-quality pass that only looks for injected-looking problems and never checks its own upstream logic isn't a complete one.

Per this project's own rule (business-case.md, realism rules; requirements.md NFR-05), **no issue below was silently fixed**. Each either (a) is structurally unrecoverable and is removed from the analysis-ready dataset with the row logged to an exceptions file, or (b) is kept with an explicit boolean quality-flag column so downstream SQL can decide, per query, whether to include it — never a fabricated "corrected" value standing in for missing or contradictory data.

---

## 2. Data Quality Issues Found

| Issue | Severity | Impact | Resolution | Status |
|---|---|---|---|---|
| 15 duplicate `transaction_id` rows (exact row duplicates) | Low | Would double-count 15 transactions (0.008% of volume) in every downstream KPI if left in | Keep first occurrence; quarantine the 15 extra rows to `exceptions/transactions_duplicates.csv` | Resolved |
| 45 transactions with a missing or non-positive `amount` (25 missing, 20 ≤ 0) | Medium | Would corrupt financial-exposure sums (Phase 13) if included; 0.025% of volume | Row kept (still valid for count-based KPIs); added `is_valid_amount` flag — financial queries must filter `WHERE is_valid_amount` | Resolved (flagged) |
| 10 transactions with an unrecognized `final_status` (8 case variants of `success`, 2 genuinely unrecognized: `unknown`, `error`) | Low–Medium | Case variants would silently fail an exact-match filter; the 2 unrecognized values have no safe mapping | 8 case variants normalized to `success` (unambiguous); the 2 genuine unknowns set to `unclassified` with `is_valid_status=False`, original value preserved in `final_status_raw` | Resolved (2 flagged, unmapped) |
| 12 transactions where `final_outcome_at` precedes `initiated_at` | Medium | Would produce negative time-to-resolution durations if used directly | Row and values kept as received (not overwritten); added `is_valid_outcome_timestamp` flag — duration calculations must filter on it | Resolved (flagged) |
| 10 transaction events timestamped before their own transaction's `initiated_at` | Medium | Would produce negative time-in-stage durations for Phase 11 stage-timing analysis | Row kept; added `is_valid_event_timestamp` flag | Resolved (flagged) |
| 8 accounts referencing a `customer_id` not present in `customers.csv`, affecting 114 downstream transactions | Medium | Those 114 transactions cannot be attributed to a real customer segment — would silently inflate or corrupt segment-level rollups (Phase 13, Customer Impact) if the orphan join were allowed to pass through | Quarantine the 8 account rows to `exceptions/accounts_orphan_customer.csv`; the 114 transactions remain in the clean transaction table (valid for channel/type/failure analysis) but are excluded from any customer-segment-level cut, which is documented here rather than discovered as a silent gap later | Resolved |
| 18 transaction events referencing a `failure_reason_id` (`FR-99`) not present in the failure-reason taxonomy | Medium | Would either break a join (event dropped) or, worse, be silently miscategorized if a fuzzy-matched to the wrong reason | Added a sentinel row `FR-00 / UNCLASSIFIED` to the failure-reason lookup and remapped these 18 events to it — visible in every root-cause rollup as its own category rather than disappearing | Resolved |
| 15 transaction events referencing a `transaction_id` not present in `transactions.csv` | Medium | An event with no parent transaction can't be attributed to a lifecycle, channel, or customer — unusable and potentially misleading if left in an event-count KPI | Quarantine to `exceptions/events_orphan_transaction.csv` | Resolved |
| 30 duplicate `event_id` rows (exact row duplicates) | Low | Would inflate average-events-per-transaction and any event-count-based KPI | Keep first occurrence; quarantine extras to `exceptions/events_duplicates.csv` | Resolved |
| 10 recovery attempts marked `outcome = recovered` with a null `completed_at` | Medium | Logically inconsistent (can't be recovered without a completion time) — if trusted as-is, would inflate the recovery-rate KPI (a headline dashboard number) with unconfirmed recoveries | Row kept; added `is_consistent_outcome` flag — the recovery-rate KPI's numerator must filter on it rather than trust `outcome` alone | Resolved (flagged) |
| 6 recovery attempts referencing a `triggering_event_id` not present in `transaction_events.csv` | Low | Can't be attributed to a real failure event | Quarantine to `exceptions/recovery_orphan_event.csv` | Resolved |
| *(Consistency check)* `success` transactions also carrying a failure event | — | None found (0 of 180,015) | No action needed — confirms Phase 8's lifecycle simulation logic was internally consistent | Verified, no issue |

---

## 3. Assumptions Behind Each Resolution (Stated, Not Silent)

- **Duplicates are treated as extract artifacts, not real repeated events.** The data model (data-architecture.md) defines `transaction_id` and `event_id` as unique identifiers; a second identical row under the same ID is assumed to be a duplicate transmission, not two genuine occurrences. This is a reasonable assumption for a synthetic dataset and would need confirming against the real source system's replay/idempotency behavior in production.
- **Case-variant statuses were normalized; genuinely unknown ones were not invented.** `Success` → `success` is a safe, unambiguous correction. `unknown` and `error` have no defensible mapping to one of the four valid states, so they were left explicitly unclassified rather than guessed.
- **Invalid amounts and inconsistent timestamps are flagged, not dropped or imputed**, because the rest of each row (status, channel, failure reason) is still informative for non-financial, non-duration analysis. Dropping the whole row would throw away valid information; imputing a fabricated amount or timestamp would misrepresent the analysis as more precise than the source data actually supports.
- **The 114 transactions on orphaned accounts stay in the clean transaction table.** Excluding them entirely would understate overall volume and failure counts for no reason — the account-to-customer link is broken, not the transaction record itself. This is a judgment call, recorded here so it can be revisited if the review below disagrees with it.

---

## 4. Clean Dataset Output

`scripts/clean_dataset.py` applies every resolution above and writes:
- `data/clean/*.csv` — the analysis-ready tables Phase 10's SQL is written against, each carrying the quality-flag columns listed above where applicable
- `data/exceptions/*.csv` — every row removed from the clean set, each with an `exception_reason` column, so nothing is discarded without a trace

| Table | Raw rows | Clean rows | Quarantined | Flagged (kept, marked uncertain) |
|---|---|---|---|---|
| transactions | 180,015 | 180,000 | 15 (duplicates) | 45 amount, 2 status, 12 timestamp |
| accounts | 15,323 | 15,315 | 8 (orphan customer) | — |
| transaction_events | 918,993 | 918,948 | 45 (30 duplicate + 15 orphan) | 10 timestamp |
| recovery_attempts | 7,607 | 7,601 | 6 (orphan event) | 10 outcome consistency |
| failure_reasons | 12 | 13 (+ `FR-00` sentinel) | — | — |

---

## Open Items for Stakeholder Review

- Confirm the "flag, don't drop" resolution for amount/timestamp/outcome issues is the right default — an alternative, stricter policy would exclude any flagged row from *all* analysis, not just the specific KPI it would corrupt. The current approach keeps more data usable but requires every future SQL query in Phase 10 to remember to filter on the relevant flag, which is itself a risk worth weighing.
- Confirm the decision to keep the 114 transactions on orphaned accounts in the clean transaction table (excluded only from customer-segment cuts) rather than quarantining them entirely.
- Confirm `FR-00 / UNCLASSIFIED` as a visible category in root-cause rollups (Phase 11) is preferable to quarantining those 18 events outright — it was chosen so the *existence* of unclassified failures stays visible to management rather than disappearing from the count.
