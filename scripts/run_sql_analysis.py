"""
Executes every query in sql/*.sql against the DuckDB database built by
load_database.py, and writes real captured output to sql/query-results.md.
Splits each file on semicolons (each query in these files ends with one),
skipping comment-only fragments. Run with: python3 run_sql_analysis.py
"""

import duckdb
import glob
import os
import re

DB_PATH = "/home/claude/bank-transaction-failure-intelligence/sql/kestrel.duckdb"
SQL_DIR = "/home/claude/bank-transaction-failure-intelligence/sql"
OUT_PATH = f"{SQL_DIR}/query-results.md"

con = duckdb.connect(DB_PATH, read_only=True)

def split_statements(text):
    # split on semicolons that end a statement; keep the preceding comment
    # block attached to each statement so we can show the business question.
    parts = re.split(r";\s*\n", text)
    statements = []
    for p in parts:
        p = p.strip()
        if not p:
            continue
        # a fragment is a real statement if it has a non-comment line
        if any(line.strip() and not line.strip().startswith("--") for line in p.split("\n")):
            statements.append(p + ";")
    return statements

def extract_label(stmt):
    m = re.search(r"--\s*(Q\d[^\n]*)", stmt)
    return m.group(1).strip() if m else "Query"

report_lines = []
files = sorted(glob.glob(f"{SQL_DIR}/*.sql"))
for f in files:
    fname = os.path.basename(f)
    with open(f) as fh:
        text = fh.read()
    report_lines.append(f"\n## `{fname}`\n")
    statements = split_statements(text)
    for i, stmt in enumerate(statements, 1):
        label = extract_label(stmt)
        report_lines.append(f"\n### {label}\n")
        # pull the full comment block preceding the SQL as documentation
        comment_lines = [l for l in stmt.split("\n") if l.strip().startswith("--")]
        doc = "\n".join(l.lstrip("- ").strip() for l in comment_lines if l.strip() not in ("--",))
        if doc:
            report_lines.append(f"*{doc}*\n")
        try:
            df = con.execute(stmt).fetchdf()
            report_lines.append(f"```\n{df.to_string(index=False, max_rows=20)}\n```\n")
            print(f"[OK] {fname} :: {label} -> {len(df)} rows")
        except Exception as e:
            report_lines.append(f"**ERROR:** {e}\n")
            print(f"[FAIL] {fname} :: {label} -> {e}")

with open(OUT_PATH, "w") as fh:
    fh.write("# SQL Analysis — Captured Query Results\n")
    fh.write("\nEvery result below is real output from running the queries in this folder ")
    fh.write("against the Phase 9 clean dataset (DuckDB). Nothing here is hand-typed.\n")
    fh.write("\n".join(report_lines))

print(f"\nWrote {OUT_PATH}")
con.close()
