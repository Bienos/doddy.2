# DODDY × Shopify: Real Shop MCP / UCP integration

Date: 2026-11-11. **Implementation PR #332, unmerged.** No fake products or storefront data, and no production deployment or financial transaction has been performed.

## Why Shop MCP instead of retired Shopify REST

- Shopify turned off Global Catalog **REST** on 2026-11-02. Calls to `discover.shopifyapps.com/global/v2` will fail.
- Shop MCP at `https://mcp.shop.com/` uses MCP JSON-RPC and Shopify's UCP catalog/cart/checkout tools.
- It explicitly supports anonymous `search_catalog`, `lookup_catalog`, `create_cart`, `create_checkout`; no Shop OAuth token is needed for these. **Distributed account sign-in to Shop would need a separate registered OAuth client.**
- We are NOT invoking `complete_checkout`, payment instruments, buyer-linked Shop OAuth, card/wallet, bank transfers, or order queries.

Official docs:
- https://shop.dev/docs/quickstart
- https://shop.dev/docs/tools
- https://shop.dev/docs/checkout
- https://shop.dev/docs/authentication
- https://shopify.dev/changelog/posts/global-catalog-rest-api-stops-serving-traffic-on-november-2-2026

## What is implemented (once backend & iOS build are deployed together)

1. Home → ••• → Shopping / Zakupy online opens an iPhone SwiftUI view.
2. Person searches for a product, e.g. `kurtka zimowa`.
3. The **authenticated** iPhone calls `POST /v1/shopify/search { "query": "kurtka zimowa" }`.
4. Doddy's live backend sends `search_catalog` to Shop MCP with `context.address_country=PL`, `currency=PLN`, and `filters.ships_to.country=PL`. This is a filter, **not** proof of delivery availability or of final costs.
5. Real Shopify results show item, merchant, catalog price and displayed variant; product URL opens the merchant.
6. The person explicitly taps `Prepare checkout` on a selected available variant.
7. `POST /v1/shopify/checkout {variantId, shop, quantity}` refreshes the selected exact variant ID via `lookup_catalog`, validates the merchant and availability, invokes `create_cart`, and invokes `create_checkout` for that cart.
8. The checkout's *merchant-returned* `continue_url` is offered directly to the shopper. The shopper reviews tax, shipping, payment and terms and **pays at the merchant**.
9. If any real provider call is unavailable/malformed or a selected offer changed, Doddy says it could not prepare checkout. Never claims the order was completed.

No orders, payments or order-tracking exist in this PR. A merchant cart and checkout session are **real side effects** but not purchases, and are created only on the user's own button tap.

## Data / security

- One fixed outbound host, `mcp.shop.com`; no arbitrary URL proxy, no scraping, no credentials, no direct merchant connection from Doddy backend.
- Durable per-user and service provider-call quotas and in-process concurrency are enforced by the existing `UsageLimiter` in live production.
- Every API route requires the existing full Doddy session; guest sessions are rejected by existing `requireFullAccess`.
- No Shop accounts, credit cards, delivery addresses or bank details are collected or persisted in this integration.
- Search terms are forwarded to Shopify only on an explicit search action; no server logging of request bodies.
- Source data is untrusted: typed parsing, merchant and selected-variant validation, HTTPS links with refused credentials/ports/private hosts.
- Exact generated checkout token/URL is sent back only to the authenticated user. **Do not log, index, share or persist checkout URLs.**
- Duplicate write safety: one Shopify idempotency key per create operation, no blind retry on timeouts. A timeout after a cart/checkout write may leave a merchant draft; it does not charge funds.
- Catalog price may change between search and checkout. The merchant is authoritative for totals; **never** promise savings, free shipping, product safety, stock certainty or final price from the first search.
- `filters.ships_to.country=PL` and the shopper's delivery country do not guarantee every selected offer delivers to the exact Polish address.

## ElevenLabs voice agent integration (11 Nov 2026, owner request)

**Implemented in repo, NOT synced to live agent or deployed.** This PR now has two local phone tools in `voice-agent/tools.json` (both `elevenlabs_tool_id=not_synced`). The live agent still does NOT know them.

