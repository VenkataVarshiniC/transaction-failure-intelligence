"""
Phase 9 cleaning pass. Applies the resolutions documented in
data/data-quality-report.md to the raw extract in data/, producing:
  - data/clean/*.csv        -- the analysis-ready dataset Phase 10 SQL builds on
  - data/exceptions/*.csv   -- every row removed from the clean set, logged with a reason

Nothing is silently dropped: every removed row is written to an exceptions
file, and every row that is kept-but-uncertain gets an explicit boolean
quality flag column rather than a fabricated "fixed" value. Run with:
python3 clean_dataset.py
"""

import numpy as np
import pandas as pd
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
DATA_DIR = PROJECT_ROOT / "data"
CLEAN_DIR = DATA_DIR / "clean"
EXC_DIR = DATA_DIR / "exceptions"
CLEAN_DIR.mkdir(parents=True, exist_ok=True)
EXC_DIR.mkdir(parents=True, exist_ok=True)

txn = pd.read_csv(f"{DATA_DIR}/transactions.csv")
acct = pd.read_csv(f"{DATA_DIR}/accounts.csv")
cust = pd.read_csv(f"{DATA_DIR}/customers.csv")
ev = pd.read_csv(f"{DATA_DIR}/transaction_events.csv")
fr = pd.read_csv(f"{DATA_DIR}/failure_reasons.csv")
rec = pd.read_csv(f"{DATA_DIR}/recovery_attempts.csv")
seg = pd.read_csv(f"{DATA_DIR}/customer_segments.csv")
chan = pd.read_csv(f"{DATA_DIR}/channels.csv")
rail = pd.read_csv(f"{DATA_DIR}/payment_rails.csv")

txn["initiated_at"] = pd.to_datetime(txn["initiated_at"])
txn["final_outcome_at"] = pd.to_datetime(txn["final_outcome_at"])
ev["event_timestamp"] = pd.to_datetime(ev["event_timestamp"])
rec["completed_at"] = pd.to_datetime(rec["completed_at"])

VALID_STATUSES = {"success", "recovered_success", "permanently_failed", "pending"}

# ---------------------------------------------------------------------------
# TRANSACTIONS
# ---------------------------------------------------------------------------

# Structural: duplicate transaction_id rows -> quarantine extras, keep first
dup_mask = txn["transaction_id"].duplicated(keep="first")
txn.loc[dup_mask].assign(exception_reason="duplicate_transaction_id").to_csv(
    f"{EXC_DIR}/transactions_duplicates.csv", index=False)
txn = txn.loc[~dup_mask].copy()

# Flaggable: amount validity (covers both missing and non-positive amounts)
txn["is_valid_amount"] = txn["amount"].notna() & (txn["amount"] > 0)

# Flaggable: status validity -- normalize unambiguous case variants, flag the rest
txn["final_status_raw"] = txn["final_status"]
is_case_variant = txn["final_status"].str.lower() == "success"
txn.loc[is_case_variant & (txn["final_status"] != "success"), "final_status"] = "success"
txn["is_valid_status"] = txn["final_status"].isin(VALID_STATUSES)
# genuinely unrecognized values (not a case variant of a known one) -> sentinel
still_invalid = ~txn["is_valid_status"]
txn.loc[still_invalid, "final_status"] = "unclassified"
# is_valid_status already correctly False for these; recompute for clarity
txn["is_valid_status"] = txn["final_status_raw"].str.lower().isin(VALID_STATUSES)

# Flaggable: outcome-timestamp ordering
txn["is_valid_outcome_timestamp"] = ~(
    txn["final_outcome_at"].notna() & (txn["final_outcome_at"] < txn["initiated_at"])
)

txn.to_csv(f"{CLEAN_DIR}/transactions.csv", index=False)

# ---------------------------------------------------------------------------
# ACCOUNTS
# ---------------------------------------------------------------------------

orphan_acct_mask = ~acct["customer_id"].isin(cust["customer_id"])
acct.loc[orphan_acct_mask].assign(exception_reason="orphan_customer_id").to_csv(
    f"{EXC_DIR}/accounts_orphan_customer.csv", index=False)
acct_clean = acct.loc[~orphan_acct_mask].copy()
acct_clean.to_csv(f"{CLEAN_DIR}/accounts.csv", index=False)

# ---------------------------------------------------------------------------
# FAILURE_REASONS -- add an "unclassified" sentinel row for invalid references
# ---------------------------------------------------------------------------

fr_clean = pd.concat([fr, pd.DataFrame([{
    "failure_reason_id": "FR-00", "reason_code": "UNCLASSIFIED",
    "reason_description": "Referenced a failure_reason_id not present in the standard taxonomy at extract time",
    "lifecycle_stage": np.nan, "failure_category": "Unclassified", "origin": "unknown",
    "default_recovery_track": "Not Applicable",
}])], ignore_index=True)
fr_clean.to_csv(f"{CLEAN_DIR}/failure_reasons.csv", index=False)

