-- ============================================================================
-- 05_customer_analysis.sql
-- BR-04: which customers and segments experience repeated failures. All
-- output here is aggregated or uses synthetic IDs only -- no individually
-- identifying detail is exposed (NFR-04).
-- ============================================================================

-- Q1: Business Question -- What share of customers experience 1, 2, 3, or 4+
--     failed transactions -- is the repeat-failure problem concentrated in a
--     small group, or spread evenly (a direct test of the "problem cohort"
--     pattern designed into dataset-design.md Section 3)?
--     SQL Logic -- a CTE counts failures per customer, a CASE expression
--     buckets the count, then GROUP BY produces the distribution.
WITH customer_failures AS (
    SELECT a.customer_id, COUNT(*) AS failure_count
    FROM transactions t
    JOIN accounts a ON t.account_id = a.account_id
    WHERE t.final_status != 'success'
    GROUP BY a.customer_id
)
SELECT
    CASE
        WHEN failure_count = 1 THEN '1 failure'
        WHEN failure_count = 2 THEN '2 failures'
        WHEN failure_count = 3 THEN '3 failures'
        ELSE '4+ failures'
    END AS failure_bucket,
    COUNT(*) AS customers_in_bucket,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_affected_customers
FROM customer_failures
GROUP BY failure_bucket
ORDER BY MIN(failure_count);

-- Q2: Business Question -- Which specific customers are the heaviest repeat
--     offenders (for Operations to review, not to publish)?
--     SQL Logic -- window RANK() over failure count, top 15 only.
WITH customer_failures AS (
    SELECT a.customer_id, COUNT(*) AS failure_count
    FROM transactions t
    JOIN accounts a ON t.account_id = a.account_id
    WHERE t.final_status != 'success'
    GROUP BY a.customer_id
)
SELECT customer_id, failure_count,
       RANK() OVER (ORDER BY failure_count DESC) AS repeat_failure_rank
FROM customer_failures
QUALIFY repeat_failure_rank <= 15
ORDER BY failure_count DESC;

-- Q3: Business Question -- Do failure rates differ by customer segment
--     (retail vs. small-business, and within retail, standard vs. premium)?
--     SQL Logic -- two JOINs (accounts -> customers -> segments) then
--     conditional aggregation.
SELECT
    cs.segment_name,
    COUNT(*) AS txn_count,
    ROUND(100.0 * SUM(CASE WHEN t.final_status != 'success' THEN 1 ELSE 0 END) / COUNT(*), 2) AS failure_rate_pct,
    ROUND(AVG(CASE WHEN t.is_valid_amount THEN t.amount END), 2) AS avg_txn_amount
FROM transactions t
JOIN accounts a ON t.account_id = a.account_id
JOIN customers c ON a.customer_id = c.customer_id
JOIN customer_segments cs ON c.segment_id = cs.segment_id
GROUP BY cs.segment_name
ORDER BY failure_rate_pct DESC;

-- Q4: Business Question -- For small-business customers specifically, how
--     much higher is the per-failure financial stake than for retail (the
--     "a failed payroll matters more than a failed P2P transfer" claim from
--     stakeholder-analysis.md)?
--     SQL Logic -- segment_category rollup with AVG amount on failed txns only.
SELECT
    cs.segment_category,
    COUNT(*) AS failed_txn_count,
    ROUND(AVG(CASE WHEN t.is_valid_amount THEN t.amount END), 2) AS avg_failed_txn_amount,
    ROUND(SUM(CASE WHEN t.is_valid_amount THEN t.amount ELSE 0 END), 2) AS total_failed_value
FROM transactions t
JOIN accounts a ON t.account_id = a.account_id
JOIN customers c ON a.customer_id = c.customer_id
JOIN customer_segments cs ON c.segment_id = cs.segment_id
WHERE t.final_status != 'success'
GROUP BY cs.segment_category
ORDER BY avg_failed_txn_amount DESC;
