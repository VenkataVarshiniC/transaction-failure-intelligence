"""
Deliberately injects a small, documented set of realistic data-quality issues
into the Phase 8 dataset, simulating what a real extract from Kestrel's systems
would plausibly contain. This is run once, after generate_dataset.py, so that
Phase 9's data-quality analysis has real issues to find rather than fabricated
ones. Seed is distinct from the generator's (42) to keep the two steps clearly
separable. Run with: python3 inject_data_quality_issues.py
"""

import numpy as np
import pandas as pd
from pathlib import Path

SEED = 2026
rng = np.random.default_rng(SEED)
PROJECT_ROOT = Path(__file__).resolve().parents[1]
DATA_DIR = PROJECT_ROOT / "data"

txn = pd.read_csv(f"{DATA_DIR}/transactions.csv")
acct = pd.read_csv(f"{DATA_DIR}/accounts.csv")
cust = pd.read_csv(f"{DATA_DIR}/customers.csv")
ev = pd.read_csv(f"{DATA_DIR}/transaction_events.csv")
fr = pd.read_csv(f"{DATA_DIR}/failure_reasons.csv")
rec = pd.read_csv(f"{DATA_DIR}/recovery_attempts.csv")

print("Baseline row counts:", {n: len(d) for n, d in
      [("transactions", txn), ("accounts", acct), ("events", ev), ("recovery", rec)]})

# --- transactions.csv -------------------------------------------------------

# 1. Duplicate rows (exact duplicate of an existing transaction_id + full row)
dup_idx = rng.choice(txn.index, size=15, replace=False)
txn = pd.concat([txn, txn.loc[dup_idx]], ignore_index=True)

# 2. Invalid (non-positive) amounts
bad_amount_idx = rng.choice(txn.index, size=20, replace=False)
half = len(bad_amount_idx) // 2
txn.loc[bad_amount_idx[:half], "amount"] = 0.0
txn.loc[bad_amount_idx[half:], "amount"] = -np.round(
    rng.uniform(1, 500, size=len(bad_amount_idx) - half), 2
)

# 3. Missing amounts
missing_amount_idx = rng.choice(txn.index.difference(bad_amount_idx), size=25, replace=False)
txn.loc[missing_amount_idx, "amount"] = np.nan

# 4. Invalid final_status values (case variants / unrecognized)
bad_status_idx = rng.choice(txn.index, size=10, replace=False)
bad_status_values = ["Success", "SUCCESS", "unknown", "error"]
txn.loc[bad_status_idx, "final_status"] = rng.choice(bad_status_values, size=10)

# 5. Impossible timestamp ordering (final_outcome_at before initiated_at)
resolved_idx = txn[txn["final_outcome_at"].notna()].index
bad_ts_idx = rng.choice(resolved_idx, size=12, replace=False)
txn["initiated_at"] = pd.to_datetime(txn["initiated_at"])
txn["final_outcome_at"] = pd.to_datetime(txn["final_outcome_at"])
txn.loc[bad_ts_idx, "final_outcome_at"] = txn.loc[bad_ts_idx, "initiated_at"] - pd.to_timedelta(
    rng.integers(1, 3600, size=12), unit="s")

# --- accounts.csv ------------------------------------------------------------

# 6. Orphan accounts (customer_id not present in customers.csv)
orphan_acct_idx = rng.choice(acct.index, size=8, replace=False)
fake_customer_ids = [f"CUST-{9990000 + i:07d}" for i in range(8)]
acct.loc[orphan_acct_idx, "customer_id"] = fake_customer_ids

# --- transaction_events.csv ---------------------------------------------------

# 7. Duplicate events (exact duplicate row, same event_id)
dup_ev_idx = rng.choice(ev.index, size=30, replace=False)
ev = pd.concat([ev, ev.loc[dup_ev_idx]], ignore_index=True)

# 8. Invalid failure_reason_id (references a code that doesn't exist)
failure_events_idx = ev[ev["failure_reason_id"].notna()].index
bad_fr_idx = rng.choice(failure_events_idx, size=18, replace=False)
ev.loc[bad_fr_idx, "failure_reason_id"] = "FR-99"

# 9. Orphan events (transaction_id not present in transactions.csv)
orphan_ev_idx = rng.choice(ev.index, size=15, replace=False)
fake_txn_ids = [f"TXN-{99990000 + i:08d}" for i in range(15)]
ev.loc[orphan_ev_idx, "transaction_id"] = fake_txn_ids

# 10. Impossible processing times (event_timestamp before the transaction's initiated_at)
ev["event_timestamp"] = pd.to_datetime(ev["event_timestamp"])
txn_init_map = dict(zip(txn["transaction_id"], txn["initiated_at"]))
candidate_idx = ev.index.difference(orphan_ev_idx)
bad_time_idx = rng.choice(candidate_idx, size=10, replace=False)
for i in bad_time_idx:
    t_id = ev.at[i, "transaction_id"]
    if t_id in txn_init_map:
        ev.at[i, "event_timestamp"] = txn_init_map[t_id] - pd.Timedelta(seconds=int(rng.integers(30, 600)))

# --- recovery_attempts.csv ----------------------------------------------------

# 11. Inconsistent recovery status (outcome='recovered' but completed_at is null)
recovered_idx = rec[rec["outcome"] == "recovered"].index
bad_rec_idx = rng.choice(recovered_idx, size=10, replace=False)
rec.loc[bad_rec_idx, "completed_at"] = np.nan

# 12. Orphan recovery attempts (triggering_event_id not present in transaction_events.csv)
orphan_rec_idx = rng.choice(rec.index, size=6, replace=False)
fake_event_ids = [f"EVT-{999990000 + i:09d}" for i in range(6)]
rec.loc[orphan_rec_idx, "triggering_event_id"] = fake_event_ids

# --- write back ---------------------------------------------------------------

txn.to_csv(f"{DATA_DIR}/transactions.csv", index=False)
acct.to_csv(f"{DATA_DIR}/accounts.csv", index=False)
ev.to_csv(f"{DATA_DIR}/transaction_events.csv", index=False)
rec.to_csv(f"{DATA_DIR}/recovery_attempts.csv", index=False)

print("Post-injection row counts:", {n: len(d) for n, d in
      [("transactions", txn), ("accounts", acct), ("events", ev), ("recovery", rec)]})
print("Data quality issues injected.")
