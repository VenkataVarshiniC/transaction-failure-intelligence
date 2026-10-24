"""
Loads the Phase 9 clean dataset into a DuckDB database file so the Phase 10
SQL scripts run against real tables. Run with: python3 load_database.py
"""

import duckdb
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
DATA_DIR = PROJECT_ROOT / "data"
DB_PATH = PROJECT_ROOT / "sql" / "kestrel.duckdb"

DB_PATH.parent.mkdir(parents=True, exist_ok=True)
DB_PATH.unlink(missing_ok=True)

con = duckdb.connect(str(DB_PATH))

TABLES = {
    "customer_segments": "clean/customer_segments.csv",
    "customers": "clean/customers.csv",
    "channels": "clean/channels.csv",
    "payment_rails": "clean/payment_rails.csv",
    "failure_reasons": "clean/failure_reasons.csv",
    "accounts": "clean/accounts.csv",
    "transactions": "clean/transactions.csv",
    "transaction_events": "clean/transaction_events.csv",
    "recovery_attempts": "clean/recovery_attempts.csv",
    "exceptions_transactions_duplicates": "exceptions/transactions_duplicates.csv",
    "exceptions_accounts_orphan": "exceptions/accounts_orphan_customer.csv",
    "exceptions_events_duplicates": "exceptions/events_duplicates.csv",
    "exceptions_events_orphan": "exceptions/events_orphan_transaction.csv",
    "exceptions_recovery_orphan": "exceptions/recovery_orphan_event.csv",
}

for table, relpath in TABLES.items():
    csv_path = (DATA_DIR / relpath).as_posix()
    con.execute(f"CREATE TABLE {table} AS SELECT * FROM read_csv_auto('{csv_path}', header=True)")
    n = con.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
    print(f"Loaded {table}: {n} rows")

# also load the RAW (pre-clean) transactions/events for the 01_data_quality.sql script
con.execute(f"CREATE TABLE raw_transactions AS SELECT * FROM read_csv_auto('{(DATA_DIR / 'transactions.csv').as_posix()}', header=True)")
con.execute(f"CREATE TABLE raw_transaction_events AS SELECT * FROM read_csv_auto('{(DATA_DIR / 'transaction_events.csv').as_posix()}', header=True)")
con.execute(f"CREATE TABLE raw_accounts AS SELECT * FROM read_csv_auto('{(DATA_DIR / 'accounts.csv').as_posix()}', header=True)")
con.execute(f"CREATE TABLE raw_recovery_attempts AS SELECT * FROM read_csv_auto('{(DATA_DIR / 'recovery_attempts.csv').as_posix()}', header=True)")
print("Loaded raw_* tables for data-quality re-verification")

con.close()
print(f"\nDatabase written to {DB_PATH}")
