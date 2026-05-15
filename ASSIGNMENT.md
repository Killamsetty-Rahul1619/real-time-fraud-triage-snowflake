# Capstone Project: Real-Time Fraud Triage Agent on Snowflake

**Course:** Agentic AI Systems on the Modern Data Cloud
**Project type:** Multi-week capstone (recommended 3–4 weeks, individual or pairs)
**Maximum marks:** 100

---

## Table of contents

1. [Project overview](#1-project-overview)
2. [Business context](#2-business-context)
3. [Learning objectives](#3-learning-objectives)
4. [The challenge](#4-the-challenge)
5. [Provided materials](#5-provided-materials)
6. [Dataset documentation](#6-dataset-documentation)
7. [Functional requirements](#7-functional-requirements)
8. [Architectural requirements](#8-architectural-requirements)
9. [The agent's output contract](#9-the-agents-output-contract)
10. [Suggested phases and milestones](#10-suggested-phases-and-milestones)
11. [Test cases you must triage](#11-test-cases-you-must-triage)
12. [Deliverables](#12-deliverables)
13. [Evaluation rubric](#13-evaluation-rubric)
14. [Tips and common pitfalls](#14-tips-and-common-pitfalls)
15. [Stretch goals (bonus marks)](#15-stretch-goals-bonus-marks)
16. [Submission instructions](#16-submission-instructions)
17. [Academic honesty](#17-academic-honesty)
18. [Reference reading](#18-reference-reading)

---

## 1. Project overview

You will design and build a **real-time, agentic fraud triage system** end-to-end on Snowflake. Your system must ingest a stream of card-payment events, identify high-risk transactions, and use a Cortex Agent armed with multiple tools (SQL analytics, semantic search, web search, and custom action tools) to decide — within seconds — whether each suspicious transaction should be auto-blocked, escalated to a human analyst, or dismissed as a false alarm.

This is intentionally not a notebook-and-a-model assignment. You are building a **production-shaped data system**: streams, tasks, an LLM-orchestrated agent, an audit trail, and an observability surface. Treat it like an artifact you would hand to an on-call engineer.

---

## 2. Business context

You are joining the Fraud Operations team at a mid-size card issuer, *Meridian Bank*. The bank processes about 12 million card authorizations per day across ~3 million active cardholders. An upstream ML risk model already scores every authorization on a 0–100 scale. The pipeline currently does the following:

* `score < 70` → auto-approve. No human in the loop.
* `score ≥ 95` → auto-decline. No human in the loop.
* `70 ≤ score < 95` → a human fraud analyst reviews the case manually.

The bottleneck is the middle band. Roughly 30,000 events per day fall into the review band, and the bank's 40 analysts each handle ~100 cases per shift. The queue regularly backs up to **8 hours**, which means a confirmed-fraud case discovered at 11 PM might not be blocked until 7 AM the next day — by which point the attackers have moved on to the next card. The COO has asked your team to build an agent that triages this middle band in seconds, escalating only the genuinely uncertain cases.

**Business goal:** reduce average analyst review queue depth by 60% while holding the false-block rate under 2%.

---

## 3. Learning objectives

By the end of this project you will be able to:

1. Architect a real-time data pipeline on Snowflake using **Snowpipe Streaming**, **Dynamic Tables**, **Streams**, and **Tasks**.
2. Engineer streaming features (velocity, cross-entity joins, anomaly flags) declaratively.
3. Build and operate a **Cortex Search service** over an unstructured corpus.
4. Design a **Cortex Analyst semantic model** that exposes business vocabulary to an LLM.
5. Compose a **Cortex Agent** with multiple tools and write the instructions / orchestration prompts that make it behave reliably.
6. Integrate **custom action tools** (stored procedures, External Access Integrations) so the agent can take real-world actions.
7. Reason about agent safety: when to auto-act vs escalate, how to log every decision, and how to evaluate quality offline.

---

## 4. The challenge

Your task is to design and implement a system that, given an incoming card transaction with `risk_score ≥ 70`:

1. Enriches the transaction with the cardholder's profile, the merchant's profile, and rolling velocity features.
2. Triggers an LLM agent for each enriched event.
3. The agent investigates the case using at least four kinds of evidence (each delivered by a distinct tool — see §8).
4. The agent returns a strictly-shaped JSON decision: one of `AUTO_BLOCK`, `ESCALATE`, or `DISMISS`, with a confidence score, the fraud-pattern ID it matched (or `NONE`), a written justification, and the list of tools it called.
5. The agent takes the corresponding side-effect action — block the card, post to Slack, or no-op — and persists everything to an audit table.

The full system must be **explainable** (every decision has a written rationale), **auditable** (the full tool trace is recorded), and **conservative** (when in doubt the agent escalates rather than blocks).

---

## 5. Provided materials

You are given the following inputs. **Do not modify the provided files** — your code must consume them as-is, exactly as a real pipeline would consume them from upstream systems.

```
project_starter/
├── ASSIGNMENT.md                              ← this document
├── data/
│   ├── customers.csv                          ← customer master (10 rows)
│   ├── merchants.csv                          ← merchant master (18 rows)
│   ├── transactions.csv                       ← 39 transactions (28 historical + 11 today)
│   └── historical_fraud_cases.csv             ← 10 confirmed past fraud cases
└── fraud_patterns/                            ← internal fraud playbook (markdown)
    ├── P001_card_testing_bustout.md
    ├── P002_geographic_anomaly.md
    ├── P003_account_takeover.md
    ├── P004_crypto_scam.md
    └── P005_frequent_traveler_suppression.md
```

The **fraud-pattern playbook** is the bank's internal knowledge corpus — five markdown documents that codify the signatures of each known fraud type and the suppression rules for known false positives. Your Cortex Search service must index these and your agent must use them to ground its decisions in policy.

---

## 6. Dataset documentation

### 6.1 `customers.csv`
Customer master records with KYC-verified profiles.

| Column                    | Type      | Notes |
|---------------------------|-----------|-------|
| customer_id               | varchar   | Primary key, e.g. `CUST006`. |
| full_name                 | varchar   | |
| email                     | varchar   | OOB contact — treat as untrusted in ATO scenarios. |
| phone                     | varchar   | The registered voice-callback number. |
| date_of_birth             | date      | Used for demographic-pattern matching. |
| home_city, home_country   | varchar   | Reference for geographic-anomaly checks. |
| account_open_date         | date      | Drives tenure features. |
| avg_monthly_spend_usd     | number    | Sets scale of "normal" for the customer. |
| customer_tier             | enum      | `STANDARD` / `GOLD` / `PLATINUM`. |
| kyc_status                | enum      | `VERIFIED` / `PENDING` / `FAILED`. |
| risk_tier                 | enum      | `LOW` / `MEDIUM` / `HIGH` — assigned by another system. |

### 6.2 `merchants.csv`
Merchant master with risk ratings.

| Column                    | Type      | Notes |
|---------------------------|-----------|-------|
| merchant_id               | varchar   | Primary key, e.g. `MERCH011`. |
| merchant_name             | varchar   | |
| merchant_category         | varchar   | Human-readable category. |
| mcc_code                  | varchar   | Standard Merchant Category Code. **Important fraud signal.** |
| city, country             | varchar   | Jurisdiction. |
| registered_date           | date      | Newness is a risk signal. |
| chargeback_rate_pct       | number    | Industry average is well under 1%. |
| merchant_risk_rating      | enum      | `LOW` / `MEDIUM` / `HIGH`. |
| is_high_risk_category     | boolean   | True for jewelry, crypto, forex, gaming, etc. |

### 6.3 `transactions.csv`
The streaming card-authorization events. In production these arrive via Snowpipe Streaming; for the project you may load them via `COPY INTO` from a stage. Treat them as a stream in your design even though you load them in bulk.

| Column                  | Type           | Notes |
|-------------------------|----------------|-------|
| transaction_id          | varchar        | Primary key. |
| customer_id, merchant_id| varchar        | Foreign keys. |
| amount_usd              | number(14,2)   | Already FX-converted upstream. |
| currency                | varchar        | Original currency. |
| transaction_ts          | timestamp_ntz  | Gateway event time. |
| channel                 | enum           | `CARD_PRESENT` / `ONLINE` / `RECURRING` / `ATM` / `CONTACTLESS`. |
| card_present            | boolean        | |
| device_id               | varchar        | Fingerprint from a device-intelligence vendor. |
| ip_address              | varchar        | Source IP. |
| ip_country              | varchar        | From IP geolocation. |
| mcc_code                | varchar        | |
| authorization_status    | enum           | `APPROVED` / `DECLINED` / `PENDING_REVIEW`. |
| risk_score              | number(5)      | Upstream ML model score, 0–100. |
| initial_decision        | enum           | `APPROVE` / `REVIEW` / `DECLINE`. |

The 28 historical rows (status `APPROVED`, initial decision `APPROVE`) are the customer's normal behaviour over the last 30 days. They are context, **not** triage targets. The 11 rows with status `PENDING_REVIEW` and initial decision `REVIEW` are the cases your agent must triage — see §11.

### 6.4 `historical_fraud_cases.csv`
Closed historical fraud cases the agent can use for analogy.

| Column                  | Type           | Notes |
|-------------------------|----------------|-------|
| case_id                 | varchar        | Primary key. |
| customer_id             | varchar        | The affected customer (anonymized in real cases). |
| fraud_type              | enum           | `CARD_TESTING` / `GEOGRAPHIC_ANOMALY` / `ACCOUNT_TAKEOVER` / `MERCHANT_COLLUSION` / `SYNTHETIC_IDENTITY` / `FIRST_PARTY_FRAUD` / `CRYPTO_RAMP_FRAUD`. |
| first_fraud_txn_ts      | timestamp      | When the fraud began. |
| detected_at_ts          | timestamp      | When the bank caught it. |
| total_loss_usd          | number         | |
| num_fraudulent_txns     | number         | |
| resolution              | enum           | `CHARGEBACK_WON` / `CHARGEBACK_PARTIAL` / `WRITTEN_OFF` / `DISPUTED`. |
| root_cause_summary      | text           | Analyst's post-mortem note. |

### 6.5 Fraud playbook documents
Five markdown documents in `fraud_patterns/`. Each one describes:
* The pattern's signature (key signals).
* Recommended action when matched.
* Historical reference cases.
* False-positive considerations.

These are your Cortex Search corpus. **Read them in full before designing your agent's prompts** — they are the bank's institutional knowledge and your agent must obey them.

---

## 7. Functional requirements

| FR# | Requirement |
|-----|-------------|
| FR-1 | Every transaction with `risk_score ≥ 70` and `initial_decision = REVIEW` must trigger an agent run within 90 seconds of landing in the raw table. |
| FR-2 | The agent must consult the customer's prior 30-day transaction history before deciding. |
| FR-3 | The agent must search the fraud-pattern playbook and cite the matched pattern ID in its decision. |
| FR-4 | For merchants the agent has never analysed before (or for merchants registered less than 12 months ago), the agent must run a web search for reputation signals. |
| FR-5 | The agent must apply suppression rule **P-005** before escalating any geographic-anomaly case. |
| FR-6 | `AUTO_BLOCK` is permitted **only when** the agent reports confidence ≥ 90%. Below that, the agent must `ESCALATE` instead. |
| FR-7 | `AUTO_BLOCK` decisions must result in a row written to a `CARD_ACTION_QUEUE` table. The agent does **not** call any external API directly. |
| FR-8 | `ESCALATE` decisions must result in a message posted to a Slack channel (or to a `SLACK_OUTBOX` table if you do not have a real webhook). |
| FR-9 | Every agent run — its inputs, its tool calls, and its final decision — must be persisted to an audit table. |
| FR-10 | The agent's output must conform exactly to the JSON contract in §9. A decision that fails to parse is a hard error and must be logged. |

---

## 8. Architectural requirements

Your design must use the following Snowflake capabilities (each one is a hard requirement, not a suggestion):

1. A **raw landing table** for the streaming events.
2. At least one **Dynamic Table** producing per-customer velocity features (count and sum of transactions over rolling windows). Set the target lag appropriately.
3. A **filtered Dynamic Table or view** that surfaces only the high-risk events the agent should triage.
4. A **Stream** on top of the triage queue and a **Task** that consumes the stream and invokes the agent. The task must use `WHEN SYSTEM$STREAM_HAS_DATA(...)` to avoid no-op runs.
5. A **Cortex Search service** built over the fraud-pattern markdown documents.
6. A **Cortex Analyst semantic model** (YAML) that exposes the transactions, customers, merchants, and historical fraud cases as a queryable business surface.
7. A **Cortex Agent** definition (`CREATE AGENT ... FROM SPECIFICATION ...`) wiring up at least these five tools:
   - A `cortex_analyst_text_to_sql` tool over your semantic model.
   - A `cortex_search` tool over your fraud-pattern index.
   - A `web_search` tool (Brave built-in).
   - A `generic` tool that calls a `BLOCK_CARD` stored procedure.
   - A `generic` tool that calls an `ESCALATE_TO_SLACK` stored procedure.
8. The Slack escalation tool must use an **External Access Integration**, a **network rule**, and a **secret**. If you don't have a webhook, document the design and write to an outbox table instead — but you must still show the EAI/network-rule/secret design in your SQL.
9. An **audit table** with the full agent trace stored in a `VARIANT` column.
10. **Role separation:** the role that invokes the agent must not be `ACCOUNTADMIN`. Create a dedicated runner role with the minimum grants.

---

## 9. The agent's output contract

Your agent's instructions must require it to return exactly this JSON shape. The stored procedure that persists the decision should fail loudly if the parse fails — that is the signal that your prompt has drifted.

```json
{
  "decision":        "AUTO_BLOCK | ESCALATE | DISMISS",
  "confidence":      0,                          
  "pattern_matched": "P-001 | P-002 | P-003 | P-004 | P-005 | NONE",
  "justification":   "free text, max 1500 chars",
  "tools_used":      ["transaction_history_analyst", "fraud_pattern_search", "..."]
}
```

Rules:
* `confidence` is an integer 0–100.
* `pattern_matched` is the playbook ID the case most resembles, or `"NONE"` if no pattern is a good match.
* `justification` must reference specific evidence from the tools the agent called. A justification of "looks suspicious" is a fail.
* `tools_used` is the deduplicated list of tool names invoked during the run.

---

## 10. Suggested phases and milestones

A reasonable cadence for a 4-week project. Adjust as your timeline allows.

### Week 1 — foundation
* Account setup, database, schemas, warehouse, roles.
* Load all four CSVs into reference and raw tables.
* Write the Dynamic Tables for velocity features and the enriched view.
* **Milestone 1 deliverable:** a screenshot or SELECT that shows your `TRIAGE_QUEUE` populated with the 11 review transactions.

### Week 2 — knowledge surface
* Build the Cortex Search service over the markdown corpus.
* Author and upload the Cortex Analyst semantic model YAML.
* Write and test five natural-language questions against the semantic model that the agent will need to ask (for example: *"show the last 30 days of transactions for customer X"*).
* **Milestone 2 deliverable:** demonstrate three successful Cortex Search queries and three successful Cortex Analyst questions, with results.

### Week 3 — agent and actions
* Write the `BLOCK_CARD` stored procedure and `CARD_ACTION_QUEUE` table.
* Write the `ESCALATE_TO_SLACK` stored procedure with its External Access Integration, network rule, and secret.
* Compose the agent specification and run it against each of the 11 transactions individually.
* **Milestone 3 deliverable:** the agent's JSON decision for each of the 11 transactions, plus the tool trace for at least three of them.

### Week 4 — pipeline and write-up
* Wire the Stream and Task so the pipeline runs end-to-end without manual invocation.
* Build a monitoring dashboard (one Streamlit-in-Snowflake page is enough): decision distribution, confidence distribution, tool-usage counts, slowest runs.
* Write your report (§12).
* **Final deliverable:** see §12.

---

## 11. Test cases you must triage

The 11 transactions in `transactions.csv` whose `initial_decision` is `REVIEW` constitute your test set. Your agent must produce a decision for every one. **Before running your agent, do this analysis by hand** so you can compare what a careful human analyst would conclude with what your agent actually does.

For each of the 11 transactions, write up in your report:

| Transaction ID | Your manual analyst verdict | Pattern you think applies | Confidence | Reasoning |
|----------------|-----------------------------|----------------------------|------------|-----------|
| TXN20260511100 | … | … | … | … |
| TXN20260511101 | … | … | … | … |
| TXN20260511102 | … | … | … | … |
| TXN20260511103 | … | … | … | … |
| TXN20260511104 | … | … | … | … |
| TXN20260511200 | … | … | … | … |
| TXN20260511300 | … | … | … | … |
| TXN20260511301 | … | … | … | … |
| TXN20260511400 | … | … | … | … |
| TXN20260511500 | … | … | … | … |
| TXN20260511600 | … | … | … | … |

Then run your agent against each transaction and report:
* Agent's decision and confidence.
* Tools the agent called (in order).
* Whether the agent's verdict matches your manual verdict — and if not, where you think the gap is (model, prompt, data, or playbook).

A perfect score does **not** require the agent to match your verdict on every transaction; some of these cases are genuinely ambiguous (that is the point — they are in the review band precisely because the upstream model is uncertain). What we look for is the quality of your reasoning about the gap.

---

## 12. Deliverables

Submit a single zip archive (or a Git repository link) containing:

1. **`setup.sql`** — every SQL statement required to provision your system from a clean Snowflake account, in the order it should be executed. Must include comments explaining each section.
2. **`semantic_model.yaml`** — your Cortex Analyst semantic model.
3. **`agent_spec.json`** — the JSON specification you pass to `CREATE AGENT … FROM SPECIFICATION`.
4. **`agent_runner.py`** (optional but recommended) — a Python script that demonstrates invoking the agent end-to-end against a single transaction.
5. **`screenshots/`** — at minimum:
   - Snowsight view of your `TRIAGE_QUEUE` populated.
   - Snowsight view of your `AGENT_DECISIONS` table after a batch run.
   - Snowsight view of `CARD_ACTION_QUEUE` and (Slack screenshot or `SLACK_OUTBOX`) for at least one escalation.
   - Your monitoring dashboard.
6. **`agent_traces/`** — the full streaming tool trace (input + output of each tool call) for at least **three** transactions of your choosing. Save them as `agent_traces/TXN20260511104.json` etc.
7. **`REPORT.md`** — your written report, structured as:
   - **Architecture overview** (one diagram + 1 page of prose).
   - **Design decisions** — why you chose your Dynamic Table target lags, what suppression logic you applied, how you wrote the agent's orchestration prompt, and what alternatives you considered.
   - **Test results** — the table from §11 fully filled in, with a paragraph of analysis per transaction.
   - **Evaluation** — for any transaction where your agent disagreed with your manual verdict, explain whether you think the agent or you was right, and what you would change.
   - **Cost and latency notes** — what you observed for end-to-end latency and what it would cost to run this system at 10,000 events per day.
   - **Limitations and future work** — what you would do with another month.

---

## 13. Evaluation rubric

| Criterion | Marks | What earns full marks |
|-----------|-------|----------------------|
| **Architecture correctness** | 20 | All §8 components present and wired correctly. Roles, grants, and target lags are appropriate. Stream + Task fires automatically without manual invocation. |
| **Feature engineering** | 10 | Dynamic Tables produce correct velocity features. The triage queue contains exactly the events that should be there. |
| **Cortex Search + Cortex Analyst** | 15 | Semantic model correctly exposes the business vocabulary. Search index returns the right pattern for at least 4 of the 5 fraud types. Verified queries are present in the YAML. |
| **Agent design** | 20 | Instructions enforce the JSON contract. Orchestration prompt produces a sensible plan. Agent uses tools appropriately — not too few (lazy) and not too many (wasteful). |
| **Decisions on the 11 test cases** | 15 | Decisions are defensible. No false `AUTO_BLOCK` with low confidence. P-005 suppression applied where applicable. Justifications cite real evidence from tool outputs. |
| **Auditability and governance** | 10 | Decisions audit table is complete with full trace. Role separation is correct. PII masking or equivalent is documented. |
| **Report quality** | 10 | Clear architecture diagram, honest analysis of agent disagreements, thoughtful limitations section. |

| **Total** | **100** | |

Bonus: see §15.

### What loses marks heavily
* Hard-coding decisions in SQL (e.g., a `CASE WHEN merchant_country = 'MY' THEN 'BLOCK'` rule). The agent must reason, not lookup.
* Calling the issuer API or any external service from inside the agent loop without going through the queue table.
* Using `ACCOUNTADMIN` to invoke the agent at runtime.
* An agent that auto-blocks the false-positive Tokyo trip without applying P-005.
* A justification that quotes the customer's PII without redaction.

---

## 14. Tips and common pitfalls

* **Start with the manual analysis.** Spend an afternoon working through the 11 transactions on paper before you write a single line of SQL. You cannot tell whether your agent is right until you know what right looks like.
* **The fraud playbook is your friend.** All five patterns and their suppression rules are deliberately documented. If your agent ignores them, you have a prompt problem, not a model problem.
* **Cortex Analyst is brittle without verified queries.** Add 4–6 `verified_queries` to your semantic model YAML. The model uses them as few-shot examples and accuracy jumps noticeably.
* **Test the agent with `SNOWFLAKE.CORTEX.AGENT_RUN()` directly** before wiring up the Stream + Task. Debugging an agent inside a task is painful.
* **Keep the agent's tool surface narrow.** Five tools maximum. More tools = more chances to pick the wrong one.
* **Slack webhook is optional for the demo.** If you don't have one, write the JSON payload to a `SLACK_OUTBOX` table and screenshot that. Document the network-rule and secret SQL even if you can't actually fire it.
* **Watch your warehouse spend.** A `SMALL` warehouse on a 1-minute task with auto-suspend at 60 seconds is plenty for this assignment. Don't run a `LARGE` overnight.
* **The 5 micro-charges + bust-out scenario will fire your agent five times.** Decide whether each run should be independent (idempotent) or whether you batch-process them in one call. Either is acceptable — document your choice.
* **`models.orchestration = "auto"`** is fine for development, but pin a specific model for the final submission so your results are reproducible.

---

## 15. Stretch goals (bonus marks)

Up to **+15 bonus marks**, awarded for genuine effort not for breadth:

* **(+5) Evaluation harness.** Build an `EVAL_GOLDEN` table with your manual verdicts on the 11 cases. Write a Snowpark Python notebook that re-runs the agent against all of them and computes precision/recall per decision class.
* **(+5) Multi-model comparison.** Run your agent under two different orchestration models (e.g. a smaller and a larger one) and report quality vs cost per decision.
* **(+5) Streamlit fraud-ops console.** Build a Streamlit-in-Snowflake page where an analyst can see the triage queue, click a case, and see the agent's full reasoning trace.
* **(+5) Alerting.** Wire `SNOWFLAKE.ALERT` objects that fire when the triage backlog exceeds 5 minutes or when median `AUTO_BLOCK` confidence falls below 92.
* **(+5) MCP server.** Replace one of your generic tools with a tool served from an MCP server you write yourself.

Total bonus capped at +15, regardless of how many stretch goals you complete.

---

## 16. Submission instructions

* Submit by **23:59 on the assignment due date** via the course portal.
* File format: zip archive or Git repository link.
* Maximum archive size: 50 MB. Do not include warehouse query logs or large dumps.
* If you submit a Git repo, ensure the assessor has read access. Use the tag `v1.0-final` to mark the version we will grade.
* Include a `README.md` at the root of your submission listing every file and a one-line description.

Late policy: −10 marks per day, up to 3 days. Submissions later than that earn zero unless a documented extension has been granted.

---

## 17. Academic honesty

* You may discuss design ideas with classmates, but every line of code and every word of your report must be your own.
* You may use AI assistants for code completion and documentation lookups. **You must disclose** in your report which assistant you used and on which sections. Using an AI assistant to write your prompts or your report verbatim is plagiarism and will be treated as such.
* You may reference Snowflake documentation freely — that is expected. Cite the docs in your report where it materially shaped a design choice.
* Submissions that look like duplicates of the public Snowflake quickstarts (without attribution and without adaptation to this specific problem) will be flagged.

---

## 18. Reference reading

You are expected to read these before starting. None is hidden behind a paywall.

* Snowflake docs — **Cortex Agents overview** (covers tool types, agent specification, agent:run REST API).
* Snowflake docs — **Cortex Analyst semantic model YAML reference**.
* Snowflake docs — **Cortex Search overview and chunking strategies**.
* Snowflake docs — **Dynamic Tables** (target lag, refresh modes, dependency ordering).
* Snowflake docs — **Streams and Tasks** (SYSTEM$STREAM_HAS_DATA, task graphs, error handling).
* Snowflake docs — **External Access Integrations** (network rules, secrets, scoped grants).
* Snowflake quickstart — **Build a Cortex Search service** (do this once end-to-end before starting; do not copy verbatim).
* Anthropic — **"Building effective agents"** blog post (tool use, control flow, evaluation).
* Vasant Dhar (NYU) — *Data Science and Prediction*, Communications of the ACM, 2013 — for the framing of model uncertainty and human-in-the-loop systems.

---

## Closing note

Building agentic systems is fundamentally different from building classification models. Most of the work goes into **the surface area around the model** — the tools, the data contracts, the audit trail, the safety rails — and not into the model itself. This assignment is designed to give you that experience. Treat the model as a fast junior analyst with no memory: it can read anything you put in front of it and answer concretely, but it cannot do anything you do not give it a tool for, and it cannot remember a single thing between runs. Your job is to design the room it operates in.

Good luck.
