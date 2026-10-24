"""
Synthetic dataset generator for the Bank Transaction Failure Intelligence project.

Implements the methodology documented in data/dataset-design.md. Fixed random
seed for reproducibility (NFR-02). Run with: python3 generate_dataset.py
"""

import numpy as np
import pandas as pd
from datetime import datetime, timedelta
from pathlib import Path

SEED = 42
rng = np.random.default_rng(SEED)

WINDOW_DAYS = 90
START_DATE = datetime(2026, 3, 16)  # 90 days ending ~2026-06-14, matches examples in the docs
N_CUSTOMERS = 12000
N_TARGET_TXNS = 180000

PROJECT_ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = PROJECT_ROOT / "data"
OUT_DIR.mkdir(parents=True, exist_ok=True)

# Three designated "stress days" modeled on the real April 2025 UPI volume/outage
# incident (business-case.md, Section 1). Each is a day offset into the window
# plus an hour window during which rtp rail_timeout/rail_outage rates spike.
STRESS_DAYS = [22, 51, 78]
STRESS_HOUR_START, STRESS_HOUR_END = 12, 16  # midday-afternoon peak window

ENGINEERING_FIX_DAY = 55  # PROCESSING_ERROR rate drops sharply after this day

# ---------------------------------------------------------------------------
# 1. Lookup tables
# ---------------------------------------------------------------------------

segments = pd.DataFrame([
    {"segment_id": "SEG-RETAIL-STD", "segment_name": "Retail-Standard", "segment_category": "retail"},
    {"segment_id": "SEG-RETAIL-PREM", "segment_name": "Retail-Premium", "segment_category": "retail"},
    {"segment_id": "SEG-SMB", "segment_name": "Small-Business", "segment_category": "small_business"},
])

channels = pd.DataFrame([
    {"channel_id": "CHN-MOBILE", "channel_name": "mobile_app"},
    {"channel_id": "CHN-WEB", "channel_name": "web"},
    {"channel_id": "CHN-POSATM", "channel_name": "pos_atm"},
    {"channel_id": "CHN-API", "channel_name": "api"},
])

rails = pd.DataFrame([
    {"rail_id": "RAIL-CARD", "rail_name": "card_network", "rail_owner": "external"},
    {"rail_id": "RAIL-ACH", "rail_name": "ach", "rail_owner": "external"},
    {"rail_id": "RAIL-RTP", "rail_name": "rtp", "rail_owner": "external"},
    {"rail_id": "RAIL-INTERNAL", "rail_name": "internal_ledger", "rail_owner": "internal"},
])

