# DODDY Food — Phase 0 Research, Architecture & Release Gates

**Research date:** 2026-11-11  
**Status:** DESIGN / RESEARCH ONLY. No food-provider credentials, live restaurant inventory, cart submission, payments, or production rollout have been validated.  
**Market:** Poland first; iPhone/SwiftUI; ElevenLabs voice, existing Doddy backend and messaging infrastructure.  
**Decision requested:** Approve a mock-only vertical slice *after* reviewing this document. Do not deploy/order/pay on the strength of this document.

## Executive decision

Build a **provider-capability-driven food experience**. Start with a clearly labeled simulated ordering flow and an approved/provider-verified external handoff, **not** an unsupported multi-platform comparison or checkout. Seek access to Uber **Consumer Delivery** API for real consumer ordering. In parallel consider a directly contracted restaurant + Wolt Drive/Glovo On-Demand fulfillment pilot: this is a different business model with the restaurant as seller and a courier service as delivery supplier.

**Critical distinction:** An API for restaurant POS, incoming orders or courier dispatch is **not** a consumer API that can browse a platform marketplace and purchase on behalf of an end user.

## Evidence and limits (primary sources, accessed 2026-11-11)

| Service | Verified public capability | What is NOT established | Classification / next step |
|---|---|---|---|
| **Uber Consumer Delivery** | Describes user account linking, merchant discovery, menus, customized carts, order submission, order status, history and reordering for voice assistants and consumer apps. | No approved Doddy account/scope, credentials, Polish coverage, production access, exact endpoints, token permissions, commercial or payout terms. Early access approval is case-by-case. **Linked intake form currently returns “survey closed.”** | **Candidate for end-to-end consumer checkout, BLOCKED by access.** Request a direct partnership introduction; never implement guessed endpoints. |
| **Uber Eats Marketplace / Order Integration** | Restaurant/integrator order acceptance *after* a customer checkout. | No ability to originate a consumer food purchase in Doddy. | Do not conflate with Consumer Delivery API. |
| **Glovo Partner API** | Receiving/handling incoming orders, menus, stocks, promotions, outlets for merchants. | No public Doddy consumer account linking, arbitrary marketplace discovery, customer checkout or purchase API verified. | **Merchant-facing.** Consumer ordering needs separate written partner approval. |
| **Glovo On-Demand** | Couriers for orders originating in a partner's own channel. | It does not give Doddy the Glovo marketplace or restaurant purchasing rights. | Potential direct-merchant pilot; check Polish contracts. |
| **Wolt Marketplace** | Merchant POS/retail integrations. | No public 3rd-party consumer purchase API established. | **Merchant-facing.** Seek separate partnership. |
| **Wolt Drive** | Last-mile courier integration with partner's own e-commerce checkout; development credentials from Wolt team. | No Wolt marketplace browse/consumer checkout. | Potential direct-merchant pilot. Polish contact published: drive.poland@wolt.com. |
| **Bolt Food Stores API** | Merchant catalog, operational order acceptance/rejection/fulfilment and POS integrations. | No 3rd-party consumer checkout. | **Merchant-facing.** |
| **Just Eat Takeaway / Pyszne.pl** | POS/integration partner ecosystem. | No public arbitrary end-user ordering API/approval for Doddy established. | **Merchant-facing evidence only.** Validate in a partner conversation. |

Sources:
- Uber Consumer Delivery: https://developer.uber.com/docs/consumer-delivery/introduction
- Uber consumer onboarding form (currently closed): https://uber.surveymonkey.com/r/consumerdeliveryintake
- Uber Identity OAuth: https://developer.uber.com/docs/consumer-identity/introduction
- Uber Eats merchant orders: https://developer.uber.com/docs/eats/guides/order-integration
- Glovo Partner API: https://qcommerce.developer.glovoapp.com/en/documentation/api-partner-api-overview
- Glovo Poland On-Demand terms: https://glovoapp.com/docs/pl/legal/terms-on-demand/
- Wolt docs: https://developer.wolt.com/docs
- Wolt Drive overview: https://developer.wolt.com/docs/wolt-drive
- Wolt Drive Poland: https://merchant.wolt.com/pl/pol/wolt-drive/api-integration
- Bolt Stores: https://developer.bolt.eu/stores
- Just Eat Takeaway integration partners: https://developers.just-eat.com/integration-partners
- Apple App Review Guidelines, especially 3.1.3(e) and 4.9: https://developer.apple.com/app-store/review/guidelines/

