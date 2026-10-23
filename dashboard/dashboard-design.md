# Power BI Dashboard — Design Specification

**Phase 15 of 20 — Bank Transaction Failure Intelligence & Recovery Optimization**

## 1. Why this is a spec, not a `.pbix`

Power BI Desktop is Windows-only software this sandboxed environment can't
run — there's no way to hand over a working `.pbix` file from here. More
importantly: if this dashboard is going on a resume as "built an
interactive Power BI dashboard," the honest and actually-useful thing is
for **you** to build it, from a spec detailed enough that you're not
guessing at anything, not for me to hand you a finished file you didn't
build. That's the approach below — everything needed to build this in
Power BI Desktop yourself: data sources, the exact model and
relationships, every DAX measure for the headline KPIs, and a full
page-by-page spec matching master brief Section 20.

## 2. Data sources

Import these directly — no new extraction needed, they're already the
Phase 9 analysis-ready layer:

| File | Role in the model |
|---|---|
| `data/clean/transactions.csv` | **Fact table** — one row per transaction |
| `data/clean/transaction_events.csv` | **Fact table** — one row per lifecycle event (the failure/recovery detail fact) |
| `data/clean/recovery_attempts.csv` | **Fact table** — one row per recovery attempt |
| `data/clean/accounts.csv` | Dimension |
| `data/clean/customers.csv` | Dimension |
| `data/clean/customer_segments.csv` | Dimension |
| `data/clean/channels.csv` | Dimension |
| `data/clean/payment_rails.csv` | Dimension |
| `data/clean/failure_reasons.csv` | Dimension |
| `dashboard/failure_reason_opportunity_category.csv` **(new this phase)** | Dimension extension — the Phase 12 classification (`sql/09_recovery_opportunity.sql`), one row per `reason_code` |
| `dashboard/scenario_simulator.csv` **(new this phase)** | Standalone table for Page 5 — the 5 scenarios from `whatif-simulation.md`, pre-computed |

