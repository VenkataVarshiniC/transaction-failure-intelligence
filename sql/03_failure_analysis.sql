-- ============================================================================
-- 03_failure_analysis.sql
-- Root-cause groundwork: which failure reasons matter most, at which stage,
-- and do the two designed real-world-inspired patterns (business-case.md
-- Section 1; dataset-design.md Section 3) actually show up when queried cold?
-- ============================================================================

-- Q1: Business Question -- What are the top failure reasons, and what's the
--     Pareto concentration (do a few reasons dominate volume)?
--     SQL Logic -- a CTE counts failure events per reason, then window
--     functions (SUM() OVER for cumulative, and a total via a second window)
--     compute the classic Pareto cumulative-percentage columns.
WITH reason_counts AS (
    SELECT fr.reason_code, fr.failure_category, COUNT(*) AS failure_count
    FROM transaction_events e
    JOIN failure_reasons fr ON e.failure_reason_id = fr.failure_reason_id
    GROUP BY fr.reason_code, fr.failure_category
)
SELECT
    reason_code,
    failure_category,
    failure_count,
    ROUND(100.0 * failure_count / SUM(failure_count) OVER (), 2) AS pct_of_failures,
    ROUND(100.0 * SUM(failure_count) OVER (ORDER BY failure_count DESC
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) / SUM(failure_count) OVER (), 2) AS cumulative_pct
FROM reason_counts
ORDER BY failure_count DESC;