**Evidence levels:** Official high-level descriptions do **not** prove contract eligibility, granted scopes or Polish production availability. Do not treat an integration or affiliate marketing program as permission to make purchases. Re-check sources when beginning implementation.

## Doddy code reuse: findings and required follow-up

Verified repository touchpoints on `main`:
- `Packages/DoddyCore/Sources/DoddyCore/Checkout.swift`: `CheckoutDraft` canonical SHA-256 digest, validity rules, `CheckoutSession` single-send transitions, `unknown` handling. This is **only local business logic**, not a connected checkout.
- `docs/implementation/SHOPPING_CHECKOUT.md`: explicit non-live status, missing provider, server route, screen, payment and voice tool.
- `backend/src/policy.ts`: confirmation tokens bound to validated argument digest, capability, account, user and expiry.
- `DoddyApp/Features/Voice/VoiceSessionController.swift`: voice tool proposal and tap-to-confirm cards.
- `voice-agent/README.md` and `voice-agent/tools.json`: large existing tool set, versioned; modifying repo tool specs does not update the live ElevenLabs agent.
- `docs/architecture/ANY_APP_CONNECTIONS_PROPOSAL.md`: reviewed bounded integrations; do not permit arbitrary generic provider calls.
- `server/messaging/`: possible future post-order status messages, **only after** truthful provider status and authenticated event processing.

Open code questions to resolve with tests and implementation review:
- Whether the existing `CheckoutDraft` covers provider identity, exact variants/modifiers, service fees, tip, promotions, payment choice and delivery address digest; if not, extend *without breaking existing tests*.
- Whether server-side idempotency, transactional persisted order attempts, customer-authenticated reconciliation, and webhook authentication are actually implemented for purchasing. **Assume NO until code and tests prove YES.**
- Staging isolation: current README/STATUS state staging is missing. Do not connect beta food orders to production agent/backends.
- Existing approval system has multiple paths (phone + backend); define one authoritative server-side purchase gate rather than duplicate permission systems.
- Find voice-agent prompt budget and routing mechanism before adding tools. Start with one intent-dispatch tool only in local spec, not live agent.

## Product scope: explicit capability tiers

**Tier 0 (simulated; first build)**: user asks for food; deterministic mock restaurants/menu/fees/availability marked **DEMO**; item options; mock cart; approval card; simulated status; no provider login, payment, external order, or provider comparison claims. May test navigation using only officially documented links verified for the provider and location.

**Tier 1 (real discovery / handoff)**: show real data only from an authorized, attributed and sufficiently fresh source; provider-specific link to its supported web/app surface; display `Open in provider`, **never `Order placed`**. No promises of preserved cart unless provider docs confirm and an actual test verifies it. Where real menus/fees are unavailable, show no fabricated prices, ETAs, ratings or availability.

**Tier 2 (verified provider order)**: provider gives contracted and enabled consumer endpoints or direct-merchant commerce partnership; identity linking; exact quote and written disclosure; fresh tap confirmation; provider handles permitted payment; authenticated order receipt; status reconciliation and cancel/refund support as actually exposed. Ship only after every release gate passes.

**Tier 3 (multi-provider intelligent comparison)**: require equal quote scope (same delivery location, fee/tip/tax treatment, identical portion/configuration, timestamps); no apples-to-oranges ranking. If unavailable, clearly label partial comparisons or abstain.

## Proposed design

```text
Voice/typed intent → FoodIntentRouter → FoodService
                                      │
               provider registry / capability declarations
                                      │
     MockFoodProvider | authorized consumer provider | direct-merchant provider
                                      │
                 Normalized menu, offers, quote
                                      │
                         CheckoutDraft (reuse/extend)
                                      │
                Review card → fresh server authorization
                                      │
                [only if real checkout licensed + enabled]
                                      │
            transaction record → submit once → reconciliation
                                      │
                    verified provider receipt / status
```

Suggested interface (design, **not an existing provider API**):

