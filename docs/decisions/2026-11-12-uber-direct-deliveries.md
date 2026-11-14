# Doddy can send a package through Uber Direct, after a tap on a card with the exact price and addresses

- **Date:** 2026-11-12
- **Decided by:** owner, 12 Nov 2026: "build the uber delivery feature what i should do next", after creating the Uber developer app `doddy` (API suite "3PL Consumer API", organization linked, agreements signed). Who pays, the caps and going live are **owner approval pending** (OWNER_QUEUE).
- **Status:** step 1 (the server half) in the pull request that adds this file; off until the owner sets the credentials and `UBER_DIRECT_ENABLED=1`. Step 2: the iPhone card and the voice tool. Step 3: live, after Uber approves production access.

## Why
The owner wants Doddy to send things for people ("send these keys to my sister"). Uber Direct is Uber's delivery API: a quote with a price and an expiry, then a delivery with a courier and a tracking link.

What Uber's documentation says, and what is not known yet (read 12 Nov 2026):
- **Uber bills the account holder.** Production access needs billing details on the Uber account; every delivery is charged to it, not to the person who asked. So Doddy pays for every delivery until there is a way to charge users.
- **Built for merchants.** Uber describes Direct for businesses delivering their goods; access "may require written approval from Uber". Person-to-person use by an app like Doddy is not described either way.
- **Poland:** Uber Direct serves merchants in Poland (Uber's own job advert), but no public page confirms the API there. The sandbox will answer it.
- **Two APIs:** the classic `/v1/customers/{customer_id}/delivery_quotes` and `/deliveries` take addresses and phone numbers (used here). The newer `/v1/eats/deliveries/orders` needs a registered Uber store (`store_id`), which a person sending keys doesn't have.

## Decision
1. **A quote first, a delivery only after the tap (DOD-07).** The server prices it and writes the card's lines (who and where from, who and where to, the recipient's number, the items, the note); the tap's hash covers Doddy's id, the price, the currency and those lines (`deliveryApprovalHash`). Anything different is refused.
2. **The courier calls the sender on the account's verified number.** Never a number typed into the card; the recipient's number must be in an allowed country (ADR-704). Polish addresses only for now.
3. **Caps, because Doddy pays:** at most 60 zł a delivery (`UBER_DIRECT_MAX_FEE`), 2 a day per account, 5 a day for the whole server, checked under one lock. A price over the cap is said and can't be confirmed. These are proposals until the owner decides.
4. **`unknown` is never success and never sent again (DOD-08, DOD-09).** Uber gets Doddy's id as `idempotency_key` and `external_id`; an unclear answer stays `unknown` until Uber's own list shows the delivery.
5. **Status and "cancelled" only from Uber's answers.** In test mode every delivery asks for Uber's simulated courier, and a delivery Uber marks live is cancelled at once.
6. **Privacy (DOD-11):** names, addresses, numbers and items are encrypted per row and erased when the delivery ends or the quote lapses. Logs carry ids and codes only. The privacy policy needs a line before step 3: addresses and phone numbers go to Uber.
7. **Off by default:** `UBER_DIRECT_ENABLED=0`, `UBER_DIRECT_MODE=test`.

## Consequences
- Until users pay, every delivery is a cost on the owner's Uber account; the caps bound it (worst case with the defaults: 5 × 60 zł a day).
- Uber may refuse production access for person-to-person sending; then this stays a sandbox demo, or moves to a merchant shape (a shop delivering to a customer).
- Step 2 changes `voice-agent/tools.json` (a tool with `ask: tap`), the live agent (owner's word), and the app (a card in Messages and voice).

## Evidence
`server/messaging/test/deliveries.test.ts` (23 tests: the client against a fake network, the routes against Postgres with a scripted Uber); the whole messaging suite. Not run: anything against Uber itself (no credentials in this session).