failure_reasons = pd.DataFrame([
    {"failure_reason_id": "FR-01", "reason_code": "CLIENT_INIT_FAILURE", "reason_description": "Client-side app/network failure before request reached backend", "lifecycle_stage": 1, "failure_category": "Technology", "origin": "internal", "default_recovery_track": "Not Applicable"},
    {"failure_reason_id": "FR-02", "reason_code": "AUTH_FAILED", "reason_description": "Authentication/session failure at transaction time", "lifecycle_stage": 2, "failure_category": "Technology", "origin": "internal", "default_recovery_track": "Auto-Retry"},
    {"failure_reason_id": "FR-03", "reason_code": "VALIDATION_FAILED", "reason_description": "Invalid or malformed transaction request", "lifecycle_stage": 3, "failure_category": "Process", "origin": "internal", "default_recovery_track": "Not Applicable"},
    {"failure_reason_id": "FR-04", "reason_code": "RISK_HELD", "reason_description": "Transaction held by risk/fraud screening pending review", "lifecycle_stage": 4, "failure_category": "Risk", "origin": "internal", "default_recovery_track": "Do Not Retry-Monitor"},
    {"failure_reason_id": "FR-05", "reason_code": "RISK_ENGINE_TIMEOUT", "reason_description": "Risk engine failed to respond within SLA", "lifecycle_stage": 4, "failure_category": "Technology", "origin": "internal", "default_recovery_track": "Auto-Retry"},
    {"failure_reason_id": "FR-06", "reason_code": "BALANCE_DECLINED_INSUFFICIENT_FUNDS", "reason_description": "Insufficient funds in source account", "lifecycle_stage": 5, "failure_category": "Process", "origin": "internal", "default_recovery_track": "Customer Intervention"},
    {"failure_reason_id": "FR-07", "reason_code": "BALANCE_DECLINED_STALE_READ", "reason_description": "Balance check used a stale/out-of-date read", "lifecycle_stage": 5, "failure_category": "Technology", "origin": "internal", "default_recovery_track": "Auto-Retry"},
    {"failure_reason_id": "FR-08", "reason_code": "ACCOUNT_RESTRICTED_DECLINE", "reason_description": "Source account is restricted or frozen", "lifecycle_stage": 5, "failure_category": "Policy", "origin": "internal", "default_recovery_track": "Do Not Retry-Monitor"},
    {"failure_reason_id": "FR-09", "reason_code": "PROCESSING_ERROR", "reason_description": "Internal orchestration/routing error before rail submission", "lifecycle_stage": 6, "failure_category": "Technology", "origin": "internal", "default_recovery_track": "Engineering Fix"},
    {"failure_reason_id": "FR-10", "reason_code": "RAIL_DECLINED_ISSUER", "reason_description": "Counterparty issuer/bank declined the transaction", "lifecycle_stage": 7, "failure_category": "External Dependency", "origin": "external", "default_recovery_track": "Do Not Retry-Monitor"},
    {"failure_reason_id": "FR-11", "reason_code": "RAIL_TIMEOUT", "reason_description": "External payment rail did not respond within timeout", "lifecycle_stage": 7, "failure_category": "External Dependency", "origin": "external", "default_recovery_track": "Auto-Retry"},
    {"failure_reason_id": "FR-12", "reason_code": "RAIL_OUTAGE", "reason_description": "External payment rail reported a service outage", "lifecycle_stage": 7, "failure_category": "External Dependency", "origin": "external", "default_recovery_track": "Do Not Retry-Monitor"},
])
FR = failure_reasons.set_index("reason_code").to_dict("index")

# Which failures get OUTCOME_TEMP_FAILURE (pursued for recovery) vs
# OUTCOME_PERMANENT_FAILURE immediately (see dataset-design.md Section 5 logic).
TEMP_FAILURE_CODES = {"AUTH_FAILED", "RISK_ENGINE_TIMEOUT", "BALANCE_DECLINED_INSUFFICIENT_FUNDS",
                       "BALANCE_DECLINED_STALE_READ", "RAIL_TIMEOUT", "RISK_HELD", "RAIL_OUTAGE"}

# ---------------------------------------------------------------------------
# 2. Customers and Accounts
# ---------------------------------------------------------------------------

customer_type = rng.choice(["retail", "small_business"], size=N_CUSTOMERS, p=[0.92, 0.08])
seg_for_customer = []
for ct in customer_type:
    if ct == "small_business":
        seg_for_customer.append("SEG-SMB")
    else:
        seg_for_customer.append(rng.choice(["SEG-RETAIL-STD", "SEG-RETAIL-PREM"], p=[0.8, 0.2]))

signup_days_ago = rng.integers(30, 365 * 4, size=N_CUSTOMERS)
customers = pd.DataFrame({
    "customer_id": [f"CUST-{i:07d}" for i in range(N_CUSTOMERS)],
    "segment_id": seg_for_customer,
    "customer_type": customer_type,
    "signup_date": [(START_DATE - timedelta(days=int(d))).date().isoformat() for d in signup_days_ago],
})

# "Problem cohort": ~4% of customers with an elevated failure multiplier across
# all stages (data-dictionary/dataset-design Section 3, point 3). Not a stored
# field -- an internal generation-time weight only.
problem_flag = rng.random(N_CUSTOMERS) < 0.04
problem_multiplier = np.where(problem_flag, 3.0, 1.0)
customer_problem_mult = dict(zip(customers["customer_id"], problem_multiplier))

accounts_rows = []
acct_counter = 0
for idx, row in customers.iterrows():
    n_accounts = 1
    if row["customer_type"] == "small_business":
        n_accounts = rng.choice([1, 2, 3], p=[0.5, 0.35, 0.15])
    else:
        n_accounts = rng.choice([1, 2], p=[0.75, 0.25])
    for j in range(n_accounts):
        acct_type = "business" if row["customer_type"] == "small_business" else rng.choice(["checking", "savings"], p=[0.8, 0.2])
        status = rng.choice(["active", "restricted", "closed"], p=[0.965, 0.02, 0.015])
        opened_days_ago = rng.integers(1, 365 * 4)
        accounts_rows.append({
            "account_id": f"ACCT-{acct_counter:07d}",
            "customer_id": row["customer_id"],
            "account_type": acct_type,
            "account_status": status,
            "opened_date": (START_DATE - timedelta(days=int(opened_days_ago))).date().isoformat(),
        })
        acct_counter += 1