```typescript
type FoodCapability = "discovery" | "menu" | "cart" | "quote" | "place_order" | "status" | "handoff";
interface FoodProvider {
  id: string;
  capabilities: ReadonlySet<FoodCapability>;
  discover?(input: SearchInput): Promise<Restaurant[]>;
  menu?(restaurantId: string): Promise<Menu>;
  quote?(input: BasketInput): Promise<VerifiedQuote>;
  placeOrder?(input: ApprovedOrder): Promise<SubmissionResult>;
  orderStatus?(orderId: string): Promise<ProviderStatus>;
  handoff?(input: HandoffInput): Promise<VerifiedDestination>;
}
```

**Provider registry:** default deny. `place_order` cannot become available from LLM output, feature hints, generic Composio tools or a client-side flag; require server configuration, contract/license evidence, tenant scopes, provider credential presence, permitted geography, account binding, production allowlist and per-user purchase entitlement.

**Data models:** stable provider/store/item/variant IDs; merchant address and tax seller; price per item in integer minor units; fees, tax, discount, tip, delivery amount, payable total, currency, quote expiration, address reference, availability timestamp; accurate dietary/allergen provenance. Never derive money figures from LLM text. Distinguish estimated subtotal from final binding quote.

**User account linking:** request minimum scopes; use provider-supported OAuth authorization-code flow with PKCE/state where appropriate, exact redirect validation and secure backend/token storage; never collect platform passwords or intercept app traffic. Uber Identity documentation covers OAuth but does not itself prove the necessary Consumer Delivery authorization scopes are granted.

**Approval:** show all item variants, total incl. fees/tax/tip, provider and merchant, delivery address, payment method/party and terms; require deliberate on-screen user action for that *exact* unexpired quote. Any change invalidates consent; voice “yes” alone is not purchase authorization in current Doddy trust model. Require provider's payment flow and any additional authentication.

**Order attempt lifecycle:** `draft → quoted → needs_approval → approved → submitting → confirmed | rejected | unknown`. Persist a unique operation ID and provider idempotency key **before** external call (when supported); enforce a unique atomic server constraint for each approved order. On timeout/network loss after submit: `unknown`; **no second submit**, reconcile by provider status/history or human-facing provider UI. Signed webhooks, out-of-order events, delayed settlement, duplicate events, event ownership and account mapping require explicit tests.

**Privacy:** minimize precise delivery location and phone data, never put credentials, full delivery address, or sensitive diet/health details in general LLM prompts/logs; consent separately to storing reusable preferences; full user control to delete data and unlink provider; apply GDPR policy review. Do not infer health status from a food choice.

**Latency:** keep existing ElevenLabs voice startup unchanged. Invoke food retrieval only on food intent, async with bounded timeout and honest `not available` fallback. No giant per-provider tool dump into the live agent.

**External provider handoff:** use only documented/observed legitimate URLs (HTTPS + allowlisted host), with correct iOS Universal Link behavior tested on device; if no cart support, open storefront and say explicitly that checkout happens there.

## Release gates (FAIL CLOSED)

- **G0 Evidence:** current source, capability/territory, written provider terms, partner contact, rate limits, data retention and quota. If missing, provider's feature stays OFF.
- **G1 Architecture:** reuse checkout and confirmation; no arbitrary executable URL or generic tool proxy; server-only secrets; production and staging isolated.
- **G2 Data quality:** real menus, prices, modifier availability, service/delivery fees and ETAs from authorized source with fetch time; no false comparison claims; no menu injection into instructions.
- **G3 Identity:** OAuth/connection scopes, server token handling, revoke + disconnect, user isolation, account transfer/cancellation.
- **G4 User consent:** exact merchant/items/options/fees/tax/tip/total/delivery/payment shown; quote validity check **at submit**; fresh explicit tap; changes invalidate approval.
- **G5 Submission:** durable transactional record, single attempt, idempotency key only if provider contract supports it; unknown≠failed≠success; provider confirmed order ID required for success.
- **G6 Payment & legal:** merchant of record, authorization/capture/refunds, merchant agreements and GDPR terms reviewed; Apple guideline 3.1.3(e) and 4.9 applied; no card numbers stored in Doddy.
- **G7 Security:** webhook authentication/signature/replay prevention, rate limiting, tenant isolation, redaction, no PII/credentials in voice logs.
- **G8 QA:** deterministic unit tests, contract tests, auth and expiry tests, staging provider sandbox, iPhone TestFlight test, screen reader + Polish/English QA; record exact run evidence.
- **G9 Launch:** feature flag OFF by default; initial user/provider allowlist; operator support, monitoring and kill switch; no claim "order placed" without verified receipt.

