# Shopping mode, stage 1 (ADR-607 to ADR-610)

Owner, 24 Oct 2026: "Cały etap 1" of `docs/strategy/TRYB_ZAKUPOW_2026-10.md`, leaflets read on request from four chains, Claude Haiku 5.5 may read leaflet pages and shop pages in the cloud, and "use something cheap" for shop offers. This page is the contract the server (`server/messaging`), the shared core (`Packages/DoddyCore`) and the app (`DoddyApp`) build against. Fixtures: `schemas/fixtures/errand_create_shopping_v1.json`, `errand_result_shopping_v1.json`, `deals_search_v1.json`. Status of what is built and checked is at the end.

Three parts:

1. **Find me this** ("Znajdź mi to"): a shopping errand. The existing errand flow (ADR-570) with `kind: "shopping"` and the user's priorities. The runner finds offers through tools the code runs, and **no price ever comes from the model**: the result card refers to offers by id, and the code writes every price, shop, link and time.
2. **Leaflets** ("Gazetki"): `POST /v1/deals/search`, read on request from the official leaflets of Biedronka, Lidl, Dino and Rossmann. Nothing is kept on the server except daily counts. Other chains come back as a link.
3. **The app**: the cheapest-this-week list, the basket (one shop or two, summed by code in DoddyCore), three picks, a PDF report drawn on the iPhone, and "Buy in the shop", which opens the shop's page in Safari (the shop takes the payment; Doddy records "the shop's page was opened", never "bought"; the app has no web view outside sign-in, scripts/check_forbidden_capabilities.sh).

## 1. Shopping errand

### Create (`POST /v1/errands`)

The research errand's body plus two fields:

| Field | Rule |
|---|---|
| `kind` | optional; the only value is `"shopping"`. Absent means a research errand, exactly as before. |
| `priorities` | required when `kind` is `"shopping"`, not allowed otherwise. 0 to 5 strings in the user's order, each 1 to 40 characters with no leading or trailing spaces, no two equal ignoring case. |

**Digest.** For a research errand nothing changes: SHA-256 of `canonicalJson({brief, language, title, words})`. For a shopping errand: SHA-256 of `canonicalJson({brief, kind, language, priorities, title, words})`, keys sorted, no spaces, arrays as `["a","b"]`. The app recomputes it and approves only when it matches (fixture `errand_create_shopping_v1.json` has the canonical string and both digests). The preview (`201`) also returns `kind` and `priorities`.

### The runner