accounts = pd.DataFrame(accounts_rows)
active_accounts = accounts[accounts["account_status"] == "active"].reset_index(drop=True)
account_to_customer = dict(zip(accounts["account_id"], accounts["customer_id"]))
account_to_status = dict(zip(accounts["account_id"], accounts["account_status"]))
customer_to_type = dict(zip(customers["customer_id"], customers["customer_type"]))

print(f"Customers: {len(customers)}, Accounts: {len(accounts)} ({len(active_accounts)} active)")

# ---------------------------------------------------------------------------
# 3. Transactions (header attributes)
# ---------------------------------------------------------------------------

# Weighted account activity (power-law-ish): some accounts transact far more than others.
# Restricted accounts are included (at low weight) specifically so
# ACCOUNT_RESTRICTED_DECLINE actually has transactions to attach to -- closed
# accounts are excluded entirely (no legitimate way to initiate from one).
transactable_accounts = accounts[accounts["account_status"] != "closed"].reset_index(drop=True)
activity_weight = rng.gamma(shape=1.5, scale=1.0, size=len(transactable_accounts))
is_restricted = (transactable_accounts["account_status"] == "restricted").values
activity_weight = np.where(is_restricted, activity_weight * 0.1, activity_weight)
activity_weight = activity_weight / activity_weight.sum()
chosen_accounts = rng.choice(transactable_accounts["account_id"].values, size=N_TARGET_TXNS, p=activity_weight)

RETAIL_TYPES = ["p2p", "external_transfer", "bill_pay", "card_pos", "rtp_transfer"]
RETAIL_TYPE_P = [0.28, 0.18, 0.17, 0.25, 0.12]
SMB_TYPES = ["wire", "payroll", "external_transfer", "bill_pay"]
SMB_TYPE_P = [0.20, 0.15, 0.35, 0.30]

CHANNEL_ID_TO_NAME = dict(zip(channels["channel_id"], channels["channel_name"]))

TYPE_TO_RAIL = {
    "p2p": "RAIL-INTERNAL", "external_transfer": "RAIL-ACH", "bill_pay": "RAIL-ACH",
    "card_pos": "RAIL-CARD", "rtp_transfer": "RAIL-RTP", "wire": "RAIL-ACH", "payroll": "RAIL-ACH",
}
TYPE_TO_COUNTERPARTY = {
    "p2p": "internal_kestrel_customer", "external_transfer": "external_bank_account",
    "bill_pay": "business_payee", "card_pos": "business_payee", "rtp_transfer": "external_bank_account",
    "wire": "external_bank_account", "payroll": "business_payee",
}
# log-normal amount params (mean, sigma of underlying normal) per type -- PaySim-informed
# right-skewed shape; medians roughly reflect the product each type represents.
AMOUNT_PARAMS = {
    "p2p": (3.6, 0.9), "external_transfer": (5.2, 1.0), "bill_pay": (4.3, 0.8),
    "card_pos": (3.0, 1.0), "rtp_transfer": (4.8, 0.9), "wire": (7.5, 1.1), "payroll": (7.0, 0.6),
}
# PaySim-informed: transfer-type transactions get elevated risk-hold likelihood
RISK_MULT_BY_TYPE = {"wire": 1.6, "payroll": 1.6, "external_transfer": 1.6, "rtp_transfer": 1.6,
                      "p2p": 1.0, "card_pos": 0.6, "bill_pay": 0.6}

txn_types = []
for acct_id in chosen_accounts:
    cust_id = account_to_customer[acct_id]
    ctype = customer_to_type[cust_id]
    if ctype == "small_business":
        txn_types.append(rng.choice(SMB_TYPES, p=SMB_TYPE_P))
    else:
        txn_types.append(rng.choice(RETAIL_TYPES, p=RETAIL_TYPE_P))
txn_types = np.array(txn_types)

