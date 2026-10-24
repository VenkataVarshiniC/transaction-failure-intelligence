-- ============================================================================
-- 01_data_quality.sql
-- Re-verifies, in SQL, that the Phase 9 cleaning pass is complete and that no
-- row was silently lost or duplicated. Every later script in this folder
-- queries the `clean` tables produced by scripts/clean_dataset.py -- this
-- file is the checkpoint that earns that trust.
-- ============================================================================

-- Q1: Business Question -- Does raw = clean + quarantined, for every table?
--     SQL Logic -- count each raw table, count its clean counterpart, count
--     every exceptions table that draws from it, and confirm they reconcile.
--     Run once per table; shown here for transactions and transaction_events.
SELECT
    'transactions' AS table_name,
    (SELECT COUNT(*) FROM raw_transactions) AS raw_rows,
    (SELECT COUNT(*) FROM transactions) AS clean_rows,
    (SELECT COUNT(*) FROM exceptions_transactions_duplicates) AS quarantined_rows,
    (SELECT COUNT(*) FROM transactions) + (SELECT COUNT(*) FROM exceptions_transactions_duplicates)
        = (SELECT COUNT(*) FROM raw_transactions) AS reconciles
UNION ALL
SELECT
    'transaction_events',
    (SELECT COUNT(*) FROM raw_transaction_events),
    (SELECT COUNT(*) FROM transaction_events),
    (SELECT COUNT(*) FROM exceptions_events_duplicates) + (SELECT COUNT(*) FROM exceptions_events_orphan),
    (SELECT COUNT(*) FROM transaction_events)
        + (SELECT COUNT(*) FROM exceptions_events_duplicates)
        + (SELECT COUNT(*) FROM exceptions_events_orphan)
        = (SELECT COUNT(*) FROM raw_transaction_events);
-- Result / Business meaning: both rows return reconciles = TRUE, confirming
-- every quarantined row is accounted for and none simply vanished.

-- Q2: Business Question -- How much of the clean transaction table is
--     unusable for a given kind of analysis, and which kind specifically?
--     SQL Logic -- conditional aggregation (CASE inside COUNT/SUM) over the
--     quality-flag columns Phase 9 added, expressed as a share of total volume.
SELECT
    COUNT(*) AS total_transactions,
    SUM(CASE WHEN NOT is_valid_amount THEN 1 ELSE 0 END) AS invalid_amount_count,
    ROUND(100.0 * SUM(CASE WHEN NOT is_valid_amount THEN 1 ELSE 0 END) / COUNT(*), 4) AS invalid_amount_pct,
    SUM(CASE WHEN NOT is_valid_status THEN 1 ELSE 0 END) AS invalid_status_count,
    SUM(CASE WHEN NOT is_valid_outcome_timestamp THEN 1 ELSE 0 END) AS invalid_outcome_ts_count
FROM transactions;
-- Business meaning: this is the number every later financial query (07) must
-- filter out with `WHERE is_valid_amount`, quantified up front so it's a
-- stated, known gap rather than a silent one discovered mid-analysis.

-- Q3: Business Question -- Are there still any orphan references in the
--     CLEAN tables (i.e., did the cleaning script actually do its job)?
--     SQL Logic -- LEFT JOIN + IS NULL anti-join pattern, the standard way to
--     find child rows with no matching parent.
SELECT
    (SELECT COUNT(*) FROM transaction_events e
        LEFT JOIN transactions t ON e.transaction_id = t.transaction_id
        WHERE t.transaction_id IS NULL) AS orphan_events,
    (SELECT COUNT(*) FROM accounts a
        LEFT JOIN customers c ON a.customer_id = c.customer_id
        WHERE c.customer_id IS NULL) AS orphan_accounts,
    (SELECT COUNT(*) FROM recovery_attempts r
        LEFT JOIN transaction_events e ON r.triggering_event_id = e.event_id
        WHERE e.event_id IS NULL) AS orphan_recovery_attempts;
-- Result: all three return 0. Business meaning: the clean tables are safe to
-- INNER JOIN in every subsequent script without silently dropping rows.

-- Q4: Business Question -- Of the 12 issue categories in the Data Quality
--     Report, which were the highest-volume?
--     SQL Logic -- UNION ALL across every exceptions table, ordered by count.
SELECT 'duplicate_transaction' AS issue, COUNT(*) AS n FROM exceptions_transactions_duplicates
UNION ALL SELECT 'duplicate_event', COUNT(*) FROM exceptions_events_duplicates
UNION ALL SELECT 'orphan_event_transaction_id', COUNT(*) FROM exceptions_events_orphan
UNION ALL SELECT 'orphan_account_customer_id', COUNT(*) FROM exceptions_accounts_orphan
UNION ALL SELECT 'orphan_recovery_triggering_event', COUNT(*) FROM exceptions_recovery_orphan
ORDER BY n DESC, issue;
