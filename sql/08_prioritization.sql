-- ============================================================================
-- 08_prioritization.sql
-- BR-05 / FR-07: a single, transparent, documented priority score per failure
-- reason. Every weight is stated here in SQL, not hidden in application code,
-- specifically because BR-06/NFR-05 require Risk & Compliance to be able to
-- see exactly why a category was ranked where it was.
--
-- Weights (stated assumption, revisited in root-cause-analysis.md, Phase 11):
--   30% volume        -- how often it happens
--   30% financial      -- how much value it touches
--   20% urgency        -- inverse of recovery rate (a reason that rarely
--                         recovers on its own needs a *process* fix, not just
--                         more retries)
--   10% customer impact -- how many distinct customers it touches
--   10% operational burden -- a 0/1 proxy: does it require manual review
--                             (Do Not Retry/Monitor track) today
-- ============================================================================

WITH volume AS (
    SELECT fr.reason_code, COUNT(*) AS failure_count
    FROM transaction_events e
    JOIN failure_reasons fr ON e.failure_reason_id = fr.failure_reason_id
    GROUP BY fr.reason_code
),
financial AS (
    SELECT fr.reason_code, ROUND(SUM(CASE WHEN t.is_valid_amount THEN t.amount ELSE 0 END), 2) AS failed_value
    FROM transaction_events e
    JOIN failure_reasons fr ON e.failure_reason_id = fr.failure_reason_id
    JOIN transactions t ON e.transaction_id = t.transaction_id
    GROUP BY fr.reason_code
),
recoverability AS (
    -- Reasons with no recovery attempts at all (Not Applicable track) are
    -- conservatively scored as 0% recovery -- stated assumption, not a gap.
    SELECT fr.reason_code,
        COALESCE(ROUND(100.0 * SUM(CASE WHEN ra.is_consistent_outcome AND ra.outcome = 'recovered' THEN 1 ELSE 0 END)
            / NULLIF(SUM(CASE WHEN ra.is_consistent_outcome THEN 1 ELSE 0 END), 0), 2), 0) AS recovery_rate_pct
    FROM failure_reasons fr
    LEFT JOIN transaction_events e ON e.failure_reason_id = fr.failure_reason_id
    LEFT JOIN recovery_attempts ra ON ra.triggering_event_id = e.event_id
    GROUP BY fr.reason_code
),
customer_impact AS (
    SELECT fr.reason_code, COUNT(DISTINCT a.customer_id) AS distinct_customers
    FROM transaction_events e
    JOIN failure_reasons fr ON e.failure_reason_id = fr.failure_reason_id
    JOIN transactions t ON e.transaction_id = t.transaction_id
    JOIN accounts a ON t.account_id = a.account_id
    GROUP BY fr.reason_code
),
combined AS (
    SELECT
        v.reason_code,
        fr.failure_category,
        fr.default_recovery_track,
        v.failure_count,
        f.failed_value,
        r.recovery_rate_pct,
        c.distinct_customers,
        CASE WHEN fr.default_recovery_track = 'Do Not Retry-Monitor' THEN 1 ELSE 0 END AS operational_burden_flag
    FROM volume v
    JOIN failure_reasons fr ON v.reason_code = fr.reason_code
    JOIN financial f ON v.reason_code = f.reason_code
    JOIN recoverability r ON v.reason_code = r.reason_code
    JOIN customer_impact c ON v.reason_code = c.reason_code
),
normalized AS (
    -- Min-max normalization to 0-1 across the failure-reason population,
    -- computed with window functions so every reason is scored relative to
    -- the same population in one pass.
    SELECT *,
        (failure_count - MIN(failure_count) OVER ()) * 1.0 / NULLIF(MAX(failure_count) OVER () - MIN(failure_count) OVER (), 0) AS volume_score,
        (failed_value - MIN(failed_value) OVER ()) * 1.0 / NULLIF(MAX(failed_value) OVER () - MIN(failed_value) OVER (), 0) AS financial_score,
        (100 - recovery_rate_pct) / 100.0 AS urgency_score,
        (distinct_customers - MIN(distinct_customers) OVER ()) * 1.0 / NULLIF(MAX(distinct_customers) OVER () - MIN(distinct_customers) OVER (), 0) AS customer_impact_score,
        operational_burden_flag * 1.0 AS operational_burden_score
    FROM combined
)
SELECT
    reason_code,
    failure_category,
    failure_count,
    failed_value,
    recovery_rate_pct,
    distinct_customers,
    ROUND(
        0.30 * volume_score +
        0.30 * financial_score +
        0.20 * urgency_score +
        0.10 * customer_impact_score +
        0.10 * operational_burden_score
    , 4) AS priority_score,
    RANK() OVER (ORDER BY
        0.30 * volume_score + 0.30 * financial_score + 0.20 * urgency_score
        + 0.10 * customer_impact_score + 0.10 * operational_burden_score DESC
    ) AS priority_rank
FROM normalized
ORDER BY priority_rank;
-- Result / Business meaning: the ranked output of this query IS the
-- prioritized action list BR-05 asks for -- Phase 11 narrates why the top
-- few ranked where they did and what to do about each.