# Channel: SMB skews to web/api, retail skews to mobile
channel_for_txn = []
for acct_id in chosen_accounts:
    cust_id = account_to_customer[acct_id]
    ctype = customer_to_type[cust_id]
    if ctype == "small_business":
        channel_for_txn.append(rng.choice(["mobile_app", "web", "pos_atm", "api"], p=[0.15, 0.35, 0.05, 0.45]))
    else:
        channel_for_txn.append(rng.choice(["mobile_app", "web", "pos_atm", "api"], p=[0.68, 0.20, 0.11, 0.01]))
channel_for_txn = np.array(channel_for_txn)
channel_name_to_id = dict(zip(channels["channel_name"], channels["channel_id"]))

rail_for_txn = np.array([TYPE_TO_RAIL[t] for t in txn_types])
counterparty_for_txn = np.array([TYPE_TO_COUNTERPARTY[t] for t in txn_types])

amounts = np.empty(N_TARGET_TXNS)
for t, (mu, sigma) in AMOUNT_PARAMS.items():
    mask = txn_types == t
    n = mask.sum()
    if n:
        amounts[mask] = np.round(rng.lognormal(mean=mu, sigma=sigma, size=n), 2)
amounts = np.clip(amounts, 1.0, 250000.0)

# Timestamps: day-of-week + intraday shape, with elevated volume on stress days
# ~20% elevated volume on the 3 stress days, per dataset-design.md Section 3, point 4
day_weights = np.ones(WINDOW_DAYS)
for d in STRESS_DAYS:
    day_weights[d] = 1.2
day_weights = day_weights / day_weights.sum()
day_offsets = rng.choice(WINDOW_DAYS, size=N_TARGET_TXNS, p=day_weights)
# Business days get slightly more volume for wire/payroll; keep simple: uniform day pick,
# then bias hour-of-day using a daytime curve (low overnight, peak midday/afternoon).
HOURLY_WEIGHTS = np.array([0.3,0.2,0.15,0.1,0.1,0.3,0.8,1.5,2.5,4,5.5,6.5,
                            7,6.5,6,5.5,5.5,6,6.5,6,5,4,2,1])
hour_choices = rng.choice(range(24), size=N_TARGET_TXNS, p=HOURLY_WEIGHTS / HOURLY_WEIGHTS.sum())
minute_choices = rng.integers(0, 60, size=N_TARGET_TXNS)
second_choices = rng.integers(0, 60, size=N_TARGET_TXNS)

initiated_at = [START_DATE + timedelta(days=int(d), hours=int(h), minutes=int(m), seconds=int(s))
                for d, h, m, s in zip(day_offsets, hour_choices, minute_choices, second_choices)]

transactions = pd.DataFrame({
    "transaction_id": [f"TXN-{i:08d}" for i in range(N_TARGET_TXNS)],
    "account_id": chosen_accounts,
    "channel_id": [channel_name_to_id[c] for c in channel_for_txn],
    "rail_id": rail_for_txn,
    "transaction_type": txn_types,
    "counterparty_type": counterparty_for_txn,
    "amount": amounts,
    "initiated_at": initiated_at,
    "day_offset_tmp": day_offsets,
    "hour_tmp": hour_choices,
})

print(f"Transactions generated: {len(transactions)}")

# ---------------------------------------------------------------------------
# 4. Lifecycle simulation
# ---------------------------------------------------------------------------

events_rows = []
recovery_rows = []
event_counter = 0
recovery_counter = 0
final_status_list = []
final_outcome_at_list = []

def new_event(txn_id, seq, stage, etype, ts, failure_reason_id=None, risk_score=None):
    global event_counter
    event_counter += 1
    events_rows.append({
        "event_id": f"EVT-{event_counter:09d}", "transaction_id": txn_id, "event_sequence": seq,
        "lifecycle_stage": stage, "event_type": etype, "event_timestamp": ts,
        "failure_reason_id": failure_reason_id, "risk_score": risk_score,
    })

def new_recovery(txn_id, trigger_event_id, track, attempt_number, initiated_at, completed_at, outcome):
    global recovery_counter
    recovery_counter += 1
    recovery_rows.append({
        "recovery_attempt_id": f"REC-{recovery_counter:06d}", "transaction_id": txn_id,
        "triggering_event_id": trigger_event_id, "recovery_track": track, "attempt_number": attempt_number,
        "initiated_at": initiated_at, "completed_at": completed_at, "outcome": outcome,
    })

