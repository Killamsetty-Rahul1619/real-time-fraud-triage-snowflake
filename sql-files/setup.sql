-- ============================================================
-- Project: Real-Time Fraud Triage Agent on Snowflake
-- File: setup.sql
-- Purpose:
--   End-to-end infrastructure and ingestion setup.
--   This script provisions database objects, core tables,
--   external storage integration, stages, and Snowpipes.
--
-- Execution:
--   Run this file first from a clean Snowflake account.
-- ============================================================


-- ============================================================
-- DATABASE, SCHEMA, AND WAREHOUSE SETUP
-- ============================================================

-- Create project database
CREATE DATABASE project;

-- Create core schema to hold all primary objects
CREATE SCHEMA core;

-- Create a cost-controlled warehouse for ingestion and processing
CREATE WAREHOUSE project_wh
    WAREHOUSE_SIZE = 'SMALL'
    AUTO_SUSPEND = 60;

-- Set execution context
USE DATABASE project;
USE SCHEMA core;
USE WAREHOUSE project_wh;


-- ============================================================
-- CORE REFERENCE TABLES
-- These tables represent the bank’s source-of-truth entities
-- ============================================================

-- ------------------------------------------------------------
-- CUSTOMERS TABLE
-- Stores KYC-verified customer master data
-- ------------------------------------------------------------
CREATE OR REPLACE TABLE customers (
    customer_id             VARCHAR(20) PRIMARY KEY,
    full_name               VARCHAR(100),
    email                   VARCHAR(255),
    phone                   VARCHAR(20),
    date_of_birth           DATE,
    home_city               VARCHAR(50),
    home_country            VARCHAR(50),
    account_open_date       DATE,
    avg_monthly_spend_usd   NUMBER(12,2),
    customer_tier           VARCHAR(20),
    kyc_status              VARCHAR(20),
    risk_tier               VARCHAR(20)
);

-- ------------------------------------------------------------
-- MERCHANTS TABLE
-- Stores merchant profile and inherent risk indicators
-- ------------------------------------------------------------
CREATE OR REPLACE TABLE merchants (
    merchant_id             VARCHAR(20) PRIMARY KEY,
    merchant_name           VARCHAR(150),
    merchant_category       VARCHAR(100),
    mcc_code                VARCHAR(10),
    city                    VARCHAR(50),
    country                 VARCHAR(50),
    registered_date         DATE,
    chargeback_rate_pct     NUMBER(5,2),
    merchant_risk_rating    VARCHAR(20),
    is_high_risk_category   BOOLEAN
);

-- ------------------------------------------------------------
-- TRANSACTIONS TABLE
-- Central fact table for all card authorization events
-- ------------------------------------------------------------
CREATE OR REPLACE TABLE transactions (
    transaction_id          VARCHAR(30) PRIMARY KEY,
    customer_id             VARCHAR(20),
    merchant_id             VARCHAR(20),
    amount_usd              NUMBER(14,2),
    currency                VARCHAR(10),
    transaction_ts          TIMESTAMP_NTZ,
    channel                 VARCHAR(20),
    card_present            BOOLEAN,
    device_id               VARCHAR(100),
    ip_address              VARCHAR(50),
    ip_country              VARCHAR(50),
    mcc_code                VARCHAR(10),
    authorization_status    VARCHAR(20),
    risk_score              NUMBER(5,0),
    initial_decision        VARCHAR(20),

    -- Foreign keys ensure referential integrity and
    -- support semantic modeling for Cortex Analyst
    CONSTRAINT fk_txn_customer 
        FOREIGN KEY (customer_id) REFERENCES customers(customer_id),

    CONSTRAINT fk_txn_merchant 
        FOREIGN KEY (merchant_id) REFERENCES merchants(merchant_id)
);

-- ------------------------------------------------------------
-- HISTORICAL FRAUD CASES TABLE
-- Closed fraud cases used for analogy and agent reasoning
-- ------------------------------------------------------------
CREATE OR REPLACE TABLE historical_fraud_cases (
    case_id                 VARCHAR(30) PRIMARY KEY,
    customer_id             VARCHAR(20),
    fraud_type              VARCHAR(50),
    first_fraud_txn_ts      TIMESTAMP_NTZ,
    detected_at_ts          TIMESTAMP_NTZ,
    total_loss_usd          NUMBER(14,2),
    num_fraudulent_txns     NUMBER,
    resolution              VARCHAR(30),
    root_cause_summary      VARCHAR,

    -- Foreign key links historical cases back to customers
    CONSTRAINT fk_case_customer 
        FOREIGN KEY (customer_id) REFERENCES customers(customer_id)
);


