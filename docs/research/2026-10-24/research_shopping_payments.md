# Shopping mode: paying inside Doddy with Apple Pay or BLIK (24 Oct 2026)

Research for the shopping-mode proposal (`docs/strategy/TRYB_ZAKUPOW_2026-10.md`). All sources checked 2026-10-24 by a research agent in this session. Tags: **[V]** read on the source page, **[S]** secondary source or search snippet, **[I]** inference. Not legal advice: a Polish lawyer must confirm the regulatory points before anything beyond the hand-off is built.

## Apple

- **No in-app purchase for physical goods.** Guideline 3.1.3(e): physical goods and real-world services are paid with something other than IAP, such as Apple Pay or card entry [V, 1].
- **Everything before the sale.** Guideline 4.9: the user sees all material purchase information before paying [V, 1]. The guidelines (updated 16 Oct 2026) say nothing about AI agents buying for users [V, 1].
- **Regulated services.** Guideline 5.1.1(ix): an app offering regulated financial services is submitted by the legal entity that provides them [V, 1].
- **Two Apple Pay roles** (Developer Program License Agreement, 18 Aug 2026, §3.3.9(C)): the app is the **Merchant**, or an **Intermediary Party** passing payment data to the real merchant [V, 2]. An intermediary names itself as such and shows the merchant on the Apple Pay sheet, never uses payment data for marketing or profiles, has a written agreement with the merchant and is liable to Apple for it.
- **Hosting a shop's checkout** in a web view: the app must not touch the Apple Pay payment data at all [V, 2].
- Apple's platform-integration tool "cannot be used for native in-app integrations": inside an app, each merchant needs its own Apple developer account [V, 3]. iOS 16+ can pay several merchants on one sheet [S, 4]. On the web, Apple Pay may not be used with a "substitute merchant of record" [V, 5].
- The EU NFC/HCE commitments (2024) cover in-store tap-to-pay, not in-app checkout [S, 6].

## BLIK

- **Not inside Apple Pay.** BLIK tap-to-pay on iPhone is a separate pilot: first payment 30 Jul 2026 (PKO Junior), wide rollout "at least several months" away [V, 7].
- **In apps:** the 6-digit code ("Level 0"), OneClick (the bank remembers the shop), recurring payments in models A, M, O [V, 8].
- **Stripe:** one-time BLIK and Connect [V, 9]; recurring (Model O) PLN only, max 2,000 zł per charge, listed banks only, not for "payment-intermediary services" businesses [V, 10].
- **BLIK for AI agents: pilots only.** Polski Standard Płatności and PPRO announced a partnership on 12 Aug 2026, no protocol or date [V, 11]. The first agent-initiated purchase paid with BLIK was reported on 14 Sep 2026 (PayU, Juo, Your KAYA; 19.99 zł after one-time consent with a BLIK code) [V, 12]. PSP names regulation as the barrier [S, 13].

## Payment providers

| PSP | BLIK | Apple Pay in iOS | Platform / split | Standard fees |
|---|---|---|---|---|
| Stripe | code + recurring (Model O) [V, 9, 10] | native SDK [V, 45] | Connect; agent-payment tools in preview, Poland listed [V, 22] | EEA cards 1.5% + 1 zł; BLIK 1.6% + 1 zł [V, 14] |
| PayU | code; one-click via SDK [V, 15] | in SDK [V, 15] | not verified | BLIK 0.99%, cards from 1.6% + 0.20 zł [S, 16] |
| Przelewy24 | code + One Click [V, 17] | listed [V, 17] | "Marketplace" listed, not reviewed | 1.29% + 0.30 zł [S, 16] |
| Tpay | Level 0, OneClick, recurring [V, 8] | not checked | Marketplace API splits one payment across sellers [V, 18] | BLIK 1.59% + 0.41 zł [S, 16] |
| Autopay | yes [S] | older source only | not found | BLIK from 0.79% [S, 16] |
| Adyen | code; OneClick needs certification [V, 19] | not verified | Adyen for Platforms [I] | negotiated |

