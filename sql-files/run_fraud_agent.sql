-- ============================================================
-- File: run_fraud_agent.sql
-- Purpose:
--   Stored procedure that simulates a fraud triage agent.
--   It consumes records from triage_stream, applies
--   rule-based pattern logic, records decisions, and
--   triggers downstream actions.
--
-- Notes:
--   - This is a procedural simulation of agent behavior
--   - Decisions are logged to agent_decisions (audit)
--   - Side effects are written to queue tables
-- ============================================================


-- ============================================================
-- ACTION & AUDIT TABLES
-- Must exist before the procedure runs
-- ============================================================

CREATE OR REPLACE TABLE card_action_queue (
    action_id STRING DEFAULT UUID_STRING(),
    transaction_id STRING,
    customer_id STRING,
    action_type STRING,
    reason STRING,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
);

CREATE OR REPLACE TABLE slack_outbox (
    message_id STRING DEFAULT UUID_STRING(),
    transaction_id STRING,
    message STRING,
    priority STRING,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
);

CREATE OR REPLACE TABLE agent_decisions (
    transaction_id STRING,
    decision VARIANT,
    decision_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
    parsed_decision STRING,
    confidence NUMBER,
    pattern_matched STRING
);


-- ============================================================
-- FRAUD AGENT PROCEDURE
-- ============================================================

CREATE OR REPLACE PROCEDURE run_fraud_agent()
RETURNS STRING
LANGUAGE SQL
AS
$$

DECLARE 
    -- Core identifiers
    v_txn STRING;
    v_customer STRING;

    -- Decision outputs
    v_decision STRING;
    v_confidence NUMBER;
    v_pattern STRING;
    v_reason STRING;
    v_tools ARRAY;

    -- Feature inputs
    v_cnt NUMBER;
    v_amt NUMBER;
    v_new_device BOOLEAN;
    v_off_hours BOOLEAN;
    v_geo BOOLEAN;
    v_crypto BOOLEAN;
    v_round BOOLEAN;
    v_extreme BOOLEAN;

    -- Simulated enrichment flags
    v_has_travel_history BOOLEAN;
    v_recent_travel BOOLEAN;
    v_same_device BOOLEAN;

    -- Cursor over triage stream
    c1 CURSOR FOR
        SELECT * FROM triage_stream;

BEGIN