- **Model (ADR-611):** `SHOPPING_MODEL`, default **`claude-haiku-5-5`**, for everyone; **`claude-sonnet-5-5`** (`SHOPPING_PREMIUM_MODEL`) for the premium option. There are no plans in the app yet, so premium is the accounts listed in `SHOPPING_PREMIUM_ACCOUNTS` (comma-separated account ids, empty by default); the account id is passed to the runner only for shopping errands. Effort `SHOPPING_EFFORT` (default `medium`, Haiku 5.5's own default), adaptive thinking, prompt caching. Same time limit, cancel and stop rules as research errands. Two per-model rules in code: the server-side `fallbacks` parameter is sent only to the models that accept it (not Haiku 5.5, which rejects it), and Haiku gets the basic web tools (`web_search_20250305`, `web_fetch_20250910`), because the documentation lists the dynamic-filtering `_20260209` tools for other models and nobody has run Haiku 5.5 with them. To check a model's capabilities with a key: `curl https://api.anthropic.com/v1/models/claude-haiku-5-5 -H "x-api-key: $ANTHROPIC_API_KEY" -H "anthropic-version: 2023-06-01"` and read `capabilities.server_tools`.
- **Tools** (nothing else exists, so nothing it reads can buy, book or send):
  - `find_offers(query)`, run by the code against the offer source (section 1.1). Each offer the code gets back is registered with an id (`o1`, `o2`, …) and the facts the source gave: title, shop, price, delivery text, link, time. The model sees them with their ids as **leads**: a listed price is never shown to the person (ADR-611).
  - `check_offer_page(url)`, run by the code: fetches one shop page (rules in 1.2), reads the price from its schema.org Product/Offer data, and registers or upgrades an offer with `evidence: "shop_page"`. Fails as "couldn't read a price" when the shop blocks, robots.txt disallows, or there is no structured price.
  - `web_search` and `web_fetch` (Anthropic's), to read specs and reviews. Prices read this way are notes only: they never become offers.
- **The card** (second call, structured output): the answer's reasons and the picks **by offer id**: `role` (`best`, `cheapest`, `premium`, `alternative`), `why`, `tradeoff`, plus short notes per offer (e.g. "42 dB · 10 kompletów"), `howChosen`, `watchOuts`, `unknowns`, `rejected`, and the budget the person gave as a number.

### Code rules on the shopping result

- An offer exists only if a tool run by the code registered it. **Only an offer whose price the code read on the shop's own page (`evidence: "shop_page"`) can be picked, priced or shown** (owner, 24 Oct 2026: "daj tylko potwierdzone ceny a jak nie są to powiedz"). A pick naming an unknown or unconfirmed id is dropped; a result with no `best` pick left fails as `unreadable_result`. The card writer is given only the confirmed offers. A model sentence may state only the confirmed offers' prices, the budget and differences between picks.
- **Unconfirmed offers are said, not shown.** When some offers stayed unconfirmed, the code writes the first `unknowns` line itself: "Oferty z listy Google Shopping bez potwierdzenia na stronie sklepu (nie podaję ich cen): <shops>." When **no** offer was confirmed (or none was found), the errand still finishes (`done`) with a plain research card and **no `shopping` block**: the answer says no price was confirmed so none is given, a section "Bez potwierdzonej ceny" names the products and shops with no price and no link, and the card writer is not called (fixture `errand_result_shopping_unconfirmed_v1.json`, written exactly by `buildUnconfirmedResult`).
- Prices, shops, links, delivery and times come from the registry, never from the model's text.
- `cheapest` is relabelled `alternative` when another picked offer is cheaper (same currency). `overBudget` is computed by the code (price minus budget) when the price is above the budget.
- Model-written lines (`why`, `tradeoff`, `notes`, `howChosen`, `watchOuts`, `unknowns`, `rejected`, `recommendation`) lose any sentence that states a money amount which is not an offer's price or the budget (DOD-02).
- The generic fields stay valid for older apps and for `check_errands`: `answer` is written by the code ("Mój wybór: …, 1 899,00 zł w Media Expert. …"); `sections[0]` is "Propozycje" built from the picks with the price text, the evidence label and the link; `sources` are the picked offers' links; `budget.within` follows the best pick.
- Every price shows its evidence and the time it was seen. The server now emits only `shop_page` ("Cena sprawdzona na stronie sklepu"); `listing` ("Cena z listy Google Shopping") stays in the schema and the apps so a result stored before ADR-611 still opens.

### Result (`result.shopping`, next to the research card's fields)

| Field | Content |
|---|---|
| `priorities` | the user's order, from the errand |
| `budget` | `{minor, currency}`, optional |
| `offers[]` | 1 to 12: `id`, `title` (≤160), `shop` (≤80), `price {minor, currency}`, `delivery?` (≤120), `url` (the shop's own page), `buyUrl?` (a tracked link to the same page, only with an affiliate programme: "Affiliate links" below), `site`, `evidence` (`shop_page` / `listing`), `seenAt`, `gtin?` (8 to 14 digits), `notes?` (≤160, Doddy's words) |
| `picks[]` | 1 to 4: `role`, `offerId`, `why` (≤200), `tradeoff?` (≤200), `overBudget? {minor, currency}` |
| `howChosen[]`, `watchOuts[]`, `unknowns[]`, `rejected[]` | at most 3, 4, 4 and 4 lines of ≤200 |
| `stats` | `{offersSeen, shops}`, counted by the code |

Money is always integer minor units (grosze) with an ISO currency code.

### 1.1 Offer source

`OfferSource` is an interface; the first one is **Serper** (`google.serper.dev/shopping`, `gl=pl`, `hl=pl`; 2,500 free queries, then about $0.30 to $1 per 1,000 [V, serper.dev, 24 Oct 2026]), chosen for being the cheapest that answers in one call. Key: `SERPER_API_KEY`. Google Shopping results usually link to Google's product page, not the shop, so those offers are `listing`; a shop link that `check_offer_page` can read becomes `shop_page`. Without the key, `find_offers` answers "not set up" and the runner relies on `web_search` plus `check_offer_page`.

### 1.2 Fetching shop and leaflet pages

One fetcher for both parts: `User-Agent: DoddyBot/1.0 (+https://doddy.lol/bot)`, robots.txt checked for that agent and `*` (a fetch the file disallows is not made), 10 s timeout, 3 MB cap, HTTPS only, no cookies, no login. A 403, 429, a challenge page or a captcha is reported as blocked and never retried around.

## 2. Leaflets (`POST /v1/deals/search`)

Bearer: the account's device token, like errands. Off unless `DEALS_ENABLED=1`.

**Request:** `items`: 1 to 12 strings of 1 to 60 characters; `chains`: optional, any of `biedronka`, `lidl`, `dino`, `rossmann` (read) and `kaufland`, `carrefour`, `auchan`, `netto`, `zabka` (link only); default the four read chains; `language`: two letters.

**Response:** fixture `deals_search_v1.json`.

- `chains[]`: one row per requested chain: `checked` (read; `leaflet {title?, url, validFrom?, validTo?}`), `no_match` (read, nothing matched), `no_leaflet`, `blocked`, `failed`, or `link_only` (`leafletUrl`).
- `items[]`: per query, up to 6 `offers` sorted by price: `chain`, `product` (≤160), `price`, `size? {value, unit: g|kg|ml|l|szt}`, `unitPrice? {minor, per: kg|l|szt}` (computed by the code from price and size, never read), `regularPrice?`, `lowest30d?`, `conditions[]` (≤4 × ≤80: app, card, minimum quantity, "2+1"), `validFrom?`, `validTo?`, `source {url, page?}`, `readBy` (`leaflet_data` when the chain's own data gave name and price; `page_image` when Haiku read the page), `ean?`, `check` (true when the code could not confirm it: a regular price at or below the price, a 30-day price below the "promo", a unit price that doesn't follow from the size, a low-confidence read).
- Errors: `400 invalid_request {fields}`, `429 daily_limit`, `503 deals_disabled`.

**How it reads** (per chain, in parallel, the whole request within about 25 s): find this week's leaflet from the chain's official page; where the chain publishes product data (Dino, Rossmann, Lidl's page text) use it to find the products or the candidate pages; where it publishes only images (Biedronka), send pages to Claude Haiku 5.5 (`DEALS_VISION_MODEL`, structured output, at most `DEALS_MAX_PAGES` pages per chain per request, default 40). Matching a query to products is code first (normalised words), then Haiku picks among candidates by id. Prices from an image are checked by the code where it can (unit price from size, regular price above price, dates inside the leaflet's dates).

**Nothing is stored:** no page images, no extracted offers, no index shared between users. Only counts: `deals_usage (account_id, day, requests, pages_read, input_tokens, output_tokens)`. Caps: `DEALS_DAILY_PER_ACCOUNT` (default 30) and `DEALS_DAILY_PER_SERVER` (default 1,000), reserved before anything is fetched.

**Legal stance** (research: `docs/research/2026-10-24/research_shopping_leaflets.md`; not legal advice): read on the user's request from the official source, facts only (names, prices, conditions, dates), no leaflet images shown or kept, link to the leaflet page, blocks never bypassed, a lawyer for database rights before launch.

### Affiliate links (ADR-612)

The owner said yes (24 Oct 2026). `AFFILIATE_LINKS` is a JSON object of a shop's host to an https template with exactly one `{url}`, for example `{"mediaexpert.pl": "https://network.example/click?id=123&to={url}"}`; empty by default, so nothing is tracked until a programme exists. The code wraps the shop's own page address (percent-encoded) for that host and its subdomains and writes it as `offers[].buyUrl` **last, into the finished result**. It never reaches the model or the card writer, so it can't change a pick, an order or a sentence (a test compares the result with and without it). `url` stays the shop's own page, used by the card's sources, the activity log and the PDF's source list. The app says it before the tap (caption under the button, a note in the PDF, and a line in what the voice agent reads). A bad setting stops the server at start with a message that names the problem, not the template.

## 3. Shared core and app

- **`ErrandDraft`** gains `kind` and `priorities` with the digest rule above; `ErrandResult` gains the optional `shopping` block (older servers send none).
- **`BasketSolver`** (DoddyCore, pure): from a deals answer, per chain the cheapest offer for each item; the cheapest single chain (most items first, then the lowest total), the cheapest pair (each item at the cheaper of the two), and every item at its cheapest; totals in minor units, coverage ("5 z 6"), the conditions carried along. Offers with `check: true` count, and the basket says they need checking.
- **Voice:** `find_deals {items, chains?}` (a read of public data: the ask card under ASK-01; whether leaflet look-ups join the public look-ups that run at once is an open owner decision), and `hand_over_errand` with `kind: "shopping"` and `priorities`.
- **Screens:** "Najtaniej w tym tygodniu", "Koszyk", the three picks inside a task's result, the PDF report (drawn on the iPhone from the stored result: no model, nothing sent), "Kup w sklepie" (the shop's page in Safari, or its partner link when `buyUrl` is present, with the caption above; its own checkout; recorded in What Doddy did as "opened", never as bought).

## Stage 3: buying through Doddy

Designed and its safety rules built, nothing connected: `docs/implementation/SHOPPING_CHECKOUT.md` (ADR-613).

## Privacy

- **Find me this:** as research errands (ERRANDS.md "Privacy"), plus search words to Serper (when set) and page requests to shops from Doddy's server. The user's words never go to Serper or the shops; only search phrases the model writes and the shop page addresses.
- **Leaflets:** the item names go to Doddy's server; leaflet pages are fetched from the chains by the server and, for image leaflets, sent to Anthropic with the item names. Rossmann's leaflet site disallows all robots, so Rossmann is read from `rossmann.pl/promocje?Search=…`: **the item names go to rossmann.pl as a search**, from the server, with no cookies and nothing that identifies the user (an open owner decision: keep, or make Rossmann link-only). Nothing that identifies the user goes to any chain. Alcohol offers are skipped (Dino, Lidl). Logs carry counts and timings only.
- **A partner link** (ADR-612): the tap opens Safari through the affiliate network, which can set cookies and tells the shop that Doddy sent the user. Nothing from the user's words or notes goes with it. The Terms and Privacy pages must name each network once a programme is signed.
- **The report** is made on the iPhone from what is already there.

## Built and checked

Stage 1, 24 Oct 2026, on `claude/loving-dirac-uuxoux` (ADR-607 to 610). Run on Linux in a cloud session (Node 22, Postgres 16, Swift 6.1.2); no Xcode, no device, no real Anthropic, Serper or chain traffic.

| Part | Where | Checked | Not checked |
|---|---|---|---|
| Find me this (section 1) | `server/messaging/src/shopping/`, `src/errands/schema.ts`, `worker.ts` | `npm test` in `server/messaging`: 284/284 (after ADR-613) with Postgres (shopping runner with a scripted model and fake offers and pages; ids only on the card; unknown ids dropped; budget; the digest with kind and priorities; JSON-LD, microdata and Open Graph price reading; money parsing) | A real Sonnet 5.5 run with web search; Serper's real answers; real shop pages; what one task costs |
| Leaflets (section 2) | `server/messaging/src/deals/`, `src/routes/deals.ts`, migration `012_deals_usage.sql` | 64 of those tests: robots.txt and blocks, each chain against small fixtures taken on 24 Oct, sizes and unit prices, matching, the page reader with a fake model, the route against `deals_search_v1.json`, both daily caps under concurrency, account deletion | Real Haiku 5.5 on Polish leaflet pages; the 25 s budget under real latency; Biedronka's cost (up to 40 pages a request); whether the chains' pages still look like the fixtures |
| Affiliate links | `server/messaging/src/shopping/affiliate.ts`, `build.ts`, `config.ts`; `Shopping.swift` | Server tests (rules, no effect on the result, never shown to a model); DoddyCore tests (decode, round trip, agent line) | The SwiftUI caption and the PDF note compile (Mac job run 40123163712); no programme exists, so no real link was made |
| Stage 3 rules | `Packages/DoddyCore/Sources/DoddyCore/Checkout.swift` | `CheckoutTests`: 10 tests, 0 failures | Nothing runs against a provider, a shop or Apple; no screen, route or tool exists |
| Shared core (section 3) | `Packages/DoddyCore` | `swift test`: 1,751/1,751 (draft and result, `DealsClient` against the fixture, `BasketSolver`, `find_deals` and its ask card, What leaves this iPhone) | — |
| Voice agent spec | `voice-agent/` | `scripts/voice_agent_spec.py check`: PASS, 95 tools (`find_deals` and the new `hand_over_errand` fields are `not_synced`) | Not on the live ElevenLabs agent (needs the owner's yes to the exact text) |
| iPhone screens and PDF | `DoddyApp/Features/Shopping/`, `ErrandsView`, `HomeView`, `VoiceSessionController` | `scripts/typecheck_app_logic.sh` (27 files, including `DealsModel`), the string catalogs, the forbidden-capability guard | The SwiftUI views and the PDF drawing compile and the Mac job's unit and UI tests pass (run 40123163712 on `3b06a1c`); **not seen on a device**, and no UI test opens the shopping screens |

The whole `scripts/ci.sh --core-only` run is recorded in STATUS.md.
