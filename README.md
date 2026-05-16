# Real-Time Fraud Triage System on Snowflake

This repository contains an end-to-end implementation of a **real-time fraud triage system** built on **Snowflake**.  
The system ingests card transaction data from **Amazon S3** using **Snowpipe**, enriches and analyzes transactions using SQL-based feature engineering, and applies an agent-style decision procedure to determine whether transactions should be **auto-blocked**, **escalated**, or **dismissed**.

The project demonstrates **streaming ingestion**, **incremental processing**, and an **append-only audit trail**, closely simulating a production fraud-operations pipeline.

---

## 🚀 Key Capabilities

- Real-time ingestion using **Snowpipe AUTO_INGEST**
- Incremental processing of new transactions
- Feature engineering for fraud detection
- Stream-driven triage queue
- Rule-based fraud agent (stored procedure)
- Action queues for blocking and escalation
- Full auditability of decisions
- No overwriting of historical results

---

## 🏗️ High-Level Architecture


Local Machine (CSV upload)  
→ AWS S3  
→ Snowpipe (AUTO_INGEST)  
→ Snowflake Raw Tables  
→ Enriched Transactions  
→ Feature Engineering  
→ Triage Queue + Stream  
→ Fraud Agent Procedure  
  ├── card_action_queue  
  ├── slack_outbox  
  └── agent_decisions (


---

## 📁 Repository Structure

real-time-fraud-triage-snowflake  
→ data  
 → customers.csv  
 → merchants.csv  
 → transactions.csv  
 → new_transactions.csv  
 → historical_fraud_cases.csv  
 → Output.csv  

→ sql-files  
 → setup.sql  
 → enriched_transactions.sql  
 → txn_features_and_fraud_signals.sql  
 → triage_queue_and_stream.sql  
 → run_fraud_agent.sql  

→ CApstone Project  
 → ASSIGNMENT.md  
 → P001_card_testing_bustout.md  
 → P002_geographic_anomaly.md  
 → P003_account_takeover.md  
 → P004_crypto_scam.md  
 → P005_frequent_traveler_suppression.md  
 
→ README.md

---

## ✅ Prerequisites

### 1. AWS
- AWS account
- S3 bucket
- IAM Role with:
  - `AmazonS3ReadOnlyAccess`
  - Trust relationship allowing Snowflake

### 2. Snowflake
- Snowflake account
- Ability to create:
  - Database, schema, warehouse
  - Storage integration
  - Snowpipe
  - Streams and tasks

### 3. Local Machine
- Any OS (Windows / macOS / Linux)
- CSV files prepared locally
- AWS Console access (browser is sufficient)

---

## ☁️ AWS Setup (S3 + IAM)

### Step 1: Create S3 Bucket
Create an S3 bucket, for example:

s3://sprintproject1619/

Inside the bucket, keep logical folders per entity:

s3://sprintproject1619/
├── customers/
│   └── customers.csv
│
├── merchants/
│   └── merchants.csv
│
├── transactions/
│   ├── transactions.csv
│   └── new_transactions.csv
│
├── historical_fraud_cases/
│   └── historical_fraud_cases.csv

---

### Step 2: Create IAM Role
Create an IAM Role with:
- **Trusted entity**: Snowflake
- **Permissions**:
  - `AmazonS3ReadOnlyAccess`

Copy the **Role ARN** and use it in `setup.sql`:
```sql
STORAGE_AWS_ROLE_ARN = 'arn:aws:iam::<account-id>:role/<role-name>'
```

❄️ Snowflake Setup
Step 1: Run Initial Setup
Execute:
sql-files/setup.sql

This creates:

Database & schema
Warehouse
Core tables
Storage integration
External stage
Snowpipes


Step 2: Create Enrichment Layer
sql-files/enriched_transactions.sql

Step 3: Feature Engineering & Fraud Signals
sql-files/txn_features_and_fraud_signals.sql

Step 4: Triage Queue and Stream
sql-files/triage_queue_and_stream.sql

This:
Filters high-risk transactions (risk_score >= 70)
Creates a stream to capture new review records

Step 5: Run Fraud Agent
sql-files/run_fraud_agent.sql

This:
Consumes stream records
Applies fraud pattern logic
Writes decisions to audit table
Queues block/escalation actions


🔄 Simulating Real-Time Ingestion

1. Upload new_transactions.csv to the S3 transactions/ folder
2. Snowpipe automatically ingests the data
3. New records flow through:
 > Enrichment
 > Feature computation
 > Triage queue
 > Stream
4. Fraud agent processes only new transactions


📊 Output & Audit

agent_decisions → full audit trail
card_action_queue → auto-block actions
slack_outbox → escalation messages
Output.csv → exported snapshot of decisions

Output.csv grows over time and includes both historical and newly ingested transactions.


🧠 Fraud Patterns Implemented





























Pattern IDDescriptionP-001Card testing / burst transactionsP-002Geographic anomalyP-003Account takeoverP-004Crypto scamP-005Frequent traveler suppression
Each pattern is documented in its corresponding markdown file.

✅ Decision Types

AUTO_BLOCK – High confidence fraud
ESCALATE – Requires analyst review
DISMISS – Legitimate activity

Each decision includes:

Confidence score
Pattern matched
Justification
Timestamp