-- Q2: Business Question -- Which lifecycle stage generates the most failures?
--     SQL Logic -- straightforward GROUP BY on the stage stamped on every
--     failure event (process-analysis.md's 10-stage model, operationalized).
SELECT
    e.lifecycle_stage,
    COUNT(*) AS failure_count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_failures
FROM transaction_events e
WHERE e.failure_reason_id IS NOT NULL
GROUP BY e.lifecycle_stage
ORDER BY failure_count DESC;

-- Q3: Business Question -- Split failures by root-cause category (People /
--     Process / Technology / Policy / Risk / External Dependency / Unclassified)
--     and by whether Kestrel can actually fix it (origin).
--     SQL Logic -- JOIN + GROUP BY with two grouping columns.
SELECT
    fr.failure_category,
    fr.origin,
    COUNT(*) AS failure_count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_failures
FROM transaction_events e
JOIN failure_reasons fr ON e.failure_reason_id = fr.failure_reason_id
GROUP BY fr.failure_category, fr.origin
ORDER BY failure_count DESC;

-- Q4a: Business Question (the stress-window discovery, first attempt) --
--      Does the RTP rail's timeout/outage rate spike inside the specific
--      hours flagged as high-risk (12-16), averaged across the whole
--      90-day window? This does NOT hard-code which days are "stress
--      days" -- it derives the answer purely from hour-of-day, which is
--      what a real analyst might try first without knowing the
--      generator's design in advance.
--      SQL Logic -- CTE isolates RTP-rail transactions, a CASE bucket
--      splits midday-afternoon hours (12-16) from the rest, then
--      conditional aggregation compares failure rate between the two
--      cohorts.
WITH rtp_txns AS (
    SELECT t.transaction_id, t.initiated_at, t.final_status,
        CASE WHEN EXTRACT(HOUR FROM t.initiated_at) BETWEEN 12 AND 16 THEN 'midday_afternoon' ELSE 'other_hours' END AS hour_bucket
    FROM transactions t
    WHERE t.rail_id = 'RAIL-RTP'
),
rtp_fail_events AS (
    SELECT DISTINCT e.transaction_id
    FROM transaction_events e
    JOIN failure_reasons fr ON e.failure_reason_id = fr.failure_reason_id
    WHERE fr.reason_code IN ('RAIL_TIMEOUT', 'RAIL_OUTAGE')
)
SELECT
    r.hour_bucket,
    COUNT(*) AS rtp_txn_count,
    SUM(CASE WHEN f.transaction_id IS NOT NULL THEN 1 ELSE 0 END) AS rail_timeout_or_outage_count,
    ROUND(100.0 * SUM(CASE WHEN f.transaction_id IS NOT NULL THEN 1 ELSE 0 END) / COUNT(*), 2) AS rate_pct
FROM rtp_txns r
LEFT JOIN rtp_fail_events f ON r.transaction_id = f.transaction_id
GROUP BY r.hour_bucket
ORDER BY r.hour_bucket;
-- Result (real, run against this dataset): other_hours 0.72% vs.
-- midday_afternoon 0.69% -- essentially flat. This is an honest NEGATIVE
-- finding, kept rather than dropped: the stress condition only occupies 3
-- of 90 days, so averaging every hour across all 90 days dilutes a real
-- 3-day spike into invisibility. Business meaning: "no signal in the
-- obvious cut" is itself informative -- it means a flat hour-of-day alert
-- threshold would never catch this, and a finer slice is needed. Q4b below
-- is that finer slice.

-- Q4b: Business Question (the stress-window discovery, corrected) -- if
--      hour-of-day alone doesn't show it, does slicing by CALENDAR DAY
--      surface specific outlier days -- still without hard-coding which
--      days those are, only ranking every day by its own RTP rail-issue
--      rate?
--      SQL Logic -- CTE computes each day's RTP timeout/outage rate, then
--      RANK() orders every one of the 90 days by that rate with no prior
--      knowledge of which are "stress days" -- the top of the ranking is
--      the finding.
WITH rtp_by_day AS (
    SELECT
        CAST(t.initiated_at AS DATE) AS txn_date,
        COUNT(DISTINCT t.transaction_id) AS rtp_txn_count,
        COUNT(DISTINCT CASE WHEN fr.reason_code IN ('RAIL_TIMEOUT', 'RAIL_OUTAGE') THEN t.transaction_id END) AS rail_issue_txns
    FROM transactions t
    LEFT JOIN transaction_events e ON t.transaction_id = e.transaction_id
    LEFT JOIN failure_reasons fr ON e.failure_reason_id = fr.failure_reason_id
    WHERE t.rail_id = 'RAIL-RTP'
    GROUP BY CAST(t.initiated_at AS DATE)
)
SELECT
    txn_date,
    rtp_txn_count,
    rail_issue_txns,
    ROUND(100.0 * rail_issue_txns / rtp_txn_count, 2) AS rate_pct,
    RANK() OVER (ORDER BY rail_issue_txns * 1.0 / rtp_txn_count DESC) AS day_rank
FROM rtp_by_day
QUALIFY day_rank <= 10
ORDER BY day_rank;
-- Result (real): three of the top-4 ranked days out of 90 (2026-04-07,
-- 2026-05-06, 2026-06-12) sit well above the rest, at roughly 1.5-2.7%
-- versus a ~0.7-0.9% rate on nearby days. Grouped as designed-stress-day
-- (n=3, avg 2.08%) vs. every other day (n=87, avg 0.66%), that is a real
-- ~3x elevation. Business meaning: the RTP rail has genuine bad-day risk
-- that a hierarchical monitoring approach (rank days first, THEN ask what
-- else was different about them -- time-of-day, volume, etc.) would catch
-- and a single flat threshold would not; Phase 11 root-causes what made
-- those specific days different.

-- Q5: Business Question (the engineering-fix discovery) -- Did the internal
--     processing-error rate actually change partway through the window?
--     SQL Logic -- CTE buckets days into two periods with a CASE expression,
--     then compares a per-day rate between them (not just a raw count, since
--     the two periods are different lengths).
WITH proc_errors AS (
    SELECT
        CAST(t.initiated_at AS DATE) AS txn_date,
        CASE WHEN CAST(t.initiated_at AS DATE) < (SELECT MIN(CAST(initiated_at AS DATE)) FROM transactions) + INTERVAL 55 DAY
             THEN 'before_day_55' ELSE 'day_55_and_after' END AS period
    FROM transaction_events e
    JOIN transactions t ON e.transaction_id = t.transaction_id
    JOIN failure_reasons fr ON e.failure_reason_id = fr.failure_reason_id
    WHERE fr.reason_code = 'PROCESSING_ERROR'
)
SELECT
    period,
    COUNT(*) AS processing_error_count,
    COUNT(DISTINCT txn_date) AS days_in_period,
    ROUND(COUNT(*) * 1.0 / COUNT(DISTINCT txn_date), 2) AS avg_per_day
FROM proc_errors
GROUP BY period
ORDER BY period;
-- Business meaning: a visible before/after break in a per-day rate, not just
-- a raw count, is what makes this defensible as "something changed" rather
-- than "the second period happened to have fewer days".
