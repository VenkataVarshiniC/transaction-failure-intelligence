# Data Dictionary: Transaction Lifecycle / Event Model

**Phase:** 7 of 20 — Data Dictionary
**Depends on:** [../business-analysis/data-architecture.md](../business-analysis/data-architecture.md)

---

## 1. Scope and Conventions

This dictionary specifies every field in the nine entities defined in Phase 6, at the precision needed to generate the synthetic dataset (Phase 8) and write SQL against it (Phase 10) without ambiguity. **Note (added at Phase 9):** the analysis-ready tables in `data/clean/` carry a small number of additional boolean quality-flag columns (`is_valid_amount`, `is_valid_status`, `is_valid_outcome_timestamp`, `is_valid_event_timestamp`, `is_consistent_outcome`) not listed below — these are documented in full, with the issue each one guards against, in data-quality-report.md rather than duplicated here. Two conventions apply throughout:

- **Single currency.** All amounts are in USD. No `currency` field is carried on `TRANSACTION` — adding one would imply multi-currency behavior (FX conversion, rate-date sensitivity) that is out of scope (business-case.md, Section 5) and would need its own handling in every downstream financial calculation for no analytical benefit.
- **One refinement from Phase 6:** `TRANSACTION.rail_id` is treated as **not nullable**. In Phase 6 it was described as nullable for internal-ledger transfers; on reflection, a nullable foreign key on the core fact table is a worse design than simply treating "internal ledger" as one more row in `PAYMENT_RAIL` (`rail_owner = internal`). Every transaction now references *some* rail — internal or external — and "was this externally dependent?" becomes a filter on `rail_owner`, not a null check. This is called out explicitly rather than silently changed.

---

## 2. CUSTOMER

| Field | Data Type | Description | Business Meaning | Example | Nullable |
|---|---|---|---|---|---|
| customer_id | string (PK) | Unique synthetic customer identifier | Anchors all customer-level aggregation (repeat-failure rate, segment rollups) | `CUST-0004821` | No |
| segment_id | string (FK → CUSTOMER_SEGMENT) | Segment the customer belongs to | Drives every segment-level cut in the Customer Impact dashboard page | `SEG-RETAIL-STD` | No |
| customer_type | enum: `retail`, `small_business` | Broad customer category | Distinguishes the two customer bases named in business-case.md (2.4M retail / 180K SMB) | `retail` | No |
| signup_date | date | Date the customer's account relationship began | Enables tenure-based analysis (e.g., do newer customers see more auth failures) if useful later | `2022-03-14` | No |

## 3. CUSTOMER_SEGMENT

| Field | Data Type | Description | Business Meaning | Example | Nullable |
|---|---|---|---|---|---|
| segment_id | string (PK) | Unique segment identifier | — | `SEG-SMB-01` | No |
| segment_name | string | Human-readable segment label | What appears on dashboard filters | `Small-Business` | No |
| segment_category | enum: `retail`, `small_business` | Convenience rollup of segment_name | Lets Finance/Support group by broad category without parsing segment_name strings | `small_business` | No |

## 4. ACCOUNT

| Field | Data Type | Description | Business Meaning | Example | Nullable |
|---|---|---|---|---|---|
| account_id | string (PK) | Unique account identifier | Balance-validation failures (Stage 5) are tracked here, not at customer level | `ACCT-1029384` | No |
| customer_id | string (FK → CUSTOMER) | Owning customer | — | `CUST-0004821` | No |
| account_type | enum: `checking`, `savings`, `business` | Account product type | `business` accounts are the source of payroll/wire transactions | `checking` | No |
| account_status | enum: `active`, `restricted`, `closed` | Current standing of the account | A `restricted` status is itself a Stage 5 failure cause, distinct from insufficient funds | `active` | No |
| opened_date | date | Date the account was opened | — | `2021-11-02` | No |

## 5. CHANNEL

| Field | Data Type | Description | Business Meaning | Example | Nullable |
|---|---|---|---|---|---|
| channel_id | string (PK) | Unique channel identifier | — | `CHN-MOBILE` | No |
| channel_name | enum: `mobile_app`, `web`, `pos_atm`, `api` | The channel a transaction was submitted through | Primary cut for BR-01's channel-level failure rate | `mobile_app` | No |

## 6. PAYMENT_RAIL

| Field | Data Type | Description | Business Meaning | Example | Nullable |
|---|---|---|---|---|---|
| rail_id | string (PK) | Unique rail identifier | — | `RAIL-ACH` | No |
| rail_name | enum: `card_network`, `ach`, `rtp`, `internal_ledger` | The payment rail a transaction was routed over | `internal_ledger` covers Kestrel Pay P2P, which never leaves the bank | `ach` | No |
| rail_owner | enum: `external`, `internal` | Whether Kestrel controls this rail | Direct implementation of the internal-vs-external-dependency distinction (business-case.md, Section 1; BR-02) | `external` | No |

