# Stakeholder Analysis: Transaction Failure Intelligence & Recovery Optimization

**Phase:** 2 of 20 — Stakeholder Analysis
**Depends on:** [business-case.md](./business-case.md)

---

## 1. Purpose

Before requirements can be gathered (Phase 3), we need to know whose questions this project has to answer, who has the authority to act on its findings, and who is affected but has no seat at the table. Getting this wrong is exactly the kind of gap the Synapse–Evolve case (business-case.md, Section 1) exposed: no single stakeholder group owned "is this transaction recoverable, and who decides." This analysis assigns that ownership explicitly.

---

## 2. Stakeholder Register

| Stakeholder | Interest | Responsibility | Pain Point | Information Needed | Influence |
|---|---|---|---|---|---|
| **VP, Digital Operations** (Project Sponsor) | Wants transaction reliability to stop being a reactive, ticket-driven problem and become a managed one | Owns the P&L impact of operational issues in digital channels; sponsors and funds this initiative | Cannot currently tell the executive team how big the failure problem is or what it's costing | A defensible baseline, a prioritized action list, and a way to track progress over time | High |
| **Operations Manager, Payments** | Wants a systematic way to triage failures instead of responding ticket-by-ticket | Runs day-to-day monitoring of the payment gateway and coordinates retries/escalations today | Currently reacts to alerts with no way to tell a high-impact failure from a low-impact one | Failure volume and severity by category, in near-real time, with clear ownership per category | High |
| **Product Manager, Payments & Transfers** | Wants to know which product changes (e.g., building an auto-retry flow, adding a "transaction status" screen) would move the needle | Owns the roadmap for transfer/payment features and the customer-facing failure experience | Has no data to justify prioritizing failure-reduction work over new features on a competitive roadmap | Which failure categories are recoverable, how large the affected customer base is, and expected impact of fixes | High |
| **Engineering Lead, Payments Platform** | Wants root causes that are specific enough to actually fix, not "payments are flaky" | Owns the microservices in the transaction lifecycle (auth, validation, risk screening, ledger, rail gateway) | Gets paged on symptoms (elevated decline rate) without a way to see which stage or which upstream dependency is responsible | Failure breakdown by lifecycle stage and by internal vs. external (rail) cause | High |
| **Risk & Fraud Team Lead** | Wants confidence that any automated retry or recovery action doesn't reopen fraud exposure | Owns the risk/fraud screening step in the transaction lifecycle and approves recovery-automation policy | Is a probable source of some declines being investigated as "unexplained failures" when they are in fact risk holds | Which failures originate from risk screening, and confirmation that recovery recommendations won't bypass risk controls | Medium |
| **Customer Support Operations Lead** | Wants fewer repeat contacts about the same unresolved failure | Handles the customer-facing fallout of failed transactions and logs the contact volume this project depends on as a signal | Cannot distinguish a one-off failure from a pattern until many customers have already called in | Which failure categories are driving repeat contacts, so Support can get ahead of them instead of reacting | Medium |
| **Finance / FP&A** | Wants failed-transaction exposure quantified in dollars, not just transaction counts | Tracks interchange and fee revenue; would fund any recovery-automation build with an ROI case | Cannot currently size how much revenue is at risk or recoverable from failures | Financial exposure and recoverable value by failure category (Phase 18, Business Impact) | Medium |
| **Compliance / Legal** | Wants any customer communication or automated action (e.g., an auto-retry that debits an account again) to meet regulatory obligations | Reviews recovery and communication policies for regulatory risk (e.g., unauthorized re-attempt rules, fair and consistent treatment across customer segments) | Was not consulted on ad hoc recovery decisions in the past — a specific exposure the Synapse–Evolve fallout demonstrated can escalate into a regulatory issue | Which recovery actions are proposed, and evidence they are applied consistently across customer segments | Medium |
| **Senior Management (COO / CEO)** | Wants a single, trustworthy view of whether the business is managing this risk, without needing an analyst to interpret it | Approves budget and roadmap priority for whatever this project recommends | Only sees this issue when it is already a headline-risk-sized problem, not while it is still manageable | An executive dashboard: current state, financial exposure, and a recommended action, in one view | High |
| **Retail Customers** | Wants transactions to work, and if one fails, wants to know why and whether the money is safe | Not a project participant — the party the entire initiative exists to protect | Experiences failed transactions as ambiguous and anxiety-inducing ("where is my money?") | Not a data consumer of this project directly, but their behavior (repeat failures, complaint volume) is a primary input | Low (no direct influence over the project, but the reason it exists) |
| **Small-Business Customers** | Wants failed payroll or vendor payments to be rare and, when they happen, resolved fast | Not a project participant — a customer segment with disproportionately high per-failure impact | A failed payroll run has consequences (late employee pay) well beyond a failed retail P2P transfer | Same as retail customers, but this segment justifies weighting business-impact severity by transaction type, not just volume | Low (no direct influence, but the segment most likely to justify prioritizing a fix) |