# snapshot time = end of the 90-day window; anything unresolved right at the edge -> pending
SNAPSHOT_TIME = START_DATE + timedelta(days=WINDOW_DAYS)

for row in transactions.itertuples(index=False):
    txn_id = row.transaction_id
    acct_id = row.account_id
    cust_id = account_to_customer[acct_id]
    pmult = customer_problem_mult[cust_id]
    chan = row.channel_id
    ttype = row.transaction_type
    day_off = row.day_offset_tmp
    hour = row.hour_tmp
    t0 = row.initiated_at

    seq = 1
    new_event(txn_id, seq, 1, "TXN_INITIATED", t0); seq += 1

    # channel multipliers
    chan_name = CHANNEL_ID_TO_NAME[chan]

    web_mult = 1.4 if chan_name == "web" else 1.0
    posatm_mult = 1.3 if chan_name == "pos_atm" else 1.0
    api_risk_mult = 1.5 if chan_name == "api" else 1.0
    api_proc_mult = 1.3 if chan_name == "api" else 1.0
    risk_type_mult = RISK_MULT_BY_TYPE.get(ttype, 1.0)

    is_stress_window = (day_off in STRESS_DAYS) and (STRESS_HOUR_START <= hour <= STRESS_HOUR_END) and (row.rail_id == "RAIL-RTP")

    failed = False
    failure_code = None
    fail_stage = None

    # Stage 1: client init failure
    if rng.random() < 0.003 * pmult:
        new_event(txn_id, seq, 1, "CLIENT_INIT_FAILURE", t0, "FR-01"); seq += 1
        failed, failure_code, fail_stage = True, "CLIENT_INIT_FAILURE", 1

    # Stage 2: authentication
    if not failed and rng.random() < 0.004 * pmult * web_mult:
        new_event(txn_id, seq, 2, "AUTH_FAILED", t0, "FR-02"); seq += 1
        failed, failure_code, fail_stage = True, "AUTH_FAILED", 2

    # Stage 3: validation
    if not failed and rng.random() < 0.005 * pmult:
        new_event(txn_id, seq, 3, "VALIDATION_FAILED", t0, "FR-03"); seq += 1
        failed, failure_code, fail_stage = True, "VALIDATION_FAILED", 3

    # Stage 4: risk screening (always produces an event -- risk_score always populated)
    risk_score = int(np.clip(rng.normal(30, 15) + (20 if ttype in ("wire", "payroll") else 0), 0, 100))
    if not failed:
        p_risk_held = 0.010 * pmult * risk_type_mult * api_risk_mult
        p_risk_timeout = 0.002 * pmult * api_risk_mult
        roll = rng.random()
        if roll < p_risk_timeout:
            new_event(txn_id, seq, 4, "RISK_ENGINE_TIMEOUT", t0, "FR-05", risk_score); seq += 1
            failed, failure_code, fail_stage = True, "RISK_ENGINE_TIMEOUT", 4
        elif roll < p_risk_timeout + p_risk_held:
            new_event(txn_id, seq, 4, "RISK_HELD", t0, "FR-04", risk_score); seq += 1
            failed, failure_code, fail_stage = True, "RISK_HELD", 4
        else:
            new_event(txn_id, seq, 4, "RISK_CLEARED", t0, None, risk_score); seq += 1

    # Stage 5: balance / account validation
    if not failed:
        if account_to_status[acct_id] == "restricted" and rng.random() < 0.6:
            new_event(txn_id, seq, 5, "ACCOUNT_RESTRICTED_DECLINE", t0, "FR-08"); seq += 1
            failed, failure_code, fail_stage = True, "ACCOUNT_RESTRICTED_DECLINE", 5
        else:
            roll = rng.random()
            p_insuff = 0.013 * pmult
            p_stale = 0.003 * pmult
            if roll < p_stale:
                new_event(txn_id, seq, 5, "BALANCE_DECLINED_STALE_READ", t0, "FR-07"); seq += 1
                failed, failure_code, fail_stage = True, "BALANCE_DECLINED_STALE_READ", 5
            elif roll < p_stale + p_insuff:
                new_event(txn_id, seq, 5, "BALANCE_DECLINED_INSUFFICIENT_FUNDS", t0, "FR-06"); seq += 1
                failed, failure_code, fail_stage = True, "BALANCE_DECLINED_INSUFFICIENT_FUNDS", 5

    # Stage 6: payment processing
    if not failed:
        p_proc_err = (0.0025 if day_off < ENGINEERING_FIX_DAY else 0.0005) * pmult * api_proc_mult
        if rng.random() < p_proc_err:
            new_event(txn_id, seq, 6, "PROCESSING_ERROR", t0, "FR-09"); seq += 1
            failed, failure_code, fail_stage = True, "PROCESSING_ERROR", 6

    # Stage 7: external network response (internal_ledger transfers skip rail risk)
    if not failed and row.rail_id != "RAIL-INTERNAL":
        p_issuer = 0.010 * pmult * posatm_mult
        p_timeout = 0.005 * pmult * posatm_mult * (8.0 if is_stress_window else 1.0)
        p_outage = 0.001 * pmult * (15.0 if is_stress_window else 1.0)
        roll = rng.random()
        if roll < p_outage:
            new_event(txn_id, seq, 7, "RAIL_OUTAGE", t0, "FR-12"); seq += 1
            failed, failure_code, fail_stage = True, "RAIL_OUTAGE", 7
        elif roll < p_outage + p_timeout:
            new_event(txn_id, seq, 7, "RAIL_TIMEOUT", t0, "FR-11"); seq += 1
            failed, failure_code, fail_stage = True, "RAIL_TIMEOUT", 7
        elif roll < p_outage + p_timeout + p_issuer:
            new_event(txn_id, seq, 7, "RAIL_DECLINED_ISSUER", t0, "FR-10"); seq += 1
            failed, failure_code, fail_stage = True, "RAIL_DECLINED_ISSUER", 7

    # ---- Stage 8: outcome determination ----
    if not failed:
        new_event(txn_id, seq, 8, "OUTCOME_SUCCESS", t0); seq += 1
        new_event(txn_id, seq, 10, "FINAL_SETTLED", t0 + timedelta(seconds=3)); seq += 1
        new_event(txn_id, seq, 10, "CUSTOMER_NOTIFIED", t0 + timedelta(seconds=5)); seq += 1
        final_status_list.append("success")
        final_outcome_at_list.append(t0 + timedelta(seconds=5))
        continue

    is_temp = failure_code in TEMP_FAILURE_CODES
    outcome_evt = "OUTCOME_TEMP_FAILURE" if is_temp else "OUTCOME_PERMANENT_FAILURE"
    new_event(txn_id, seq, 8, outcome_evt, t0); seq += 1
    # the failure event is the one immediately before the OUTCOME_* event just added
    failure_event_id = events_rows[-2]["event_id"]

    # near end-of-window: a slice of unresolved failures become 'pending'
    is_near_edge = day_off >= WINDOW_DAYS - 1
    force_pending = is_temp and is_near_edge and rng.random() < 0.5

    if not is_temp or force_pending:
        if force_pending:
            final_status_list.append("pending")
            final_outcome_at_list.append(pd.NaT)
        else:
            new_event(txn_id, seq, 10, "FINAL_PERMANENTLY_FAILED", t0 + timedelta(minutes=2)); seq += 1
            new_event(txn_id, seq, 10, "CUSTOMER_NOTIFIED", t0 + timedelta(minutes=3)); seq += 1
            final_status_list.append("permanently_failed")
            final_outcome_at_list.append(t0 + timedelta(minutes=3))
        continue

    # ---- Recovery routing (Stage 9) ----
    track = FR[failure_code]["default_recovery_track"]
    recovered = False
    last_completed = t0

    if track == "Auto-Retry":
        max_attempts = int(rng.integers(1, 4))
        for attempt in range(1, max_attempts + 1):
            rt = t0 + timedelta(seconds=10 * attempt)
            ct = rt + timedelta(seconds=int(rng.integers(2, 20)))
            success = rng.random() < rng.uniform(0.70, 0.85)
            new_event(txn_id, seq, 9, "RETRY_INITIATED", rt); seq += 1
            outcome = "recovered" if success else "still_failed"
            new_recovery(txn_id, failure_event_id, track, attempt, rt, ct, outcome)
            new_event(txn_id, seq, 9, "RETRY_SUCCESS" if success else "RETRY_FAILED", ct); seq += 1
            last_completed = ct
            if success:
                recovered = True
                break
    elif track == "Customer Intervention":
        rt = t0 + timedelta(hours=int(rng.integers(1, 12)))
        ct = rt + timedelta(hours=int(rng.integers(1, 36)))
        success = rng.random() < rng.uniform(0.30, 0.50)
        outcome = "recovered" if success else "still_failed"
        new_recovery(txn_id, failure_event_id, track, 1, rt, ct, outcome)
        new_event(txn_id, seq, 9, "RETRY_INITIATED", rt); seq += 1
        new_event(txn_id, seq, 9, "RETRY_SUCCESS" if success else "RETRY_FAILED", ct); seq += 1
        last_completed = ct
        recovered = success
    elif track == "Do Not Retry-Monitor" and failure_code == "RISK_HELD":
        rt = t0 + timedelta(hours=int(rng.integers(2, 6)))
        ct = rt + timedelta(hours=int(rng.integers(2, 20)))
        success = rng.random() < 0.40
        outcome = "recovered" if success else "still_failed"
        new_recovery(txn_id, failure_event_id, track, 1, rt, ct, outcome)
        new_event(txn_id, seq, 4, "RISK_REVIEWED_CONFIRMED_LEGITIMATE" if success else "RISK_REVIEWED_CONFIRMED_FRAUD", ct); seq += 1
        last_completed = ct
        recovered = success
    elif track == "Do Not Retry-Monitor" and failure_code == "RAIL_OUTAGE":
        outage_clear = t0.replace(hour=STRESS_HOUR_END, minute=0, second=0) + timedelta(hours=1)
        if outage_clear < t0:
            outage_clear = t0 + timedelta(hours=1)
        ct = outage_clear + timedelta(minutes=int(rng.integers(1, 30)))
        success = rng.random() < 0.90
        outcome = "recovered" if success else "still_failed"
        new_recovery(txn_id, failure_event_id, track, 1, t0, ct, outcome)
        new_event(txn_id, seq, 9, "RETRY_INITIATED", outage_clear); seq += 1
        new_event(txn_id, seq, 9, "RETRY_SUCCESS" if success else "RETRY_FAILED", ct); seq += 1
        last_completed = ct
        recovered = success

    if recovered:
        new_event(txn_id, seq, 10, "FINAL_RECOVERED", last_completed + timedelta(seconds=2)); seq += 1
        new_event(txn_id, seq, 10, "CUSTOMER_NOTIFIED", last_completed + timedelta(seconds=5)); seq += 1
        final_status_list.append("recovered_success")
        final_outcome_at_list.append(last_completed + timedelta(seconds=5))
    else:
        new_event(txn_id, seq, 10, "FINAL_PERMANENTLY_FAILED", last_completed + timedelta(seconds=2)); seq += 1
        new_event(txn_id, seq, 10, "CUSTOMER_NOTIFIED", last_completed + timedelta(seconds=5)); seq += 1
        final_status_list.append("permanently_failed")
        final_outcome_at_list.append(last_completed + timedelta(seconds=5))

