# Fraud Pattern P-002: Geographic Anomaly / Impossible Travel

**Pattern ID:** P-002
**Category:** Counterfeit / Cloned Card Fraud
**Severity:** HIGH
**Last reviewed:** 2026-02-20

## Signature
A card is used in a location physically incompatible with the cardholder's verified position at the same time, or with their established travel pattern. This typically indicates the card has been cloned (magstripe skimmed or e-commerce credentials leaked) and is being used by a separate party while the customer still possesses the physical card.

## Detection signals
- Transaction country differs from cardholder's home country
- No travel signal in the prior 14 days (no airline, lodging, or rideshare bookings)
- Transaction occurs during cardholder's typical sleeping hours in their home time zone
- IP geolocation places the device in a third country (often Eastern Europe, Southeast Asia, or West Africa proxy locations)
- Single high-value transaction rather than a sequence
- Merchant categories favored: jewelry (MCC 5944), electronics (MCC 5732), forex (MCC 4829), gold dealers

## Heightening factors
- Card was recently used at a known compromised merchant
- A "card present" flag on a foreign POS while the cardholder's device is geolocated at home
- Customer has no prior history of international transactions

## Recommended action when matched
1. Hard decline if pending; chargeback recall if already settled
2. Block the card immediately
3. Verify cardholder location via app push, then SMS, then phone
4. If verified fraud: open a case, file SAFE (Suspicious Activity File Exchange) report, request merchant transaction record
5. Issue a replacement card

## Reference cases
- FC2025-0529 — Kuala Lumpur jewelry while cardholder was in Boston — USD 8,200
- FC2026-0303 — Bangkok jewelry while cardholder was in Chicago — USD 4,850

## False-positive considerations
Frequent international travelers (segment tier PLATINUM with > 4 foreign trips per year) often produce this signal legitimately. Look for corroborating travel evidence in the past 14 days. If the customer's prior month includes an airline transaction whose destination matches the current country, suppress alert unless other signals (new device, proxy IP, atypical merchant) are also present.
