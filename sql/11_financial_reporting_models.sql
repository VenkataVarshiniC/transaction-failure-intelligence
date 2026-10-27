-- Financial operations reporting layer.
-- Prerequisites: scripts/build_financial_reporting.py loads the three
-- versioned config tables and forecast outputs before executing this file.

CREATE OR REPLACE VIEW vw_transaction_performance AS
SELECT
    CAST(DATE_TRUNC('month', initiated_at) AS DATE) AS month,
    COUNT(*) AS transaction_count,
    COUNT(*) FILTER (WHERE final_status = 'success') AS direct_success_count,
    COUNT(*) FILTER (WHERE final_status = 'recovered_success') AS recovered_count,
    COUNT(*) FILTER (WHERE final_status = 'permanently_failed') AS permanently_failed_count,
    COUNT(*) FILTER (WHERE final_status = 'pending') AS pending_count,
    COUNT(*) FILTER (WHERE final_status = 'unclassified') AS unclassified_count,
    COUNT(*) FILTER (WHERE final_status != 'success') AS not_success_count,
    ROUND(100.0 * COUNT(*) FILTER (WHERE final_status != 'success') / COUNT(*), 4) AS not_success_rate_pct,
    ROUND(SUM(CASE WHEN is_valid_amount THEN amount ELSE 0 END), 2) AS valid_transaction_value_usd,
    ROUND(SUM(CASE WHEN is_valid_amount AND final_status != 'success' THEN amount ELSE 0 END), 2) AS failed_face_value_usd,
    ROUND(SUM(CASE WHEN is_valid_amount AND final_status = 'recovered_success' THEN amount ELSE 0 END), 2) AS recovered_face_value_usd
FROM transactions
GROUP BY 1;

CREATE OR REPLACE VIEW vw_failed_transaction_exposure AS
WITH one_failure_reason AS (
    SELECT
        e.transaction_id,
        fr.reason_code,
        fr.failure_category,
        fr.origin,
        fr.default_recovery_track,
        ROW_NUMBER() OVER (PARTITION BY e.transaction_id ORDER BY e.event_sequence) AS reason_order
    FROM transaction_events e
    JOIN failure_reasons fr ON e.failure_reason_id = fr.failure_reason_id
)
SELECT
    t.transaction_id,
    CAST(DATE_TRUNC('month', t.initiated_at) AS DATE) AS month,
    t.final_status,
    r.reason_code,
    r.failure_category,
    r.origin,
    r.default_recovery_track,
    c.channel_name,
    pr.rail_name,
    COALESCE(cs.segment_name, 'Unattributed') AS customer_segment,
    CASE WHEN t.is_valid_amount THEN t.amount ELSE NULL END AS failed_face_value_usd,
    'Observed transaction face value exposed; not financial loss' AS financial_treatment
FROM transactions t
JOIN one_failure_reason r ON t.transaction_id = r.transaction_id AND r.reason_order = 1
JOIN channels c ON t.channel_id = c.channel_id
JOIN payment_rails pr ON t.rail_id = pr.rail_id
LEFT JOIN accounts a ON t.account_id = a.account_id
LEFT JOIN customers cu ON a.customer_id = cu.customer_id
LEFT JOIN customer_segments cs ON cu.segment_id = cs.segment_id;

CREATE OR REPLACE VIEW vw_recovery_performance AS
SELECT
    CAST(DATE_TRUNC('month', t.initiated_at) AS DATE) AS month,
    fr.reason_code,
    fr.failure_category,
    ra.recovery_track,
    COUNT(*) AS recovery_attempts,
    COUNT(*) FILTER (WHERE ra.is_consistent_outcome) AS consistent_attempts,
    COUNT(*) FILTER (WHERE ra.is_consistent_outcome AND ra.outcome = 'recovered') AS successful_attempts,
    COUNT(DISTINCT t.transaction_id) AS transactions_attempted,
    COUNT(DISTINCT t.transaction_id) FILTER (WHERE t.final_status = 'recovered_success') AS transactions_recovered,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE ra.is_consistent_outcome AND ra.outcome = 'recovered')
        / NULLIF(COUNT(*) FILTER (WHERE ra.is_consistent_outcome), 0), 2
    ) AS attempt_success_rate_pct
FROM recovery_attempts ra
JOIN transaction_events e ON ra.triggering_event_id = e.event_id
JOIN failure_reasons fr ON e.failure_reason_id = fr.failure_reason_id
JOIN transactions t ON ra.transaction_id = t.transaction_id
GROUP BY 1, 2, 3, 4;