-- ============================================================
-- EXTERNAL STORAGE INTEGRATION (AWS S3)
-- Used by Snowpipe for auto-ingestion of CSV files
-- ============================================================

CREATE OR REPLACE STORAGE INTEGRATION s3_snowpipe_int
    TYPE = EXTERNAL_STAGE
    STORAGE_PROVIDER = S3
    ENABLED = TRUE
    STORAGE_AWS_ROLE_ARN = 'arn:aws:iam::551670267107:role/sprintsnowflakes3'
    STORAGE_ALLOWED_LOCATIONS = ('s3://sprintproject1619/');

-- Inspect integration details (for validation/debugging)
DESC INTEGRATION s3_snowpipe_int;


-- ============================================================
-- EXTERNAL STAGE DEFINITION
-- Points to the S3 bucket containing incoming CSV data
-- ============================================================

CREATE OR REPLACE STAGE fraud_s3_stage
    URL = 's3://sprintproject1619/'
    STORAGE_INTEGRATION = s3_snowpipe_int
    FILE_FORMAT = (
        TYPE = CSV
        SKIP_HEADER = 1
        FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    );

-- Validate that Snowflake can see files in S3
LIST @fraud_s3_stage;


-- ============================================================
-- SNOWPIPE DEFINITIONS
-- AUTO_INGEST simulates real-time streaming ingestion
-- ============================================================

-- ------------------------------------------------------------
-- Customers Snowpipe
-- ------------------------------------------------------------
CREATE OR REPLACE PIPE customers_pipe
    AUTO_INGEST = TRUE
AS
COPY INTO customers
FROM @fraud_s3_stage/customers/
FILE_FORMAT = (
    TYPE = CSV,
    SKIP_HEADER = 1,
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
);

DESC PIPE customers_pipe;

-- ------------------------------------------------------------
-- Merchants Snowpipe
-- ------------------------------------------------------------
CREATE OR REPLACE PIPE merchants_pipe
    AUTO_INGEST = TRUE
AS
COPY INTO merchants
FROM @fraud_s3_stage/merchants/
FILE_FORMAT = (
    TYPE = CSV,
    SKIP_HEADER = 1,
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
);

-- ------------------------------------------------------------
-- Transactions Snowpipe (Critical streaming source)
-- ------------------------------------------------------------
CREATE OR REPLACE PIPE transactions_pipe
    AUTO_INGEST = TRUE
AS
COPY INTO transactions
FROM @fraud_s3_stage/transactions/
FILE_FORMAT = (
    TYPE = CSV,
    SKIP_HEADER = 1,
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
);

-- ------------------------------------------------------------
-- Historical Fraud Cases Snowpipe
-- ------------------------------------------------------------
CREATE OR REPLACE PIPE fraud_cases_pipe
    AUTO_INGEST = TRUE
AS
COPY INTO historical_fraud_cases
FROM @fraud_s3_stage/historical_fraud_cases/
FILE_FORMAT = (
    TYPE = CSV,
    SKIP_HEADER = 1,
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
);

-- View all defined pipes
SHOW PIPES;


-- ============================================================
-- MANUAL REFRESH & DEBUGGING (FOR DEVELOPMENT)
-- ============================================================

-- Trigger ingestion manually if needed
ALTER PIPE transactions_pipe REFRESH;

-- Debug sample transactions
SELECT *
FROM transactions
WHERE transaction_id LIKE 'TXN_TEST%';

-- Inspect Snowpipe copy history
SELECT *
FROM TABLE(
    information_schema.copy_history(
        table_name => 'TRANSACTIONS',
        start_time => DATEADD(hour, -1, CURRENT_TIMESTAMP())
    )
);

-- Final validation checks
SELECT * FROM customers;
SELECT * FROM merchants;
SELECT * FROM transactions;
SELECT * FROM historical_fraud_cases;
