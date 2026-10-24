-- ============================================================================
-- 10_business_impact.sql
-- Phase 13 / master brief Section 18: quantify observed impact, at the
-- OPPORTUNITY-CATEGORY grain established in 09_recovery_opportunity.sql
-- (not the raw default_recovery_track grain 07_financial_impact.sql Q3
-- used) -- so this query and analysis/business-impact-model.md's estimate
-- both trace back to the same category definitions Phase 12 already
-- validated.
--
-- Every column here is OBSERVED (a straight aggregation of what happened).
-- The one arithmetic step that turns any of it into an ESTIMATE happens in
-- the markdown, not in SQL, and is shown as an explicit multiplication a
-- reader can redo by hand -- nothing here just "outputs an estimate".
-- ============================================================================

-- Q1: Business Question -- For each Phase 12 opportunity category, how much
--     value is STILL sitting in permanently_failed status today (i.e., not
--     yet recovered), and how much has already been recovered? This is the
--     base the estimate in Phase 13 is built on top of.
--     SQL Logic -- reproduces the Phase 12 classification CASE (same
--     precedence order, same thresholds) inline per-transaction, then
--     conditional aggregation split by current transaction status.
WITH recovery_stats AS (
    SELECT
        fr.reason_code,
        ROUND(100.0 * SUM(CASE WHEN ra.is_consistent_outcome AND ra.outcome = 'recovered' THEN 1 ELSE 0 END)
            / NULLIF(SUM(CASE WHEN ra.is_consistent_outcome THEN 1 ELSE 0 END), 0), 2) AS recovery_rate_pct
    FROM failure_reasons fr
    LEFT JOIN transaction_events e ON e.failure_reason_id = fr.failure_reason_id
    LEFT JOIN recovery_attempts ra ON ra.triggering_event_id = e.event_id
    GROUP BY fr.reason_code
),
reason_value AS (
    SELECT fr.reason_code,
        ROUND(SUM(CASE WHEN t.is_valid_amount THEN t.amount ELSE 0 END), 2) AS failed_value
    FROM transaction_events e
    JOIN failure_reasons fr ON e.failure_reason_id = fr.failure_reason_id
    JOIN transactions t ON e.transaction_id = t.transaction_id
    GROUP BY fr.reason_code
),
classified AS (
    SELECT fr.reason_code,
        CASE
            WHEN fr.default_recovery_track = 'Not Applicable' THEN 'Do Not Retry'
            WHEN fr.failure_category = 'Policy' THEN 'Do Not Retry'
            WHEN rs.recovery_rate_pct IS NOT NULL AND rs.recovery_rate_pct >= 70 THEN 'Immediate Recovery Candidate'
            WHEN fr.failure_category = 'Risk' THEN 'Investigate'
            WHEN rs.recovery_rate_pct IS NULL AND rv.failed_value >= 100000 THEN 'Investigate'
            WHEN fr.default_recovery_track = 'Customer Intervention' THEN 'Customer Intervention'
            WHEN fr.default_recovery_track = 'Engineering Fix' THEN 'Engineering Fix'
            ELSE 'Investigate'
        END AS opportunity_category,
        rs.recovery_rate_pct
    FROM failure_reasons fr
    LEFT JOIN recovery_stats rs ON fr.reason_code = rs.reason_code
    LEFT JOIN reason_value rv ON fr.reason_code = rv.reason_code
),
txn_reason AS (
    -- one row per (transaction, reason) it was ever tagged with, so a
    -- transaction that failed under two different reasons across its
    -- lifecycle is counted under each -- consistent with how 09's own
    -- event-level convention already works.
    SELECT DISTINCT t.transaction_id, t.final_status, t.is_valid_amount, t.amount,
        c.opportunity_category
    FROM transactions t
    JOIN transaction_events e ON t.transaction_id = e.transaction_id
    JOIN classified c ON e.failure_reason_id = (
        SELECT fr2.failure_reason_id FROM failure_reasons fr2 WHERE fr2.reason_code = c.reason_code
    )
    WHERE e.failure_reason_id IS NOT NULL
)
SELECT
    opportunity_category,
    COUNT(DISTINCT CASE WHEN final_status = 'permanently_failed' THEN transaction_id END) AS still_unrecovered_txn_count,
    ROUND(SUM(CASE WHEN final_status = 'permanently_failed' AND is_valid_amount THEN amount ELSE 0 END), 2) AS still_unrecovered_value,
    COUNT(DISTINCT CASE WHEN final_status = 'recovered_success' THEN transaction_id END) AS already_recovered_txn_count,
    ROUND(SUM(CASE WHEN final_status = 'recovered_success' AND is_valid_amount THEN amount ELSE 0 END), 2) AS already_recovered_value
FROM txn_reason
GROUP BY opportunity_category
ORDER BY still_unrecovered_value DESC;

