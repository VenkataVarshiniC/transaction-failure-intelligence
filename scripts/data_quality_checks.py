"""
Phase 9 data-quality detection pass. Scans the extract as received (no
assumptions about what was injected) and reports every issue found, at the
granularity needed for data-quality-report.md. Run with:
python3 data_quality_checks.py
"""

import pandas as pd
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
DATA_DIR = PROJECT_ROOT / "data"

txn = pd.read_csv(f"{DATA_DIR}/transactions.csv")
acct = pd.read_csv(f"{DATA_DIR}/accounts.csv")
cust = pd.read_csv(f"{DATA_DIR}/customers.csv")
ev = pd.read_csv(f"{DATA_DIR}/transaction_events.csv")
fr = pd.read_csv(f"{DATA_DIR}/failure_reasons.csv")
rec = pd.read_csv(f"{DATA_DIR}/recovery_attempts.csv")

txn["initiated_at"] = pd.to_datetime(txn["initiated_at"])
txn["final_outcome_at"] = pd.to_datetime(txn["final_outcome_at"])
ev["event_timestamp"] = pd.to_datetime(ev["event_timestamp"])
rec["completed_at"] = pd.to_datetime(rec["completed_at"])

print(f"Extract sizes: transactions={len(txn)}, accounts={len(acct)}, customers={len(cust)}, "
      f"events={len(ev)}, failure_reasons={len(fr)}, recovery_attempts={len(rec)}")
print()

VALID_STATUSES = {"success", "recovered_success", "permanently_failed", "pending"}

# 1. Missing values -----------------------------------------------------------
missing_amount = txn["amount"].isna().sum()
print(f"[1] Missing amount values in transactions.csv: {missing_amount}")

# 2. Duplicate transactions ----------------------------------------------------
dup_txn_ids = txn["transaction_id"][txn["transaction_id"].duplicated(keep=False)]
n_dup_txn_rows = txn["transaction_id"].duplicated(keep="first").sum()
print(f"[2] Duplicate transaction_id rows (extra copies beyond the first): {n_dup_txn_rows} "
      f"({dup_txn_ids.nunique()} distinct transaction_ids affected)")

# 3. Invalid transaction amounts ------------------------------------------------
invalid_amount = txn[(txn["amount"].notna()) & (txn["amount"] <= 0)]
print(f"[3] Transactions with non-positive amount: {len(invalid_amount)}")

# 4. Invalid statuses -----------------------------------------------------------
invalid_status = txn[~txn["final_status"].isin(VALID_STATUSES)]
print(f"[4] Transactions with an unrecognized final_status value: {len(invalid_status)} "
      f"-- values found: {sorted(invalid_status['final_status'].unique().tolist())}")

# 5. Inconsistent timestamps ----------------------------------------------------
bad_order = txn[(txn["final_outcome_at"].notna()) & (txn["final_outcome_at"] < txn["initiated_at"])]
print(f"[5] Transactions where final_outcome_at precedes initiated_at: {len(bad_order)}")

# 6. Impossible processing times (event before its transaction was initiated) ---
ev_with_txn = ev.merge(txn[["transaction_id", "initiated_at"]], on="transaction_id", how="inner", suffixes=("", "_txn"))
impossible_time = ev_with_txn[ev_with_txn["event_timestamp"] < ev_with_txn["initiated_at"]]
print(f"[6] Events timestamped before their transaction's initiated_at: {len(impossible_time)}")

# 7. Invalid customer references (accounts pointing to a customer that doesn't exist)
orphan_accounts = acct[~acct["customer_id"].isin(cust["customer_id"])]
print(f"[7] Accounts referencing a nonexistent customer_id: {len(orphan_accounts)}")

# 8. Invalid failure reasons (events referencing a failure_reason_id not in the lookup)
events_with_fr = ev[ev["failure_reason_id"].notna()]
invalid_fr = events_with_fr[~events_with_fr["failure_reason_id"].isin(fr["failure_reason_id"])]
print(f"[8] Events referencing a nonexistent failure_reason_id: {len(invalid_fr)} "
      f"-- values found: {sorted(invalid_fr['failure_reason_id'].unique().tolist())}")

# 9. Orphan records (events referencing a transaction_id that doesn't exist) ----
orphan_events = ev[~ev["transaction_id"].isin(txn["transaction_id"])]
print(f"[9] Events referencing a nonexistent transaction_id: {len(orphan_events)}")

orphan_recovery = rec[~rec["triggering_event_id"].isin(ev["event_id"])]
print(f"[9b] Recovery attempts referencing a nonexistent triggering_event_id: {len(orphan_recovery)}")

# 10. Duplicate events -----------------------------------------------------------
n_dup_events = ev["event_id"].duplicated(keep="first").sum()
print(f"[10] Duplicate event_id rows (extra copies beyond the first): {n_dup_events}")

# 11. Inconsistent recovery statuses ---------------------------------------------
inconsistent_recovery = rec[(rec["outcome"] == "recovered") & (rec["completed_at"].isna())]
print(f"[11] Recovery attempts marked 'recovered' with a null completed_at: {len(inconsistent_recovery)}")

# --- Cross-check: transactions with final_status='success' that also carry a
# failure event attached (a genuine internal-consistency check, not an injected issue) --
fail_txn_ids = set(ev[ev["failure_reason_id"].notna()]["transaction_id"])
success_with_failure = txn[(txn["final_status"] == "success") & (txn["transaction_id"].isin(fail_txn_ids))]
print(f"\n[Consistency check] 'success' transactions that also carry a failure event: {len(success_with_failure)} "
      f"(0 expected if lifecycle simulation logic is internally consistent)")