## Minimum automated test cases (must be green before Tier 2)

1. Mock-only provider never makes network calls or records a real purchase.
2. Unavailable capability returns unsupported, not a synthetic result.
3. Item price or option changes invalidate quote digest.
4. Delivery address or tip/fee changes invalidate consent.
5. Expired quote cannot be approved or submitted.
6. Invalid tax/discount/fee arithmetic cannot be displayed as a final quote.
7. Double-tap, concurrent clients and duplicate HTTP requests produce at most one accepted order operation.
8. Submit timeout produces UNKNOWN; no automatic retry, read-only reconciliation only.
9. Webhook with invalid signature, wrong account, replay or old state is rejected.
10. User unlink revokes access; no token/password leaks into logs or agent context.
11. Failed provider auth and geographic ineligibility fail closed.
12. Deep link destination is host-allowlisted and does not imply order completion.
13. Prompt injection in menu descriptions cannot trigger purchasing or alter policy.
14. Dietary/allergen missing/uncertain data is not asserted as safe.
15. Polish currency formatting, VoiceOver, localization and slow/poor network tested on device.
16. Quote changes after review require a new on-screen confirmation, even if voice agent still intends to buy.
17. No third-party or staging account can order for another tenant.
18. Provider events arrive duplicate/out-of-order: verified state never reverts to an unsafe claim.

## Partner discovery: questions that must be answered in writing

1. Is the API for **end consumers ordering** or merchants receiving/dispatching existing orders?
2. Is Poland (especially Warsaw) supported in sandbox and production?
3. Who can obtain access, and what proof/contract is required? Is the early-access application route still open?
4. Are discovery, menus, modifiers, cart, final binding quote, submission, order status/history all enabled?
5. What OAuth grants/scopes, security requirements, token TTL and refresh constraints apply?
6. Can user-linked payment methods be used? Who is merchant of record and handles refunds, failed payments, chargebacks and customer support?
7. Are fees, discounts, tips, tax, delivery ETA and availability in the quote? When do they become final?
8. Are order-idempotency keys, status lookup and signed webhooks supported? Retention windows?
9. Does the partner permit AI voice ordering, app-based ordering, comparison/ranking and use of branding?
10. Is affiliate/referral compensation possible, on what exact attributed event, and can it coexist with API access?
11. May provider-specific deep links preserve a merchant/cart, and what documented URL schema is supported?
12. What are SLA, request quotas, rate limits, access fees, commissions, test credentials and legal conditions?

## First implementation PR after Phase 0 acceptance

**PR A — Mock and contracts, no externally executable purchasing**
- Model `FoodProviderCapabilities` and provider registry with fail-closed tests.
- Implement deterministic `MockFoodProvider` and typed `FoodQuote` response for demo.
- Add `FoodIntent` routing behind local feature flag (no change to live ElevenLabs agent).
- Render a single SwiftUI FoodSuggestionCard + review card with a visible `DEMO` label.
- Reuse checkout canonicalization; verify fee breakdown and changed payload rejection.
- Add 10+ focused core tests, CI gates and Polish/English UI copy.
- Add truthful `Open provider` handoff only for specifically verified URLs; otherwise omit.
- No real provider tokens, payment SDK, active purchase endpoints or deploy.

**Not in PR A:** full 5-provider scraping, full marketplace comparison, access to real Uber Consumer Delivery scopes, orders/payments, live agent tool sync, production deployment, Dynamic Island delivery ETA, or claims of confirmed restaurants.

## Decision log

**Approved direction from product conversation:** Do Phase 0 research and produce safety-first architecture; stage a proposal for review. **Not approved or executed:** using real accounts, live merchant outreach, credential creation, paying, ordering, changing production services, changing the live voice agent, or merging a PR.

**Recommended next action:** approve PR A and get a direct response from the Uber Consumer Delivery team about Poland eligibility. Consider one Warsaw restaurant + Wolt Drive as a separate pilot while consumer marketplace access is being negotiated.

---
*This document is intentionally a source-linked implementation decision draft, not evidence that a provider integration works.*