## Agent-commerce protocols

| Protocol | Status, late 2026 | Poland / EU | Merchant of record |
|---|---|---|---|
| OpenAI + Stripe ACP | open spec; OpenAI dropped Instant Checkout around Mar 2026 [V, 20, 21] | no Polish checkout found [I] | merchant |
| Stripe Shared Payment Tokens / Agentic Commerce Suite | **private preview**, physical goods; cards, Link, Apple Pay, Google Pay, Klarna, Affirm, **no BLIK**; each seller on Stripe with an agreement with the agent [V, 22, 23] | **Poland listed** [V] | seller |
| Google UCP checkout | select merchants [V, 24] | US, CA, AU only [V, 24] | merchant |
| Google AP2 | spec v0.2, moving to FIDO [V, 25] | spec only | — |
| Visa Intelligent Commerce | live agent purchases in Europe since 2 Jul 2026; PKO BP and mBank among 30+ issuers [V, 26] | no Polish merchants named | merchant |
| Mastercard Agent Pay | all European issuers enabled; Pekao, mBank, UniCredit Polska listed [V, 27] | pilots | merchant |
| PayPal Agent Ready | US-focused [V, 28] | not confirmed | merchant |
| Shopify agent tools | only top-tier agents complete checkout; others hand off via `continue_url` [V, 29, 30]; Checkout Kit for iOS [S, 31] | no country limit stated | merchant |

Polish shops: Allegro has its own assistant and no external agent protocol found [S, 33]; Zalando works with Google on UCP [S, 35]; Empik nothing found.

## Regulation

- **Holding the user's money needs a licence.** The Polish payment services act excludes an agent acting for only the payer or only the payee (art. 6 pkt 2) and technical providers that never hold the funds (art. 6 pkt 10) [V, 36]. Collecting the user's money and paying shops is a payment service: a KNF licence or an agent agreement with a licensed institution [I]. The new EU PSR narrows the agent exclusion; agreed, not yet published [S, 37, 38].
- **Consumer law** sits with the merchant of record: 14-day withdrawal for distance purchases (perishables excluded, art. 38 pkt 4) [S, 39].
- **Tax:** agents that both find and buy may count as marketplace facilitators [V, 22].

## Models, ranked for a small Polish startup

1. **Hand off to the shop's own checkout** (link, the shop's app, or Safari in the app). Lowest legal weight; the shop is merchant of record. Doddy gets no trusted confirmation, so it may say "handed off", never "bought".
2. **Agent checkout through a protocol** (Stripe Agentic Commerce Suite, Shopify top tier). A native Apple Pay sheet and a webhook confirmation that fits "done only on provider confirmation"; medium legal weight (Apple intermediary duties); preview only, sellers opt in, no BLIK, no Polish sellers live found.
3. **Doddy as reseller or merchant of record.** Heaviest: returns, warranty, VAT, fraud, chargebacks; collecting money to pay shops needs a licence.

## Grocery delivery

No public partner APIs found [I]. Barbora left Poland in Mar 2024 [S, 40]; Biedronka delivers through Glovo and its own Biek [S, 41]; Wolt's APIs are for merchants [S, 42]; Żabka Jush cut to 2 cities in 2023 [S, 43]; Carrefour Polska under sale review [S, 44]. The realistic grocery flow is a list split by shop, with leaflet prices and dates, and no payment.

## Recommendation

v1: product and leaflet search with exact price, shop, source and time; a list split by shop; "open in shop" logged as `handed_off`, never `purchased`; no payment inside Doddy, and the BLIK-transfer drafts stay separate. v2 (model 2) when the Stripe suite is generally available with Polish sellers, a BLIK agent standard is published, card-network agent tokens come through a PSP, and the PSR text is final; then bind approval to the exact cart and mark done only on the provider's webhook. Owner: drop in-app payment from v1; legal opinion before model 2 or 3.