## 7. TRANSACTION

| Field | Data Type | Description | Business Meaning | Example | Nullable |
|---|---|---|---|---|---|
| transaction_id | string (PK) | Unique identifier for one customer-initiated payment request | The grain the customer and Finance think in | `TXN-88231940` | No |
| account_id | string (FK → ACCOUNT) | Source account initiating the transaction | — | `ACCT-1029384` | No |
| channel_id | string (FK → CHANNEL) | Channel used to submit the transaction | — | `CHN-MOBILE` | No |
| rail_id | string (FK → PAYMENT_RAIL) | Rail the transaction was routed over | See Section 1 refinement — always populated | `RAIL-RTP` | No |
| transaction_type | enum: `p2p`, `external_transfer`, `bill_pay`, `card_pos`, `wire`, `payroll`, `rtp_transfer` | The product/transaction type | Drives which failure reasons are even possible (e.g., only `wire`/`payroll` can fail for small-business-specific reasons) | `payroll` | No |
| counterparty_type | enum: `internal_kestrel_customer`, `external_bank_account`, `business_payee` | Nature of the receiving party | Explains why, e.g., a `p2p` transaction stays on `internal_ledger` while an `external_transfer` must use `ach` | `external_bank_account` | No |
| amount | decimal(12,2) | Transaction amount in USD | The basis for all financial-exposure calculations (Phase 13) | `1250.00` | No |
| initiated_at | datetime | Timestamp the transaction was submitted (Stage 1) | Anchors time-based and volume/peak-load analysis (business-case.md Section 1, UPI volume-sensitivity assumption) | `2026-06-14T09:32:11Z` | No |
| final_status | enum: `success`, `recovered_success`, `permanently_failed`, `pending` | The transaction's current, overall outcome | `recovered_success` is distinct from `success` specifically so recovery's contribution is visible, not hidden inside a generic success count | `recovered_success` | No |
| final_outcome_at | datetime | Timestamp the final_status was reached | Null only while a transaction is still mid-lifecycle at the moment the dataset snapshot was taken | `2026-06-14T09:32:14Z` | Yes — null while `final_status = pending` |

## 8. TRANSACTION_EVENT

| Field | Data Type | Description | Business Meaning | Example | Nullable |
|---|---|---|---|---|---|
| event_id | string (PK) | Unique event identifier | — | `EVT-772910345` | No |
| transaction_id | string (FK → TRANSACTION) | The transaction this event belongs to | One transaction has many events — this is the model's core fact table | `TXN-88231940` | No |
| event_sequence | int | Order of this event within the transaction, starting at 1 | Lets SQL reconstruct the exact path a transaction took (Phase 10, Phase 11) | `4` | No |
| lifecycle_stage | int (1–10) | Which of the ten lifecycle stages this event represents | Direct foreign concept to process-analysis.md — every stage there is a valid value here | `4` | No |
| event_type | string (controlled vocabulary — Section 10 below) | The specific thing that happened at this stage | The actual unit of root-cause analysis | `RISK_HELD` | No |
| event_timestamp | datetime | When this event occurred | Used for time-to-resolution and time-in-stage KPIs | `2026-06-14T09:32:12Z` | No |
| failure_reason_id | string (FK → FAILURE_REASON) | The standardized reason, if this event represents a failure | Null for pass-through events (e.g., `AUTH_PASSED`) | `FR-RISK-004` | Yes — only failure-type events |
| risk_score | int (0–100) | Risk-engine score at the moment of this event | Only meaningful for Stage 4 events; supports the false-positive-rate KPI (process-analysis.md, Stage 4) | `78` | Yes — only Stage 4 events |

## 9. FAILURE_REASON

| Field | Data Type | Description | Business Meaning | Example | Nullable |
|---|---|---|---|---|---|
| failure_reason_id | string (PK) | Unique failure-reason identifier | — | `FR-RISK-004` | No |
| reason_code | string | Short machine-readable code | Used in dashboard filters and SQL groupings | `FALSE_POSITIVE_RISK_HOLD` | No |
| reason_description | string | Human-readable explanation | Shown in the Failure Intelligence dashboard page | `Legitimate transaction held by risk engine pending review` | No |
| lifecycle_stage | int (1–10) | Stage this reason originates at | Ties every failure reason back to a single stage owner (process-analysis.md) | `4` | No |
| failure_category | enum: `People`, `Process`, `Technology`, `Policy`, `Risk`, `External Dependency` | Root-cause category (Section 15 framework) | The basis for Phase 11's Pareto and segmentation analysis | `Risk` | No |
| origin | enum: `internal`, `external` | Whether Kestrel can directly fix this cause | Implements BR-02 | `internal` | No |
| default_recovery_track | enum: `Auto-Retry`, `Customer Intervention`, `Engineering Fix`, `Do Not Retry-Monitor`, `Not Applicable` | The future-state routing this reason defaults to (future-state.md, Section 4) | Seeds Phase 12's Recovery Opportunity Engine | `Auto-Retry` | No |

