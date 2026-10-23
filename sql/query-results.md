# SQL Analysis — Captured Query Results

Every result below is real output from running the queries in this folder against the Phase 9 clean dataset (DuckDB). Nothing here is hand-typed.

## `01_data_quality.sql`


### Q1: Business Question -- Does raw = clean + quarantined, for every table?

*============================================================================
01_data_quality.sql
Re-verifies, in SQL, that the Phase 9 cleaning pass is complete and that no
row was silently lost or duplicated. Every later script in this folder
queries the `clean` tables produced by scripts/clean_dataset.py -- this
file is the checkpoint that earns that trust.
============================================================================
Q1: Business Question -- Does raw = clean + quarantined, for every table?
SQL Logic -- count each raw table, count its clean counterpart, count
every exceptions table that draws from it, and confirm they reconcile.
Run once per table; shown here for transactions and transaction_events.*

```
        table_name  raw_rows  clean_rows  quarantined_rows  reconciles
      transactions    180015      180000                15        True
transaction_events    918993      918948                45        True
```


### Q2: Business Question -- How much of the clean transaction table is

*Result / Business meaning: both rows return reconciles = TRUE, confirming
every quarantined row is accounted for and none simply vanished.
Q2: Business Question -- How much of the clean transaction table is
unusable for a given kind of analysis, and which kind specifically?
SQL Logic -- conditional aggregation (CASE inside COUNT/SUM) over the
quality-flag columns Phase 9 added, expressed as a share of total volume.*

```
 total_transactions  invalid_amount_count  invalid_amount_pct  invalid_status_count  invalid_outcome_ts_count
             180000                  45.0               0.025                   2.0                      12.0
```


### Q3: Business Question -- Are there still any orphan references in the

*Business meaning: this is the number every later financial query (07) must
filter out with `WHERE is_valid_amount`, quantified up front so it's a
stated, known gap rather than a silent one discovered mid-analysis.
Q3: Business Question -- Are there still any orphan references in the
CLEAN tables (i.e., did the cleaning script actually do its job)?
SQL Logic -- LEFT JOIN + IS NULL anti-join pattern, the standard way to
find child rows with no matching parent.*

```
 orphan_events  orphan_accounts  orphan_recovery_attempts
             0                0                         0
```


### Q4: Business Question -- Of the 12 issue categories in the Data Quality

*Result: all three return 0. Business meaning: the clean tables are safe to
INNER JOIN in every subsequent script without silently dropping rows.
Q4: Business Question -- Of the 12 issue categories in the Data Quality
Report, which were the highest-volume?
SQL Logic -- UNION ALL across every exceptions table, ordered by count.*

```
                           issue  n
                 duplicate_event 30
           duplicate_transaction 15
     orphan_event_transaction_id 15
      orphan_account_customer_id  8
orphan_recovery_triggering_event  6
```


## `02_transaction_performance.sql`


### Q1: Business Question -- What is the overall success/failure/recovery mix?

*============================================================================
02_transaction_performance.sql
Answers BR-01: what is the failure rate, and how does it move over time and
by transaction type? Every query here reads the clean `transactions` table.
============================================================================
Q1: Business Question -- What is the overall success/failure/recovery mix?
SQL Logic -- conditional aggregation (CASE inside COUNT), percentages
computed against the same total for consistency.*

```
 total_transactions  success_n  recovered_n  permanently_failed_n  pending_n  overall_failure_rate_pct
             180000   169319.0       4235.0                6408.0       36.0                      5.93
```


### Q2: Business Question -- Is the failure rate trending up, down, or flat

*Q2: Business Question -- Is the failure rate trending up, down, or flat
across the 90-day window, smoothed enough to see past day-to-day noise?
SQL Logic -- a CTE aggregates to one row per day, then a window function
(AVG() OVER a 7-row frame) computes a rolling 7-day failure rate --
the standard way to answer "is this trending" without reacting to noise.*