- `shopify_search(query)`: a public read performed through `ShopifyLiveClient.search` and the live Doddy backend. It returns only genuine Shopify offers, numbers 1–5, and a catalog price from the provider; the iPhone shows the same items using `ShopifyVoiceResultsCard`. No invented fallback.
- `shopify_prepare_checkout(index, quantity?)`: the number MUST match an available offer that the same conversation fetched from Shopify. The controller pins its exact product/variant/seller before displaying a named consent card. `AskFirst.tapFirst` + the `AskLedger` require an on-screen tap; a spoken `yes` cannot create a cart.
- After tap, the phone requests the existing authenticated `POST /v1/shopify/checkout`. The backend rechecks exact selected variant and merchant through `lookup_catalog`, creates a real cart and checkout via Shop MCP; the app displays the actual seller, totals/disclosures/policy links and the Shopify checkout `continue_url`. The link stays ON DEVICE; it is never included in the voice agent's tool reply. The user pays externally at the merchant.
- `ConnectionPause`, driving policy, release scope, exact typed arguments, and activity-log redaction apply. No wallet, payments, order submission, auto purchase, saved payment method or agent-held checkout token.
- **Unknown outcome** after a remote cart/checkout write is not retried automatically; nothing has been charged or purchased.

### Release order required before actual voice use

1. CI must pass native iOS (including the new cards and controller), Swift core policy tests, TypeScript backend tests and tool catalog/spec validation.
2. Fix any security/test failures. Verify with a real Shop MCP merchant listing that ships to Poland and produces `continue_url`.
3. Deploy matching real backend, build matching iPhone TestFlight version. Test the complete spoken `search → select # → tap → merchant checkout` with **no payment**.
4. **Only after** the matching TestFlight/app is available should the two tools be added to/published on the live ElevenLabs agent. Otherwise older installed apps reply `unsupported`.
5. Merchant payments, delegated payment tokens and `complete_checkout` remain **not in this milestone** and require separate approval, legal review, and durable server-side authorization. The current cart-creation endpoint does not mint an explicit server-side purchase authorization, so do not extend it to placing orders.

### Files extended
- `voice-agent/tools.json`, `voice-agent/instructions.md`, `voice-agent/README.md`
- `Packages/DoddyCore/Sources/DoddyCore/{VoiceTools.swift,AskFirst.swift,ConnectionPause.swift,CarProfile.swift,ToolCatalog.swift,ActivityLog.swift,ReleaseScope.swift}`
- `DoddyApp/Features/Voice/{VoiceSessionController.swift,VoiceView.swift,ShopifyVoiceCards.swift}`
- `DoddyApp/Features/Shopping/ShopifyLiveShoppingView.swift` (shared typed models and checkout client)
- `Packages/DoddyCore/Tests/DoddyCoreTests/ShopifyVoiceToolTests.swift`

## Test plan and release gates

**Added** `backend/test/shopifyUcp.test.ts` with fake injected HTTP to exercise the real UCP contract, including no fake data on errors and no payment tools. These injected fakes are internal tests only, not user-visible demos.

**Must validate before merge**:
- Backend TypeScript typecheck/test and repo security guards; build iOS simulator on CI and physical device.
- Real Shop MCP response through the configured live backend, including successful Polish results and a shop that truly supports cart + checkout.
- No checkout/payment unless the exact variant, seller and permitted country were verified from the same live provider.
- Server rate limiting and quotas suitable for real user traffic; Shop MCP anonymous traffic has rate limits.
- Manual review of returned merchant disclosures, fees and currencies and localization on Polish iPhone.
- Test expiration, unavailable variants, ambiguous cart/checkout creation, invalid URLs, disconnect/offline and repeated taps.
- App and backend should be deployed together; mismatched versions return honest errors rather than fabricated results.

### Future capabilities, NOT built
- Merchant checkout completion inside Doddy, delegated card/Apple Pay, Shop OAuth, spend authorizations and scheduled auto-buy require separate approval, consent and contractual/legal analysis.
- Reuse existing `CheckoutDraft` digest and `ConfirmationPolicy` for any future **real payment**; never bypass the one-tap confirmation and merchant receipt gates.
- Production purchases must be single-submit with durable idempotency and `outcome_unknown` reconciliation before another attempt.
- The live ElevenLabs agent remains unchanged; voice shopping requires a separate reviewed tool and truthful action statuses.

## Files
- `backend/src/shopify/ucp.ts` — UCP adapter.
- `backend/src/app.ts` and `backend/src/http.ts` — authenticated routes; live mode only.
- `backend/test/shopifyUcp.test.ts` — protocol/response tests.
- `DoddyApp/Features/Shopping/ShopifyLiveShoppingView.swift` — real search / merchant checkout handoff.
- `DoddyApp/Features/Home/HomeView.swift` — menu entry.

**Release status**: Pending CI, device validation, owner PR review, merge and deployment. Nothing here is a live capability in currently installed TestFlight builds.
