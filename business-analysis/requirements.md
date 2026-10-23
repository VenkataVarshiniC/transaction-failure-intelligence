# Requirements: Transaction Failure Intelligence & Recovery Optimization

**Phase:** 3 of 20 — Requirements
**Depends on:** [business-case.md](./business-case.md), [stakeholder-analysis.md](./stakeholder-analysis.md)

---

## 1. Purpose

This document translates the business objectives (business-case.md, Section 4) and stakeholder needs (stakeholder-analysis.md, Section 2) into requirements the rest of the project is built against. Every functional and non-functional requirement below traces back to a business requirement, and every business requirement traces back to a named stakeholder need — not to "things that would be interesting to build." The Requirements Traceability Matrix (Section 6) makes that chain explicit.

---

## 2. Business Requirements

| ID | Requirement | Source |
|---|---|---|
| BR-01 | The organization must be able to measure transaction failure rate and recovery rate on a recurring basis, segmented by channel, transaction type, and time period | Business Objective O1; VP Digital Operations, Operations Manager |
| BR-02 | The organization must be able to distinguish failures it can control (technical/process) from failures caused by external payment-rail dependencies it cannot control | Business Objective O2; Engineering Lead — mirrors the internal-vs-rail ambiguity in the Synapse–Evolve precedent |
| BR-03 | The organization must be able to identify which failed transactions are recoverable and prioritize recovery actions accordingly | Business Objective O3; Operations Manager, Product Manager |
| BR-04 | The organization must be able to identify customers and segments experiencing repeated failures | Business Objective O4; Customer Support Operations Lead |
| BR-05 | The organization must have a standing, transparent, quantified framework for prioritizing which failure categories to fund, replacing ad hoc response | Business Objective O5; Senior Management |
| BR-06 | Any recommended automated recovery or retry action must be auditable and subject to Risk/Fraud and Compliance review before it could be considered for deployment | Stakeholder veto power (stakeholder-analysis.md, Section 3) |
| BR-07 | Financial exposure and potentially recoverable value from failed transactions must be quantifiable in dollar terms, with observed figures kept clearly distinct from estimates | Finance/FP&A; business-case.md Success Criteria #5 |

---

## 3. Functional Requirements

