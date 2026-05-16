# Fraud Pattern P-005: Frequent Traveler — False Positive Suppression

**Pattern ID:** P-005
**Category:** False-Positive Suppression Rule
**Severity:** N/A (suppression rule)
**Last reviewed:** 2026-01-30

## Purpose
This document describes the corroborating evidence required to suppress geographic-anomaly alerts (Pattern P-002) when the cardholder is on legitimate international travel. Approximately 38% of geographic-anomaly alerts in our portfolio are false positives driven by frequent travelers, so accurate suppression is essential to reduce review queue load.

## Suppression criteria — all of the following must hold

### 1. Established travel pattern
The customer's tier is GOLD or PLATINUM **and** has at least 3 prior cross-border transactions in the past 12 months.

### 2. Corroborating travel signal in the past 14 days
At least one of:
- A successful authorization at an airline merchant (MCC 3000-3299, 4511) where the destination city matches the country of the current alerted transaction
- A hotel authorization (MCC 3501-3999, 7011) in the same country as the alerted transaction
- A rideshare transaction (MCC 4121) in the same country in the prior 72 hours

### 3. Device continuity
The device ID on the alerted transaction matches a device that has been used on the account for at least 30 days.

### 4. No proxy / VPN indicator
The IP address on the alerted transaction does not match any of: known TOR exit nodes, datacenter IP ranges, commercial VPN providers.

## Decision
- All four criteria satisfied → **SUPPRESS** the alert and approve the transaction
- Three of four criteria satisfied → reduce risk score by 30 points and route to standard review
- Two or fewer satisfied → no suppression; treat as Pattern P-002

## Reference cases
- Suppression analysis monthly report — see Cortex Search index `FRAUD_OPS.DOCS.FRAUD_PATTERN_INDEX` for the rolling FP rate
- Audit sample of 500 alerts, March 2026: applying this rule reduced FP rate from 38% to 11% while missing zero true-positive cases

## Notes for the agent
When you encounter a geographic-anomaly signal, always check this suppression rule before escalating. The travel signal need not be on the same card; check any card belonging to the same customer.