## 10. RECOVERY_ATTEMPT

| Field | Data Type | Description | Business Meaning | Example | Nullable |
|---|---|---|---|---|---|
| recovery_attempt_id | string (PK) | Unique recovery-attempt identifier | — | `REC-33210` | No |
| transaction_id | string (FK → TRANSACTION) | The transaction being recovered | — | `TXN-88231940` | No |
| triggering_event_id | string (FK → TRANSACTION_EVENT) | The specific failure event this attempt is responding to | Not just "was it retried" — *which* failure it was retrying, since a transaction can fail more than once for different reasons (data-architecture.md, Section 5) | `EVT-772910345` | No |
| recovery_track | enum: `Auto-Retry`, `Customer Intervention`, `Engineering Fix`, `Do Not Retry-Monitor` | Which future-state track handled this attempt | — | `Auto-Retry` | No |
| attempt_number | int | Which attempt this is for the triggering event (1st, 2nd, …) | Supports "how many retries are typically required" (Section 13 analytical questions) | `1` | No |
| initiated_at | datetime | When the recovery attempt started | — | `2026-06-14T09:33:00Z` | No |
| completed_at | datetime | When the recovery attempt concluded | Null while the attempt is still in progress at snapshot time | `2026-06-14T09:33:04Z` | Yes — null while in progress |
| outcome | enum: `recovered`, `still_failed`, `escalated` | Result of this attempt | Directly computes the recovery-rate KPI (FR-04) | `recovered` | Yes — null while `completed_at` is null |

---

## 11. Controlled Vocabulary: `event_type` by Lifecycle Stage

This table is what Phase 8's dataset generator and Phase 10's SQL both build from — it is the authoritative list of valid `event_type` values, so no stage produces an ad hoc event string that isn't accounted for elsewhere.

| Stage | Pass-through event_type(s) | Failure event_type(s) |
|---|---|---|
| 1. Transaction Initiated | `TXN_INITIATED` | `CLIENT_INIT_FAILURE` |
| 2. Authentication | `AUTH_PASSED` | `AUTH_FAILED` |
| 3. Request Validation | `VALIDATION_PASSED` | `VALIDATION_FAILED` |
| 4. Risk & Fraud Screening | `RISK_CLEARED` | `RISK_HELD`, `RISK_ENGINE_TIMEOUT` |
| 4b. Risk Review (post-hoc, may occur later) | `RISK_REVIEWED_CONFIRMED_LEGITIMATE` | `RISK_REVIEWED_CONFIRMED_FRAUD` |
| 5. Balance / Account Validation | `BALANCE_CONFIRMED` | `BALANCE_DECLINED_INSUFFICIENT_FUNDS`, `BALANCE_DECLINED_STALE_READ`, `ACCOUNT_RESTRICTED_DECLINE` |
| 6. Payment Processing & Rail Submission | `PROCESSING_SUBMITTED` | `PROCESSING_ERROR` |
| 7. External Network Response | `RAIL_APPROVED` | `RAIL_DECLINED_ISSUER`, `RAIL_TIMEOUT`, `RAIL_OUTAGE` |
| 8. Outcome Determination | `OUTCOME_SUCCESS` | `OUTCOME_TEMP_FAILURE`, `OUTCOME_PERMANENT_FAILURE` |
| 9. Retry / Recovery Attempt | `RETRY_INITIATED`, `RETRY_SUCCESS` | `RETRY_FAILED` |
| 10. Final Outcome | `FINAL_SETTLED`, `FINAL_RECOVERED`, `CUSTOMER_NOTIFIED` | `FINAL_PERMANENTLY_FAILED` |

Row 4b is intentionally listed apart from Stage 4 itself — it is the append-only "later correction" event described in data-architecture.md, Section 6, and can occur well after the original `RISK_HELD` event, out of strict lifecycle order, which is precisely why it needs its own `event_sequence` rather than overwriting the original event.

---

## Open Items for Stakeholder Review

- Confirm the `rail_id` refinement in Section 1 (not nullable; internal ledger is a rail row) is the right call before Phase 8 generates data against this schema — reversing it later means regenerating the dataset.
- Confirm the `event_type` vocabulary in Section 11 has the right granularity — in particular, whether `RAIL_DECLINED_ISSUER` should be split further by decline reason (e.g., expired card vs. blocked card) or is intentionally left at this level to avoid modeling detail Kestrel wouldn't actually receive from an external issuer.
- Confirm no additional field is needed on `TRANSACTION` for small-business-specific analysis (e.g., a payroll batch identifier) before Phase 8 — small-business impact is currently derived entirely through `customer_type`/`segment_category`, not a dedicated field.
