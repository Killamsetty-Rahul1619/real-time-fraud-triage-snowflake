-- ============================================================
-- File: enriched_transactions.sql
-- Purpose:
--   Create an enriched view of transactions by joining
--   customers and merchants, and deriving key fraud signals.
--
-- Notes:
--   This view is used as an analytical and agent-input layer.
--   No data is modified; this is a read-only enrichment.
-- ============================================================


-- ============================================================
-- ENRICHED TRANSACTIONS VIEW
-- ============================================================

CREATE OR REPLACE VIEW enriched_transactions AS
SELECT 
    -- --------------------------------------------------------
    -- CORE TRANSACTION ATTRIBUTES
    -- --------------------------------------------------------
    t.transaction_id,
    t.customer_id,
    t.merchant_id,
    t.amount_usd,
    t.currency,
    t.transaction_ts,
    t.channel,
    t.card_present,
    t.device_id,
    t.ip_address,
    t.ip_country,
    t.mcc_code,
    t.authorization_status,
    t.risk_score,
    t.initial_decision,

    -- --------------------------------------------------------
    -- CUSTOMER CONTEXT
    -- --------------------------------------------------------
    c.full_name,
    c.home_country,
    c.home_city,
    c.customer_tier,
    c.avg_monthly_spend_usd,
    c.account_open_date,

    -- --------------------------------------------------------
    -- MERCHANT CONTEXT
    -- --------------------------------------------------------
    m.merchant_name,
    m.merchant_category,
    m.merchant_risk_rating,
    m.chargeback_rate_pct,
    m.registered_date AS merchant_registered_date,
    m.is_high_risk_category,

    -- --------------------------------------------------------
    -- DERIVED FRAUD SIGNALS
    -- --------------------------------------------------------

    -- Geographic anomaly signal (Fraud Pattern P-002)
    CASE 
        WHEN t.ip_country <> c.home_country THEN TRUE 
        ELSE FALSE 
    END AS geo_mismatch,

    -- New merchant risk signal (merchant age < 12 months)
    CASE 
        WHEN DATEDIFF(month, m.registered_date, t.transaction_ts) < 12 THEN TRUE
        ELSE FALSE
    END AS is_new_merchant,

    -- High-value transaction relative to customer baseline
    CASE 
        WHEN t.amount_usd > 5 * COALESCE(c.avg_monthly_spend_usd, 0) THEN TRUE
        ELSE FALSE
    END AS is_high_value_txn

FROM transactions t
JOIN customers c
    ON t.customer_id = c.customer_id
JOIN merchants m
    ON t.merchant_id = m.merchant_id;


-- ============================================================
-- VALIDATION QUERIES
-- These queries are for manual inspection and debugging
-- ============================================================

-- Preview enriched records
SELECT *
FROM enriched_transactions
LIMIT 20;

-- ------------------------------------------------------------
-- Inspect high-risk review transactions
-- ------------------------------------------------------------
SELECT
    transaction_id,
    customer_id,
    amount_usd,
    geo_mismatch,
    is_new_merchant,
    is_high_value_txn
FROM enriched_transactions
WHERE initial_decision = 'REVIEW';
