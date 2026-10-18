# Payments: Apple Pay, BLIK and the shop's checkout (ADR-490)

Status 2026-10-18. Owner: "connect it with Doddy, I want a seamless Apple Pay experience or BLIK for Doddy to pay for stuff", then chose **both** ways below and a PR. This page says what is built, what is only written, and what has to happen before real money moves.

## What the user sees

1. They say what to buy. The agent calls `prepare_purchase` (only if Settings › Connections › **Payments** is on; it starts off like every connection).
2. Doddy's server checks it against the limits and keeps the purchase with a **single-use approval bound to exactly what the card shows**, valid 5 minutes. Only then does the **Buy card** appear: shop, what is bought, price, and who is paid.
3. One of two kinds:
   - **Native** (test mode only in this milestone): **Apple Pay** (one tap, Face ID) or a **BLIK** code typed on the card and approved in the bank app. The payment goes to Doddy's Stripe account on **test keys**; the card says "Test · no real money" and the Apple Pay sheet says "Doddy (test)", never the shop's name.
   - **Checkout**: "Open the shop's checkout" shows the shop's own page in Safari's view inside Doddy. The user pays the shop there with whatever it offers (Apple Pay works in Safari's view). Doddy can't see the page; afterwards the card asks "Did you pay?" and records the answer as the user's own.
4. The agent hears the result once: `paid:` (Stripe confirmed it through Doddy's server), `opened:` (checkout page opened; never "paid"), `declined:`, `failed:` (nothing paid) or `unknown:` (may have gone through; the user is asked to check their bank app and nothing is tried again). The card stays as a receipt with "Check again" while the outcome is unknown.
5. "What Doddy did" gets a row: "Pay for something" or "Open a checkout", with the shop and the price or the page's host. Never a card number, token or BLIK code.

## Why it is built this way

From the payments research (owner's doc "Doddy Payments Research", 2026-10-18, with sources):
- **App Store:** real-world goods and services must not use In-App Purchase (guideline 3.1.3(e), page updated 2026-10-16); Apple Pay or card entry is the way.
- **Who is paid:** Doddy must not charge the user and then pay a shop itself. That looks like money remittance under PSD2 (a payment-institution licence, UUP art. 150 fines), Stripe restricts it as payment facilitation, and Apple's acceptable-use rules ban a substitute merchant of record. So: test payments to Doddy now, the shop's own checkout for real purchases, and later Stripe Shared Payment Tokens (the shop charges) or Apple's Pay-on-behalf delegate API.
- **SCA:** each tapped purchase is customer-initiated and needs strong customer authentication. Apple Pay's Face ID and the bank-app BLIK approval are that; Doddy's own Face ID prompt would not be.
- **Apple Pay rule:** a saved Apple Pay method may not be charged while the user is in the flow, so every purchase shows a fresh Apple Pay sheet.
- **No Stripe SDK in the app:** its networking and telemetry would break the capability guard's "the app talks only to Doddy's server" claim. The phone passes the Apple Pay token to Doddy's server, which creates the payment with Stripe using the same token parameters Stripe's own SDK sends (`pk_token…`, read in stripe-ios `Token+API.swift`).

## What is built

| Part | Where | State |
|---|---|---|
| API contract and fixtures | `contracts/purchases/` | Written; both sides decode the same JSON |
| Server: prepare, pay (Apple Pay, BLIK), status, cancel, hand-off, report, list; limits; approvals; Stripe over HTTPS; mock gateway | `backend/src/payments/` | Built; tested offline with a mock gateway and a fake Stripe (see the PR) |
| Rules with no UI: contract types, client, price format, BLIK code, checkout link check, voice tool parsing, replies | `Packages/DoddyCore/Sources/DoddyCore/Payments/` | Written with tests (`PaymentsTests.swift`); **not compiled here** (no Swift on this machine); CI runs them on the PR |
| Buy card, Apple Pay sheet, Safari checkout, BLIK wait, receipt | `DoddyApp/Features/Payments/` | Written; **not compiled or run** |
| Voice controller and screen | `VoiceSessionController`, `VoiceView` | `.purchase` card, `prepare_purchase` routing |
| Settings switch | Connections › Money › Payments | Off by default |
| Voice agent spec | `voice-agent/tools.json`, `instructions.md` | `prepare_purchase` added, `elevenlabs_tool_id: not_synced` |
| Apple Pay entitlement | `Config/Doddy-AppGroup-ApplePay.entitlements`, `DODDY_APPLE_PAY_MERCHANT_ID` | Off by default; BLIK and checkout work without it |
| Guard | `scripts/check_forbidden_capabilities.sh` | PassKit only in `ApplePayPresenter.swift`; Safari's view only in `CheckoutBrowser.swift` (plus the sign-in file); Stripe only in `backend/src/payments/stripe.ts` |

## To try it (owner)

**Demo, no Stripe:** run the backend in mock mode (`DODDY_MODE=mock`), point Settings › Connected apps at it, turn on Settings › Connections › Payments, and ask "test paying 10 złoty for coffee at Doddy Café". Apple Pay always succeeds, BLIK code `000000` is declined, any other code waits about 3 seconds then succeeds.

**Stripe test mode:** set `STRIPE_SECRET_KEY` to a **test** key (`sk_test_…` or `rk_test_…`; live keys stop the server) on the backend in live mode, and turn on BLIK in the Stripe Dashboard (it needs a Polish Stripe account). Use Stripe's test BLIK codes.

**Apple Pay on a device:** paid team only. Register a merchant ID, make its payment processing certificate from the request in Stripe's Dashboard (Settings › Payment methods › Apple Pay), set `DODDY_APPLE_PAY_MERCHANT_ID` and `DODDY_APP_ENTITLEMENTS = Config/Doddy-AppGroup-ApplePay.entitlements`, rebuild. In the simulator Apple Pay returns an empty token; the server then uses Stripe's `tok_visa` (test keys only).

**Voice agent:** sync `prepare_purchase` to the live ElevenLabs agent (`voice-agent/README.md`) and replace `not_synced` with its id. Until then only the OpenAI Realtime voice (which reads `tools.json`) can call it.

## Not done, and before real money

- **Live payments are blocked on purpose** (config refuses live keys). Before switching: a Polish counsel's opinion on the no-licence model, Stripe's view of Doddy's business (intermediaries can't use reusable BLIK; P24 bans marketplaces), terms of service with a liability cap, a DPIA, and the AI Act Art. 50 disclosure checked.
- **Real shops in-app** need either Stripe Shared Payment Tokens (preview, Poland included; ask Stripe for access) or Apple's delegate entitlement (iOS 26.4; ask Apple who qualifies). The card and server were shaped so the payee can change without the user flow changing.
- **Not verified:** Stripe accepting `pk_token` from a server with a secret key (Stripe's SDK sends it with a publishable key); a test-mode run against Stripe; BLIK's `requires_action` → succeeded transition on a real test account; any Swift compile; the card on a device at large Dynamic Type; VoiceOver; the Apple Pay sheet.
- **Translations:** the card is in English and Polish; the eight draft languages show it in English. Server summaries are English.
- **Webhooks:** none. Status is read from Stripe when the card or "Check again" asks, which is enough for one user on test keys.