FOR rec IN c1 DO

    -- --------------------------------------------------------
    -- ASSIGN INPUT VALUES
    -- --------------------------------------------------------
    v_txn := rec.transaction_id;
    v_customer := rec.customer_id;

    v_amt := rec.amount_usd;
    v_cnt := rec.txn_count_15m;
    v_new_device := rec.is_new_device;
    v_off_hours := rec.is_off_hours;
    v_geo := rec.geo_mismatch_flag;
    v_crypto := rec.is_crypto_txn;
    v_round := rec.is_round_amount;
    v_extreme := rec.is_extreme_value;

    -- Simulated attributes (not fully modeled)
    v_has_travel_history := FALSE;
    v_recent_travel := FALSE;
    v_same_device := NOT v_new_device;

    -- --------------------------------------------------------
    -- DEFAULT DECISION (SAFE FALLBACK)
    -- --------------------------------------------------------
    v_decision := 'ESCALATE';
    v_confidence := 60;
    v_pattern := 'NONE';
    v_reason := 'No strong fraud pattern match';

    v_tools := ARRAY_CONSTRUCT(
        'transaction_history_analyst',
        'fraud_pattern_search'
    );

    -- --------------------------------------------------------
    -- P-003: ACCOUNT TAKEOVER (STRICT)
    -- --------------------------------------------------------
    IF (v_new_device = TRUE AND v_off_hours = TRUE AND v_extreme = TRUE) THEN

        v_pattern := 'P-003';
        v_decision := 'AUTO_BLOCK';
        v_confidence := 95;
        v_reason := 'New device, off-hours, and extreme value indicate account takeover';

    -- --------------------------------------------------------
    -- P-002: GEOGRAPHIC ANOMALY
    -- --------------------------------------------------------
    ELSEIF (v_geo = TRUE AND v_extreme = TRUE AND v_new_device = TRUE) THEN

        v_pattern := 'P-002';

        IF v_off_hours = TRUE THEN
            v_confidence := 93;
            v_reason := 'Geo mismatch with high value during off-hours suggests fraud';
        ELSE
            v_confidence := 90;
            v_reason := 'Geographic anomaly with high value and unknown device';
        END IF;

        IF v_confidence >= 90 THEN
            v_decision := 'AUTO_BLOCK';
        ELSE
            v_decision := 'ESCALATE';
        END IF;

    -- --------------------------------------------------------
    -- P-001: CARD TESTING
    -- --------------------------------------------------------
    ELSEIF (v_cnt >= 3 AND v_amt < 10 AND v_new_device = TRUE) THEN

        v_pattern := 'P-001';
        v_decision := 'AUTO_BLOCK';
        v_confidence := 92;
        v_reason := 'Burst of low-value transactions indicates card testing';

    -- --------------------------------------------------------
    -- P-004: CRYPTO SCAM (ESCALATE ONLY)
    -- --------------------------------------------------------
    ELSEIF (v_crypto = TRUE AND v_round = TRUE) THEN

        v_pattern := 'P-004';
        v_decision := 'ESCALATE';
        v_confidence := 80;
        v_reason := 'Crypto transaction with round amount suggests scam risk';

    -- --------------------------------------------------------
    -- P-005: FREQUENT TRAVEL SUPPRESSION
    -- --------------------------------------------------------
    ELSEIF (
        v_geo = TRUE
        AND v_same_device = TRUE
        AND v_off_hours = FALSE
        AND v_has_travel_history = TRUE
        AND v_recent_travel = TRUE
    ) THEN

        v_pattern := 'P-005';
        v_decision := 'DISMISS';
        v_confidence := 85;
        v_reason := 'Geographic change aligns with known travel behavior';

    END IF;

    -- --------------------------------------------------------
    -- AUDIT: UPSERT AGENT DECISION
    -- --------------------------------------------------------
    MERGE INTO agent_decisions tgt
    USING (
        SELECT 
            :v_txn AS transaction_id,
            OBJECT_CONSTRUCT(
                'decision', :v_decision,
                'confidence', :v_confidence,
                'pattern_matched', :v_pattern,
                'justification', :v_reason,
                'tools_used', :v_tools
            ) AS decision_json,
            :v_decision AS parsed_decision,
            :v_confidence AS confidence,
            :v_pattern AS pattern_matched
    ) src
    ON tgt.transaction_id = src.transaction_id

    WHEN MATCHED THEN UPDATE SET
        tgt.decision = src.decision_json,
        tgt.decision_time = CURRENT_TIMESTAMP(),
        tgt.parsed_decision = src.parsed_decision,
        tgt.confidence = src.confidence,
        tgt.pattern_matched = src.pattern_matched

    WHEN NOT MATCHED THEN INSERT
    VALUES (
        src.transaction_id,
        src.decision_json,
        CURRENT_TIMESTAMP(),
        src.parsed_decision,
        src.confidence,
        src.pattern_matched
    );

    -- --------------------------------------------------------
    -- SIDE EFFECTS (QUEUED ACTIONS)
    -- --------------------------------------------------------
    IF (v_decision = 'AUTO_BLOCK' AND v_confidence >= 90) THEN
        INSERT INTO card_action_queue
        SELECT
            UUID_STRING(),
            :v_txn,
            :v_customer,
            'BLOCK_CARD',
            :v_reason,
            CURRENT_TIMESTAMP();
    END IF;

    IF (v_decision = 'ESCALATE') THEN
        INSERT INTO slack_outbox
        SELECT
            UUID_STRING(),
            :v_txn,
            :v_reason,
            'HIGH',
            CURRENT_TIMESTAMP();
    END IF;

END FOR;

RETURN 'Agent run completed';

END;
$$;


-- ============================================================
-- DEVELOPMENT UTILITIES
-- ============================================================

TRUNCATE TABLE agent_decisions;
TRUNCATE TABLE card_action_queue;
TRUNCATE TABLE slack_outbox;

CALL run_fraud_agent();

-- ============================================================
-- INSPECTION QUERIES
-- ============================================================

SELECT
    transaction_id,
    parsed_decision,
    confidence,
    pattern_matched,
    decision
FROM agent_decisions
ORDER BY transaction_id;

SELECT * FROM card_action_queue;
SELECT * FROM slack_outbox;
