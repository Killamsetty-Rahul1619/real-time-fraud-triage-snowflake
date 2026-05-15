create database project;

create schema core;


CREATE WAREHOUSE project_wh WAREHOUSE_SIZE = 'SMALL' AUTO_SUSPEND = 60;
USE DATABASE project;
USE SCHEMA core;

-- CUSTOMERS TABLE

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

-- MERCHANTS TABLE

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

-- TRANSACTIONS TABLE (CENTRAL TABLE)

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

    -- FOREIGN KEYS
    CONSTRAINT fk_txn_customer 
        FOREIGN KEY (customer_id) REFERENCES customers(customer_id),

    CONSTRAINT fk_txn_merchant 
        FOREIGN KEY (merchant_id) REFERENCES merchants(merchant_id)
);

-- HISTORICAL FRAUD CASES TABLE

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

    -- FOREIGN KEY
    CONSTRAINT fk_case_customer 
        FOREIGN KEY (customer_id) REFERENCES customers(customer_id)
);

-- CREATE STORAGE INTEGRATION

CREATE OR REPLACE STORAGE INTEGRATION s3_snowpipe_int
TYPE = EXTERNAL_STAGE
STORAGE_PROVIDER = S3
ENABLED = TRUE
STORAGE_AWS_ROLE_ARN = 'arn:aws:iam::551670267107:role/sprintsnowflakes3'
STORAGE_ALLOWED_LOCATIONS = ('s3://sprintproject1619/');

DESC INTEGRATION s3_snowpipe_int;

-- CREATE STAGE

CREATE OR REPLACE STAGE fraud_s3_stage
URL = 's3://sprintproject1619/'
STORAGE_INTEGRATION = s3_snowpipe_int
FILE_FORMAT = (
    TYPE = CSV
    SKIP_HEADER = 1
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
);

LIST @fraud_s3_stage;

-- CREATE SNOWPIPES
-- 1) Customers Pipe

CREATE OR REPLACE PIPE customers_pipe
AUTO_INGEST = TRUE
AS
COPY INTO customers
FROM @fraud_s3_stage/customers/
FILE_FORMAT = (TYPE = CSV,
    SKIP_HEADER = 1,
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
);

DESC PIPE customers_pipe;


-- 2) Merchants Pipe

CREATE OR REPLACE PIPE merchants_pipe
AUTO_INGEST = TRUE
AS
COPY INTO merchants
FROM @fraud_s3_stage/merchants/
FILE_FORMAT = (TYPE = CSV,
    SKIP_HEADER = 1,
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
);

-- 3) Transactions Pipe (CRITICAL)

CREATE OR REPLACE PIPE transactions_pipe
AUTO_INGEST = TRUE
AS
COPY INTO transactions
FROM @fraud_s3_stage/transactions/
FILE_FORMAT = (TYPE = CSV,
    SKIP_HEADER = 1,
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
);

-- 4) Historical Fraud Pipe

CREATE OR REPLACE PIPE fraud_cases_pipe
AUTO_INGEST = TRUE
AS
COPY INTO historical_fraud_cases
FROM @fraud_s3_stage/historical_fraud_cases/
FILE_FORMAT = (TYPE = CSV,
    SKIP_HEADER = 1,
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
);

show pipes;

-- LOAD DATA (trigger)(REFRESH)
ALTER PIPE transactions_pipe REFRESH;

-- Debugging
SELECT *
FROM transactions 
WHERE transaction_id LIKE 'TXN_TEST%';

SELECT *
FROM TABLE(
    information_schema.copy_history(
        table_name => 'TRANSACTIONS',
        start_time => dateadd(hour, -1, current_timestamp())
    )
);

select * from customers;
select * from merchants;
select * from transactions;
select * from historical_fraud_cases;
