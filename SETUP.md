# Setup & Navigation

Practical instructions for running this project locally. For the
project's business story, read `README.md` instead — this file is just
the "how do I get this running" reference.

## Folder structure

```
business-analysis/    Phases 1-5: business case, stakeholders, requirements,
                       process analysis, future-state design (all .md)
data/                  Phases 6-9: data dictionary, dataset design doc,
                       data quality report, and the dataset itself:
                         data/*.csv                 raw generated extract
                         data/clean/*.csv            analysis-ready tables
                                                      (quality-flag columns,
                                                      nothing silently dropped)
                         data/exceptions/*.csv       quarantined rows, each
                                                      with an exception_reason
scripts/               All Python that produced the above, in run order:
                         generate_dataset.py          Phase 8: builds data/*.csv
                         inject_data_quality_issues.py  Phase 9: injects issues
                         data_quality_checks.py       Phase 9: detects them
                         clean_dataset.py             Phase 9: produces
                                                       data/clean + data/exceptions
                         load_database.py             Phase 10: loads clean +
                                                       exceptions into DuckDB
                         run_sql_analysis.py          Phase 10: runs every
                                                       sql/*.sql query for real
                                                       and writes query-results.md
sql/                    Phase 10 + 12 + 13: 10 .sql files (36 business
                       questions total) plus query-results.md — real
                       captured output, nothing hand-typed. (kestrel.duckdb
                       itself is not distributed in delivered zips to keep
                       them small — rebuild it with load_database.py.)
analysis/               Phases 11, 12, 13, 14: root-cause-analysis.md,
                       recovery-intelligence.md, business-impact-model.md,
                       whatif-simulation.md
dashboard/              Phase 15: dashboard-design.md (the Power BI spec)
                       plus the two lookup CSVs it needs
recommendations/        Phase 16: business-recommendations.md
screenshots/            Placeholder for Power BI screenshots once built
                       (Phase 17/18)
```

## Setup — running this in VS Code

1. **Install Python 3.10+** if you don't have it (`python3 --version` to check).

2. **Open the folder in VS Code**: `File → Open Folder…` → select the
   unzipped `transaction-failure-intelligence` folder. Install the
   Microsoft **Python** extension if prompted.

3. **Create and activate a virtual environment** (Terminal → New Terminal
   inside VS Code):
   ```bash
   python3 -m venv .venv
   source .venv/bin/activate        # Windows: .venv\Scripts\activate
   ```
   In VS Code, when prompted (or via `Ctrl+Shift+P` → "Python: Select
   Interpreter"), pick the `.venv` interpreter so the terminal and any
   `.py` file you run use the same environment.

4. **Install dependencies**:
   ```bash
   pip install -r requirements.txt
   ```
   For the exact environment verified for this repository, use
   `pip install -r requirements.lock.txt` instead.

5. **Rebuild the DuckDB database**:
   ```bash
   python scripts/load_database.py
   ```
   This creates `sql/kestrel.duckdb` with 9 clean tables, 5 exception
   tables, and 4 raw tables, matching the row counts in
   `data/data-quality-report.md`.

6. **Re-run the SQL analysis** (optional — `sql/query-results.md` already
   has the captured output, but you can regenerate it or explore the
   queries yourself):
   ```bash
   python scripts/run_sql_analysis.py
   ```
   Or open `sql/kestrel.duckdb` directly with the VS Code **SQLTools**
   extension (with the SQLite/DuckDB driver) or the `duckdb` CLI
   (`duckdb sql/kestrel.duckdb`) to run individual queries from the
   `sql/*.sql` files interactively.

7. **Regenerating the dataset from scratch** (not needed to continue the
   project — `data/` already has the output — but useful if you want to
   see the generation logic run): `python scripts/generate_dataset.py`, then
   `python scripts/inject_data_quality_issues.py`, then
   `python scripts/data_quality_checks.py`, then
   `python scripts/clean_dataset.py`, in that order, from the project root. All use a
   fixed random seed, so re-running reproduces the same numbers documented
   in `data/dataset-design.md` and `data/data-quality-report.md`.

8. **Building the Power BI dashboard**: follow `dashboard/dashboard-design.md`
   end to end — it has the exact data types, relationships, and DAX
   measures needed. Import from `data/clean/*.csv` plus the two extra
   files in `dashboard/`.

## Where things stand

Phases 1-17 are complete (business case through the final case study in
this `README.md`). Remaining: Phase 15's actual `.pbix` build (spec is
done, the build itself is a manual Power BI Desktop exercise), Phase 18
(polish the GitHub repo structure and push it), Phase 19 (resume
bullets), and Phase 20 (interview preparation).
