-- ============================================================================
-- 06_recovery_analysis.sql
-- BR-03 / FR-04: which failures recover, through which track, how fast, and
-- how many attempts does it typically take.
-- ============================================================================

-- Q1: Business Question -- What is the recovery rate by track, using only
--     outcomes we can actually trust (Phase 9's is_consistent_outcome flag)?
--     SQL Logic -- conditional aggregation, filtered on the quality flag
--     rather than trusting `outcome` blindly (this is exactly why that flag
--     exists -- see data-quality-report.md).
SELECT
    recovery_track,
    COUNT(*) AS total_attempts,
    SUM(CASE WHEN is_consistent_outcome AND outcome = 'recovered' THEN 1 ELSE 0 END) AS recovered_count,
    ROUND(100.0 * SUM(CASE WHEN is_consistent_outcome AND outcome = 'recovered' THEN 1 ELSE 0 END)
        / SUM(CASE WHEN is_consistent_outcome THEN 1 ELSE 0 END), 2) AS recovery_rate_pct,
    SUM(CASE WHEN NOT is_consistent_outcome THEN 1 ELSE 0 END) AS excluded_inconsistent_count
FROM recovery_attempts
GROUP BY recovery_track
ORDER BY recovery_rate_pct DESC;

-- Q2: Business Question -- For Auto-Retry specifically, how many attempts
--     does it typically take to recover (1st try, 2nd, 3rd)?
--     SQL Logic -- GROUP BY attempt_number, restricted to the track where
--     multiple sequential attempts are actually expected.
SELECT
    attempt_number,
    COUNT(*) AS attempts_at_this_number,
    SUM(CASE WHEN outcome = 'recovered' THEN 1 ELSE 0 END) AS recovered_at_this_number,
    ROUND(100.0 * SUM(CASE WHEN outcome = 'recovered' THEN 1 ELSE 0 END) / COUNT(*), 2) AS success_rate_at_this_attempt_pct
FROM recovery_attempts
WHERE recovery_track = 'Auto-Retry'
GROUP BY attempt_number
ORDER BY attempt_number;

-- Q3: Business Question -- How long does recovery actually take, by track --
--     seconds for an automated retry versus hours for a customer nudge?
--     SQL Logic -- timestamp subtraction (DuckDB returns an INTERVAL; cast to
--     seconds for a comparable numeric column), AVG/MEDIAN aggregation.
SELECT
    recovery_track,
    ROUND(AVG(EPOCH(completed_at) - EPOCH(initiated_at)), 1) AS avg_seconds_to_resolution,
    ROUND(MEDIAN(EPOCH(completed_at) - EPOCH(initiated_at)), 1) AS median_seconds_to_resolution
FROM recovery_attempts
WHERE is_consistent_outcome AND completed_at IS NOT NULL
GROUP BY recovery_track
ORDER BY avg_seconds_to_resolution;

-- Q4: Business Question -- Which specific failure reasons recover best and
--     worst -- the input Phase 12's Recovery Opportunity classification and
--     Phase 8's prioritization score both need.
--     SQL Logic -- JOIN recovery_attempts back to its triggering event, then
--     to the failure-reason lookup, then conditional aggregation.
SELECT
    fr.reason_code,
    fr.default_recovery_track,
    COUNT(*) AS attempts,
    ROUND(100.0 * SUM(CASE WHEN ra.is_consistent_outcome AND ra.outcome = 'recovered' THEN 1 ELSE 0 END)
        / SUM(CASE WHEN ra.is_consistent_outcome THEN 1 ELSE 0 END), 2) AS recovery_rate_pct
FROM recovery_attempts ra
JOIN transaction_events e ON ra.triggering_event_id = e.event_id
JOIN failure_reasons fr ON e.failure_reason_id = fr.failure_reason_id
GROUP BY fr.reason_code, fr.default_recovery_track
ORDER BY recovery_rate_pct DESC;
