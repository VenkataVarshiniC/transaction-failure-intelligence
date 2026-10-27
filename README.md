# Bank Transaction Failure Intelligence

*End-to-end Business Analyst / Data Analyst portfolio project — a
simulated digital bank's transaction-failure and recovery problem, worked
from business case through SQL analysis, root-cause investigation,
financial impact modeling, scenario simulation, and a Power BI dashboard
design. Every figure in this document is either directly observed from
the dataset or explicitly labeled as an estimate or scenario assumption
— none is invented, and no part of this data or these figures represents
a real bank, real customers, or real financial results.*

## Executive Summary

Kestrel Bank, a fictional digital-only retail and small-business bank,
loses roughly 1 in 17 transactions to failure — 5.93% of 180,000 simulated
transactions over a 90-day window, representing $2.60M in failed value
(6.83% of total transaction value). About 40% of that ever gets recovered
today (39.79%, observed). This project builds the analytical case for
where the rest of it is going, why, and what to do about it: a
transaction-lifecycle data model purpose-built to trace failures to a
specific stage and cause, 36 SQL-driven business questions answered
against the real dataset, a data-driven Recovery Opportunity Engine that
overturns one of its own design-time assumptions with evidence, a
financial impact model that finds 73.6% of all failed value concentrated
in just 21.6% of customers, and a 9-item recommendation roadmap led by
one config change and one policy review that together account for the
two highest-leverage moves in the whole analysis.

## Business Problem

Kestrel Bank has no systematic way to answer *why* transactions fail,
*where* in the pipeline they fail, *which* failures are worth recovering,
or *how much* money is at stake. Operations reacts to failures
ticket-by-ticket with no way to distinguish a high-impact failure from a
low-impact one; Engineering gets paged on symptoms without a way to trace
them to a specific stage or root cause; Finance has no defensible number
for what failure actually costs the business. This mirrors real
incidents in the digital banking space — the 2024 Synapse-Evolve
middleware/ledger collapse (~200K frozen accounts) and recurring
volume-driven UPI/NPCI outages — used here as inspiration for a realistic
failure pattern, not as a source of real data (`business-analysis/business-case.md`
Section 1).

## Business Objective

Build a repeatable analytical capability to measure transaction failure
and recovery performance, identify root causes, quantify financial
exposure, and prioritize remediation — not a one-time report.
`business-case.md` frames this as one measurement objective (establish
the baseline this document reports) plus four directional objectives
whose specific targets are set in this project's KPI Framework
(`recommendations/business-recommendations.md` Section 3), not asserted
upfront before any data existed to ground them.

## Stakeholders

Eleven stakeholders were mapped by interest, influence, and information
need (`business-analysis/stakeholder-analysis.md`), from the VP of
Digital Operations (project sponsor) through Risk & Fraud, Compliance,
Engineering, Product, Support, Finance, and the retail and small-business
customer segments themselves. Two design decisions came directly from
this analysis: Risk & Fraud and Compliance were given explicit veto power
over any automated recovery action (a lesson pulled straight from the
Synapse-Evolve fallout), and the small-business segment was flagged early
as disproportionately affected per failure — a prediction this project's
data later confirmed (see Key Findings).

## Current-State Process

A 10-stage transaction lifecycle was mapped end to end — Initiation,
Authentication, Validation, Risk Screening, Balance/Account Validation,
Processing & Rail Submission, External Network Response, Outcome
Determination, Retry/Recovery, Final Outcome
(`business-analysis/process-analysis.md`) — with every stage's potential
failure points, owners, and business impact documented before a single
row of data was generated. This process map is what makes the dataset's
`lifecycle_stage` field meaningful rather than arbitrary, and it's the
backbone every later phase's "which stage is this failure coming from"
analysis traces back to.

## Data Architecture