CREATE OR REPLACE VIEW vw_financial_costs AS
WITH assumptions AS (
    SELECT
        MAX(CASE WHEN assumption_id = 'platform_cost_per_transaction' THEN value END) AS platform_cost,
        MAX(CASE WHEN assumption_id = 'payment_processing_fixed_per_settled_transaction' THEN value END) AS processing_fixed,
        MAX(CASE WHEN assumption_id = 'payment_processing_bps' THEN value END) AS processing_bps,
        MAX(CASE WHEN assumption_id = 'retry_cost_per_attempt' THEN value END) AS retry_cost,
        MAX(CASE WHEN assumption_id = 'customer_support_cost_per_intervention_attempt' THEN value END) AS support_cost,
        MAX(CASE WHEN assumption_id = 'manual_review_cost_per_attempt' THEN value END) AS manual_review_cost,
        MAX(CASE WHEN assumption_id = 'notification_cost_per_notification' THEN value END) AS notification_cost,
        MAX(CASE WHEN assumption_id = 'failure_investigation_cost_per_failure' THEN value END) AS failure_cost,
        MAX(CASE WHEN assumption_id = 'engineering_remediation_monthly' THEN value END) AS engineering_monthly,
        MAX(CASE WHEN assumption_id = 'operations_platform_monthly' THEN value END) AS operations_monthly,
        MAX(CASE WHEN assumption_id = 'other_operations_monthly' THEN value END) AS other_monthly
    FROM financial_assumptions
),
months AS (
    SELECT
        CAST(DATE_TRUNC('month', initiated_at) AS DATE) AS month,
        COUNT(DISTINCT CAST(initiated_at AS DATE)) AS active_days,
        DAY(LAST_DAY(CAST(DATE_TRUNC('month', initiated_at) AS DATE))) AS calendar_days
    FROM transactions GROUP BY 1
),
transaction_month AS (
    SELECT
        CAST(DATE_TRUNC('month', initiated_at) AS DATE) AS month,
        COUNT(*) AS transaction_count,
        COUNT(*) FILTER (WHERE final_status IN ('success', 'recovered_success')) AS settled_count,
        SUM(CASE WHEN is_valid_amount AND final_status IN ('success', 'recovered_success') THEN amount ELSE 0 END) AS settled_value,
        COUNT(*) FILTER (WHERE final_status != 'success') AS failure_count
    FROM transactions GROUP BY 1
),
recovery_month AS (
    SELECT
        CAST(DATE_TRUNC('month', t.initiated_at) AS DATE) AS month,
        COUNT(*) AS retry_attempt_count,
        COUNT(*) FILTER (WHERE ra.recovery_track = 'Customer Intervention') AS customer_intervention_count,
        COUNT(*) FILTER (WHERE ra.recovery_track = 'Do Not Retry-Monitor') AS manual_review_count
    FROM recovery_attempts ra
    JOIN transactions t ON ra.transaction_id = t.transaction_id
    GROUP BY 1
),
notification_month AS (
    SELECT
        CAST(DATE_TRUNC('month', t.initiated_at) AS DATE) AS month,
        COUNT(*) AS notification_count
    FROM transaction_events e
    JOIN transactions t ON e.transaction_id = t.transaction_id
    WHERE e.event_type = 'CUSTOMER_NOTIFIED'
    GROUP BY 1
)
SELECT tm.month, 'variable' AS expense_class, 'Platform and Processing' AS cost_category,
       'Core transaction platform' AS line_item, tm.transaction_count AS driver_quantity,
       a.platform_cost AS unit_rate, ROUND(tm.transaction_count * a.platform_cost, 2) AS modeled_cost_usd
FROM transaction_month tm CROSS JOIN assumptions a
UNION ALL
SELECT tm.month, 'variable', 'Platform and Processing', 'Fixed payment processing', tm.settled_count,
       a.processing_fixed, ROUND(tm.settled_count * a.processing_fixed, 2)
FROM transaction_month tm CROSS JOIN assumptions a
UNION ALL
SELECT tm.month, 'variable', 'Platform and Processing', 'Value-based payment processing', tm.settled_value,
       a.processing_bps / 10000.0, ROUND(tm.settled_value * a.processing_bps / 10000.0, 2)
FROM transaction_month tm CROSS JOIN assumptions a
UNION ALL
SELECT rm.month, 'variable', 'Recovery and Manual Review', 'Retry attempts', rm.retry_attempt_count,
       a.retry_cost, ROUND(rm.retry_attempt_count * a.retry_cost, 2)
FROM recovery_month rm CROSS JOIN assumptions a
UNION ALL
SELECT rm.month, 'variable', 'Customer Intervention', 'Customer support handling', rm.customer_intervention_count,
       a.support_cost, ROUND(rm.customer_intervention_count * a.support_cost, 2)
