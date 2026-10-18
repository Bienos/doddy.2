# Purchases API (ADR-490)

Doddy's own API for paying for things the user asked for. Every route needs the session token, the
user comes from the token only, and nothing here takes a provider name, a Stripe id or a URL to call.
The JSON files in this folder are the shapes the iPhone decodes; the backend tests and the
DoddyCore tests both read them.

## Two kinds of purchase

| Kind | Who is paid | How the user pays | What Doddy can confirm |
|---|---|---|---|
| `native` | Doddy's Stripe account, **test keys only** in this milestone (live keys are refused at start-up) | Apple Pay sheet with Face ID, or a BLIK code approved in the bank app, inside Doddy | Paid, failed or "not sure", read from Stripe by the server |
| `checkout` | The shop itself, on its own checkout page | Inside an in-app Safari view, with whatever the shop offers (Apple Pay, BLIK, card) | Only that the page was opened. "I paid" is the user's own word and is labelled so |

Doddy never holds money for a shop and never charges the user on a shop's behalf (ADR-490).

## Routes

All are `POST` with a JSON body except the list. Errors use the existing error body
(`{"error":{"code","message","correlationId"}}`).

| Route | Body | Answer |
|---|---|---|
| `POST /v1/purchases/prepare` | `PrepareRequest` | `PrepareResult`: the purchase, a single-use approval bound to exactly what the card shows, valid 5 minutes |
| `POST /v1/purchases/pay` | `PayRequest` | `PurchaseResult`. Native only. Uses up the approval |
| `POST /v1/purchases/status` | `{"purchaseId"}` | `PurchaseResult`, re-read from Stripe while paying, waiting for the bank or unsure |
| `POST /v1/purchases/cancel` | `{"purchaseId"}` | `PurchaseResult`. Before paying, or while BLIK waits for the bank |
| `POST /v1/purchases/handoff` | `{"purchaseId","approvalId"}` | `HandoffResult`. Checkout only. Uses up the approval and returns the page to open |
| `POST /v1/purchases/report` | `{"purchaseId","paid":true|false}` | `PurchaseResult`. Checkout only, after the hand-off: the user's own answer |
| `GET /v1/purchases` | none | `{"purchases":[PurchaseView]}`, newest first, the last 90 days, at most 50 |

## Types

`PrepareRequest`
- `kind`: `"native"` or `"checkout"`
- `merchantName`: 1 to 80 characters, the shop or service the user asked for
- `description`: 1 to 200 characters, what is bought ("2 tickets, Friday 19:30")
- `amountMinor`: whole grosze. Native: 200 (2 zł, Stripe's PLN minimum) to the per-purchase cap. Checkout: 1 to the cap (an expected price; the shop's page shows the real one)
- `currency`: `"PLN"` only in this milestone
- `checkoutUrl`: checkout only, required there and refused for native. `https`, at most 2048 characters, no user name or password, not an IP address; when the server has a shop allowlist, the host must be on it

`PayRequest`
- `purchaseId`, `approvalId`: from `PrepareResult`
- `method`: `"apple_pay"` or `"blik"`
- `applePay` (Apple Pay only): `paymentData` (the `PKPaymentToken.paymentData` bytes as a UTF-8 string; may be empty only with test keys, in the simulator), `network`, `instrumentName`, `transactionId`
- `blikCode` (BLIK only): exactly six digits. Never stored or logged

`PurchaseView`
- `id`, `kind`, `merchantName`, `description`, `amountMinor`, `currency`
- `checkoutHost`: checkout only, the host of the page that opens
- `status`: one of
  - `awaiting_tap`: prepared, nothing paid
  - `paying`: sent to Stripe, no answer yet
  - `waiting_for_bank`: BLIK sent, the user approves in the bank app
  - `paid`: Stripe says the payment succeeded
  - `failed`: Stripe says it did not go through, or it was never sent. Nothing was charged
  - `outcome_unknown`: sent, but Doddy can't tell yet whether it went through. Never shown as paid, never retried by itself
  - `cancelled`: the user said no, or cancelled while the bank waited
  - `expired`: the approval ran out before payment
  - `handed_off`: checkout page opened; Doddy can't see what happened there
  - `user_reported_paid`: after a hand-off, the user said they paid. Doddy did not confirm it
- `method`: `"apple_pay"`, `"blik"` or null
- `testMode`: true for native purchases on test keys or in mock mode
- `summary`: one plain sentence for the screen and the voice agent, e.g. "Paid 56,00 zł with Apple Pay (test mode, no real money)."
- `createdAt`, `updatedAt`: ISO 8601

`PrepareResult`: `mode` (`"mock"` or `"test"`), `purchase`, `approvalId`, `expiresAt`, `methods` (`["apple_pay","blik"]` for native, `[]` for checkout), `payee` (the name on the Apple Pay sheet for native, the page's host for checkout)

`PurchaseResult`: `mode`, `purchase`

`HandoffResult`: `mode`, `purchase`, `checkoutUrl`

## Limits (server settings)
- `DODDY_PURCHASE_MAX_MINOR` (default 20000, 200 zł) per purchase
- `DODDY_PURCHASE_DAILY_MAX_MINOR` (default 50000, 500 zł) per user per UTC day, counting everything paid, paying, waiting for the bank, unsure, handed off or reported paid
- `DODDY_LIMIT_USER_DAILY_PURCHASES` (default 10) prepares per user per UTC day
- `DODDY_CHECKOUT_HOSTS`: optional comma-separated allowlist of checkout hosts