Rather than a flat transactions table, the data model is event-sourced: a
`TRANSACTION` header plus an append-only `TRANSACTION_EVENT` log (one row
per lifecycle-stage transition), with `FAILURE_REASON` and
`RECOVERY_ATTEMPT` as first-class entities carrying their own category,
origin (internal/external), and recovery-track taxonomy
(`business-analysis/data-architecture.md`). Nine entities in total,
documented field-by-field in `data/data-dictionary.md`. This shape is
what makes questions like "which specific lifecycle stage generates the
most failures" or "how many recovery attempts did this transaction go
through before it resolved" directly queryable instead of requiring
after-the-fact reconstruction.

A real Kaggle search was run before any synthetic data was generated
(PaySim, Bank Transaction Fraud Detection, and UPI datasets were
evaluated) — none had the failure/lifecycle/recovery structure this
project needed, only completed-transaction fraud labels. PaySim's
publicly documented structural characteristics (transaction-type risk
concentration, right-skewed amounts) were used to calibrate the
generator instead (`data/dataset-design.md` Section 1) — the raw Kaggle
file itself was not accessible from this project's build environment, so
calibration against documented characteristics, not literal reuse, is
what "PaySim-informed" means throughout this project.

The result: **180,000 transactions across 12,000 customers over a 90-day
window** (seed 42, fully reproducible), with five deliberately-designed,
non-random patterns baked in — channel/type failure correlation, a 4%
"problem cohort" of repeat-failure customers, three UPI-inspired stress
days on the RTP rail, and a mid-window internal engineering fix — plus
12 categories of realistic data-quality issues (duplicates, invalid
amounts, bad timestamps, orphaned references) injected and then detected,
documented, and cleaned with a "flag, don't silently drop" philosophy
(`data/data-quality-report.md`): every questionable row is either
quarantined with a stated reason or kept with a boolean quality flag,
never quietly removed.

## Analytical Approach

**36 SQL business questions** across 10 files (`sql/`), every one
answered with real DuckDB query output captured verbatim into
`sql/query-results.md` — no hand-typed numbers anywhere in this project.
The approach moved through five layers, each building on the last:

1. **Data quality reconciliation** — confirming raw = clean + quarantined
   for every table before trusting any downstream number.
2. **Descriptive analysis** — performance trends, channel and customer
   cuts, a Pareto breakdown of failure reasons.
3. **Root-cause analysis** (`analysis/root-cause-analysis.md`) — six
   analytical lenses (Pareto, process-stage, category/origin, channel,
   temporal, customer-level) applied to every one of the 13 failure
   reasons, including one deliberately-kept honest negative finding: an
   hour-of-day cut found no stress-window signal at all (0.72% vs.
   0.69%), and only a day-level cut correctly surfaced the real ~3x
   elevation on the three designed stress days — evidence that query
   design, not just data quality, determines whether a real pattern gets
   found.
4. **A data-driven Recovery Opportunity Engine** (`analysis/recovery-intelligence.md`)
   — classifying every failure reason by *observed* recovery rate rather
   than trusting the design-time assumption made before any data existed.
5. **Financial impact and scenario modeling**
   (`analysis/business-impact-model.md`, `analysis/whatif-simulation.md`)
   — Observed, Estimated, and Scenario-assumption figures kept visibly
   separate throughout, per this project's one non-negotiable rule: never
   present an assumption as a fact.

## Key Findings

Ten insights were developed (full detail with evidence and
recommendations in `recommendations/business-recommendations.md` Section
1); the five with the most business consequence:

- **A small cohort drives most of the dollar problem.** 21.6% of
  customers (2,587 people) who fail more than once account for **73.6%**
  of all failed transaction value ($1.91M of $2.60M). A uniform fix
  leaves most of the dollar problem untouched.
- **Most of the failure problem is Kestrel's own.** ~78% of failure
  events are internal-origin (Process, Technology, Risk, Policy); only
  ~22% originate with external rails or issuers.