Get Data → Text/CSV for each. On import, fix these data types explicitly
(Power BI's auto-detect gets IDs wrong by default):

- Every `*_id` column → **Text** (not Whole Number — these are labels like
  `TXN-000123`, not quantities; leaving them as numbers breaks sorting
  and lets them get accidentally summed)
- `initiated_at`, `final_outcome_at`, `event_timestamp`, `opened_date`,
  `signup_date` → **Date/Time**
- `amount`, `risk_score` → **Decimal Number**
- `is_valid_amount`, `is_valid_status`, `is_valid_outcome_timestamp`,
  `is_valid_event_timestamp`, `is_consistent_outcome` → **True/False**

## 3. Data model

**Merge the opportunity category onto `failure_reasons` before building
relationships** (Power Query Editor → `failure_reasons` → Merge Queries →
`failure_reason_opportunity_category` → join on `reason_code` → expand
`opportunity_category`). This keeps the model to one dimension table per
concept instead of an extra small table to relate.

Relationships (all Power BI defaults: single-direction, many-to-one, from
fact to dimension):

```
transactions[account_id]      -> accounts[account_id]
transactions[channel_id]      -> channels[channel_id]
transactions[rail_id]         -> payment_rails[rail_id]
accounts[customer_id]         -> customers[customer_id]
customers[segment_id]         -> customer_segments[segment_id]
transaction_events[transaction_id]     -> transactions[transaction_id]
transaction_events[failure_reason_id]  -> failure_reasons[failure_reason_id]
recovery_attempts[transaction_id]      -> transactions[transaction_id]
recovery_attempts[triggering_event_id] -> transaction_events[event_id]
```

`scenario_simulator` stays **unrelated** to everything else — it's a
standalone lookup table for Page 5's What-If Parameter, deliberately not
joined to the transaction data (see Page 5 below for why).

This is a galaxy schema (three fact tables — `transactions`,
`transaction_events`, `recovery_attempts` — sharing dimensions), not a
pure single-fact star. That's normal for a lifecycle/event model like
this one (`data-architecture.md` Section 5 already explains why a single
flat fact table doesn't fit this domain) — just be deliberate that a
measure meant to count *transactions* should use `transactions` as its
table, and a measure meant to count *failure events* should use
`transaction_events`, since they're different grains.

## 4. Core DAX measures

Create a dedicated measures table (New Table → `_Measures = {BLANK()}`,
hide the column) to keep these organized instead of scattering them
across the data tables.

```DAX
Total Transactions = COUNTROWS(transactions)

Failed Transactions =
CALCULATE(COUNTROWS(transactions), transactions[final_status] <> "success")

Failure Rate % = DIVIDE([Failed Transactions], [Total Transactions])

Total Transaction Value =
CALCULATE(SUM(transactions[amount]), transactions[is_valid_amount] = TRUE)

Failed Transaction Value =
CALCULATE(
    SUM(transactions[amount]),
    transactions[is_valid_amount] = TRUE,
    transactions[final_status] <> "success"
)

Recovered Transactions =
CALCULATE(COUNTROWS(transactions), transactions[final_status] = "recovered_success")

Recovered Value =
CALCULATE(
    SUM(transactions[amount]),
    transactions[is_valid_amount] = TRUE,
    transactions[final_status] = "recovered_success"
)

Recovery Rate % =
VAR EverEnteredRecovery =
    CALCULATE(
        COUNTROWS(transactions),
        transactions[final_status] IN {"recovered_success", "permanently_failed"}
    )
RETURN DIVIDE([Recovered Transactions], EverEnteredRecovery)
-- Matches sql/06_recovery_analysis.sql Q1's definition: recovered as a
-- share of transactions that ever entered the recovery process, not as
-- a share of ALL transactions (which would understate it).
```

**Potentially Recoverable Value** needs the Phase 12 classification, at
the same event-level grain `sql/10_business_impact.sql` already used
(documented in `business-impact-model.md` Section 3) — kept consistent
here rather than quietly changing methodology between SQL and Power BI.
Add three calculated columns on `transaction_events` first:

```DAX
Event Txn Amount = RELATED(transactions[amount])
Event Txn Status = RELATED(transactions[final_status])
Event Txn Valid Amount = RELATED(transactions[is_valid_amount])
Event Opportunity Category = RELATED(failure_reasons[opportunity_category])
```

Then the measure:

```DAX
Potentially Recoverable Value =
CALCULATE(
    SUMX(transaction_events, transaction_events[Event Txn Amount]),
    transaction_events[Event Txn Status] = "permanently_failed",
    transaction_events[Event Txn Valid Amount] = TRUE,
    transaction_events[Event Opportunity Category] IN
        {"Immediate Recovery Candidate", "Investigate", "Customer Intervention"}
)
-- Should return $1,264,295.11 against the full, unfiltered dataset --
-- cross-check against business-impact-model.md Section 3 after building.
```

**Top Failure Driver** (a dynamic text KPI card):

```DAX
Top Failure Driver =
VAR RankedReasons =
    TOPN(
        1,
        ADDCOLUMNS(
            VALUES(failure_reasons[reason_code]),
            "@FailCount", CALCULATE(COUNTROWS(transaction_events))
        ),
        [@FailCount], DESC
    )
RETURN CONCATENATEX(RankedReasons, failure_reasons[reason_code])
-- Should return "BALANCE_DECLINED_INSUFFICIENT_FUNDS" unfiltered
-- (03_failure_analysis.sql Q1, Pareto rank #1) -- and change correctly
-- when a page filter (e.g. a channel slicer) is applied, which a
-- hard-coded label wouldn't.
```

Page-specific measures are listed under their page below rather than
repeated here.

## 5. Page 1 — Executive Command Center

**Answers:** *"What is happening?"*

| KPI card | Measure | Format |
|---|---|---|
| Total Transactions | `[Total Transactions]` | #,##0 |
| Failure Rate | `[Failure Rate %]` | 0.00% |
| Failed Transaction Value | `[Failed Transaction Value]` | $#,##0 |
| Recovery Rate | `[Recovery Rate %]` | 0.00% |
| Potentially Recoverable Value | `[Potentially Recoverable Value]` | $#,##0 |
| Top Failure Driver | `[Top Failure Driver]` | text card |

Visuals:

- **Failure trend** — line chart, X = `transactions[initiated_at]` (Date
  hierarchy → Day), Y = `[Failure Rate %]`. Add a 7-day rolling average
  as a second line (matches `02_transaction_performance.sql` Q2) so the
  trend reads smoothed, not noisy day-to-day.
- **Failure contribution** — 100% stacked bar, one bar, segmented by
  `transactions[final_status]` (success / recovered_success /
  permanently_failed / pending) — the single-glance "where does every
  transaction end up" visual.
- **Channel performance** — clustered bar, `channels[channel_name]` on Y,
  `[Failure Rate %]` and `[Failed Transaction Value]` as two measures (dual
  axis) — deliberately shows both on one visual because
  `04_channel_analysis.sql` found rate and value exposure don't rank the
  same way (`mobile_app` lowest rate, highest value).
- **Financial exposure** — donut or stacked bar of `[Failed Transaction
  Value]` by `payment_rails[rail_owner]` (internal vs. external) — the
  BR-02 finding (~96% of failed value sits on external rails) belongs on
  page 1, it's a "what's happening" fact, not a root-cause explanation.

**Annotation** (text box, pinned near the trend chart): *"Simulated data
— Kestrel Bank is a fictional company; all figures are synthetic. See
business-case.md."* Every page should carry a version of this — Section
31's realism rule doesn't stop at the written docs.

## 6. Page 2 — Failure Intelligence

**Answers:** *"Why is it happening?"*

Visuals:

- **Failure reasons** — horizontal bar, `failure_reasons[reason_code]` by
  `COUNTROWS(transaction_events)`, sorted descending. Add a **Pareto
  line** (cumulative % — Power BI's built-in Pareto chart type handles
  this in one visual, or a combo chart with a second axis) — this is
  literally `03_failure_analysis.sql` Q1's cumulative_pct column made
  visual.
- **Failure by process stage** — bar, `transaction_events[lifecycle_stage]`
  by failure count. Add a slicer or tooltip mapping stage number to name
  (1=Initiated … 7=External Network Response) since the raw number alone
  isn't self-explanatory to a first-time viewer (Section 21's "clear
  titles, consistent terminology" rule).
- **Failure by channel** — same as Page 1's channel visual but sliced by
  `failure_reasons[failure_category]` for a channel × category cross-tab
  (matrix visual) — this is where `04_channel_analysis.sql` Q4's
  channel-weakest-link finding (payroll worst on 3 of 4 channels) lives.
- **Pareto analysis (category level)** — a second Pareto, this time by
  `failure_reasons[failure_category]` rather than individual reason —
  shows the Section 4 `root-cause-analysis.md` finding that three
  process-stage chokepoints cover 75% of failures.
- **High-impact failure categories** — a matrix: rows =
  `failure_reasons[failure_category]`, columns = COUNT and SUM(value),
  with **two separate rank columns** (volume rank, value rank) using
  `RANKX` — surfaces the Risk-category volume/value divergence
  (`business-impact-model.md`, `root-cause-analysis.md` Section 4)
  directly instead of requiring the viewer to compare two different
  visuals by eye.

```DAX
Volume Rank =
RANKX(ALL(failure_reasons[failure_category]), CALCULATE(COUNTROWS(transaction_events)), , DESC)

Value Rank =
RANKX(
    ALL(failure_reasons[failure_category]),
    CALCULATE(
        SUMX(transaction_events, transaction_events[Event Txn Amount]),
        transaction_events[Event Txn Valid Amount] = TRUE
    ),
    , DESC
)
```

## 7. Page 3 — Customer Impact

**Answers:** *"Who is affected?"*

No PII anywhere on this page — every visual aggregates by segment or uses
the synthetic `customer_id` only (never a name, email, or account
number — the dataset has none, `data-dictionary.md` Section 9, but worth
stating on the page itself as a design principle, not just an accident of
what data exists).

- **Customer segment** — bar, `customer_segments[segment_name]` by
  `[Failure Rate %]` and average transaction amount (dual axis) —
  `05_customer_analysis.sql` Q3.
- **Repeat failures** — a histogram-style bar of the failure-count
  buckets (1 / 2 / 3 / 4+) with a DAX measure bucketing on the fly:

```DAX
Repeat Failure Bucket =
VAR FailCount =
    CALCULATE(
        COUNTROWS(transactions),
        transactions[final_status] <> "success",
        ALLEXCEPT(accounts, accounts[customer_id])
    )
RETURN
    SWITCH(
        TRUE(),
        FailCount = 1, "1 failure",
        FailCount = 2, "2 failures",
        FailCount = 3, "3 failures",
        FailCount >= 4, "4+ failures",
        "No failure"
    )
```
  (Best built as a calculated column on `customers`, not a measure, since
  it needs to exist per-customer before it can be grouped and counted.)

- **Transaction behavior** — small multiples or a matrix of average
  transaction amount and transaction count by segment × transaction type.
- **Customer impact** — a card pair: distinct customers affected
  (`DISTINCTCOUNT` of `accounts[customer_id]` filtered to failed
  transactions) and that as a % of all customers — should read 5,900
  (49.2%) unfiltered, matching `05_customer_analysis.sql` Q1.
- **High-frequency failure groups** — a table capped at Top 15 by failure
  count (`05_customer_analysis.sql` Q2's own RANK-and-QUALIFY-15 logic,
  reproduced with a Top N filter on the visual) — labeled clearly as an
  internal Operations view, not something meant to leave the dashboard
  (`stakeholder-analysis.md`'s Operations Manager is the actual audience
  for this specific table).

## 8. Page 4 — Recovery Opportunities

**Answers:** *"What can we recover?"*

- **Recoverable failures** — card: `[Potentially Recoverable Value]`,
  with a subtitle breaking it into the three contributing categories
  (Investigate / Customer Intervention / Immediate Recovery residual) —
  a stacked bar works better than a single card here so the $1.09M
  Investigate share doesn't disappear into one aggregate number.
- **Recovery rate** — `[Recovery Rate %]` by `failure_reasons[reason_code]`,
  bar chart, sorted descending — this is where `RAIL_OUTAGE`'s
  reclassification story (Phase 12) becomes visible: it's a
  `Do Not Retry-Monitor`-tagged reason sitting at the top of an
  auto-retry-style recovery rate, immediately visually odd in a useful
  way that invites the annotation below.
- **Retry effectiveness** — line or bar, `recovery_attempts[attempt_number]`
  by success rate — `06_recovery_analysis.sql` Q2's attempt curve
  (75.4% → 79.1% → 90.7%).
- **Recovery by failure category** — matrix, `failure_reasons[failure_category]`
  rows, recovery rate + attempt count columns.
- **Recovery opportunity matrix** — this is the one visual on this page
  that's a table, not a chart, deliberately: reproduce
  `recovery-intelligence.md` Section 2's matrix (category / criteria /
  action / owner / KPI) as a formatted table visual or, if Power BI's
  table formatting can't hold that much text cleanly, as an embedded
  image export of the matrix from the markdown doc. Either way it needs
  to be on this page — a chart can't carry "recommended action" and
  "owner" columns meaningfully.

**Annotation:** callout on the `RAIL_OUTAGE` bar: *"Reclassified from its
original design-time track based on observed data — see
recovery-intelligence.md Section 3."* — this is exactly the kind of
"annotation for an important finding" Section 21 asks for, and it's a
genuinely interesting one to have ready to explain live in an interview.

## 9. Page 5 — Decision Simulator

**Answers:** *"What should we do?"*

This is the one page that uses `dashboard/scenario_simulator.csv` instead
of the transaction data, via a **Power BI What-If Parameter** — the
standard mechanism for a page like this, and worth knowing well since
it's a distinctive, interview-worthy DAX/modeling feature (not every
candidate's dashboard will have used one).

**Setup:**

1. Modeling ribbon → New Parameter → "Scenario Selector" → Data type:
   Text (or use "Fields" parameter type pointing at
   `scenario_simulator[scenario_name]`, which is simpler here since the 5
   values are literal rows in an existing table, not a numeric range).
2. This creates a disconnected table + a slicer visual automatically —
   place that slicer prominently at the top of the page.
3. Build the KPI cards below using a measure that reads the *selected*
   scenario's value from `scenario_simulator`, not the live transaction
   data:

```DAX
Selected Scenario Value =
CALCULATE(
    SUM(scenario_simulator[value_recovered_or_avoided_usd]),
    scenario_simulator[scenario_name] = SELECTEDVALUE('Scenario Selector'[Scenario Selector])
)

Selected Scenario Units =
CALCULATE(
    SUM(scenario_simulator[units_affected]),
    scenario_simulator[scenario_name] = SELECTEDVALUE('Scenario Selector'[Scenario Selector])
)

Selected Scenario Confidence =
CALCULATE(
    SELECTEDVALUE(scenario_simulator[confidence]),
    scenario_simulator[scenario_name] = SELECTEDVALUE('Scenario Selector'[Scenario Selector])
)
```

Visuals:

- **Scenario selector slicer** (from setup above) — front and center.
- **KPI cards**: `[Selected Scenario Value]`, `[Selected Scenario Units]`,
  `[Selected Scenario Confidence]` — update live as the slicer changes.
- **Comparison bar chart**: all 5 scenarios side by side, reading
  `scenario_simulator` directly (not through the parameter) so all 5 are
  always visible regardless of what's selected in the slicer above —
  gives the "current state vs. every alternative" comparison the brief
  asks for in one glance.
- **Description text card**: `SELECTEDVALUE(scenario_simulator[description])`
  filtered the same way as the KPI measures — so the page also explains
  *what* the selected scenario assumes, not just its number.

**Annotation:** *"Every figure on this page is a stated scenario
assumption, not a guaranteed outcome — see whatif-simulation.md for the
full reasoning behind each rate."* This page is the one most likely to
get over-read by a viewer as "the plan" rather than "a model" — the
annotation exists specifically to prevent that misread, consistent with
Section 18/19's labeling discipline carried all the way through to the
dashboard.

## 10. UX principles checklist (Section 21)

| Principle | How this spec satisfies it |
|---|---|
| Understandable to a first-time viewer | Every page opens with its one-line business question as a page subtitle |
| Not overloaded | 5-6 visuals per page max, never a "everything on one page" layout |
| Every visual answers a business question | Each visual above is tied to a specific analytical question from Phases 10-14 |
| Clear titles / descriptive subtitles | Use the exact business-question phrasing from `sql/query-results.md`, not generic chart titles like "Chart 1" |
| Consistent terminology | `final_status` values, category names, and track names used identically across every page — never renamed page to page |
| Filters | A global slicer panel (channel, transaction type, date range) on Pages 1-4; the What-If Parameter is Page 5's dedicated filter |
| Drill-down | Failure trend (Page 1) and failure-by-stage (Page 2) both use Power BI's built-in date/category drill hierarchy |
| Tooltips | Custom tooltip pages showing the underlying SQL business question text for each major visual (a nice touch: literally surfacing "Business Question → SQL Logic" from `query-results.md` on hover) |
| KPI cards | Pages 1, 4, 5 each lead with cards, not charts |
| Annotations for important findings | RAIL_OUTAGE reclassification (Page 4), stress-window/day-55 findings (Page 2, via a text box referencing `root-cause-analysis.md` Sections 7-8), the simulated-data disclaimer (every page) |

## 11. Build order (a realistic sequence, not "build everything at once")

1. Import all files, fix data types (Section 2).
2. Build the model and relationships (Section 3) — verify with a quick
   test visual (e.g., Total Transactions by channel) before writing any
   DAX.
3. Write the core measures (Section 4) one at a time, checking each
   against the known value from `sql/query-results.md` as you go — e.g.,
   `[Failure Rate %]` should read 5.93% unfiltered. A measure that
   doesn't match a number this project already validated in SQL is a
   modeling bug to fix before moving on, not a discrepancy to shrug off.
4. Build Page 1 first (it uses only the core measures).
5. Build Pages 2-4 (mostly reuse Page 1's measures plus a few new ones).
6. Build Page 5 last (the What-If Parameter is the one genuinely new
   mechanic).
7. Add annotations and verify every visual title matches its business
   question.

## 12. What this produces for the portfolio

The `.pbix` itself stays on your machine (Power BI files aren't something
you'd commit raw to GitHub anyway — they're binary and get huge fast).
What belongs in the project repo and the eventual case study (Phase 17)
is: 4-5 clean screenshots (one per page) and, ideally, a short screen
recording of Page 5's What-If slicer actually changing the numbers live —
that's the single most convincing 15 seconds of proof that this was
really built and isn't just static images.