FROM recovery_month rm CROSS JOIN assumptions a
UNION ALL
SELECT rm.month, 'variable', 'Recovery and Manual Review', 'Manual review', rm.manual_review_count,
       a.manual_review_cost, ROUND(rm.manual_review_count * a.manual_review_cost, 2)
FROM recovery_month rm CROSS JOIN assumptions a
UNION ALL
SELECT nm.month, 'variable', 'Notification and Failure Operations', 'Customer notifications', nm.notification_count,
       a.notification_cost, ROUND(nm.notification_count * a.notification_cost, 2)
FROM notification_month nm CROSS JOIN assumptions a
UNION ALL
SELECT tm.month, 'variable', 'Notification and Failure Operations', 'Failure investigation', tm.failure_count,
       a.failure_cost, ROUND(tm.failure_count * a.failure_cost, 2)
FROM transaction_month tm CROSS JOIN assumptions a
UNION ALL
SELECT m.month, 'recurring_fixed', 'Recurring Fixed', 'Engineering remediation allocation', m.active_days,
       a.engineering_monthly / m.calendar_days, ROUND(a.engineering_monthly * m.active_days / m.calendar_days, 2)
FROM months m CROSS JOIN assumptions a
UNION ALL
SELECT m.month, 'recurring_fixed', 'Recurring Fixed', 'Operations platform allocation', m.active_days,
       a.operations_monthly / m.calendar_days, ROUND(a.operations_monthly * m.active_days / m.calendar_days, 2)
FROM months m CROSS JOIN assumptions a
UNION ALL
SELECT m.month, 'recurring_fixed', 'Recurring Fixed', 'Other operations allocation', m.active_days,
       a.other_monthly / m.calendar_days, ROUND(a.other_monthly * m.active_days / m.calendar_days, 2)
FROM months m CROSS JOIN assumptions a;

CREATE OR REPLACE VIEW vw_monthly_opex AS
SELECT
    month,
    ROUND(SUM(modeled_cost_usd) FILTER (WHERE cost_category = 'Platform and Processing'), 2) AS platform_and_processing_usd,
    ROUND(SUM(modeled_cost_usd) FILTER (WHERE cost_category = 'Recovery and Manual Review'), 2) AS recovery_and_manual_review_usd,
    ROUND(SUM(modeled_cost_usd) FILTER (WHERE cost_category = 'Customer Intervention'), 2) AS customer_intervention_usd,
    ROUND(SUM(modeled_cost_usd) FILTER (WHERE cost_category = 'Notification and Failure Operations'), 2) AS notification_and_failure_ops_usd,
    ROUND(SUM(modeled_cost_usd) FILTER (WHERE cost_category = 'Recurring Fixed'), 2) AS recurring_fixed_usd,
    ROUND(SUM(modeled_cost_usd), 2) AS total_opex_usd
FROM vw_financial_costs
GROUP BY month;

CREATE OR REPLACE VIEW vw_financial_kpis AS
WITH totals AS (
    SELECT
        SUM(modeled_cost_usd) AS total_opex,
        SUM(modeled_cost_usd) FILTER (WHERE expense_class = 'variable') AS variable_opex,
        SUM(modeled_cost_usd) FILTER (WHERE expense_class = 'recurring_fixed') AS recurring_fixed_opex,
        SUM(modeled_cost_usd) FILTER (
            WHERE line_item IN ('Retry attempts', 'Manual review', 'Customer support handling')
        ) AS recovery_servicing_cost,
        SUM(modeled_cost_usd) FILTER (
            WHERE line_item IN ('Retry attempts', 'Manual review', 'Customer support handling', 'Failure investigation')
        ) AS failure_management_cost
    FROM vw_financial_costs
),
volumes AS (
    SELECT
        COUNT(*) AS transactions,
        COUNT(*) FILTER (WHERE final_status != 'success') AS not_success_transactions,
        COUNT(*) FILTER (WHERE final_status = 'recovered_success') AS recovered_transactions
    FROM transactions
)
SELECT
    ROUND(t.total_opex, 2) AS total_modeled_opex_usd,
    ROUND(t.variable_opex, 2) AS variable_opex_usd,
    ROUND(t.recurring_fixed_opex, 2) AS recurring_fixed_opex_usd,
    ROUND(t.total_opex / v.transactions, 4) AS opex_per_transaction_usd,
    ROUND(t.total_opex / v.not_success_transactions, 4) AS allocated_opex_per_not_success_transaction_usd,
    ROUND(t.failure_management_cost / v.not_success_transactions, 4) AS failure_management_cost_per_not_success_transaction_usd,
    ROUND(t.recovery_servicing_cost / v.recovered_transactions, 4) AS recovery_cost_per_successful_recovery_usd,
    v.transactions AS transaction_count,
    v.not_success_transactions,
    v.recovered_transactions,
    'Modeled costs only; failed face value is excluded from OpEx' AS cost_scope
