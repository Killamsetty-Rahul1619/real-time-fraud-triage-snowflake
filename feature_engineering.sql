CREATE OR REPLACE DYNAMIC TABLE txn_features
TARGET_LAG = '1 minute'
WAREHOUSE = project_wh
AS
SELECT
    e.*,

    ---------------------------------------------------
    -- 🔴 P-001: BURST DETECTION (FIXED)
    ---------------------------------------------------
    
    COUNT(*) OVER (
        PARTITION BY customer_id
        ORDER BY transaction_ts
        ROWS BETWEEN 10 PRECEDING AND CURRENT ROW
    ) AS txn_count_15m,

    ---------------------------------------------------
    -- ✅ SAFE AVG (NO RANGE ISSUE)
    ---------------------------------------------------

    AVG(amount_usd) OVER (
        PARTITION BY customer_id
        ORDER BY transaction_ts
        ROWS BETWEEN 20 PRECEDING AND CURRENT ROW
    ) AS avg_amt_1d,

    ---------------------------------------------------
    -- 🌍 GEO SIGNAL
    ---------------------------------------------------

    CASE 
        WHEN ip_country != home_country THEN TRUE
        ELSE FALSE
    END AS geo_mismatch_flag,

    ---------------------------------------------------
    -- 🔐 NEW DEVICE LOGIC (FIX IMPROVED)
    ---------------------------------------------------

    CASE 
        WHEN device_id NOT IN (
            SELECT device_id 
            FROM transactions
            WHERE customer_id = e.customer_id
              AND transaction_ts < e.transaction_ts
        )
        THEN TRUE ELSE FALSE
    END AS is_new_device,

    ---------------------------------------------------
    -- 🕒 OFF HOURS
    ---------------------------------------------------

    CASE 
        WHEN HOUR(transaction_ts) BETWEEN 2 AND 5 THEN TRUE
        ELSE FALSE
    END AS is_off_hours,

    ---------------------------------------------------
    -- 💰 CRYPTO
    ---------------------------------------------------

    CASE 
        WHEN mcc_code IN ('6051','4829') THEN TRUE
        ELSE FALSE
    END AS is_crypto_txn,

    ---------------------------------------------------
    -- ROUND AMOUNT
    ---------------------------------------------------

    CASE 
        WHEN MOD(amount_usd,1000)=0 THEN TRUE
        ELSE FALSE
    END AS is_round_amount,

    ---------------------------------------------------
    -- HIGH VALUE
    ---------------------------------------------------

    CASE 
        WHEN amount_usd > 5 * avg_monthly_spend_usd THEN TRUE
        ELSE FALSE
    END AS is_extreme_value

FROM enriched_transactions e;

-- VALIDATE FEATURE TABLE

SELECT
    transaction_id,
    txn_count_15m,
    avg_amt_1d,
    geo_mismatch_flag,
    is_new_device,
    is_crypto_txn
FROM txn_features
WHERE initial_decision = 'REVIEW';

-- CREATE FRAUD SIGNAL VIEW

CREATE OR REPLACE VIEW fraud_signals AS
SELECT
    transaction_id,

    -- P-001 signals
    txn_count_15m >= 3 AS s_burst,
    amount_usd < 10 AS s_small_amt,

    -- P-002 signals
    geo_mismatch_flag AS s_geo,

    -- P-003 signals
    is_new_device AS s_new_device,
    is_off_hours AS s_off_hours,

    -- P-004 signals
    is_crypto_txn AS s_crypto,
    is_round_amount AS s_round_amt,

    -- extra signals
    is_extreme_value AS s_high_value

FROM txn_features;

-- QUICK VALIDATION QUERY

SELECT *
FROM fraud_signals;
WHERE transaction_id IN (
    'TXN20260511100',
    'TXN20260511200',
    'TXN20260511500'
);