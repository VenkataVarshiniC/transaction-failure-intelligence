-- ============================================================================
-- 07_financial_impact.sql
-- BR-07: quantify financial exposure. Every figure here is OBSERVED --
-- computed directly from what happened in the dataset. Modeled/projected
-- figures (what a scenario like automated retry COULD recover) are Phase 13
-- and Phase 14's job, built on top of these observed numbers, and are never
-- computed here so the two are never confused with each other.
-- ============================================================================

-- Q1: Business Question -- What is total transaction value, and what share of
--     it is tied up in failure, restricted to amounts we trust?
--     SQL Logic -- conditional SUM, filtered by is_valid_amount throughout.
SELECT
    ROUND(SUM(CASE WHEN is_valid_amount THEN amount ELSE 0 END), 2) AS total_valid_value_usd,
    ROUND(SUM(CASE WHEN is_valid_amount AND final_status != 'success' THEN amount ELSE 0 END), 2) AS failed_value_usd,
    ROUND(100.0 * SUM(CASE WHEN is_valid_amount AND final_status != 'success' THEN amount ELSE 0 END)
        / SUM(CASE WHEN is_valid_amount THEN amount ELSE 0 END), 3) AS failed_value_pct
FROM transactions;

-- Q2: Business Question -- Of the value that failed, how much was actually
--     recovered (an OBSERVED figure -- these transactions really did end in
--     recovered_success)?
--     SQL Logic -- conditional SUM restricted to one specific final_status.
SELECT
    ROUND(SUM(CASE WHEN is_valid_amount AND final_status = 'recovered_success' THEN amount ELSE 0 END), 2) AS observed_recovered_value_usd,
    COUNT(CASE WHEN final_status = 'recovered_success' THEN 1 END) AS recovered_txn_count
FROM transactions;

-- Q3: Business Question -- Of the value that failed and was ROUTED for
--     recovery (i.e., the failure reason's default track wasn't "Not
--     Applicable") but still ended up permanently failed, how much value is
--     that -- the closest thing to an observed "missed opportunity" baseline,
--     which Phase 13/14 will apply a scenario recovery-rate assumption to.
--     SQL Logic -- JOIN transactions -> transaction_events -> failure_reasons
--     to get each failure's default track, then filter to permanently_failed
--     outcomes whose track wasn't Not Applicable.
WITH failed_with_reason AS (
    SELECT DISTINCT t.transaction_id, t.amount, t.is_valid_amount, fr.default_recovery_track
    FROM transactions t
    JOIN transaction_events e ON t.transaction_id = e.transaction_id
    JOIN failure_reasons fr ON e.failure_reason_id = fr.failure_reason_id
    WHERE t.final_status = 'permanently_failed'
)
SELECT
    default_recovery_track,
    COUNT(*) AS txn_count,
    ROUND(SUM(CASE WHEN is_valid_amount THEN amount ELSE 0 END), 2) AS unrecovered_value_usd
FROM failed_with_reason
WHERE default_recovery_track != 'Not Applicable'
GROUP BY default_recovery_track
ORDER BY unrecovered_value_usd DESC;
-- Business meaning: this table, not a single total, is what Phase 14's
-- scenarios apply a recovery-rate assumption to -- per track, since each
-- track has a different realistic recovery ceiling (06_recovery_analysis.sql).

-- Q4: Business Question -- Which failure category carries the most financial
--     exposure -- and does that ranking match the *volume* ranking from
--     03_failure_analysis.sql, or diverge (a high-value/low-frequency cause
--     the volume-only view would under-prioritize)?
--     SQL Logic -- JOIN + GROUP BY on category, both COUNT and SUM in the
--     same query specifically to let volume and value be compared directly.
SELECT
    fr.failure_category,
    COUNT(*) AS failure_event_count,
    ROUND(SUM(CASE WHEN t.is_valid_amount THEN t.amount ELSE 0 END), 2) AS associated_value_usd,
    RANK() OVER (ORDER BY COUNT(*) DESC) AS volume_rank,
    RANK() OVER (ORDER BY SUM(CASE WHEN t.is_valid_amount THEN t.amount ELSE 0 END) DESC) AS value_rank
FROM transaction_events e
JOIN failure_reasons fr ON e.failure_reason_id = fr.failure_reason_id
JOIN transactions t ON e.transaction_id = t.transaction_id
GROUP BY fr.failure_category
ORDER BY associated_value_usd DESC;
