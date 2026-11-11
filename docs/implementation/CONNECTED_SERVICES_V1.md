# DODDY Connected Services — stage 1 (11 November 2026)

## Scope and honest status

This is an additive, disabled-until-configured first slice of shopping/booking integrations. It does **not** create a Vinted crawler, Vinted login, Booksy calendar access, a SimplyBook booking API connection, payment capability, or autonomous ordering.

1. **Share Sheet** (already implemented): the iPhone extension passes a web link/text to a local capture screen. New: trusted-domain recognition for Vinted, Booksy and SimplyBook.me, with an honest hint. Recognition never retrieves the page; nothing is saved until the user confirms on the capture screen. Nothing is booked.
2. **Used-products** (new, optional): eBay Browse API official, read-only; enabled by server-only `EBAY_CLIENT_ID` and `EBAY_CLIENT_SECRET`. The existing `find_offers` shopping tool adds eBay searches when a user explicitly asks for second-hand goods. The existing shopping errand approval and budget rules still apply. The adapter only returns offer *leads*; products are only priced/recommended when the existing independent page verification can confirm price. If eBay blocks page reads, DODDY must say the price is unconfirmed.
3. **Booksy/SimplyBook.me**: links can be recognised and saved for later. No availability, calendar, or write access is claimed. A user opens and completes booking at the provider until real partner credentials and merchant consent exist.

## Setup: eBay

- Register in [eBay Developers Program](https://developer.ebay.com/).
- Obtain Production application Client ID and Client Secret and arrange any required API approval.
- Store these as `EBAY_CLIENT_ID` / `EBAY_CLIENT_SECRET` in the messaging server's secret environment; **never** in iOS, Git, logs or an LLM prompt.
- Use a shopping errand such as "Znajdź używane New Balance 2002R". The server sends a keyword query to eBay Browse API with marketplace `EBAY_PL` and `conditions:{USED}`. The user's shopping text may leave DODDY for the provider as a search query; add this to the privacy disclosure before release.
- Existing `SERPER_API_KEY` continues to work unchanged for ordinary shopping queries. With no eBay credentials, eBay is not contacted.
- No affiliate commission has been enabled. eBay Partner Network enrollment and permitted click tracking are **separate** from API access.

API references:
- https://developer.ebay.com/api-docs/buy/api-browse.html
- https://developer.ebay.com/api-docs/buy/ref-marketplace-supported.html
- https://developer.ebay.com/api-docs/static/oauth-credentials.html

## Booksy and SimplyBook.me next gates

**Booksy:** obtain written partner approval / actual API contract before offering availability or confirmed booking. A public booking URL is not authorization to read private calendars. Store no Booksy credentials in a mobile app. No unauthorised scraping or bot login.

**SimplyBook.me:** a business owner must explicitly enable the API feature and provide company-specific credentials with appropriate rights. Its documented JSON-RPC 2.0 API supports `getToken`, service lists, staff, slots, and `book`. Do not run `book` until a server-side signed proposal, one-time consent for exact service/staff/time/cost/customer data, idempotency/reconciliation, and a trusted confirmation receipt are implemented. Existing checkout safety conventions should be reused. Never treat timeout as "booked".

- https://simplybook.me/en/api/developer-api
- https://help.simplybook.me/wiki/User_API_guide

## Next technical PRs

1. A user-facing **"Analyse listing"** action after a Vinted share: extract only the data the user explicitly provided, then optional opt-in retrieval when permitted. Compare with verified retailer offers; do not assert authenticity from a photo. No Vinted catalog crawling.
2. A **"My services"** directory with user-chosen Booksy/SimplyBook.me bookmarks and an explicit "Open provider booking" action.
3. SimplyBook read-only service/staff/availability connector, scoped to a consenting merchant; automated bookings only in a later reviewed PR.
4. User-visible results/QA with configured sandbox/provider credentials before enabling commercial traffic.

## Verification & constitution evidence

- Changed Swift model: recognised hosts using HTTPS + exact hostname/subdomain boundaries; spoofed hosts do not match. Share Sheet continues to require user action and capture-screen Save.
- Changed shopping source: eBay token stays on the server; no account impersonation, payment, messages, external writes, model-chosen prices, or provider claims of checkout.
- Tests added: `ShareInboxTests` for trusted/nontrusted domains, `ebayUsed.test.ts` for missing keys, OAuth request, token reuse, filtering, and routing.
- **Not yet verified:** backend TypeScript compilation, Swift compilation, CI, real eBay API calls, real phone Share Sheet, marketplace legal/data rights, and provider booking flows. Check CI before merge.
- Policy: `action_policy.external_write_default`, `ask_first.one_tap_also_covers`, `unknown_status_must_not_claim_success`, `privacy_policy.raw_secrets_in_model_prompt_or_logs`; relevant implementation: `shopping/runner.ts`, `shopping/ebay.ts`, `ShareInbox.swift`.