# ---------------------------------------------------------------------------
# TRANSACTION_EVENTS
# ---------------------------------------------------------------------------

dup_ev_mask = ev["event_id"].duplicated(keep="first")
ev.loc[dup_ev_mask].assign(exception_reason="duplicate_event_id").to_csv(
    f"{EXC_DIR}/events_duplicates.csv", index=False)
ev = ev.loc[~dup_ev_mask].copy()

orphan_ev_mask = ~ev["transaction_id"].isin(txn["transaction_id"])
ev.loc[orphan_ev_mask].assign(exception_reason="orphan_transaction_id").to_csv(
    f"{EXC_DIR}/events_orphan_transaction.csv", index=False)
ev = ev.loc[~orphan_ev_mask].copy()

valid_fr_ids = set(fr["failure_reason_id"])
invalid_fr_mask = ev["failure_reason_id"].notna() & ~ev["failure_reason_id"].isin(valid_fr_ids)
ev.loc[invalid_fr_mask, "failure_reason_id"] = "FR-00"

ev_with_init = ev.merge(txn[["transaction_id", "initiated_at"]], on="transaction_id", how="left")
ev["is_valid_event_timestamp"] = ~(ev_with_init["event_timestamp"] < ev_with_init["initiated_at"]).values

ev.to_csv(f"{CLEAN_DIR}/transaction_events.csv", index=False)

# ---------------------------------------------------------------------------
# RECOVERY_ATTEMPTS
# ---------------------------------------------------------------------------

orphan_rec_mask = ~rec["triggering_event_id"].isin(ev["event_id"]) & ~rec["triggering_event_id"].isin(
    pd.read_csv(f"{DATA_DIR}/transaction_events.csv")["event_id"])
# (checked against the full raw event set, not just the cleaned one, so a
# recovery attempt pointing at a since-deduplicated-but-real event isn't
# wrongly quarantined)
rec.loc[orphan_rec_mask].assign(exception_reason="orphan_triggering_event_id").to_csv(
    f"{EXC_DIR}/recovery_orphan_event.csv", index=False)
rec_clean = rec.loc[~orphan_rec_mask].copy()

rec_clean["is_consistent_outcome"] = ~((rec_clean["outcome"] == "recovered") & (rec_clean["completed_at"].isna()))
rec_clean.to_csv(f"{CLEAN_DIR}/recovery_attempts.csv", index=False)

# ---------------------------------------------------------------------------
# Pass-through tables with no detected issues
# ---------------------------------------------------------------------------

cust.to_csv(f"{CLEAN_DIR}/customers.csv", index=False)
seg.to_csv(f"{CLEAN_DIR}/customer_segments.csv", index=False)
chan.to_csv(f"{CLEAN_DIR}/channels.csv", index=False)
rail.to_csv(f"{CLEAN_DIR}/payment_rails.csv", index=False)

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

print("=== Clean dataset row counts ===")
for name, path in [("customers", "customers.csv"), ("accounts", "accounts.csv"),
                    ("transactions", "transactions.csv"), ("transaction_events", "transaction_events.csv"),
                    ("recovery_attempts", "recovery_attempts.csv"), ("failure_reasons", "failure_reasons.csv")]:
    print(f"  {name}: {len(pd.read_csv(f'{CLEAN_DIR}/{path}'))}")

print("\n=== Quality flags (flagged rows kept in clean set, excluded per-analysis) ===")
txn_clean = pd.read_csv(f"{CLEAN_DIR}/transactions.csv")
print(f"  transactions.is_valid_amount = False: {(~txn_clean['is_valid_amount']).sum()}")
print(f"  transactions.is_valid_status = False: {(~txn_clean['is_valid_status']).sum()}")
print(f"  transactions.is_valid_outcome_timestamp = False: {(~txn_clean['is_valid_outcome_timestamp']).sum()}")
ev_clean = pd.read_csv(f"{CLEAN_DIR}/transaction_events.csv")
print(f"  transaction_events.is_valid_event_timestamp = False: {(~ev_clean['is_valid_event_timestamp']).sum()}")
rec_clean_r = pd.read_csv(f"{CLEAN_DIR}/recovery_attempts.csv")
print(f"  recovery_attempts.is_consistent_outcome = False: {(~rec_clean_r['is_consistent_outcome']).sum()}")

print("\n=== Exceptions logged (rows removed from clean set) ===")
for path in sorted(EXC_DIR.iterdir()):
    if path.suffix == ".csv":
        print(f"  {path.name}: {len(pd.read_csv(path))} rows")
