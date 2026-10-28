# Leaflets: reading them better and making better suggestions (28 Oct 2026)

The owner asked (in Polish): what else can make Doddy read the leaflets better and give better suggestions, what would make it easier for the user, how do other apps and agents do it, and how can Doddy do it better. Three research agents worked in this session on 28 Oct 2026: competitors and AI agents, reading techniques (with local OCR timings), and Polish users (1,299 recent App Store reviews of ten apps, store locators checked with Doddy's bot). Nothing here is built. Tags: **[V]** seen on the source that day, **[S]** secondary source, **[I]** inference. Not legal advice. Rules that still hold: ADR-609 (read on request, nothing shared stored, no block worked around), ADR-611 (prices only from code-read data), the constitution (no price from a model, preferences only with consent and a verified write).

## 1. Where Doddy stands today (from the code and the 28 Oct live checks)

- **Biedronka:** the leaflet "od 29.10" has 95 image pages; at the 40-page cap 55 are never read [V]. Page 17 holds six brand-wide offers ("1+1 gratis", "drugi za 5 zł", limits, card or app) with no printed price, and the reader drops every product without a price, so all six are lost [V]. A cold-cache page arrives as a 6.19 MB PNG (over the fetcher's 3 MB cap, so it fails as `too_large`); a warm one as a 0.30–0.37 MB WebP [V].
- **Matching** is a light stemmer plus Haiku's pick; without the pick Rossmann's "masło" brings body butters [V]. "Różne rodzaje" and category questions (mielona vs ziarnista) depend on words.
- **Ranking** is now best value per kg/l/piece (ADR-659); multi-buy is turned into a per-item price only for Aldi's data (ADR-660), not for offers the reader reads.
- **Not used yet:** the user's loyalty apps, their nearest stores, trading Sundays, the deposit, the quantity they need, the 30-day price as a "real discount" signal, a saved list checked in one go, anything proactive.

## 2. What others do (selected)

| Product | What matters | How | Tag |
|---|---|---|---|
| Flipp (US/CA, 4.8, 535K ratings) | flyer search, list ↔ deal match, watch list with a max price | retailers supply flyers (paid) | [V/S] |
| eTilbudsavis/Tjek (DK), marktguru (DE) | product alerts ("tilbudsagent", "Merkliste"), favourite stores, price limit | saved search + bell | [V] |
| Blix, Gazetkowo, Moja Gazetka (PL) | followed products, search one product across leaflets (the most praised feature) | alerts on new leaflets, ads between pages | [V] reviews |
| Listonic (PL, 4.75, 27K) | "dopasowanie promocji": cheapest shop per list item, conditions included; voice entry | across all or favourite shops | [V/S] |
| Tańszy Koszyk (PL, web) | coverage "8 z 10", conditions, substitutes flagged, price history, alerts | threshold alerts; says it doesn't confirm stock | [V] |
| Trolley (UK), smhaggle (DE) | price history, "cheaper than usual", "buy now or wait" | shared price histories, receipts | [V/S] |
| Checkjebon (NL) | "Winkelplan": pick N shops, compare with the best single shop, "not found" per shop | — | [V] |
| ChatGPT shopping research | clarifying questions, buyer's guide with trade-offs | warns prices may be wrong; Instant Checkout wound down in Mar 2026 partly over wrong stock and shipping data | [S] |
| Google AI Mode, Alexa for Shopping (ex-Rufus) | price tracking, 30/90/365-day history, target price, "is this the lowest recently?" | US first | [S/V] |
| Moja Biedronka, Lidl Plus, Żappka, Rossmann | personal offers, coupons to activate, "Cena z apką" | login only; no aggregator shows them | [V/I] |

**Pitfalls seen elsewhere:** AI shopping answers with money-losing errors on 14–56% of questions (Product.ai test, 22.09.2026) [S]; app prices not found in the shop (Stiftung Warentest) [V]; paid ranking and ads [S]; personal price tests (Instacart, ended Dec 2025) [S]; preferences pushing pricier picks (Wharton, Aug 2026) [S]; misleading multi-buy and voucher promotions (UOKiK charges against Biedronka, 9.09.2025; a fine of about 105 mln zł reported, not final) [S].

## 3. What Polish users complain about (App Store PL, recent reviews)

1. **Coupons to activate and app-only prices:** 29 of 94 recent low Lidl Plus reviews; "Każdorazowe aktywowanie kuponów jest zbędne i strata czasu" (23.10.2026); Biedronka: "zapomnij zeskanować = strać 2 razy więcej pieniędzy" [V].
2. **Ads and notification spam** (Gazetkowo, Blix, Biedronka's compulsory SMS) [V].
3. **The app freezing at the till** (Lidl, Żappka) [V].
4. **Finding one product across all leaflets** is what users praise most [V].
5. **Offers not valid yet** ("będzie dopiero w następnej gazetce") [V].
6. **Shops and offers they don't care about** [V].
7. **Not in my store / already gone**; Żabka: "Obowiązuje w wybranych sklepach" [V].
8. **Fine print:** per-account limits, multi-buy, the deposit noticed only at the till [V/S].
9. **Coupons and points disappearing** (Żappka) [V].
10. **Shared lists breaking, no offline mode; leaflets unreadable with VoiceOver** (Moja Gazetka) [V].

**Polish context to handle:** trading Sundays 2026: 25.01, 29.03, 26.04, 28.06, 30.08, 6, 13 and 20.12 [V zielonalinia.gov.pl]; holiday hours (Aldi closed 1.11, 11.11, 24–26.12) [V]; leaflets start on different days (Lidl Mon and Thu, Biedronka Thu, Dino Tue, Żabka every second Wed) [V], so dates are read from each leaflet; the Żappka programme ends 31.10.2026 and a new one starts 1.11 (points usable to 31.12) [S]; deposit 0,50 zł on bottles up to 3 l and cans up to 1 l since 1.10.2025, not in the shelf price [S].

**Store data:** Lidl (store sitemap, schema.org hours), Aldi (436 pages with hours and closures) and Rossmann (about 2,000 shops with coordinates and hours) are readable [V]; Biedronka's store data host answers 403, Dino's and Żabka's are behind undocumented APIs or a token [V]. MapKit on the phone finds nearby stores privately but gives no opening hours as data [V Apple DTS, Mar 2026].

## 4. Reading better: ranked technical improvements

| # | Improvement | Fixes | Gain and cost | Effort |
|---|---|---|---|---|
| 1 | **Labelled Polish test set first** (about 150 pages, two weeks; per offer: name, size, every printed price, conditions, mechanic, dates, box; per page: items shown); metrics: price exact match, field match, condition recall, hallucinations, page-screen recall, whether `check` catches wrong prices; run 3× (Haiku 5.5 refuses a non-default temperature) | every change is measured | about $0.06 a run through the Batch API [I] | M |
| 2 | **Screen every page, read only the matches** (Biedronka): about 5 parallel Haiku calls of ≤20 images, each under 100k tokens (Haiku 5.5 is dearer above that) [V], asking which items and brand-wide promotions each page shows; full reads of the flagged pages and neighbours | the 55 unread pages | all pages screened instead of 42%; full reads 40 → about 3–12; ≈$0.025 a leaflet, +4–6 s [I]; screen recall unmeasured (target ≥95%) | M |
| 3 | **Promotions without a price** (`promotions` in the schema: range, mechanic, conditions, limit) | "1+1 na Persil z aplikacją, cena na półce" is lost today | no price ever invented | S |
| 4 | **Effective multi-buy price by code** for every chain: 1+1 → p/2, 2+1 → 2p/3, "drugi za X" → (p+X)/2, "co n-ta −k%" → p(1−k/(100n)); limits kept | compares like with like | — | S |
| 5 | **Real discount and value ranking**: discount against the 30-day lowest; a promo at or above it is not a reduction (CJEU C‑330/23) [S]; rank by effective unit price, then a penalty for app/card/minimum quantity, then the real discount; per-use units (washes, capsules) | fake "−50%" | wording checked by a lawyer (Omnibus) | S |
| 6 | **Zoomed second read** of the offers Doddy will show: crop the reader's box (+15%), read again, disagreement → `check` | regular price read right only 37–49%, discount 32–39% in a study [V arXiv 2504.11838] | ≈1,300 tokens a crop, +2–4 s; boxes can be imprecise on busy pages (Instacart) [V] | M |
| 7 | **Category matching**: a closed list of about 200 categories with Polish synonyms from the Open Food Facts taxonomy (data dump, ODbL attribution; the API allows only 15 reads a minute) [V]; the reader names the category; neighbours shown as labelled substitutes; brand or size the user names is a filter | masło/masło shea, mielona/ziarnista, "różne rodzaje" | — | M |
| 8 | **Downloads**: keep asking for WebP; a PNG over 3 MB is fetched once more after about 2 s (the WebP copy is usually ready); otherwise counted in `pages`; never convert images on a 0.1-CPU server | memory and `too_large` | — | S |
| 9 | **Prompt caching** of the system prompt and schema; test thinking off at low effort against the set | latency, cost | — | S |
| 10 | **Short caches**: an account's result in memory for 15–30 min for follow-ups; the app keeps its own result until the leaflet ends | repeated questions | per-user only (legal note below) | S |
| 11 | Later: EAN lookups in Open Food Facts (Dino, Rossmann publish EANs); Polish embeddings (mmlw-roberta-base beats multilingual-e5-base on PL-MTEB) but too slow on 0.1 CPU | — | 91% of leaflet products are in one chain only [S] | L |

**Not now: OCR on the server.** Tesseract 5.3.4 (Polish) took 1.2–1.8 s a page on one full core here, about 12–18 s on Render's free plan [V/I]; RapidOCR and PP-OCRv5 were slower and misread prices ("9,99" as "999") [V]. Apple's Live Text supports Polish [V], but the phone would download about 30 MB a leaflet. Biedronka's image host offers no smaller versions [V].

**Law, briefly (not legal advice):** prices are facts, photos and layout are protected; art. 26³ of the copyright act and art. 8a of the database act allow copies for automated analysis unless reserved in machine-readable form (Biedronka publishes no TDMRep opt-out; robots.txt blocks only search) [V], kept only as long as needed; in-memory copies per request are safest; a per-user or on-phone cache is like the person's own browsing; a cache shared between users is the CV-Online pattern and needs the owner and a lawyer.

## 5. Making it easier: ranked product ideas

| # | Idea: what the user gets | Others | Doddy, better | Effort |
|---|---|---|---|---|
| 1 | **"Przed wyjściem" checklist** from the offers' conditions: Lidl Plus coupons to activate, scan the card, limits, "kup 2", deposit | top complaint; nobody solves it | spoken and on screen, one tap to Reminders | S |
| 2 | **"Moje programy"**: the user says which loyalty apps they use; the basket counts only prices they can get; the rest marked "z aplikacją, której nie masz" | nobody [I] | kept only with consent and a verified write | S |
| 3 | **"Sprawdź moją listę"**: one sentence checks the saved list (Shopping list+) | Flipp, Listonic | coverage said aloud, including what wasn't checked | S |
| 4 | **Real price line**: app vs no-app price when known, "+0,50 zł kaucji", per-item price on multi-buy, the limit, "nie jest to prawdziwa obniżka" when at or above the 30-day low | Trolley, Amazon | code-written, no model numbers | S |
| 5 | **Honest timing**: "jeszcze nie obowiązuje, od czwartku", "do wyczerpania zapasów", "sprawdź na półce", trading Sundays and holiday closures, an optional reminder on the start day | passive dates | voice and a local notification the user approves | S |
| 6 | **Quantity and limits**: "taniej tylko przy 3 sztukach" against the quantity the user needs; the basket respects limits | Listonic | code compares | S–M |
| 7 | **"Ten sam" or "podobny"** on every line ("ten sam" only on an EAN match) and user rules ("tylko Łaciate", "bez laktozy") as filters | Tańszy Koszyk, Instacart | rules applied in code, never to upsell | M |
| 8 | **One clarifying question**, only when matches differ a lot | ChatGPT, Google | at most one spoken question | S–M |
| 9 | **Second shop only when worth it**: a minimum saving the user sets | Checkjebon | BasketSolver exists | S |
| 10 | **"Moje sklepy"** picked on the phone with MapKit; filter to those chains; warn "w wybranych sklepach"; Apple's place card for hours | kaufDA, Moja Gazetka | private, no server | M |
| 11 | **"Dlaczego to?"**: one code-written sentence per pick | ChatGPT buyer's guide | no model numbers | S |
| 12 | **Trip list grouped by shop**, exported to Reminders | Flipp, Listonic | no accounts | S |
| 13 | **Quiet weekly check** of the list on each chain's real start day, at most one notification a week, only real deals | marktguru, Blix (noisy) | needs push (off today) and a lawyer on scheduled reads | M |
| 14 | **Watch by unit price** ("masło poniżej 30 zł/kg") | Flipp, Tjek | per-kg threshold, conditions included | M–L |
| 15 | **Shelf barcode scan**: EAN checked against this week's offers on the phone | Biedronka, Klarna | no image leaves the phone | M |
| 16 | **Meal ideas from this week's deals**: the model suggests dishes, the code prices them only from offers it read | Listonic AI, Instacart | — | M |
| 17 | **Restock reminders** ("kawa co 2 tygodnie") | Rossmann | the user sets it; no receipts | M |
| 18 | **"Tydzień temu 5,99 w Lidlu"** from what this user was shown, kept on the phone | Trolley, Alexa | labelled as their own history (lawyer check) | M |
| 19 | **Żappka change explainer** (new programme 1.11.2026, points to 31.12) | — | optional reminder | S |
| 20 | **Accessibility and no ads**: VoiceOver-first answers, plain language | Moja Gazetka fails VoiceOver | already the default | S |

## 6. Proposed order

- **Stage 1 (small, all within today's rules):** the test set started (§4 #1), promotions without a price (#3), the effective multi-buy price for every chain (#4), real discount and ranking (#5), downloads (#8), prompt caching (#9); product: "Przed wyjściem" (§5 #1), "Moje programy" (#2), "Sprawdź moją listę" (#3), the real price line (#4), honest timing with trading Sundays (#5).
- **Stage 2 (medium):** Biedronka's screen-then-read pass (§4 #2), category matching and substitutes (#7, §5 #7), the zoomed second read (#6), "Moje sklepy" with MapKit, quantity and limits, one clarifying question.
- **Stage 3 (needs decisions):** the weekly check and unit-price watch (push, a lawyer on scheduled reads), price history, meal ideas.

**Owner decisions:** push notifications (APNs not set up); a lawyer on scheduled reads and per-user caching; whether about $0.025 a request for a fully read Biedronka is fine; Render's free plan (0.1 CPU, and the free database expires 10.11.2026 per `GO_LIVE_DAILY_NEWS.md`).

**Session note:** one Open Food Facts request made by a research agent carried the owner's email in its User-Agent header; every later request used DoddyBot's.