FROM totals t CROSS JOIN volumes v;

CREATE OR REPLACE VIEW vw_intervention_cost_by_failure_category AS
WITH a AS (
    SELECT
        MAX(CASE WHEN assumption_id = 'retry_cost_per_attempt' THEN value END) AS retry_cost,
        MAX(CASE WHEN assumption_id = 'customer_support_cost_per_intervention_attempt' THEN value END) AS support_cost,
        MAX(CASE WHEN assumption_id = 'manual_review_cost_per_attempt' THEN value END) AS manual_cost,
        MAX(CASE WHEN assumption_id = 'failure_investigation_cost_per_failure' THEN value END) AS failure_cost,
        MAX(CASE WHEN assumption_id = 'notification_cost_per_notification' THEN value END) AS notification_cost
    FROM financial_assumptions
),
failures AS (
    SELECT fr.failure_category, COUNT(DISTINCT e.transaction_id) AS failure_transactions
    FROM transaction_events e JOIN failure_reasons fr ON e.failure_reason_id = fr.failure_reason_id
    GROUP BY 1
),
attempts AS (
    SELECT fr.failure_category,
        COUNT(*) AS attempts,
        COUNT(*) FILTER (WHERE ra.recovery_track = 'Customer Intervention') AS support_attempts,
        COUNT(*) FILTER (WHERE ra.recovery_track = 'Do Not Retry-Monitor') AS manual_attempts
    FROM recovery_attempts ra
    JOIN transaction_events e ON ra.triggering_event_id = e.event_id
    JOIN failure_reasons fr ON e.failure_reason_id = fr.failure_reason_id
    GROUP BY 1
)
SELECT
    f.failure_category,
    f.failure_transactions,
    COALESCE(rat.attempts, 0) AS recovery_attempts,
    ROUND(
        COALESCE(rat.attempts, 0) * a.retry_cost
        + COALESCE(rat.support_attempts, 0) * a.support_cost
        + COALESCE(rat.manual_attempts, 0) * a.manual_cost
        + f.failure_transactions * (a.failure_cost + a.notification_cost), 2
    ) AS modeled_intervention_cost_usd,
    ROUND(
        (COALESCE(rat.attempts, 0) * a.retry_cost
        + COALESCE(rat.support_attempts, 0) * a.support_cost
        + COALESCE(rat.manual_attempts, 0) * a.manual_cost
        + f.failure_transactions * (a.failure_cost + a.notification_cost)) / NULLIF(f.failure_transactions, 0), 4
    ) AS modeled_cost_per_failed_transaction_usd
FROM failures f
LEFT JOIN attempts rat USING (failure_category)
CROSS JOIN a;