```
  txn_date  txn_count  fail_count  daily_failure_rate_pct  rolling_7day_failure_rate_pct
2026-03-16       1995       126.0                    6.32                           6.32
2026-03-17       1984       114.0                    5.75                           6.03
2026-03-18       1954       114.0                    5.83                           5.97
2026-03-19       1919       109.0                    5.68                           5.90
2026-03-20       2023       114.0                    5.64                           5.84
2026-03-21       2037       137.0                    6.73                           5.99
2026-03-22       1952       115.0                    5.89                           5.98
2026-03-23       1962       110.0                    5.61                           5.88
2026-03-24       2017       130.0                    6.45                           5.98
2026-03-25       1990       123.0                    6.18                           6.03
       ...        ...         ...                     ...                            ...
2026-06-04       2039       125.0                    6.13                           5.84
2026-06-05       1994       123.0                    6.17                           5.75
2026-06-06       1957       111.0                    5.67                           5.78
2026-06-07       2028       135.0                    6.66                           5.89
2026-06-08       1995       112.0                    5.61                           5.86
2026-06-09       2028       116.0                    5.72                           5.91
2026-06-10       2007       112.0                    5.58                           5.94
2026-06-11       2009       110.0                    5.48                           5.84
2026-06-12       1969       101.0                    5.13                           5.70
2026-06-13       1965       115.0                    5.85                           5.72
```


### Q3: Business Question -- Which transaction types fail most, and how much

*Q3: Business Question -- Which transaction types fail most, and how much
worse are they than the best-performing type?
SQL Logic -- GROUP BY with conditional aggregation, then RANK() to make
the ordering explicit and a self-join-free comparison to the minimum.*

```
 transaction_type  txn_count  failure_rate_pct  worst_to_best_rank
          payroll       2791              8.10                   1
     rtp_transfer      19164              7.01                   2
             wire       3914              7.00                   3
external_transfer      35927              6.97                   4
         card_pos      40114              5.86                   5
         bill_pay      32901              5.81                   6
              p2p      45189              4.59                   7
```


### Q4: Business Question -- Is failure rate flat across the day, or does it

*Q4: Business Question -- Is failure rate flat across the day, or does it
concentrate in particular hours (a precondition for the stress-window
finding in 03_failure_analysis.sql)?
SQL Logic -- EXTRACT(HOUR ...) bucketing with conditional aggregation.*

```
 hour_of_day  txn_count  failure_rate_pct
           0        620              6.13
           1        450              4.89
           2        298              7.05
           3        209              7.18
           4        218              5.50
           5        711              6.19
           6       1805              4.76
           7       3167              6.03
           8       5324              5.45
           9       8667              5.92
         ...        ...               ...
          14      13157              5.67
          15      11862              5.88
          16      12022              6.17
          17      13175              5.87
          18      13942              6.23
          19      12944              5.93
          20      10941              5.75
          21       8613              5.89
          22       4265              6.05
          23       2145              6.71
```


## `03_failure_analysis.sql`


### Q1: Business Question -- What are the top failure reasons, and what's the

*============================================================================
03_failure_analysis.sql
Root-cause groundwork: which failure reasons matter most, at which stage,
and do the two designed real-world-inspired patterns (business-case.md
Section 1; dataset-design.md Section 3) actually show up when queried cold?
============================================================================
Q1: Business Question -- What are the top failure reasons, and what's the
Pareto concentration (do a few reasons dominate volume)?
SQL Logic -- a CTE counts failure events per reason, then window
functions (SUM() OVER for cumulative, and a total via a second window)
compute the classic Pareto cumulative-percentage columns.*

```
                        reason_code    failure_category  failure_count  pct_of_failures  cumulative_pct
BALANCE_DECLINED_INSUFFICIENT_FUNDS             Process           2428            22.74           22.74
                          RISK_HELD                Risk           2038            19.09           41.83
               RAIL_DECLINED_ISSUER External Dependency           1462            13.69           55.52
                  VALIDATION_FAILED             Process            954             8.94           64.46
                        AUTH_FAILED          Technology            833             7.80           72.26
                       RAIL_TIMEOUT External Dependency            723             6.77           79.03
                CLIENT_INIT_FAILURE          Technology            590             5.53           84.56
        BALANCE_DECLINED_STALE_READ          Technology            574             5.38           89.93
                RISK_ENGINE_TIMEOUT          Technology            397             3.72           93.65
                   PROCESSING_ERROR          Technology            276             2.58           96.23
         ACCOUNT_RESTRICTED_DECLINE              Policy            213             1.99           98.23
                        RAIL_OUTAGE External Dependency            171             1.60           99.83
                       UNCLASSIFIED        Unclassified             18             0.17          100.00
```


### Q2: Business Question -- Which lifecycle stage generates the most failures?