---

## 3. Stakeholder Map

**Primary stakeholders** (directly involved in defining requirements, making decisions, or acting on this project's output):
VP Digital Operations, Operations Manager, Product Manager, Engineering Lead, Customer Support Operations Lead, Senior Management.

**Secondary stakeholders** (consulted, provide constraints or context, but do not drive the project's day-to-day direction):
Risk & Fraud Team Lead, Finance/FP&A, Compliance/Legal.

**Decision makers** (can approve scope, fund a recommendation, or block an action):
Senior Management (COO/CEO) — funds and prioritizes; VP Digital Operations — sponsors and scopes; Risk & Fraud Team Lead and Compliance/Legal — hold veto power specifically over any *automated* recovery action, regardless of its projected financial benefit.

**Affected users** (impacted by the outcome, not involved in producing it):
Retail customers, small-business customers, and — indirectly — Customer Support agents who handle the resulting contact volume.

### Power / Interest Grid

| | **Low Interest** | **High Interest** |
|---|---|---|
| **High Power** | Compliance/Legal, Finance/FP&A — *keep satisfied*: they don't drive priorities day-to-day, but a change they haven't cleared can stop a recommendation cold | VP Digital Operations, Senior Management, Operations Manager, Engineering Lead — *manage closely*: primary audience for the dashboard and recommendations |
| **Low Power** | Retail and small-business customers — *monitor via their behavior* (repeat failures, complaints), not via direct consultation | Product Manager, Customer Support Operations Lead, Risk & Fraud Team Lead — *keep informed*: they feel the problem daily and are natural early reviewers of findings before they reach Senior Management |

---

## 4. Implications for Phase 3 (Requirements)

- Because **Risk & Fraud** and **Compliance** hold veto power over automated actions (not just influence), the requirements phase needs explicit non-functional requirements around auditability and consistency of any recovery/retry logic — not just performance requirements.
- Because **Finance** needs dollar exposure and **Engineering** needs lifecycle-stage attribution, the data requirements (Phase 3) must support both a financial rollup and a technical/process rollup from the same underlying event data — one dataset, two lenses.
- Because **Senior Management**'s stated need is a single dashboard view, reporting requirements should treat the Executive Command Center (Phase 15, dashboard) as a first-class requirement, not an afterthought bolted onto the SQL analysis.
- Because customers are "affected but low power," their needs enter the project only through **proxy signals** — repeat-failure rate and (implicitly) support contact volume — a deliberate scope decision to record now, since it explains why the dataset (Phase 8) needs a customer-level repeat-failure field rather than only transaction-level fields.

---

## Open Items for Stakeholder Review

- Confirm the register captures the right roles — in particular, whether a fictional "Marketing/Communications" stakeholder should be added for customer-facing failure notifications (Scenario C in Phase 19, What-If Simulation, assumes someone owns that channel).
- Confirm Risk & Fraud and Compliance are correctly scoped as veto-holders rather than merely consulted — this decision shapes the Non-Functional Requirements in Phase 3.
- Confirm the Power/Interest grid placement of Finance (currently "keep satisfied," not "manage closely") matches how tightly this project should track financial sign-off.
