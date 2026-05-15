-- ============================================================
-- File: triage_queue_and_stream.sql
-- Purpose:
--   1. Create a triage queue containing only high-risk
--      REVIEW transactions
--   2. Create a stream on the triage queue
--   3. Keep the triage queue refreshed from txn_features
--
-- Notes:
--   - This table represents the agent-trigger surface
--   - Only transactions with risk_score >= 70 are included
-- ============================================================


-- ============================================================
-- TRIAGE QUEUE TABLE
-- Contains only transactions requiring agent review
-- ============================================================

CREATE OR REPLACE TABLE triage_queue AS
SELECT 
    f.transaction_id,
    f.customer_id,
    f.merchant_id,
    f.amount_usd,
    f.transaction_ts,
    f.risk_score,
    f.initial_decision,

    -- --------------------------------------------------------
    -- FRAUD FEATURES / SIGNALS
    -- --------------------------------------------------------
    f.txn_count_15m,
    f.avg_amt_1d,
    f.geo_mismatch_flag,
    f.is_new_device,
    f.is_off_hours,
    f.is_crypto_txn,
    f.is_round_amount,
    f.is_extreme_value

FROM txn_features f
WHERE f.risk_score >= 70
  AND f.initial_decision = 'REVIEW';


-- ============================================================
-- VALIDATION QUERIES
-- ============================================================

-- Count of transactions in triage queue
SELECT COUNT(*) 
FROM triage_queue;

-- Inspect triage queue contents
SELECT *
FROM triage_queue
ORDER BY transaction_ts;


-- ============================================================
-- STREAM DEFINITION
-- Captures inserts/updates to the triage queue
-- ============================================================

CREATE OR REPLACE STREAM triage_stream
ON TABLE triage_queue;

-- Inspect stream contents (for debugging)
SELECT *
FROM triage_stream;


-- ============================================================
-- TASK: KEEP TRIAGE QUEUE UPDATED
-- Periodically syncs triage_queue from txn_features
-- ============================================================

CREATE OR REPLACE TASK refresh_triage_queue
WAREHOUSE = project_wh
SCHEDULE = '1 MINUTE'
AS
MERGE INTO triage_queue t
USING (
    SELECT *
    FROM txn_features
    WHERE risk_score >= 70
      AND initial_decision = 'REVIEW'
) s
ON t.transaction_id = s.transaction_id

WHEN MATCHED THEN UPDATE SET
    t.amount_usd = s.amount_usd

WHEN NOT MATCHED THEN INSERT VALUES (
    s.transaction_id,
    s.customer_id,
    s.merchant_id,
    s.amount_usd,
    s.transaction_ts,
    s.risk_score,
    s.initial_decision,
    s.txn_count_15m,
    s.avg_amt_1d,
    s.geo_mismatch_flag,
    s.is_new_device,
    s.is_off_hours,
    s.is_crypto_txn,
    s.is_round_amount,
    s.is_extreme_value
);


-- ============================================================
-- MANUAL RESET / REBUILD (DEVELOPMENT ONLY)
-- Useful if task logic needs to be revalidated
-- ============================================================

TRUNCATE TABLE triage_queue;

INSERT INTO triage_queue
SELECT
    transaction_id,
    customer_id,
    merchant_id,
    amount_usd,
    transaction_ts,
    risk_score,
    initial_decision,
    txn_count_15m,
    avg_amt_1d,
    geo_mismatch_flag,
    is_new_device,
    is_off_hours,
    is_crypto_txn,
    is_round_amount,
    is_extreme_value
FROM txn_features
WHERE risk_score >= 70
  AND initial_decision = 'REVIEW';

-- Final inspection
SELECT *
FROM triage_queue;