CREATE OR REPLACE VIEW vw_net_recovery_benefit AS
WITH a AS (
    SELECT
        MAX(CASE WHEN assumption_id = 'incremental_fee_revenue_bps' THEN value END) AS fee_bps,
        MAX(CASE WHEN assumption_id = 'retry_cost_per_attempt' THEN value END) AS retry_cost,
        MAX(CASE WHEN assumption_id = 'customer_support_cost_per_intervention_attempt' THEN value END) AS support_cost,
        MAX(CASE WHEN assumption_id = 'notification_cost_per_notification' THEN value END) AS notification_cost,
        MAX(CASE WHEN assumption_id = 'failure_investigation_cost_per_failure' THEN value END) AS failure_cost
    FROM financial_assumptions
),
analysis_window AS (
    SELECT (DATE_DIFF('day', MIN(CAST(initiated_at AS DATE)), MAX(CAST(initiated_at AS DATE))) + 1) / 365.0 * 12 AS month_equivalent
    FROM transactions
),
target_transactions AS (
    SELECT DISTINCT
        s.scenario_id, s.scenario_name, s.target_reason, s.intervention_type,
        s.base_status, s.conversion_rate, s.implementation_cost_usd, s.monthly_recurring_cost_usd,
        s.retry_attempts_per_incremental_success, s.support_contacts_per_incremental_success,
        s.notifications_per_target, s.support_avoidance_rate, s.effort_score, s.risk_score,
        s.confidence, s.assumption_source,
        t.transaction_id, t.final_status,
        CASE WHEN t.is_valid_amount THEN t.amount ELSE 0 END AS valid_amount
    FROM recovery_scenarios s
    JOIN failure_reasons fr ON s.target_reason = fr.reason_code
    JOIN transaction_events e ON fr.failure_reason_id = e.failure_reason_id
    JOIN transactions t ON e.transaction_id = t.transaction_id
    WHERE (s.base_status = 'permanently_failed' AND t.final_status = 'permanently_failed')
       OR (s.base_status = 'all_failed' AND t.final_status != 'success')
),
target_base AS (
    SELECT
        scenario_id, scenario_name, target_reason, intervention_type, conversion_rate,
        implementation_cost_usd, monthly_recurring_cost_usd,
        retry_attempts_per_incremental_success, support_contacts_per_incremental_success,
        notifications_per_target, support_avoidance_rate, effort_score, risk_score,
        confidence, assumption_source,
        COUNT(*) AS target_transaction_count,
        SUM(valid_amount) AS target_valid_face_value_usd
    FROM target_transactions
    GROUP BY ALL
),
calculated AS (
    SELECT
        b.*,
        w.month_equivalent,
        b.target_transaction_count * b.conversion_rate AS incremental_successful_transactions,
        b.target_valid_face_value_usd * b.conversion_rate AS incremental_processed_value_usd,
        b.target_valid_face_value_usd * b.conversion_rate * a.fee_bps / 10000.0 AS incremental_fee_revenue_usd,
        b.target_transaction_count * b.conversion_rate *
            CASE WHEN b.intervention_type = 'prevention' THEN a.failure_cost + a.notification_cost
                 ELSE b.support_avoidance_rate * a.support_cost END AS avoided_operational_cost_usd,
        b.target_transaction_count * b.conversion_rate * b.retry_attempts_per_incremental_success * a.retry_cost
            AS additional_retry_cost_usd,
        b.target_transaction_count * b.conversion_rate * b.support_contacts_per_incremental_success * a.support_cost
            + b.target_transaction_count * b.notifications_per_target * a.notification_cost
            AS additional_servicing_cost_usd,
        b.monthly_recurring_cost_usd * w.month_equivalent AS analysis_window_recurring_cost_usd,
        (b.target_valid_face_value_usd / NULLIF(b.target_transaction_count, 0)) * a.fee_bps / 10000.0
            + CASE WHEN b.intervention_type = 'prevention' THEN a.failure_cost + a.notification_cost
                   ELSE b.support_avoidance_rate * a.support_cost END
            - b.retry_attempts_per_incremental_success * a.retry_cost
            - b.support_contacts_per_incremental_success * a.support_cost AS contribution_per_incremental_success,
        b.target_transaction_count * b.notifications_per_target * a.notification_cost AS target_notification_cost_usd
    FROM target_base b CROSS JOIN a CROSS JOIN analysis_window w
)
SELECT
    scenario_id, scenario_name, target_reason, intervention_type, confidence,
    effort_score, risk_score, assumption_source,
    target_transaction_count,
    ROUND(target_valid_face_value_usd, 2) AS target_face_value_usd,
    conversion_rate,
    ROUND(incremental_successful_transactions, 2) AS incremental_successful_transactions,
    ROUND(incremental_processed_value_usd, 2) AS incremental_processed_value_usd,
    ROUND(incremental_fee_revenue_usd, 2) AS incremental_fee_revenue_usd,
    ROUND(avoided_operational_cost_usd, 2) AS avoided_operational_cost_usd,
    ROUND(additional_retry_cost_usd, 2) AS additional_retry_cost_usd,
    ROUND(additional_servicing_cost_usd, 2) AS additional_servicing_cost_usd,
    ROUND(implementation_cost_usd, 2) AS implementation_cost_usd,
    ROUND(analysis_window_recurring_cost_usd, 2) AS analysis_window_recurring_cost_usd,
    ROUND(
        incremental_fee_revenue_usd + avoided_operational_cost_usd
        - additional_retry_cost_usd - additional_servicing_cost_usd
        - implementation_cost_usd - analysis_window_recurring_cost_usd, 2
    ) AS net_financial_benefit_usd,
    ROUND(
        100.0 * (incremental_fee_revenue_usd + avoided_operational_cost_usd
        - additional_retry_cost_usd - additional_servicing_cost_usd
        - implementation_cost_usd - analysis_window_recurring_cost_usd)
        / NULLIF(additional_retry_cost_usd + additional_servicing_cost_usd
                 + implementation_cost_usd + analysis_window_recurring_cost_usd, 0), 2
    ) AS roi_pct,
    ROUND(
        (implementation_cost_usd + analysis_window_recurring_cost_usd + target_notification_cost_usd)
        / NULLIF(contribution_per_incremental_success, 0), 2
    ) AS break_even_incremental_successes,
    ROUND(
        100.0 * (implementation_cost_usd + analysis_window_recurring_cost_usd + target_notification_cost_usd)
        / NULLIF(contribution_per_incremental_success * target_transaction_count, 0), 2
    ) AS break_even_conversion_rate_pct,
    'Recovered/prevented principal is reported as processed-value exposure and excluded from financial benefit' AS principal_treatment
