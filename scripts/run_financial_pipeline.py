"""Rebuild the database, forecast, financial views, and reporting extracts."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = PROJECT_ROOT / "scripts"


def run(script_name: str) -> None:
    print(f"\n=== {script_name} ===")
    subprocess.run([sys.executable, str(SCRIPTS / script_name)], cwd=PROJECT_ROOT, check=True)


def main() -> None:
    run("load_database.py")
    run("run_financial_forecast.py")
    run("build_financial_reporting.py")


if __name__ == "__main__":
    main()
