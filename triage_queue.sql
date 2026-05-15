CREATE OR REPLACE TABLE triage_queue AS
SELECT 
    f.transaction_id,
    f.customer_id,
    f.merchant_id,
    f.amount_usd,
    f.transaction_ts,
    f.risk_score,
    f.initial_decision,

    -- include signals
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

  -- VALIDATE TRIAGE QUEUE

  SELECT COUNT(*) FROM triage_queue;

  SELECT *
FROM triage_queue
ORDER BY transaction_ts;

-- CREATE STREAM

CREATE OR REPLACE STREAM triage_stream
ON table triage_queue;

select * from triage_stream;

-- KEEP TRIAGE TABLE UPDATED

CREATE OR REPLACE TASK refresh_triage_queue
WAREHOUSE = compute_wh
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

-- Error

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

select * from triage_queue;