FROM calculated;

CREATE OR REPLACE VIEW vw_customer_segment_financial_impact AS
WITH a AS (
    SELECT
        MAX(CASE WHEN assumption_id = 'platform_cost_per_transaction' THEN value END) AS platform_cost,
        MAX(CASE WHEN assumption_id = 'payment_processing_fixed_per_settled_transaction' THEN value END) AS processing_fixed,
        MAX(CASE WHEN assumption_id = 'payment_processing_bps' THEN value END) AS processing_bps,
        MAX(CASE WHEN assumption_id = 'retry_cost_per_attempt' THEN value END) AS retry_cost,
        MAX(CASE WHEN assumption_id = 'customer_support_cost_per_intervention_attempt' THEN value END) AS support_cost,
        MAX(CASE WHEN assumption_id = 'manual_review_cost_per_attempt' THEN value END) AS manual_cost,
        MAX(CASE WHEN assumption_id = 'notification_cost_per_notification' THEN value END) AS notification_cost,
        MAX(CASE WHEN assumption_id = 'failure_investigation_cost_per_failure' THEN value END) AS failure_cost,
        MAX(CASE WHEN assumption_id = 'incremental_fee_revenue_bps' THEN value END) AS fee_bps
    FROM financial_assumptions
),
recovery_by_txn AS (
    SELECT transaction_id, COUNT(*) AS attempts,
        COUNT(*) FILTER (WHERE recovery_track = 'Customer Intervention') AS support_attempts,
        COUNT(*) FILTER (WHERE recovery_track = 'Do Not Retry-Monitor') AS manual_attempts
    FROM recovery_attempts GROUP BY 1
),
notification_by_txn AS (
    SELECT transaction_id, COUNT(*) AS notification_count
    FROM transaction_events WHERE event_type = 'CUSTOMER_NOTIFIED' GROUP BY 1
),
fixed AS (SELECT SUM(modeled_cost_usd) AS fixed_cost FROM vw_financial_costs WHERE expense_class = 'recurring_fixed'),
base AS (
    SELECT COALESCE(cs.segment_name, 'Unattributed') AS customer_segment, t.*,
           COALESCE(r.attempts, 0) AS attempts, COALESCE(r.support_attempts, 0) AS support_attempts,
           COALESCE(r.manual_attempts, 0) AS manual_attempts,
           COALESCE(n.notification_count, 0) AS notification_count
    FROM transactions t
    LEFT JOIN accounts ac ON t.account_id = ac.account_id
    LEFT JOIN customers c ON ac.customer_id = c.customer_id
    LEFT JOIN customer_segments cs ON c.segment_id = cs.segment_id
    LEFT JOIN recovery_by_txn r ON t.transaction_id = r.transaction_id
    LEFT JOIN notification_by_txn n ON t.transaction_id = n.transaction_id
)
SELECT
    customer_segment,
    COUNT(*) AS transaction_count,
    COUNT(*) FILTER (WHERE final_status != 'success') AS failed_transaction_count,
    ROUND(SUM(CASE WHEN is_valid_amount AND final_status != 'success' THEN amount ELSE 0 END), 2) AS failed_face_value_usd,
    ROUND(SUM(CASE WHEN is_valid_amount AND final_status IN ('success','recovered_success') THEN amount ELSE 0 END) * a.fee_bps / 10000.0, 2) AS modeled_fee_revenue_usd,
    ROUND(
        COUNT(*) * a.platform_cost
        + COUNT(*) FILTER (WHERE final_status IN ('success','recovered_success')) * a.processing_fixed
        + SUM(CASE WHEN is_valid_amount AND final_status IN ('success','recovered_success') THEN amount ELSE 0 END) * a.processing_bps / 10000.0
        + SUM(attempts) * a.retry_cost + SUM(support_attempts) * a.support_cost + SUM(manual_attempts) * a.manual_cost
        + COUNT(*) FILTER (WHERE final_status != 'success') * a.failure_cost
        + SUM(notification_count) * a.notification_cost
        + f.fixed_cost * COUNT(*) / SUM(COUNT(*)) OVER (), 2
    ) AS modeled_operational_cost_usd
FROM base CROSS JOIN a CROSS JOIN fixed f
GROUP BY customer_segment, a.platform_cost, a.processing_fixed, a.processing_bps, a.retry_cost,
         a.support_cost, a.manual_cost, a.notification_cost, a.failure_cost, a.fee_bps, f.fixed_cost;

