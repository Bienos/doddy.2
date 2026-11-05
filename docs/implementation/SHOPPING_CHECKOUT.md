# Shopping stage 3: buying through Doddy (design, and the rules as typed code)

**Status, 24 Oct 2026: designed, with the safety rules built and tested; nothing can be bought.** Owner, 24 Oct 2026: "Zacząć płatności w aplikacji" (start in-app payment). What exists: `Packages/DoddyCore/Sources/DoddyCore/Checkout.swift` (the exact-cart digest, the order's statuses and the rule that an order is sent once), its 10 tests, the fixture `schemas/fixtures/checkout_draft_v1.json`, and this page. What does **not** exist: a payment provider, a shop that accepts orders from Doddy, a server route, an app screen, a voice tool, or any way to send an order. No money moves. Until the gates in section 2 are open this must not be called "payments".

The BLIK transfer drafts (ADR-510, ADR-541) stay separate: Doddy prepares them and the user sends them in the bank app. They are not extended to shopping.

## 1. What it is, and what it isn't

**Goal.** The user says yes to an exact cart. An Apple Pay sheet shows the shop as the merchant. The order goes to the shop through a purchasing protocol. Doddy says "ordered" only when the shop confirms with its own order reference.

**Not:** Doddy as the seller, a wallet, or anything holding the user's money (that needs a payment-services licence; research `docs/research/2026-10-24/research_shopping_payments.md`); card numbers anywhere in Doddy; BLIK until a protocol supports it; buying from a shop that has no agreement; buying while the user isn't there.

## 2. Why this can't go live from code alone (the gates)

| Gate | What has to exist | Whose step |
|---|---|---|
| G1 A provider | Access to a purchasing protocol for assistants. Today that is Stripe's agent-payment tools: private preview, Poland listed, cards and Apple Pay, **no BLIK** (research, 24 Oct). | Owner: ask Stripe for access; a Stripe account for Doddy |
| G2 A shop | Each seller on the provider with a written agreement with Doddy. No Polish shop is known to accept orders from outside assistants yet. At least one pilot shop. | Owner |
| G3 Apple | Doddy as "Intermediary Party" (Developer Program License Agreement §3.3.9(C)): says so, shows the real merchant on the Apple Pay sheet, never uses payment data for marketing or profiles, has a written agreement with each merchant. Native in-app Apple Pay needs each merchant's own Apple developer account. | Owner |
| G4 Law | A Polish lawyer on the payment-services act (the agent exclusion and what counts as holding funds), who is the seller, the 14-day withdrawal and complaints, and the Terms and Privacy wording. | Owner |
| G5 App Review | Guideline 4.9 (all material purchase information before paying) and 3.1.3(e) (physical goods are paid outside in-app purchase). | Built to it; reviewed on submission |
| G6 Ceiling | Doddy's own limit for one order. The code has a placeholder of 5,000 zł (`CheckoutDraft.maxTotalMinor`); a guard against a misheard amount, not a bank's limit. | Owner decides |

## 3. The flow it is built for

1. A result card offers "Kup przez Doddy'ego" only for an offer from a connected shop. Everything else keeps "Kup w sklepie" (the shop's own page; ADR-610).
2. Doddy's server asks the shop, through the provider, for a quote. The quote becomes a `CheckoutDraft`: shop and host, lines, shipping, total, the shop's own reference for this cart, when the quote lapses.
3. The card shows exactly that cart. The user's tap approves **this digest** (ASK-01: a tap on a card with the exact payload; one yes covers one order).
4. The tap opens the Apple Pay sheet. The sheet's own authentication is the payment consent. The payment token goes to the provider for that shop reference; Doddy never sees card data. The order is handed to the provider **once**.
5. The shop's confirmation comes back as a signed webhook with the shop's order reference. Only then the card and the voice agent say "ordered".
6. Without a trustworthy answer (no webhook in time, a lost connection, a server error, an unreadable answer, a confirmation with no reference) the order is `unknown`: not success, not failure, never sent again. Doddy says it doesn't know, tells the user to check the shop's email or their bank, and only looks the order up (read-only) afterwards.

## 4. The rules, as built (DoddyCore, Linux-tested; platforms: iPhone, Watch and Mac all compile this package, none use it yet)

| Rule | Where | Test |
|---|---|---|
| The yes is bound to the exact cart: SHA-256 of its canonical form; any change to a quantity, price, shipping, shop, host, reference or quote is a different digest | `CheckoutDraft.digest` | `testTheDigestIsTheFixturesCanonicalString…` (the fixture's digest was computed with Python), `testAnyChangeToTheCartIsADifferentDigest` |
| A cart that doesn't add up, has a bad quantity, price, currency or host, is empty, is over the ceiling or has an unreadable expiry can't be shown for approval or sent | `validationIssues()` | `testACartThatCantBeShownIsRefusedWithTheReason` |
| Approval needs the digest of the cart that was shown, an unexpired quote and a valid cart, and works once | `CheckoutSession.approve` | `testApprovalNeedsTheDigest…`, `testAnExpiredQuote…` |
| The order is handed to the provider at most once (`timesSent` is 0 or 1) | `approve` is the only move that sends | the same tests, and `testNoTrustworthyAnswerIsUnknown…` |
| "Ordered" only with the shop's confirmation **and** an order reference | `sendFinished`, `agentWords` | `testOnlyAConfirmationWithAnOrderReferenceIsOrdered`, `testOnlyConfirmedWordsAllowOrdered` |
| No trustworthy answer is `unknown`; it is never success, never failure and never sent again; only a read-only look-up can settle it | `sendFinished`, `reconcile` | `testNoTrustworthyAnswerIsUnknownNeverSuccessAndNeverSentAgain`, `testReconcilingOnlyAppliesToAnUnknownOrder` |
| Once sent, the order can't be cancelled from here | `cancel` | `testANoBeforeTheTap…` |

The statuses are the constitution's (`docs/trust/config/doddy_rules.yaml`, `action_policy`): needs approval, executing, confirmed, failed, unknown, cancelled.

## 5. Failure and recovery

| What goes wrong | What happens |
|---|---|
| The quote lapses before the tap | Approval is refused; Doddy asks the shop for a new quote and the user sees a new card |
| The cart changed after the card was shown | A different digest: the old tap can't approve it |
| The connection drops after the order was sent | `unknown`; Doddy says so and looks it up, never resends |
| The shop confirms with no reference | Treated as no trustworthy answer: `unknown` |
| A look-up finds the order | `confirmed` with the reference; if it finds it was declined, `failed` |
| The user says no | `cancelled`, nothing sent |

## 6. Privacy (design)

The cart (shop, items, prices, the shop's reference) goes between this iPhone, Doddy's server, the provider and the shop. The Apple Pay token goes straight to the provider. The delivery address comes from the Apple Pay sheet and goes to the shop through the provider; Doddy's server is not meant to keep it. Doddy keeps the digest, the status and the order reference, encrypted, on the account until the app has saved them, like an errand's result (ERRANDS.md). Never card data. `What leaves this iPhone` must list it before the first order, and the Terms and Privacy pages must name the provider.

## 7. Switch and rollout

A server switch `CHECKOUT_ENABLED`, off by default, when the route exists. First test mode only (the provider's test keys, test cards, a test shop), then a pilot shop with the owner's own card, then the release criteria in `docs/trust/05_RELEASE_CRITERIA_AND_METRICS.md` and a constitution evidence log. A tool for the voice agent only after that, with the ask card.

## 8. What I need from the owner

1. Request access to Stripe's agent-payment tools for Doddy, and say whether Doddy has a Stripe account yet (G1).
2. Name a pilot shop, or say how shops are found (G2).
3. Confirm the Apple Developer account that would hold the Apple Pay merchant setup, and who signs the Intermediary agreement (G3).
4. A Polish lawyer's opinion on G4.
5. The ceiling per order (G6).

## 9. Build order once the gates open

1. A provider adapter behind an interface, with a fake in tests (no live call in CI).
2. Server routes for quote, approve (digest-bound, like errands), status and the webhook, with signature checking and an idempotency key per cart.
3. The card in the app and Apple Pay (PassKit) in test mode on a device.
4. The read-only look-up for `unknown`.
5. End to end in test mode on the Mac job, then the evidence log and the legal review.

## Not checked

Nothing here has talked to a provider, a shop or Apple. The rules are tested as Swift on Linux only. The ceiling is a placeholder. Whether any Polish shop will accept orders from Doddy is unknown.
