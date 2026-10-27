from __future__ import annotations

import subprocess
import sys
import unittest
from pathlib import Path

import duckdb
import pandas as pd


PROJECT_ROOT = Path(__file__).resolve().parents[1]
DB_PATH = PROJECT_ROOT / "sql" / "kestrel.duckdb"
REPORTING_DIR = PROJECT_ROOT / "data" / "reporting"


class FinancialPlatformTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        subprocess.run(
            [sys.executable, str(PROJECT_ROOT / "scripts" / "run_financial_pipeline.py")],
            cwd=PROJECT_ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        cls.con = duckdb.connect(str(DB_PATH), read_only=True)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.con.close()

    def test_baseline_metrics_preserved(self) -> None:
        row = self.con.execute(
            """
            SELECT COUNT(*),
                   COUNT(*) FILTER (WHERE final_status != 'success'),
                   ROUND(100.0 * COUNT(*) FILTER (WHERE final_status != 'success') / COUNT(*), 2),
                   ROUND(SUM(CASE WHEN is_valid_amount AND final_status != 'success' THEN amount ELSE 0 END), 2),
                   ROUND(SUM(CASE WHEN is_valid_amount AND final_status = 'recovered_success' THEN amount ELSE 0 END), 2)
            FROM transactions
            """
        ).fetchone()
        self.assertEqual(row, (180000, 10681, 5.93, 2603613.29, 916896.23))

    def test_duplicate_handling_reconciles(self) -> None:
        raw, clean, quarantined, distinct_clean = self.con.execute(
            """
            SELECT (SELECT COUNT(*) FROM raw_transactions),
                   (SELECT COUNT(*) FROM transactions),
                   (SELECT COUNT(*) FROM exceptions_transactions_duplicates),
                   (SELECT COUNT(DISTINCT transaction_id) FROM transactions)
            """
        ).fetchone()
        self.assertEqual(raw, clean + quarantined)
        self.assertEqual(clean, distinct_clean)

    def test_source_to_report_reconciliations_pass(self) -> None:
        failures = self.con.execute(
            "SELECT COUNT(*) FROM vw_source_to_report_reconciliation WHERE NOT reconciles"
        ).fetchone()[0]
        self.assertEqual(failures, 0)

    def test_cost_model_and_allocation(self) -> None:
        kpi = self.con.execute("SELECT * FROM vw_financial_kpis").fetchdf().iloc[0]
        self.assertAlmostEqual(kpi["total_modeled_opex_usd"], 137142.45, places=2)
        self.assertAlmostEqual(kpi["opex_per_transaction_usd"], 0.7619, places=4)
        self.assertAlmostEqual(kpi["recovery_cost_per_successful_recovery_usd"], 5.3102, places=4)
        segment_total, channel_total, opex_total = self.con.execute(
            """
            SELECT
              (SELECT SUM(modeled_operational_cost_usd) FROM vw_customer_segment_financial_impact),
              (SELECT SUM(modeled_operational_cost_usd) FROM vw_payment_channel_profitability),
              (SELECT SUM(total_opex_usd) FROM vw_monthly_opex)
            """
        ).fetchone()
        self.assertAlmostEqual(segment_total, opex_total, delta=0.02)
        self.assertAlmostEqual(channel_total, opex_total, delta=0.02)

    def test_cost_classes_are_explicit(self) -> None:
        classes = {
            row[0]
            for row in self.con.execute("SELECT DISTINCT cost_class FROM financial_assumptions").fetchall()
        }
        self.assertTrue({"variable", "recurring_fixed", "modeled_revenue"}.issubset(classes))
        one_time_costs = self.con.execute(
            "SELECT MIN(implementation_cost_usd) FROM recovery_scenarios"
        ).fetchone()[0]
        self.assertGreater(one_time_costs, 0)

    def test_scenario_math_and_no_principal_double_count(self) -> None:
        scenarios = self.con.execute("SELECT * FROM vw_net_recovery_benefit").fetchdf()
        recomputed = (
            scenarios["incremental_fee_revenue_usd"]
            + scenarios["avoided_operational_cost_usd"]
            - scenarios["additional_retry_cost_usd"]
            - scenarios["additional_servicing_cost_usd"]
            - scenarios["implementation_cost_usd"]
            - scenarios["analysis_window_recurring_cost_usd"]
        )
        self.assertTrue(((recomputed - scenarios["net_financial_benefit_usd"]).abs() < 0.02).all())
        self.assertTrue((scenarios["incremental_processed_value_usd"] > scenarios["incremental_fee_revenue_usd"]).all())
        self.assertEqual(scenarios["target_reason"].nunique(), len(scenarios))

    def test_combined_scenario_is_sum_of_non_overlapping_interventions(self) -> None:
        individual, combined = self.con.execute(
            """
            SELECT
              (SELECT ROUND(SUM(net_financial_benefit_usd), 2) FROM vw_net_recovery_benefit),
              (SELECT ROUND(net_financial_benefit_usd, 2) FROM vw_scenario_comparison WHERE scenario_id = 'E')
            """
        ).fetchone()
        self.assertEqual(individual, combined)

    def test_budget_variance_formula(self) -> None:
        failures = self.con.execute(
            """
            SELECT COUNT(*) FROM vw_budget_vs_actual
            WHERE ABS(favorable_variance_usd - (budget_usd - modeled_actual_usd)) >= 0.011
            """
        ).fetchone()[0]
        self.assertEqual(failures, 0)

    def test_forecast_holdout_and_constraints(self) -> None:
        validation = pd.read_csv(REPORTING_DIR / "forecast_validation.csv")
        monthly = pd.read_csv(REPORTING_DIR / "forecast_monthly.csv")
        self.assertEqual(set(validation["model"]), {"weekday_seasonal_naive", "linear_trend_weekday"})
        self.assertEqual(int(validation["selected"].sum()), 3)
        self.assertTrue((validation["holdout_days"] == 14).all())
        self.assertTrue((monthly["failure_volume"] <= monthly["transaction_volume"]).all())
        self.assertTrue((monthly["recovery_volume"] <= monthly["failure_volume"]).all())
        self.assertTrue((monthly["total_opex_usd"] > 0).all())
        self.assertTrue((monthly["forecast_type"] == "synthetic_scenario_projection").all())

    def test_forecast_reproducibility(self) -> None:
        before_validation = (REPORTING_DIR / "forecast_validation.csv").read_bytes()
        before_forecast = (REPORTING_DIR / "forecast_monthly.csv").read_bytes()
        subprocess.run(
            [sys.executable, str(PROJECT_ROOT / "scripts" / "run_financial_forecast.py")],
            cwd=PROJECT_ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        self.assertEqual(before_validation, (REPORTING_DIR / "forecast_validation.csv").read_bytes())
        self.assertEqual(before_forecast, (REPORTING_DIR / "forecast_monthly.csv").read_bytes())


if __name__ == "__main__":
    unittest.main()