CREATE OR REPLACE VIEW vw_payment_channel_profitability AS
WITH a AS (
    SELECT
        MAX(CASE WHEN assumption_id = 'platform_cost_per_transaction' THEN value END) AS platform_cost,
        MAX(CASE WHEN assumption_id = 'payment_processing_fixed_per_settled_transaction' THEN value END) AS processing_fixed,
        MAX(CASE WHEN assumption_id = 'payment_processing_bps' THEN value END) AS processing_bps,
        MAX(CASE WHEN assumption_id = 'retry_cost_per_attempt' THEN value END) AS retry_cost,
        MAX(CASE WHEN assumption_id = 'customer_support_cost_per_intervention_attempt' THEN value END) AS support_cost,
        MAX(CASE WHEN assumption_id = 'manual_review_cost_per_attempt' THEN value END) AS manual_cost,
        MAX(CASE WHEN assumption_id = 'notification_cost_per_notification' THEN value END) AS notification_cost,
        MAX(CASE WHEN assumption_id = 'failure_investigation_cost_per_failure' THEN value END) AS failure_cost,
        MAX(CASE WHEN assumption_id = 'incremental_fee_revenue_bps' THEN value END) AS fee_bps
    FROM financial_assumptions
),
recovery_by_txn AS (
    SELECT transaction_id, COUNT(*) AS attempts,
        COUNT(*) FILTER (WHERE recovery_track = 'Customer Intervention') AS support_attempts,
        COUNT(*) FILTER (WHERE recovery_track = 'Do Not Retry-Monitor') AS manual_attempts
    FROM recovery_attempts GROUP BY 1
),
notification_by_txn AS (
    SELECT transaction_id, COUNT(*) AS notification_count
    FROM transaction_events WHERE event_type = 'CUSTOMER_NOTIFIED' GROUP BY 1
),
fixed AS (SELECT SUM(modeled_cost_usd) AS fixed_cost FROM vw_financial_costs WHERE expense_class = 'recurring_fixed'),
base AS (
    SELECT ch.channel_name, t.*,
           COALESCE(r.attempts, 0) AS attempts, COALESCE(r.support_attempts, 0) AS support_attempts,
           COALESCE(r.manual_attempts, 0) AS manual_attempts,
           COALESCE(n.notification_count, 0) AS notification_count
    FROM transactions t JOIN channels ch ON t.channel_id = ch.channel_id
    LEFT JOIN recovery_by_txn r ON t.transaction_id = r.transaction_id
    LEFT JOIN notification_by_txn n ON t.transaction_id = n.transaction_id
),
calculated AS (
    SELECT
        channel_name,
        COUNT(*) AS transaction_count,
        COUNT(*) FILTER (WHERE final_status != 'success') AS failed_transaction_count,
        SUM(CASE WHEN is_valid_amount AND final_status != 'success' THEN amount ELSE 0 END) AS failed_face_value,
        SUM(CASE WHEN is_valid_amount AND final_status IN ('success','recovered_success') THEN amount ELSE 0 END) * a.fee_bps / 10000.0 AS fee_revenue,
        COUNT(*) * a.platform_cost
        + COUNT(*) FILTER (WHERE final_status IN ('success','recovered_success')) * a.processing_fixed
        + SUM(CASE WHEN is_valid_amount AND final_status IN ('success','recovered_success') THEN amount ELSE 0 END) * a.processing_bps / 10000.0
        + SUM(attempts) * a.retry_cost + SUM(support_attempts) * a.support_cost + SUM(manual_attempts) * a.manual_cost
        + COUNT(*) FILTER (WHERE final_status != 'success') * a.failure_cost
        + SUM(notification_count) * a.notification_cost
        + f.fixed_cost * COUNT(*) / SUM(COUNT(*)) OVER () AS operational_cost
    FROM base CROSS JOIN a CROSS JOIN fixed f
    GROUP BY channel_name, a.platform_cost, a.processing_fixed, a.processing_bps, a.retry_cost,
             a.support_cost, a.manual_cost, a.notification_cost, a.failure_cost, a.fee_bps, f.fixed_cost
)
SELECT channel_name, transaction_count, failed_transaction_count,
       ROUND(failed_face_value, 2) AS failed_face_value_usd,
       ROUND(fee_revenue, 2) AS modeled_fee_revenue_usd,
       ROUND(operational_cost, 2) AS modeled_operational_cost_usd,
       ROUND(fee_revenue - operational_cost, 2) AS modeled_contribution_usd,
       'Modeled contribution only; excludes credit losses, interchange detail, deposits, and capital costs' AS profitability_scope