| ID | Requirement | Derived From |
|---|---|---|
| FR-01 | Calculate overall transaction failure rate and success rate, and break it down by channel, transaction type, and time period | BR-01 |
| FR-02 | Classify every failed transaction event by failure reason and by the transaction-lifecycle stage at which it failed | BR-01, BR-02 |
| FR-03 | Tag each failure reason as internally addressable or externally (rail-)dependent | BR-02 |
| FR-04 | Track retry/recovery attempts linked to an original failed transaction, and compute a recovery rate by failure category | BR-03 |
| FR-05 | Identify customers with more than one failure within a defined rolling window and compute a repeat-failure rate by segment | BR-04 |
| FR-06 | Calculate failed-transaction value and estimate a recoverable-value figure per failure category, keeping observed and estimated figures visibly separate | BR-07 |
| FR-07 | Produce a documented, weighted priority score per failure category from frequency, financial impact, recoverability, customer impact, and operational burden | BR-05 |
| FR-08 | Classify each failure category into a Recovery Opportunity type (Immediate Recovery Candidate, Investigate, Customer Intervention, Do Not Retry, Engineering Fix) | BR-03, BR-05 |
| FR-09 | Model and compare "what-if" scenarios (no action, automated retry, customer intervention, engineering fix, combined) against the observed baseline | BR-05, BR-07 |
| FR-10 | Present findings through a management-facing dashboard structured so each page answers one stated business question (what's happening / why / who's affected / what's recoverable / what should we do) | BR-01–BR-05 |
| FR-11 | Log the criteria and score behind every priority ranking and every Recovery Opportunity classification so a reviewer can see why a category was ranked or classified as it was | BR-06 |

---

## 4. Non-Functional Requirements

| ID | Category | Requirement | Rationale |
|---|---|---|---|
| NFR-01 | Performance | Dashboard interactions (filtering, drilling down) should feel interactive against the full dataset (target: sub-5-second response at the 100K–250K record scale used in this project) | Senior Management's stated need is a self-serve view, not an analyst-mediated one (stakeholder-analysis.md) |
| NFR-02 | Reliability | The analysis pipeline (dataset → SQL → dashboard) must be reproducible: re-running it against the same data produces the same KPI values every time | Numbers that shift between runs would undermine the "defensible baseline" required by BR-01 and Success Criteria #1 |
| NFR-03 | Scalability | The data model and SQL logic must be designed so they would extend to full production transaction volume without redesign, even though this project analyzes a 100K–250K record sample | business-case.md Section 5 scope note; avoids a design that only works at toy scale |
| NFR-04 | Security / Privacy | No real customer, account, or transaction data is used anywhere in the project; any customer-level views (e.g., the Customer Impact dashboard page) show only aggregated or de-identified synthetic segments, never individual synthetic identities in a way that would model poor disclosure practice | business-case.md Key Assumptions; mirrors real banking privacy obligations even though the data is fictional |
| NFR-05 | Auditability | Every priority score (FR-07) and Recovery Opportunity classification (FR-08) must be traceable to a documented formula or rule, never an unexplained output | BR-06; Risk/Fraud and Compliance hold veto power and will not accept a black-box score |
| NFR-06 | Consistency / Fairness | Recovery and intervention logic must apply the same rule set across customer segments; any segment-specific treatment must be an explicit, documented business rule, not an emergent artifact of the analysis | Compliance requirement (stakeholder-analysis.md, Section 2) |

---

## 5. Reporting Requirements

Management (Senior Management, VP Digital Operations, Operations Manager) needs to see, without analyst support:
- Current failure rate, recovery rate, and financial exposure, at a glance (Executive Command Center)
- Why failures are happening — top failure reasons, lifecycle stage, channel concentration (Failure Intelligence)
- Who is affected — customer segments and repeat-failure patterns, without exposing individual customer data (Customer Impact)
- What can realistically be recovered, and by which mechanism (Recovery Opportunities)
- What action is recommended, and what it's projected to be worth versus doing nothing (Decision Simulator)

Each of these becomes one dashboard page in Phase 15; this requirement is recorded now so the dashboard is treated as a first-class deliverable the SQL analysis is built to support, not an afterthought.

---

## 6. Data Requirements

| Business Question | Data Needed |
|---|---|
| What is the failure rate, and how does it trend? | Transaction record with status, timestamp, channel, transaction type |
| Where in the process do transactions fail? | A lifecycle-event record per transaction (not just a final status) — initiated, processing, failed, retried, recovered/permanently failed |
| Why do transactions fail? | A failure-reason code and category (technical, risk/fraud, customer-input, external-rail) attached to each failure event |
| Is a failure recoverable? | Retry/recovery attempt records linked to the originating transaction, with their own outcome |
| Who is affected, and how often? | Customer identifier (synthetic), customer segment, and a derivable repeat-failure count — without exposing individually identifying detail on the dashboard |
| What is the financial exposure? | Transaction amount, aggregated by failure category and channel |
| Which failures carry elevated risk considerations? | A risk-level or risk-indicator flag on the transaction or customer |

This table is intentionally business-question-first rather than table-first — the full entity-relationship design (Customers, Accounts, Transactions, Transaction Events, Failure Reasons, Channels, Recovery Attempts, Customer Segments, Risk Indicators) is Phase 6's job. Listing the data needs here first means Phase 6 can be checked against this list rather than the other way around.

---

## 7. Requirements Traceability Matrix

| Req ID | Requirement | Stakeholder | Data Needed | Analysis | Output | Status |
|---|---|---|---|---|---|---|
| BR-01 / FR-01 | Measure failure rate by channel, type, time | VP Digital Ops, Operations Manager | Transaction records | Phase 10, SQL — Transaction Performance | Dashboard: Executive Command Center | Draft |
| BR-02 / FR-02, FR-03 | Classify failures by reason, stage, and internal-vs-external | Engineering Lead | Transaction event + failure-reason records | Phase 11, Root-Cause Analysis | Dashboard: Failure Intelligence | Draft |
| BR-03 / FR-04, FR-08 | Determine recoverability and classify recovery opportunity | Operations Manager, Product Manager | Retry/recovery event records | Phase 12, Recovery Intelligence | Dashboard: Recovery Opportunities | Draft |
| BR-04 / FR-05 | Identify repeat-failure customers and segments | Customer Support Ops Lead | Customer + segment + repeat-failure derived field | Phase 11 / Phase 13 | Dashboard: Customer Impact | Draft |
| BR-05 / FR-07 | Produce a documented priority score per failure category | Senior Management | Volume, financial, recoverability, customer-impact, operational-burden metrics (rolled up from other analyses) | Phase 11, Prioritization | Priority Score table + writeup | Draft |
| BR-06 / FR-11 | Make every score/classification auditable | Risk & Fraud, Compliance | Documented scoring formula and rule set | Phase 11 / Phase 12 | recommendations/findings.md methodology section | Draft |
| BR-07 / FR-06 | Quantify financial exposure and recoverable value, observed vs. estimated | Finance/FP&A | Transaction amounts by category | Phase 13, Business Impact | Dashboard: Executive Command Center + Business Impact section | Draft |
| BR-05, BR-07 / FR-09 | Model and compare intervention scenarios | Senior Management, VP Digital Ops | Baseline metrics + scenario assumptions (labeled) | Phase 14, Scenario Simulation | Dashboard: Decision Simulator | Draft |
| — / FR-10 | Structure dashboard around one business question per page | All primary stakeholders | All of the above, aggregated | Phase 15, Dashboard | 5-page Power BI dashboard | Draft |

Status is "Draft" for every row until the corresponding phase actually produces the output — this matrix will be revisited and updated (not rewritten) as each phase completes, so it stays an accurate map of what's been delivered versus what's still promised.

---

## Open Items for Stakeholder Review

- Confirm NFR-01's performance target (sub-5-second dashboard interaction) is a reasonable design goal rather than an arbitrary number — flagged here because, per the project's own rule, numeric targets need a stated basis; this one is based on typical BI-tool usability expectations, not a measured constraint.
- Confirm the repeat-failure "rolling window" in FR-05 should be defined now or deferred to Phase 8 (Dataset Design), where it can be set against actual data distribution.
- Confirm BR-06/NFR-05's auditability requirement is strict enough — currently every score and classification must trace to a rule; if that's too rigid for a portfolio project's scope, it can be scoped down before Phase 11.
