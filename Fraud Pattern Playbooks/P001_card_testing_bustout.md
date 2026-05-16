# Fraud Pattern P-001: Card Testing Followed by Bust-Out

**Pattern ID:** P-001
**Category:** Card-Not-Present (CNP) Fraud
**Severity:** HIGH
**Last reviewed:** 2026-03-15

## Signature
Fraudsters who have purchased or stolen a batch of card numbers will first verify which cards are still active before attempting any large-value transaction. The verification phase is characterized by a sequence of micro-charges at low-friction merchants. Once a card responds with an authorization, the same card is hit with a large charge within minutes.

## Detection signals
- 3 or more transactions on the same PAN within a 15-minute window
- Individual amounts under USD 10, often ending in .99 or .49
- Merchants in **MCC 5815** (digital downloads), **MCC 5816** (game vouchers), or **MCC 5967** (direct marketing — outbound telemarketing)
- Merchant in a different country than the cardholder's billing country
- IP address from a hosting/VPN range or a country mismatched with the cardholder
- Device ID not previously seen on the account
- All transactions in card-not-present (CNP) channel
- A final transaction with amount > 50x the average of the testing burst

## Typical merchant clusters
- Cyprus, Malta, Isle of Man, and Gibraltar registered digital goods merchants
- Newly registered merchants (< 12 months) with elevated chargeback rates
- Gaming top-up resellers in Southeast Asia

## Recommended action when matched
1. Decline the largest pending authorization
2. Freeze the card and issue a replacement
3. Reverse-charge all successful test transactions
4. Notify the cardholder via the registered mobile number (not email — assume email is compromised)
5. Escalate to the fraud analyst queue with priority FRAUD-HIGH

## Reference cases
- FC2025-0411 — confirmed loss USD 3,450
- FC2026-0208 — confirmed loss USD 2,890

## False-positive considerations
A legitimate customer trialing a new subscription service may produce two or three small charges. The defining marker is the **bust-out transaction** within the same 30-minute window. Without the large follow-on, treat as low-priority review.