FROM calculated;

CREATE OR REPLACE VIEW vw_budget_vs_actual AS
WITH actual AS (
    SELECT month, cost_category, ROUND(SUM(modeled_cost_usd), 2) AS modeled_actual_usd
    FROM vw_financial_costs GROUP BY 1, 2
)
SELECT
    b.month,
    b.cost_category,
    b.budget_usd,
    a.modeled_actual_usd,
    ROUND(b.budget_usd - a.modeled_actual_usd, 2) AS favorable_variance_usd,
    ROUND(100.0 * (b.budget_usd - a.modeled_actual_usd) / NULLIF(b.budget_usd, 0), 2) AS favorable_variance_pct,
    b.budget_version,
    b.source_type
FROM monthly_opex_budget b
LEFT JOIN actual a USING (month, cost_category);

CREATE OR REPLACE VIEW vw_scenario_comparison AS
SELECT
    'A' AS scenario_id, 'No Action' AS scenario_name,
    0.0 AS incremental_successful_transactions,
    0.0 AS incremental_processed_value_usd,
    0.0 AS incremental_fee_revenue_usd,
    0.0 AS avoided_operational_cost_usd,
    0.0 AS additional_cost_usd,
    0.0 AS net_financial_benefit_usd,
    NULL::DOUBLE AS roi_pct,
    NULL::DOUBLE AS break_even_conversion_rate_pct,
    'Observed baseline comparator' AS confidence
UNION ALL
SELECT scenario_id, scenario_name, incremental_successful_transactions,
       incremental_processed_value_usd, incremental_fee_revenue_usd,
       avoided_operational_cost_usd,
       additional_retry_cost_usd + additional_servicing_cost_usd + implementation_cost_usd + analysis_window_recurring_cost_usd,
       net_financial_benefit_usd, roi_pct, break_even_conversion_rate_pct, confidence
FROM vw_net_recovery_benefit
UNION ALL
SELECT
    'E', 'Combined Strategy',
    SUM(incremental_successful_transactions), SUM(incremental_processed_value_usd),
    SUM(incremental_fee_revenue_usd), SUM(avoided_operational_cost_usd),
    SUM(additional_retry_cost_usd + additional_servicing_cost_usd + implementation_cost_usd + analysis_window_recurring_cost_usd),
    SUM(net_financial_benefit_usd),
    100.0 * SUM(net_financial_benefit_usd) / NULLIF(SUM(additional_retry_cost_usd + additional_servicing_cost_usd + implementation_cost_usd + analysis_window_recurring_cost_usd), 0),
    NULL, 'Mixed'
FROM vw_net_recovery_benefit;

CREATE OR REPLACE VIEW vw_source_to_report_reconciliation AS
WITH checks AS (
    SELECT 'transaction_rows' AS check_name,
           (SELECT COUNT(*)::DOUBLE FROM transactions) AS source_value,
           (SELECT SUM(transaction_count)::DOUBLE FROM vw_transaction_performance) AS report_value
    UNION ALL
    SELECT 'valid_transaction_value_usd',
           (SELECT ROUND(SUM(CASE WHEN is_valid_amount THEN amount ELSE 0 END), 2) FROM transactions),
           (SELECT ROUND(SUM(valid_transaction_value_usd), 2) FROM vw_transaction_performance)
    UNION ALL
    SELECT 'failed_face_value_usd',
           (SELECT ROUND(SUM(CASE WHEN is_valid_amount AND final_status != 'success' THEN amount ELSE 0 END), 2) FROM transactions),
           (SELECT ROUND(SUM(failed_face_value_usd), 2) FROM vw_transaction_performance)
    UNION ALL
    SELECT 'recovery_attempt_rows',
           (SELECT COUNT(*)::DOUBLE FROM recovery_attempts),
           (SELECT SUM(recovery_attempts)::DOUBLE FROM vw_recovery_performance)
    UNION ALL
    SELECT 'opex_detail_to_monthly_usd',
           (SELECT ROUND(SUM(modeled_cost_usd), 2) FROM vw_financial_costs),
           (SELECT ROUND(SUM(total_opex_usd), 2) FROM vw_monthly_opex)
    UNION ALL
    SELECT 'combined_scenario_net_benefit_usd',
           (SELECT ROUND(SUM(net_financial_benefit_usd), 2) FROM vw_net_recovery_benefit),
           (SELECT ROUND(net_financial_benefit_usd, 2) FROM vw_scenario_comparison WHERE scenario_id = 'E')
)
SELECT check_name, source_value, report_value,
       ROUND(report_value - source_value, 6) AS difference,
       ABS(report_value - source_value) < 0.01 AS reconciles
FROM checks;