## Sources (checked 2026-10-24)

[1] developer.apple.com/app-store/review/guidelines/ · [2] Apple Developer Program License Agreement (UK English PDF) · [3] Apple Pay Platform Integration Guide (PDF) · [4] developer.apple.com/documentation/passkit/pkpaymenttokencontext · [5] developer.apple.com/apple-pay/acceptable-use-guidelines-for-websites/ · [6] techcrunch.com/2024/07/11/eu-ends-apple-pay-antitrust-probe… · [7] spidersweb.pl/2026/08/blik-zblizeniowy-iphone-pierwsza-platnosc-pko-lidl-w-polsce.html · [8] docs-api.tpay.com/en/payment-methods/blik/ · [9] docs.stripe.com/payments/blik · [10] docs.stripe.com/payments/blik/recurring-payments · [11] ppro.com/news/ppro-partners-with-blik-to-enable-agentic-commerce-for-local-payments-in-poland/ · [12] pep.pl/informacje/agent-ai-po-raz-pierwszy-samodzielnie-kupil-produkt-i-zaplacil-blikiem-bez-klikniecia-uzytkownika/ · [13] bank.pl/blik-coraz-blizej-wykorzystywania-agentow-ai/ · [14] stripe.com/pl/pricing · [15] developers.payu.com/europe/docs/mobile-sdk/ · [16] freenance.io/…/bramki-platnosci-2026-ranking… (its Stripe figures conflict with [14]) · [17] przelewy24.pl/en/payment-methods · [18] docs-api.tpay.com/en/marketplace/ · [19] docs.adyen.com/payment-methods/blik · [20] digitalcommerce360.com/2026/03/06/openai-shifts-checkout-plans-agentic-commerce-strategy/ · [21] agenticcommerce.dev · [22] docs.stripe.com/agentic-commerce/agents/embedded.md · [23] docs.stripe.com/agentic-commerce/concepts/shared-payment-tokens.md · [24] support.google.com/merchants/answer/16837055 · [25] ap2-protocol.org · [26] mynewsdesk.com/uk/visa/pressreleases/visa-and-banks-across-europe-reach-the-next-phase-of-agentic-commerce… · [27] newsroom.mastercard.com/news/europe/en/perspectives/en/2026/europe-is-building-the-foundations-for-trusted-agentic-commerce/ · [28] newsroom.paypal-corp.com/2025-10-28-PayPal-Launches-Agentic-Commerce-Services… · [29] shopify.dev/docs/agents · [30] shopify.dev/docs/agents/profiles/auth-and-rate-limiting · [31] shopify.dev/docs/storefronts/mobile/checkout-kit/swift · [32] pymnts.com/…/klarna-joins-google-universal-commerce-protocol… · [33] wiadomoscihandlowe.pl/…/allegro-wdraza-asystenta-ai… · [34] developer.allegro.pl/news/get-offers-listing-tylko-dla-zweryfikowanych-aplikacji… · [35] marketbeat.com/instant-alerts/zalando-q4-earnings-call-highlights-2026-03-12/ · [36] api.sejm.gov.pl/eli/acts/DU/2018/1075/text/I/D20181075.pdf · [37] freshfields.com/…/council-adopts-position-on-psd3-and-psr… · [38] nortonrosefulbright.com/…/psd3-and-psr-from-provisional-agreement-to-2026-readiness · [39] standardyprawa.pl/akt/51/art/9883 · [40] wiadomoscihandlowe.pl/…/barbora-zakonczyla-dzialalnosc-w-polsce… · [41] retailpoland.pl/kanal-nowoczesny-fmcg-w-2026-roku/ · [42] developer.wolt.com/docs/wolt-drive · [43] wiadomoscihandlowe.pl/…/zabka-wygasza-usluge-zabka-jush… · [44] wiadomoscihandlowe.pl/…/carrefour-w-polsce-ze-spadkiem-sprzedazy… · [45] docs.stripe.com/apple-pay.md?platform=ios