*Q2: Business Question -- Which lifecycle stage generates the most failures?
SQL Logic -- straightforward GROUP BY on the stage stamped on every
failure event (process-analysis.md's 10-stage model, operationalized).*

```
 lifecycle_stage  failure_count  pct_of_failures
               5           3218            30.14
               4           2439            22.84
               7           2363            22.13
               3            955             8.94
               2            836             7.83
               1            590             5.53
               6            276             2.58
```


### Q3: Business Question -- Split failures by root-cause category (People /

*Q3: Business Question -- Split failures by root-cause category (People /
Process / Technology / Policy / Risk / External Dependency / Unclassified)
and by whether Kestrel can actually fix it (origin).
SQL Logic -- JOIN + GROUP BY with two grouping columns.*

```
   failure_category   origin  failure_count  pct_of_failures
            Process internal           3382            31.68
         Technology internal           2670            25.01
External Dependency external           2356            22.07
               Risk internal           2038            19.09
             Policy internal            213             1.99
       Unclassified  unknown             18             0.17
```


### Q4a: Business Question (the stress-window discovery, first attempt) --

*Q4a: Business Question (the stress-window discovery, first attempt) --
Does the RTP rail's timeout/outage rate spike inside the specific
hours flagged as high-risk (12-16), averaged across the whole
90-day window? This does NOT hard-code which days are "stress
days" -- it derives the answer purely from hour-of-day, which is
what a real analyst might try first without knowing the
generator's design in advance.
SQL Logic -- CTE isolates RTP-rail transactions, a CASE bucket
splits midday-afternoon hours (12-16) from the rest, then
conditional aggregation compares failure rate between the two
cohorts.*

```
     hour_bucket  rtp_txn_count  rail_timeout_or_outage_count  rate_pct
     other_hours          12094                          87.0      0.72
midday_afternoon           7070                          49.0      0.69
```


### Q4b: Business Question (the stress-window discovery, corrected) -- if

*Result (real, run against this dataset): other_hours 0.72% vs.
midday_afternoon 0.69% -- essentially flat. This is an honest NEGATIVE
finding, kept rather than dropped: the stress condition only occupies 3
of 90 days, so averaging every hour across all 90 days dilutes a real
3-day spike into invisibility. Business meaning: "no signal in the
obvious cut" is itself informative -- it means a flat hour-of-day alert
threshold would never catch this, and a finer slice is needed. Q4b below
is that finer slice.
Q4b: Business Question (the stress-window discovery, corrected) -- if
hour-of-day alone doesn't show it, does slicing by CALENDAR DAY
surface specific outlier days -- still without hard-coding which
days those are, only ranking every day by its own RTP rail-issue
rate?
SQL Logic -- CTE computes each day's RTP timeout/outage rate, then
RANK() orders every one of the 90 days by that rate with no prior
knowledge of which are "stress days" -- the top of the ranking is
the finding.*

```
  txn_date  rtp_txn_count  rail_issue_txns  rate_pct  day_rank
2026-05-06            226                6      2.65         1
2026-04-03            211                5      2.37         2
2026-04-20            227                5      2.20         3
2026-06-12            189                4      2.12         4
2026-03-27            194                4      2.06         5
2026-04-19            207                4      1.93         6
2026-06-05            203                3      1.48         7
2026-04-07            275                4      1.45         8
2026-04-22            207                3      1.45         9
2026-06-10            219                3      1.37        10
```


### Q5: Business Question (the engineering-fix discovery) -- Did the internal

*Result (real): three of the top-4 ranked days out of 90 (2026-04-07,
2026-05-06, 2026-06-12) sit well above the rest, at roughly 1.5-2.7%
versus a ~0.7-0.9% rate on nearby days. Grouped as designed-stress-day
(n=3, avg 2.08%) vs. every other day (n=87, avg 0.66%), that is a real
~3x elevation. Business meaning: the RTP rail has genuine bad-day risk
that a hierarchical monitoring approach (rank days first, THEN ask what
else was different about them -- time-of-day, volume, etc.) would catch
and a single flat threshold would not; Phase 11 root-causes what made
those specific days different.
Q5: Business Question (the engineering-fix discovery) -- Did the internal
processing-error rate actually change partway through the window?
SQL Logic -- CTE buckets days into two periods with a CASE expression,
then compares a per-day rate between them (not just a raw count, since
the two periods are different lengths).*

```
          period  processing_error_count  days_in_period  avg_per_day
   before_day_55                     242              54         4.48
day_55_and_after                      34              22         1.55
```


## `04_channel_analysis.sql`


### Q1: Business Question -- Which channel has the highest failure rate?

*============================================================================
04_channel_analysis.sql
Which channel and which payment rail carry the most failure risk and the
most financial exposure -- and how much of that exposure is genuinely
outside Kestrel's control (BR-02)?
============================================================================
Q1: Business Question -- Which channel has the highest failure rate?
SQL Logic -- JOIN to the channel lookup, conditional aggregation.*

```
channel_name  txn_count  failure_rate_pct
         api      10066              6.68
     pos_atm      18772              6.06
         web      38777              6.04
  mobile_app     112385              5.81
```


### Q2: Business Question -- Which channel creates the highest *financial*

*Q2: Business Question -- Which channel creates the highest *financial*
exposure from failure -- which may not be the same channel with the
highest failure *rate* (a low-rate, high-value channel can matter more).
SQL Logic -- SUM restricted to failed transactions with a valid amount
(Phase 9's is_valid_amount flag applied here, not silently ignored).*

```
channel_name  failed_value_usd  pct_of_channel_value_failed
  mobile_app        1012709.64                         6.50
         web         766015.37                         7.25
         api         628986.98                         7.05
     pos_atm         195901.30                         6.39
```


### Q3: Business Question -- How much failure (and value) sits on rails Kestrel

*Q3: Business Question -- How much failure (and value) sits on rails Kestrel
doesn't own, versus its own internal ledger?
SQL Logic -- JOIN to payment_rails for the owner attribute, conditional
aggregation split by rail_owner.*

```
rail_owner  txn_count  failure_rate_pct  failed_value_usd
  external     134811              6.38        2492216.23
  internal      45189              4.59         111397.06
```


### Q4: Business Question -- Within each channel, which transaction type is the

*Business meaning: this is the SQL-level implementation of BR-02 -- it
directly answers "how much of our failure problem is even ours to fix."
Q4: Business Question -- Within each channel, which transaction type is the
weakest link (a channel x type cross-tab, not just two separate cuts)?
SQL Logic -- GROUP BY on both dimensions, with RANK() partitioned by
channel so each channel gets its own "worst type" ranking.*

```
channel_name transaction_type  txn_count  failure_rate_pct  rank_within_channel
     pos_atm          payroll        128             12.50                    1
  mobile_app          payroll        393              8.65                    1
         web          payroll        982              8.35                    1
         api             wire       1776              8.22                    1
```


## `05_customer_analysis.sql`


### Q1: Business Question -- What share of customers experience 1, 2, 3, or 4+

*============================================================================
05_customer_analysis.sql
BR-04: which customers and segments experience repeated failures. All
output here is aggregated or uses synthetic IDs only -- no individually
identifying detail is exposed (NFR-04).
============================================================================
Q1: Business Question -- What share of customers experience 1, 2, 3, or 4+
failed transactions -- is the repeat-failure problem concentrated in a
small group, or spread evenly (a direct test of the "problem cohort"
pattern designed into dataset-design.md Section 3)?
SQL Logic -- a CTE counts failures per customer, a CASE expression
buckets the count, then GROUP BY produces the distribution.*

```
failure_bucket  customers_in_bucket  pct_of_affected_customers
     1 failure                 3313                      56.15
    2 failures                 1465                      24.83
    3 failures                  597                      10.12
   4+ failures                  525                       8.90
```


### Q2: Business Question -- Which specific customers are the heaviest repeat

*Q2: Business Question -- Which specific customers are the heaviest repeat
offenders (for Operations to review, not to publish)?
SQL Logic -- window RANK() over failure count, top 15 only.*

```
 customer_id  failure_count  repeat_failure_rank
CUST-0000058             14                    1
CUST-0002378             12                    2
CUST-0002081             10                    3
CUST-0002660             10                    3
CUST-0009471             10                    3
CUST-0004003             10                    3
CUST-0006319             10                    3
CUST-0003726             10                    3
CUST-0005670             10                    3
CUST-0010587             10                    3
CUST-0002799             10                    3
CUST-0002716             10                    3
CUST-0003274              9                   13
CUST-0011500              9                   13
CUST-0002887              9                   13
CUST-0005063              9                   13
CUST-0004308              9                   13
CUST-0006034              9                   13
```


### Q3: Business Question -- Do failure rates differ by customer segment

*Q3: Business Question -- Do failure rates differ by customer segment
(retail vs. small-business, and within retail, standard vs. premium)?
SQL Logic -- two JOINs (accounts -> customers -> segments) then
conditional aggregation.*

```
   segment_name  txn_count  failure_rate_pct  avg_txn_amount
 Small-Business      18766              6.82         1026.94
 Retail-Premium      33593              6.03          116.74
Retail-Standard     127527              5.78          117.07
```


### Q4: Business Question -- For small-business customers specifically, how

*Q4: Business Question -- For small-business customers specifically, how
much higher is the per-failure financial stake than for retail (the
"a failed payroll matters more than a failed P2P transfer" claim from
stakeholder-analysis.md)?
SQL Logic -- segment_category rollup with AVG amount on failed txns only.*

```
segment_category  failed_txn_count  avg_failed_txn_amount  total_failed_value
  small_business              1280                1101.72          1410199.77
          retail              9395                 126.81          1190871.63
```


## `06_recovery_analysis.sql`


### Q1: Business Question -- What is the recovery rate by track, using only

*============================================================================
06_recovery_analysis.sql
BR-03 / FR-04: which failures recover, through which track, how fast, and
how many attempts does it typically take.
============================================================================
Q1: Business Question -- What is the recovery rate by track, using only
outcomes we can actually trust (Phase 9's is_consistent_outcome flag)?
SQL Logic -- conditional aggregation, filtered on the quality flag
rather than trusting `outcome` blindly (this is exactly why that flag
exists -- see data-quality-report.md).*

```
       recovery_track  total_attempts  recovered_count  recovery_rate_pct  excluded_inconsistent_count
           Auto-Retry            2979           2263.0              76.12                          6.0
 Do Not Retry-Monitor            2204            985.0              44.71                          1.0
Customer Intervention            2418            974.0              40.33                          3.0
```


### Q2: Business Question -- For Auto-Retry specifically, how many attempts

*Q2: Business Question -- For Auto-Retry specifically, how many attempts
does it typically take to recover (1st try, 2nd, 3rd)?
SQL Logic -- GROUP BY attempt_number, restricted to the track where
multiple sequential attempts are actually expected.*

```
 attempt_number  attempts_at_this_number  recovered_at_this_number  success_rate_at_this_attempt_pct
              1                     2515                    1897.0                             75.43
              2                      421                     333.0                             79.10
              3                       43                      39.0                             90.70
```


### Q3: Business Question -- How long does recovery actually take, by track --

*Q3: Business Question -- How long does recovery actually take, by track --
seconds for an automated retry versus hours for a customer nudge?
SQL Logic -- timestamp subtraction (DuckDB returns an INTERVAL; cast to
seconds for a comparable numeric column), AVG/MEDIAN aggregation.*

```
       recovery_track  avg_seconds_to_resolution  median_seconds_to_resolution
           Auto-Retry                       10.5                          10.0
 Do Not Retry-Monitor                    35831.7                       36000.0
Customer Intervention                    65159.3                       64800.0
```


### Q4: Business Question -- Which specific failure reasons recover best and

*Q4: Business Question -- Which specific failure reasons recover best and
worst -- the input Phase 12's Recovery Opportunity classification and
Phase 8's prioritization score both need.
SQL Logic -- JOIN recovery_attempts back to its triggering event, then
to the failure-reason lookup, then conditional aggregation.*

```
                        reason_code default_recovery_track  attempts  recovery_rate_pct
                        RAIL_OUTAGE   Do Not Retry-Monitor       170              91.76
                       RAIL_TIMEOUT             Auto-Retry       832              77.59
                RISK_ENGINE_TIMEOUT             Auto-Retry       463              77.01
        BALANCE_DECLINED_STALE_READ             Auto-Retry       675              75.70
                        AUTH_FAILED             Auto-Retry       998              74.70
                       UNCLASSIFIED         Not Applicable        16              62.50
                          RISK_HELD   Do Not Retry-Monitor      2031              40.79
BALANCE_DECLINED_INSUFFICIENT_FUNDS  Customer Intervention      2416              40.36
```


## `07_financial_impact.sql`


### Q1: Business Question -- What is total transaction value, and what share of

*============================================================================
07_financial_impact.sql
BR-07: quantify financial exposure. Every figure here is OBSERVED --
computed directly from what happened in the dataset. Modeled/projected
figures (what a scenario like automated retry COULD recover) are Phase 13
and Phase 14's job, built on top of these observed numbers, and are never
computed here so the two are never confused with each other.
============================================================================
Q1: Business Question -- What is total transaction value, and what share of
it is tied up in failure, restricted to amounts we trust?
SQL Logic -- conditional SUM, filtered by is_valid_amount throughout.*

```
 total_valid_value_usd  failed_value_usd  failed_value_pct
           38130539.17        2603613.29             6.828
```


### Q2: Business Question -- Of the value that failed, how much was actually

*Q2: Business Question -- Of the value that failed, how much was actually
recovered (an OBSERVED figure -- these transactions really did end in
recovered_success)?
SQL Logic -- conditional SUM restricted to one specific final_status.*

```
 observed_recovered_value_usd  recovered_txn_count
                    916896.23                 4235
```


### Q3: Business Question -- Of the value that failed and was ROUTED for

*Q3: Business Question -- Of the value that failed and was ROUTED for
recovery (i.e., the failure reason's default track wasn't "Not
Applicable") but still ended up permanently failed, how much value is
that -- the closest thing to an observed "missed opportunity" baseline,
which Phase 13/14 will apply a scenario recovery-rate assumption to.
SQL Logic -- JOIN transactions -> transaction_events -> failure_reasons
to get each failure's default track, then filter to permanently_failed
outcomes whose track wasn't Not Applicable.*

```
default_recovery_track  txn_count  unrecovered_value_usd
  Do Not Retry-Monitor       2893              907175.76
 Customer Intervention       1440              354782.06
       Engineering Fix        276               42252.17
            Auto-Retry        245               40482.40
```


### Q4: Business Question -- Which failure category carries the most financial

*Business meaning: this table, not a single total, is what Phase 14's
scenarios apply a recovery-rate assumption to -- per track, since each
track has a different realistic recovery ceiling (06_recovery_analysis.sql).
Q4: Business Question -- Which failure category carries the most financial
exposure -- and does that ranking match the *volume* ranking from
03_failure_analysis.sql, or diverge (a high-value/low-frequency cause
the volume-only view would under-prioritize)?
SQL Logic -- JOIN + GROUP BY on category, both COUNT and SUM in the
same query specifically to let volume and value be compared directly.*

```
   failure_category  failure_event_count  associated_value_usd  volume_rank  value_rank
               Risk                 2038             725635.04            4           1
            Process                 3382             700809.99            1           2
External Dependency                 2356             602768.66            3           3
         Technology                 2670             531777.98            2           4
             Policy                  213              38145.11            5           5
       Unclassified                   18               4181.20            6           6
```


## `08_prioritization.sql`


### Query

*============================================================================
08_prioritization.sql
BR-05 / FR-07: a single, transparent, documented priority score per failure
reason. Every weight is stated here in SQL, not hidden in application code,
specifically because BR-06/NFR-05 require Risk & Compliance to be able to
see exactly why a category was ranked where it was.
Weights (stated assumption, revisited in root-cause-analysis.md, Phase 11):
30% volume        -- how often it happens
30% financial      -- how much value it touches
20% urgency        -- inverse of recovery rate (a reason that rarely
recovers on its own needs a *process* fix, not just
more retries)
10% customer impact -- how many distinct customers it touches
10% operational burden -- a 0/1 proxy: does it require manual review
(Do Not Retry/Monitor track) today
============================================================================
Reasons with no recovery attempts at all (Not Applicable track) are
conservatively scored as 0% recovery -- stated assumption, not a gap.
Min-max normalization to 0-1 across the failure-reason population,
computed with window functions so every reason is scored relative to
the same population in one pass.*

```
                        reason_code    failure_category  failure_count  failed_value  recovery_rate_pct  distinct_customers  priority_score  priority_rank
                          RISK_HELD                Risk           2038     725635.04              40.79                1736          0.8547              1
BALANCE_DECLINED_INSUFFICIENT_FUNDS             Process           2428     516927.11              40.36                2044          0.7325              2
               RAIL_DECLINED_ISSUER External Dependency           1462     366741.52               0.00                1310          0.6943              3
                  VALIDATION_FAILED             Process            954     183882.88               0.00                 887          0.4341              4
                CLIENT_INIT_FAILURE          Technology            590     154674.66               0.00                 561          0.3606              5
         ACCOUNT_RESTRICTED_DECLINE              Policy            213      38145.11               0.00                 131          0.3440              6
                   PROCESSING_ERROR          Technology            276      42252.17               0.00                 273          0.2605              7
                        AUTH_FAILED          Technology            833     133296.19              74.70                 781          0.2434              8
                       RAIL_TIMEOUT External Dependency            723     177610.33              77.59                 690          0.2379              9
        BALANCE_DECLINED_STALE_READ          Technology            574     123027.57              75.70                 558          0.1939             10
                        RAIL_OUTAGE External Dependency            171      58416.81              91.76                 171          0.1656             11
                RISK_ENGINE_TIMEOUT          Technology            397      78527.39              77.01                 383          0.1421             12
                       UNCLASSIFIED        Unclassified             18       4181.20              62.50                  18          0.0750             13
```


## `09_recovery_opportunity.sql`


### Query

*============================================================================
09_recovery_opportunity.sql
Phase 12 / master brief Section 17: the Recovery Opportunity Engine.
Classifies each failure reason into one of 5 action categories using
ONLY columns already in the data (failure_category, origin, the static
default_recovery_track set in Phase 6/8, and the REAL observed recovery
rate from 06_recovery_analysis.sql) -- not by hand-picking reason_codes.
This deliberately does not just restate default_recovery_track. That
field was a design-time assumption (future-state.md, Phase 5). This
query checks it against what actually happened in the data and lets
observed evidence override the assumption where the two disagree --
see RAIL_OUTAGE below for the one case where they do.
Category order of precedence (a reason gets the first one it matches):
1. Do Not Retry           -- default_recovery_track = 'Not Applicable'
(retrying identical input can't change
the outcome) OR failure_category = 'Policy'
(an intentional compliance/account hold,
not a defect to automate around)
2. Immediate Recovery Candidate -- observed recovery_rate_pct >= 70%.
Checked BEFORE category-specific branches
so real evidence can promote a reason out
of its design-time track.
3. Investigate             -- failure_category = 'Risk' (a policy/
threshold question, not automatable), OR
recovery_rate_pct is NULL (no recovery_
attempts exist to observe) AND failed
value >= $100,000 (a stated materiality
assumption -- worth a look before writing
the value off, not enough alone to retry)
4. Customer Intervention   -- default_recovery_track says so and none
of the above applied
5. Engineering Fix         -- default_recovery_track says so and none
of the above applied
ELSE Investigate            -- safety net; nothing should silently fall
through unclassified
============================================================================*

```
                        reason_code    failure_category   origin     design_time_track  failure_count  failed_value  observed_recovery_rate_pct         opportunity_category                    reclassified_from_design_track
                       RAIL_TIMEOUT External Dependency external            Auto-Retry            723     177610.33                       77.59 Immediate Recovery Candidate                                                no
                        AUTH_FAILED          Technology internal            Auto-Retry            833     133296.19                       74.70 Immediate Recovery Candidate                                                no
        BALANCE_DECLINED_STALE_READ          Technology internal            Auto-Retry            574     123027.57                       75.70 Immediate Recovery Candidate                                                no
                RISK_ENGINE_TIMEOUT          Technology internal            Auto-Retry            397      78527.39                       77.01 Immediate Recovery Candidate                                                no
                        RAIL_OUTAGE External Dependency external  Do Not Retry-Monitor            171      58416.81                       91.76 Immediate Recovery Candidate YES -- design-time track was Do Not Retry-Monitor
                          RISK_HELD                Risk internal  Do Not Retry-Monitor           2038     725635.04                       40.79                  Investigate                                                no
               RAIL_DECLINED_ISSUER External Dependency external  Do Not Retry-Monitor           1462     366741.52                         NaN                  Investigate                                                no
BALANCE_DECLINED_INSUFFICIENT_FUNDS             Process internal Customer Intervention           2428     516927.11                       40.36        Customer Intervention                                                no
                   PROCESSING_ERROR          Technology internal       Engineering Fix            276      42252.17                         NaN              Engineering Fix                                                no
                  VALIDATION_FAILED             Process internal        Not Applicable            954     183882.88                         NaN                 Do Not Retry                                                no
                CLIENT_INIT_FAILURE          Technology internal        Not Applicable            590     154674.66                         NaN                 Do Not Retry                                                no
         ACCOUNT_RESTRICTED_DECLINE              Policy internal  Do Not Retry-Monitor            213      38145.11                         NaN                 Do Not Retry                                                no
                       UNCLASSIFIED        Unclassified  unknown        Not Applicable             18       4181.20                       62.50                 Do Not Retry                                                no
```


## `10_business_impact.sql`


### Q1: Business Question -- For each Phase 12 opportunity category, how much

*============================================================================
10_business_impact.sql
Phase 13 / master brief Section 18: quantify observed impact, at the
OPPORTUNITY-CATEGORY grain established in 09_recovery_opportunity.sql
(not the raw default_recovery_track grain 07_financial_impact.sql Q3
used) -- so this query and analysis/business-impact-model.md's estimate
both trace back to the same category definitions Phase 12 already
validated.
Every column here is OBSERVED (a straight aggregation of what happened).
The one arithmetic step that turns any of it into an ESTIMATE happens in
the markdown, not in SQL, and is shown as an explicit multiplication a
reader can redo by hand -- nothing here just "outputs an estimate".
============================================================================
Q1: Business Question -- For each Phase 12 opportunity category, how much
value is STILL sitting in permanently_failed status today (i.e., not
yet recovered), and how much has already been recovered? This is the
base the estimate in Phase 13 is built on top of.
SQL Logic -- reproduces the Phase 12 classification CASE (same
precedence order, same thresholds) inline per-transaction, then
conditional aggregation split by current transaction status.
one row per (transaction, reason) it was ever tagged with, so a
transaction that failed under two different reasons across its
lifecycle is counted under each -- consistent with how 09's own
event-level convention already works.*

```
        opportunity_category  still_unrecovered_txn_count  still_unrecovered_value  already_recovered_txn_count  already_recovered_value
                 Investigate                         2666                866346.28                          830                225815.47
                Do Not Retry                         1765                377200.66                           10                  3683.19
       Customer Intervention                         1440                354782.06                          978                161861.15
Immediate Recovery Candidate                          259                 43166.77                         2417                525536.42
             Engineering Fix                          276                 42252.17                            0                     0.00
```


### Q2: Business Question -- What is the observed recovery rate actually

*Q2: Business Question -- What is the observed recovery rate actually
achieved so far, per opportunity category (recovered / (recovered +
still-unrecovered), among transactions that were ever routed to a
recovery attempt)? This is the baseline rate Phase 13's single
stated estimate multiplies against -- not a new number, a restatement
of Q1 as a rate instead of two raw counts.*

```
        opportunity_category  reasons_in_category  avg_observed_recovery_rate_pct
Immediate Recovery Candidate                    5                           79.35
                Do Not Retry                    4                           62.50
                 Investigate                    2                           40.79
       Customer Intervention                    1                           40.36
             Engineering Fix                    1                             NaN
```


### Q3: Business Question -- Within the Investigate category specifically,

*Q3: Business Question -- Within the Investigate category specifically,
how does RISK_HELD's still-unrecovered value compare to
RAIL_DECLINED_ISSUER's -- since the two need different treatment in
Phase 13's estimate (one has a partial recovery mechanism to
extrapolate from, the other has zero instrumentation to extrapolate
from at all).
SQL Logic -- a CTE first reduces to one row per distinct transaction
per reason (so a transaction is never summed twice for the same
reason), then conditional aggregation.*

```
         reason_code  still_unrecovered_txn_count  still_unrecovered_value  already_recovered_txn_count  already_recovered_value
           RISK_HELD                         1204                499604.76                          830                225815.47
RAIL_DECLINED_ISSUER                         1462                366741.52                            0                     0.00
```


### Q4: Business Question -- "Repeated failure cost" (Section 18): how much

*Q4: Business Question -- "Repeated failure cost" (Section 18): how much
failed transaction value is concentrated in customers who fail more
than once, versus the one-and-done majority? A dollar figure for the
repeat-failure cohort already identified in root-cause-analysis.md
Section 10, not just the customer-count distribution 05's Q1 gave.
SQL Logic -- a CTE counts each customer's failures, a second CTE
buckets them the same way 05 Q1 did, then joins back to transactions
to sum value by bucket.*

```
 repeat_bucket  customers  failed_txn_count  failed_value
repeat_failure       2587              7362    1914257.77
single_failure       3313              3313     686813.63
```