transactions["final_status"] = final_status_list
transactions["final_outcome_at"] = final_outcome_at_list
transactions = transactions.drop(columns=["day_offset_tmp", "hour_tmp"])

events = pd.DataFrame(events_rows)
recovery_attempts = pd.DataFrame(recovery_rows)

print(f"Events generated: {len(events)}")
print(f"Recovery attempts generated: {len(recovery_attempts)}")

# ---------------------------------------------------------------------------
# 5. Write outputs
# ---------------------------------------------------------------------------

segments.to_csv(f"{OUT_DIR}/customer_segments.csv", index=False)
channels.to_csv(f"{OUT_DIR}/channels.csv", index=False)
rails.to_csv(f"{OUT_DIR}/payment_rails.csv", index=False)
failure_reasons.to_csv(f"{OUT_DIR}/failure_reasons.csv", index=False)
customers.to_csv(f"{OUT_DIR}/customers.csv", index=False)
accounts.to_csv(f"{OUT_DIR}/accounts.csv", index=False)
transactions.to_csv(f"{OUT_DIR}/transactions.csv", index=False)
events.to_csv(f"{OUT_DIR}/transaction_events.csv", index=False)
recovery_attempts.to_csv(f"{OUT_DIR}/recovery_attempts.csv", index=False)

print("All CSVs written to", OUT_DIR)
