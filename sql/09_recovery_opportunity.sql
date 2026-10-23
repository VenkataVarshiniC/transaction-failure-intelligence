-- ============================================================================
-- 09_recovery_opportunity.sql
-- Phase 12 / master brief Section 17: the Recovery Opportunity Engine.
-- Classifies each failure reason into one of 5 action categories using
-- ONLY columns already in the data (failure_category, origin, the static
-- default_recovery_track set in Phase 6/8, and the REAL observed recovery
-- rate from 06_recovery_analysis.sql) -- not by hand-picking reason_codes.
--
-- This deliberately does not just restate default_recovery_track. That
-- field was a design-time assumption (future-state.md, Phase 5). This
-- query checks it against what actually happened in the data and lets
-- observed evidence override the assumption where the two disagree --
-- see RAIL_OUTAGE below for the one case where they do.
--
-- Category order of precedence (a reason gets the first one it matches):
--   1. Do Not Retry           -- default_recovery_track = 'Not Applicable'
--                                 (retrying identical input can't change
--                                 the outcome) OR failure_category = 'Policy'
--                                 (an intentional compliance/account hold,
--                                 not a defect to automate around)
--   2. Immediate Recovery Candidate -- observed recovery_rate_pct >= 70%.
--                                 Checked BEFORE category-specific branches
--                                 so real evidence can promote a reason out
--                                 of its design-time track.
--   3. Investigate             -- failure_category = 'Risk' (a policy/
--                                 threshold question, not automatable), OR
--                                 recovery_rate_pct is NULL (no recovery_
--                                 attempts exist to observe) AND failed
--                                 value >= $100,000 (a stated materiality
--                                 assumption -- worth a look before writing
--                                 the value off, not enough alone to retry)
--   4. Customer Intervention   -- default_recovery_track says so and none
--                                 of the above applied
--   5. Engineering Fix         -- default_recovery_track says so and none
--                                 of the above applied
--   ELSE Investigate            -- safety net; nothing should silently fall
--                                 through unclassified
-- ============================================================================

WITH recovery_stats AS (
    SELECT
        fr.reason_code,
        ROUND(100.0 * SUM(CASE WHEN ra.is_consistent_outcome AND ra.outcome = 'recovered' THEN 1 ELSE 0 END)
            / NULLIF(SUM(CASE WHEN ra.is_consistent_outcome THEN 1 ELSE 0 END), 0), 2) AS recovery_rate_pct,
        COUNT(ra.recovery_attempt_id) AS logged_attempts
    FROM failure_reasons fr
    LEFT JOIN transaction_events e ON e.failure_reason_id = fr.failure_reason_id
    LEFT JOIN recovery_attempts ra ON ra.triggering_event_id = e.event_id
    GROUP BY fr.reason_code
),
volume_value AS (
    SELECT fr.reason_code, COUNT(*) AS failure_count,
        ROUND(SUM(CASE WHEN t.is_valid_amount THEN t.amount ELSE 0 END), 2) AS failed_value
    FROM transaction_events e
    JOIN failure_reasons fr ON e.failure_reason_id = fr.failure_reason_id
    JOIN transactions t ON e.transaction_id = t.transaction_id
    GROUP BY fr.reason_code
)
SELECT
    fr.reason_code,
    fr.failure_category,
    fr.origin,
    fr.default_recovery_track AS design_time_track,
    vv.failure_count,
    vv.failed_value,
    rs.recovery_rate_pct AS observed_recovery_rate_pct,
    CASE
        WHEN fr.default_recovery_track = 'Not Applicable' THEN 'Do Not Retry'
        WHEN fr.failure_category = 'Policy' THEN 'Do Not Retry'
        WHEN rs.recovery_rate_pct IS NOT NULL AND rs.recovery_rate_pct >= 70 THEN 'Immediate Recovery Candidate'
        WHEN fr.failure_category = 'Risk' THEN 'Investigate'
        WHEN rs.recovery_rate_pct IS NULL AND vv.failed_value >= 100000 THEN 'Investigate'
        WHEN fr.default_recovery_track = 'Customer Intervention' THEN 'Customer Intervention'
        WHEN fr.default_recovery_track = 'Engineering Fix' THEN 'Engineering Fix'
        ELSE 'Investigate'
    END AS opportunity_category,
    CASE
        WHEN fr.default_recovery_track != 'Not Applicable' AND fr.failure_category != 'Policy'
             AND rs.recovery_rate_pct IS NOT NULL AND rs.recovery_rate_pct >= 70
             AND fr.default_recovery_track != 'Auto-Retry'
        THEN 'YES -- design-time track was ' || fr.default_recovery_track
        ELSE 'no'
    END AS reclassified_from_design_track
FROM failure_reasons fr
JOIN volume_value vv ON fr.reason_code = vv.reason_code
LEFT JOIN recovery_stats rs ON fr.reason_code = rs.reason_code
ORDER BY
    CASE CASE
        WHEN fr.default_recovery_track = 'Not Applicable' THEN 'Do Not Retry'
        WHEN fr.failure_category = 'Policy' THEN 'Do Not Retry'
        WHEN rs.recovery_rate_pct IS NOT NULL AND rs.recovery_rate_pct >= 70 THEN 'Immediate Recovery Candidate'
        WHEN fr.failure_category = 'Risk' THEN 'Investigate'
        WHEN rs.recovery_rate_pct IS NULL AND vv.failed_value >= 100000 THEN 'Investigate'
        WHEN fr.default_recovery_track = 'Customer Intervention' THEN 'Customer Intervention'
        WHEN fr.default_recovery_track = 'Engineering Fix' THEN 'Engineering Fix'
        ELSE 'Investigate'
    END
        WHEN 'Immediate Recovery Candidate' THEN 1
        WHEN 'Investigate' THEN 2
        WHEN 'Customer Intervention' THEN 3
        WHEN 'Engineering Fix' THEN 4
        WHEN 'Do Not Retry' THEN 5
    END,
    vv.failed_value DESC;
-- Business meaning: this is the row-level input to the Recovery Opportunity
-- Matrix in analysis/recovery-intelligence.md (Phase 12) -- every category,
-- action, and dollar figure in that matrix traces back to this query.
