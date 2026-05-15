# Fraud Pattern P-003: Account Takeover (ATO)

**Pattern ID:** P-003
**Category:** Credential / Session Compromise
**Severity:** HIGH
**Last reviewed:** 2026-04-02

## Signature
An attacker gains control of the customer's online banking or wallet credentials (via phishing, credential stuffing, SIM swap, or malware) and uses the legitimate card credentials from a new device. Unlike cloning, the transaction routes through the customer's own account but originates from an attacker-controlled session.

## Detection signals
- Login from a device ID never seen on the account
- Login or transaction during cardholder's typical off-hours (especially 02:00 - 05:00 local time)
- Within 24 hours of any of: password reset, email change, phone number change, new device enrollment, SIM swap notice
- High-value purchase at a merchant the cardholder has never transacted with
- Merchant categories favored: luxury watches and jewelry (MCC 5944), electronics (MCC 5732), money transfer (MCC 4829)
- Shipping address differs from the billing address
- Multiple transactions clustered in a single session, often at distinct merchants

## Recommended action when matched
1. Decline the pending authorization
2. Block all sessions across the customer's accounts
3. Force re-authentication via out-of-band channel (registered phone callback, not SMS)
4. Notify the cardholder by voice call, not email or SMS, since both may be compromised
5. Open ATO investigation case in the fraud-ops queue

## Reference cases
- FC2025-0712 — overnight jewelry purchases from new Windows device — USD 5,670
- FC2026-0421 — luxury watch after ignored SIM swap notice — USD 3,200

## False-positive considerations
A customer who legitimately replaces their phone or laptop will produce a new-device login. The defining marker is the **combination** of new device + off-hours + high-value at unfamiliar merchant. Any one of these alone is not sufficient. The customer-initiated device enrollment (which produces a confirmation event in our auth logs) should suppress the device-novelty signal for 7 days.
