CREATE OR REPLACE VIEW enriched_transactions AS
SELECT 
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

    -- CUSTOMER DATA
    c.full_name,
    c.home_country,
    c.home_city,
    c.customer_tier,
    c.avg_monthly_spend_usd,
    c.account_open_date,

    -- MERCHANT DATA
    m.merchant_name,
    m.merchant_category,
    m.merchant_risk_rating,
    m.chargeback_rate_pct,
    m.registered_date AS merchant_registered_date,
    m.is_high_risk_category,

    -- KEY DERIVED SIGNALS

    -- GEO ANOMALY SIGNAL (P-002)
    CASE 
        WHEN t.ip_country != c.home_country THEN TRUE 
        ELSE FALSE 
    END AS geo_mismatch,

    -- NEW MERCHANT SIGNAL
    CASE 
        WHEN DATEDIFF(month, m.registered_date, t.transaction_ts) < 12 THEN TRUE
        ELSE FALSE
    END AS is_new_merchant,

    -- HIGH VALUE RELATIVE TO CUSTOMER
    CASE 
        WHEN t.amount_usd > 5 * COALESCE(c.avg_monthly_spend_usd, 0) THEN TRUE
        ELSE FALSE
    END AS is_high_value_txn

FROM transactions t
JOIN customers c
  ON t.customer_id = c.customer_id
JOIN merchants m
  ON t.merchant_id = m.merchant_id;

-- VALIDATE ENRICHED VIEW

SELECT *
FROM enriched_transactions
LIMIT 20;

-- UNDERSTAND YOUR DATA(Testing)

SELECT
    transaction_id,
    customer_id,
    amount_usd,
    geo_mismatch,
    is_new_merchant,
    is_high_value_txn
FROM enriched_transactions
WHERE initial_decision = 'REVIEW';