- **Volume and financial impact don't always agree.** The `Risk` failure
  category ranks 4th by event count but **1st** by dollar value
  ($725,635) — a plain frequency chart would have under-ranked the
  single largest exposure in the dataset.
- **Evidence overturned a design-time assumption.** `RAIL_OUTAGE` was
  tagged "monitor manually" before any data existed; its observed
  recovery rate turned out to be **91.76%** — the highest of any reason
  — and the Recovery Opportunity Engine reclassified it to
  auto-retry-eligible on that evidence.
- **An internal fix already worked, once, for real.** `PROCESSING_ERROR`'s
  per-day rate dropped **65.4%** (4.48 → 1.55) after an internal fix
  landed mid-window — not a projection, an observed before/after result,
  and the benchmark this project's scenario modeling later extends to a
  second, structurally similar defect.

## Business Impact

All figures **simulated**; tiers kept explicit throughout.

| Tier | Metric | Figure |
|---|---|---|
| Observed | Failed transaction value | $2,603,613.29 (6.83% of total) |
| Observed | Recovered value | $916,896.23 |
| Observed | Customers affected | 5,900 of 12,000 (49.2%) |
| Estimated | Additional recovery if `RISK_HELD` reached this dataset's own proven 90.32% benchmark rate | ~$451,243 |
| Estimated | Potentially recoverable value (pool where a mechanism is plausible) | $1,264,295.11 |
| Scenario | Combined strategy (Auto-Retry + Customer Intervention + Engineering, moderate case) | ~$262,637 |

## Recommendations

Nine recommendations across Immediate (0-30 days), Short-Term (1-3
months), and Medium-Term (3-6 months) horizons, each with an owner,
effort estimate, expected impact, risk, and KPI
(`recommendations/business-recommendations.md` Section 2). The two
highest-priority actions, per the project's Impact vs. Effort matrix:

1. **Reclassify `RAIL_OUTAGE` to auto-retry-eligible** — a configuration
   change, not a build, that immediately puts its proven 91.76% recovery
   rate into production.
2. **Review the `RISK_HELD` clearance threshold and SLA with Risk &
   Fraud** — the single largest dollar lever in the project (~$451K
   estimated), requiring Compliance sign-off given the fraud-control
   stakes, not a fast unilateral change.

## Future-State Process

A Failure Intelligence & Recovery Orchestration layer
(`business-analysis/future-state.md`) routes every failure into one of
four tracks — Auto-Retry Eligible, Customer Intervention, Engineering Fix
Required, Do Not Retry/Monitor — based on the same classification logic
the Recovery Opportunity Engine (Phase 12) later validated against real
data. Designed in Phase 5, before any dataset existed, and confirmed
rather than contradicted by everything analyzed afterward.

## Dashboard

A 5-page Power BI dashboard was designed in full
(`dashboard/dashboard-design.md`) — Executive Command Center, Failure
Intelligence, Customer Impact, Recovery Opportunities, and a Decision
Simulator built on a real Power BI What-If Parameter — with every KPI
card's DAX measure, the full data model and relationships, and a
page-by-page visual spec. The design is complete; the `.pbix` itself is a
manual Power BI Desktop build from that spec (deliberately not built by
an AI tool — see the spec's Section 1 for why that matters for this
project specifically). Screenshots will be added to `screenshots/` once
built.

## Financial Operations Extension

The `codex/financial-operations-platform` extension adds a versioned cost
model, recovery economics, held-out forecasting, budget variance, and an
import-ready six-page Power BI financial dashboard package. Failed or
recovered transaction face value is reported as exposure/throughput and is
never treated as loss, revenue, or savings.

The v1.0 modeled baseline is **$137,142.45 of 90-day OpEx** ($0.7619 per
transaction). Twelve DuckDB management views and six reconciliation controls
feed `data/reporting/`. The four-intervention combined case processes a
modeled $512,437.23 of additional principal but produces **-$98,263.47** of
direct 90-day net benefit after fee revenue, avoided costs, servicing,
recurring costs, and implementation costs. This is a planning result, not a
realized saving.

