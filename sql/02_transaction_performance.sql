-- ============================================================================
-- 02_transaction_performance.sql
-- Answers BR-01: what is the failure rate, and how does it move over time and
-- by transaction type? Every query here reads the clean `transactions` table.
-- ============================================================================

-- Q1: Business Question -- What is the overall success/failure/recovery mix?
--     SQL Logic -- conditional aggregation (CASE inside COUNT), percentages
--     computed against the same total for consistency.
SELECT
    COUNT(*) AS total_transactions,
    SUM(CASE WHEN final_status = 'success' THEN 1 ELSE 0 END) AS success_n,
    SUM(CASE WHEN final_status = 'recovered_success' THEN 1 ELSE 0 END) AS recovered_n,
    SUM(CASE WHEN final_status = 'permanently_failed' THEN 1 ELSE 0 END) AS permanently_failed_n,
    SUM(CASE WHEN final_status = 'pending' THEN 1 ELSE 0 END) AS pending_n,
    ROUND(100.0 * SUM(CASE WHEN final_status NOT IN ('success') THEN 1 ELSE 0 END) / COUNT(*), 2) AS overall_failure_rate_pct
FROM transactions;

-- Q2: Business Question -- Is the failure rate trending up, down, or flat
--     across the 90-day window, smoothed enough to see past day-to-day noise?
--     SQL Logic -- a CTE aggregates to one row per day, then a window function
--     (AVG() OVER a 7-row frame) computes a rolling 7-day failure rate --
--     the standard way to answer "is this trending" without reacting to noise.
WITH daily AS (
    SELECT
        CAST(initiated_at AS DATE) AS txn_date,
        COUNT(*) AS txn_count,
        SUM(CASE WHEN final_status != 'success' THEN 1 ELSE 0 END) AS fail_count
    FROM transactions
    GROUP BY 1
)
SELECT
    txn_date,
    txn_count,
    fail_count,
    ROUND(100.0 * fail_count / txn_count, 2) AS daily_failure_rate_pct,
    ROUND(100.0 * AVG(fail_count) OVER (ORDER BY txn_date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW)
        / AVG(txn_count) OVER (ORDER BY txn_date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW), 2) AS rolling_7day_failure_rate_pct
FROM daily
ORDER BY txn_date;

-- Q3: Business Question -- Which transaction types fail most, and how much
--     worse are they than the best-performing type?
--     SQL Logic -- GROUP BY with conditional aggregation, then RANK() to make
--     the ordering explicit and a self-join-free comparison to the minimum.
SELECT
    transaction_type,
    COUNT(*) AS txn_count,
    ROUND(100.0 * SUM(CASE WHEN final_status != 'success' THEN 1 ELSE 0 END) / COUNT(*), 2) AS failure_rate_pct,
    RANK() OVER (ORDER BY SUM(CASE WHEN final_status != 'success' THEN 1 ELSE 0 END) * 1.0 / COUNT(*) DESC) AS worst_to_best_rank
FROM transactions
GROUP BY transaction_type
ORDER BY failure_rate_pct DESC;

-- Q4: Business Question -- Is failure rate flat across the day, or does it
--     concentrate in particular hours (a precondition for the stress-window
--     finding in 03_failure_analysis.sql)?
--     SQL Logic -- EXTRACT(HOUR ...) bucketing with conditional aggregation.
SELECT
    EXTRACT(HOUR FROM initiated_at) AS hour_of_day,
    COUNT(*) AS txn_count,
    ROUND(100.0 * SUM(CASE WHEN final_status != 'success' THEN 1 ELSE 0 END) / COUNT(*), 2) AS failure_rate_pct
FROM transactions
GROUP BY 1
ORDER BY 1;
