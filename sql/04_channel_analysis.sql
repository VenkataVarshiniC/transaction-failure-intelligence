-- ============================================================================
-- 04_channel_analysis.sql
-- Which channel and which payment rail carry the most failure risk and the
-- most financial exposure -- and how much of that exposure is genuinely
-- outside Kestrel's control (BR-02)?
-- ============================================================================

-- Q1: Business Question -- Which channel has the highest failure rate?
--     SQL Logic -- JOIN to the channel lookup, conditional aggregation.
SELECT
    c.channel_name,
    COUNT(*) AS txn_count,
    ROUND(100.0 * SUM(CASE WHEN t.final_status != 'success' THEN 1 ELSE 0 END) / COUNT(*), 2) AS failure_rate_pct
FROM transactions t
JOIN channels c ON t.channel_id = c.channel_id
GROUP BY c.channel_name
ORDER BY failure_rate_pct DESC;

-- Q2: Business Question -- Which channel creates the highest *financial*
--     exposure from failure -- which may not be the same channel with the
--     highest failure *rate* (a low-rate, high-value channel can matter more).
--     SQL Logic -- SUM restricted to failed transactions with a valid amount
--     (Phase 9's is_valid_amount flag applied here, not silently ignored).
SELECT
    c.channel_name,
    ROUND(SUM(CASE WHEN t.final_status != 'success' AND t.is_valid_amount THEN t.amount ELSE 0 END), 2) AS failed_value_usd,
    ROUND(100.0 * SUM(CASE WHEN t.final_status != 'success' AND t.is_valid_amount THEN t.amount ELSE 0 END)
        / SUM(CASE WHEN t.is_valid_amount THEN t.amount ELSE 0 END), 2) AS pct_of_channel_value_failed
FROM transactions t
JOIN channels c ON t.channel_id = c.channel_id
GROUP BY c.channel_name
ORDER BY failed_value_usd DESC;

-- Q3: Business Question -- How much failure (and value) sits on rails Kestrel
--     doesn't own, versus its own internal ledger?
--     SQL Logic -- JOIN to payment_rails for the owner attribute, conditional
--     aggregation split by rail_owner.
SELECT
    pr.rail_owner,
    COUNT(*) AS txn_count,
    ROUND(100.0 * SUM(CASE WHEN t.final_status != 'success' THEN 1 ELSE 0 END) / COUNT(*), 2) AS failure_rate_pct,
    ROUND(SUM(CASE WHEN t.final_status != 'success' AND t.is_valid_amount THEN t.amount ELSE 0 END), 2) AS failed_value_usd
FROM transactions t
JOIN payment_rails pr ON t.rail_id = pr.rail_id
GROUP BY pr.rail_owner
ORDER BY failure_rate_pct DESC;
-- Business meaning: this is the SQL-level implementation of BR-02 -- it
-- directly answers "how much of our failure problem is even ours to fix."

-- Q4: Business Question -- Within each channel, which transaction type is the
--     weakest link (a channel x type cross-tab, not just two separate cuts)?
--     SQL Logic -- GROUP BY on both dimensions, with RANK() partitioned by
--     channel so each channel gets its own "worst type" ranking.
SELECT
    channel_name,
    transaction_type,
    txn_count,
    failure_rate_pct,
    RANK() OVER (PARTITION BY channel_name ORDER BY failure_rate_pct DESC) AS rank_within_channel
FROM (
    SELECT
        c.channel_name,
        t.transaction_type,
        COUNT(*) AS txn_count,
        ROUND(100.0 * SUM(CASE WHEN t.final_status != 'success' THEN 1 ELSE 0 END) / COUNT(*), 2) AS failure_rate_pct
    FROM transactions t
    JOIN channels c ON t.channel_id = c.channel_id
    GROUP BY c.channel_name, t.transaction_type
    HAVING COUNT(*) >= 30  -- suppress noisy low-volume combinations
) sub
QUALIFY rank_within_channel = 1
ORDER BY failure_rate_pct DESC;