See `docs/BASELINE_AUDIT_AND_PLAN.md`,
`docs/FINANCIAL_OPERATIONS_MODEL.md`, and
`docs/EXECUTIVE_FINANCIAL_REPORT.md`. Power BI Desktop was not available in
the build environment; `dashboard/FINANCIAL_DASHBOARD_BUILD_GUIDE.md` and
`dashboard/financial-dashboard-measures.dax` provide the reproducible build
package, but no `.pbix` is claimed.

## Technology

Python (numpy, pandas) for synthetic data generation and cleaning;
DuckDB for SQL analysis; Power BI for visualization; Markdown for every
business-analysis and analytical deliverable, kept in a structured Git
repository throughout.

## Assumptions & Limitations

Stated plainly rather than smoothed over, consistent with this project's
approach throughout:

- **Synthetic data.** No real bank, customer, or transaction data exists
  anywhere in this project. All financial figures are simulated.
- **PaySim calibration, not reuse.** Kaggle's raw data could not be
  downloaded from this project's build environment; PaySim's
  *documented* structural characteristics were used as a calibration
  reference instead (`data/dataset-design.md` Section 1).
- **An empty `People` failure category.** The taxonomy includes a
  `People` category with zero reasons tagged to it — a stated scope
  boundary (this model covers system/policy declines, not frontline
  staff error), not an oversight patched over.
- **A real instrumentation gap, left visible.** `RAIL_DECLINED_ISSUER`
  carries $366,742 in value with zero logged recovery attempts, despite
  sharing a track designation with two well-instrumented reasons. No
  recovery rate is claimed for it — it's documented as "not observed,"
  never given an invented figure.
- **Scenario figures are not predictions.** Every number in
  `analysis/whatif-simulation.md` and every KPI target in
  `recommendations/business-recommendations.md` is a stated planning
  assumption, explicitly labeled, never presented as something the data
  proves will happen.

## Results

The baseline this project set out to establish now exists: a 5.93%
failure rate, $2.60M in failed value, a 39.79% recovery rate, and — the
result most likely to change what Kestrel actually does next — evidence
that the highest-leverage opportunity isn't spread evenly across the
failure taxonomy. It's concentrated in one customer cohort (73.6% of
value from 21.6% of customers), one mis-tagged reason a config change
already fixes, and one policy review worth roughly $451K on its own. A
Business Analyst reading this project end to end should come away with
not just "what's broken" but a ranked, resourced, risk-labeled plan for
what to do about it — which is the actual deliverable a stakeholder like
the VP of Digital Operations asked for in Phase 1.

## Future Enhancements

- Close the `RAIL_DECLINED_ISSUER` instrumentation gap and re-run the
  Recovery Opportunity Engine with real data instead of a materiality-only
  classification for that reason.
- Pilot Recommendation R4 (the `RISK_HELD` threshold review) and feed the
  real post-pilot recovery rate back into the KPI Framework's baseline —
  this project's $451K estimate should get replaced by an observed figure
  as soon as one exists.
- Build the Power BI `.pbix` from the Phase 15 spec and capture the
  screenshots and a short Decision Simulator recording this README
  currently only describes.
- Extend the event-sourced data model with a real `support_tickets`
  entity — this project's "support workload proxy" metrics
  (`analysis/business-impact-model.md` Section 2) are explicitly labeled
  proxies specifically because that entity doesn't exist yet.
- A/B test the proactive low-balance nudge (Recommendation R6) once
  built, to replace its scenario-assumption lift (+10pp) with an observed
  one.

---

*Setup and repository navigation: see [`SETUP.md`](SETUP.md). Full phase
docs: [`business-analysis/`](business-analysis/), [`data/`](data/),
[`sql/`](sql/), [`analysis/`](analysis/), [`dashboard/`](dashboard/),
[`recommendations/`](recommendations/).*