-- Q2: Business Question -- What is the observed recovery rate actually
--     achieved so far, per opportunity category (recovered / (recovered +
--     still-unrecovered), among transactions that were ever routed to a
--     recovery attempt)? This is the baseline rate Phase 13's single
--     stated estimate multiplies against -- not a new number, a restatement
--     of Q1 as a rate instead of two raw counts.
WITH recovery_stats AS (
    SELECT
        fr.reason_code,
        ROUND(100.0 * SUM(CASE WHEN ra.is_consistent_outcome AND ra.outcome = 'recovered' THEN 1 ELSE 0 END)
            / NULLIF(SUM(CASE WHEN ra.is_consistent_outcome THEN 1 ELSE 0 END), 0), 2) AS recovery_rate_pct
    FROM failure_reasons fr
    LEFT JOIN transaction_events e ON e.failure_reason_id = fr.failure_reason_id
    LEFT JOIN recovery_attempts ra ON ra.triggering_event_id = e.event_id
    GROUP BY fr.reason_code
),
reason_value AS (
    SELECT fr.reason_code,
        ROUND(SUM(CASE WHEN t.is_valid_amount THEN t.amount ELSE 0 END), 2) AS failed_value
    FROM transaction_events e
    JOIN failure_reasons fr ON e.failure_reason_id = fr.failure_reason_id
    JOIN transactions t ON e.transaction_id = t.transaction_id
    GROUP BY fr.reason_code
),
classified AS (
    SELECT fr.reason_code,
        CASE
            WHEN fr.default_recovery_track = 'Not Applicable' THEN 'Do Not Retry'
            WHEN fr.failure_category = 'Policy' THEN 'Do Not Retry'
            WHEN rs.recovery_rate_pct IS NOT NULL AND rs.recovery_rate_pct >= 70 THEN 'Immediate Recovery Candidate'
            WHEN fr.failure_category = 'Risk' THEN 'Investigate'
            WHEN rs.recovery_rate_pct IS NULL AND rv.failed_value >= 100000 THEN 'Investigate'
            WHEN fr.default_recovery_track = 'Customer Intervention' THEN 'Customer Intervention'
            WHEN fr.default_recovery_track = 'Engineering Fix' THEN 'Engineering Fix'
            ELSE 'Investigate'
        END AS opportunity_category,
        rs.recovery_rate_pct
    FROM failure_reasons fr
    LEFT JOIN recovery_stats rs ON fr.reason_code = rs.reason_code
    LEFT JOIN reason_value rv ON fr.reason_code = rv.reason_code
)
SELECT
    opportunity_category,
    COUNT(*) AS reasons_in_category,
    ROUND(AVG(recovery_rate_pct), 2) AS avg_observed_recovery_rate_pct
FROM classified
GROUP BY opportunity_category
ORDER BY avg_observed_recovery_rate_pct DESC NULLS LAST;

-- Q3: Business Question -- Within the Investigate category specifically,
--     how does RISK_HELD's still-unrecovered value compare to
--     RAIL_DECLINED_ISSUER's -- since the two need different treatment in
--     Phase 13's estimate (one has a partial recovery mechanism to
--     extrapolate from, the other has zero instrumentation to extrapolate
--     from at all).
--     SQL Logic -- a CTE first reduces to one row per distinct transaction
--     per reason (so a transaction is never summed twice for the same
--     reason), then conditional aggregation.
WITH txn_by_reason AS (
    SELECT DISTINCT fr.reason_code, t.transaction_id, t.final_status, t.is_valid_amount, t.amount
    FROM failure_reasons fr
    JOIN transaction_events e ON e.failure_reason_id = fr.failure_reason_id
    JOIN transactions t ON e.transaction_id = t.transaction_id
    WHERE fr.reason_code IN ('RISK_HELD', 'RAIL_DECLINED_ISSUER')
)
SELECT
    reason_code,
    COUNT(CASE WHEN final_status = 'permanently_failed' THEN 1 END) AS still_unrecovered_txn_count,
    ROUND(SUM(CASE WHEN final_status = 'permanently_failed' AND is_valid_amount THEN amount ELSE 0 END), 2) AS still_unrecovered_value,
    COUNT(CASE WHEN final_status = 'recovered_success' THEN 1 END) AS already_recovered_txn_count,
    ROUND(SUM(CASE WHEN final_status = 'recovered_success' AND is_valid_amount THEN amount ELSE 0 END), 2) AS already_recovered_value
FROM txn_by_reason
GROUP BY reason_code
ORDER BY reason_code;

-- Q4: Business Question -- "Repeated failure cost" (Section 18): how much
--     failed transaction value is concentrated in customers who fail more
--     than once, versus the one-and-done majority? A dollar figure for the
--     repeat-failure cohort already identified in root-cause-analysis.md
--     Section 10, not just the customer-count distribution 05's Q1 gave.
--     SQL Logic -- a CTE counts each customer's failures, a second CTE
--     buckets them the same way 05 Q1 did, then joins back to transactions
--     to sum value by bucket.
WITH customer_failures AS (
    SELECT a.customer_id, COUNT(*) AS failure_count
    FROM transactions t
    JOIN accounts a ON t.account_id = a.account_id
    WHERE t.final_status != 'success'
    GROUP BY a.customer_id
),
bucketed AS (
    SELECT customer_id,
        CASE WHEN failure_count = 1 THEN 'single_failure' ELSE 'repeat_failure' END AS repeat_bucket
    FROM customer_failures
)
SELECT
    b.repeat_bucket,
    COUNT(DISTINCT b.customer_id) AS customers,
    COUNT(t.transaction_id) AS failed_txn_count,
    ROUND(SUM(CASE WHEN t.is_valid_amount THEN t.amount ELSE 0 END), 2) AS failed_value
FROM bucketed b
JOIN accounts a ON a.customer_id = b.customer_id
JOIN transactions t ON t.account_id = a.account_id AND t.final_status != 'success'
GROUP BY b.repeat_bucket
ORDER BY failed_value DESC;
