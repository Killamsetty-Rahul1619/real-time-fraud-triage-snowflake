# Fraud Pattern P-004: Authorized Push Payment to Crypto (Scam Victim)

**Pattern ID:** P-004
**Category:** Authorized Push Payment Fraud (Scam Victim)
**Severity:** MEDIUM-HIGH
**Last reviewed:** 2026-04-25

## Signature
The cardholder themselves initiates a transaction to a cryptocurrency exchange or money-transfer merchant, but is doing so under the influence of a third-party scam (investment scam, romance scam, impersonation scam, employment scam). The transaction is **authenticated by the genuine customer** which makes it technically authorized, but the customer is a victim of social engineering.

## Detection signals
- First-ever transaction to a cryptocurrency merchant (MCC 6051) or money transfer service (MCC 4829)
- Transaction amount is a round number (e.g. USD 2,000 / 5,000 / 10,000)
- Customer demographic profile not typically associated with crypto investing (e.g. retiree, very young new-account holder)
- Funds transferred to the customer's account from a savings or external source in the 48 hours prior
- Multiple smaller transactions over days rather than a single large one
- Customer attempted the same transaction earlier and it was declined for limit reasons

## Recommended action when matched
1. **Do not auto-decline** — the customer authorized the transaction
2. Insert a friction step in the payment flow: a scam-awareness interstitial in the mobile app
3. Outbound call from the fraud team within 1 hour of the transaction
4. Provide the customer with reporting resources (FTC / Action Fraud / local equivalent)
5. Log a scam-victim flag on the account; subsequent crypto transactions should re-trigger the interstitial for 90 days

## Reference cases
- FC2026-0505 — USD 6,500 to crypto exchange after a romance scam

## False-positive considerations
Legitimate crypto investing is increasingly common, especially among customers aged 25-45. The defining marker is the **combination** of: first-ever crypto, atypical demographic, recent inbound funding to the source account, and round-number amount. Two or fewer signals = legitimate trader. Three or more = probable scam victim. Treat with empathy regardless of outcome — these customers are victims, not perpetrators.  
