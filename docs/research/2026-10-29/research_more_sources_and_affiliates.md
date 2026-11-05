# More promotion sources and affiliate programmes (29 Oct 2026)

The owner asked "Find more sources" after the leaflet "search further" work (ADR-666). Three research agents checked, from a cloud session on 2026-10-29: chains not yet covered, aggregators and data feeds, and affiliate programmes. Pages were fetched with `curl -A "DoddyBot/1.0 (+https://doddy.lol/bot)"`, robots.txt first; no block, challenge or captcha was worked around, nothing was signed up for, logged into or filled in. One slip is recorded below (Frisco). The session spot-checked the claims that decide what to build: the Tradedoubler Allegro listing, Delikatesy Centrum's page data, Lidl's promotions page, Ceneo's robots.txt, and Doddy's own cut rule.

Tags: **[V]** seen on the source that day; **[V\*]** the source's own text through a search-index copy, because the live page blocked DoddyBot; **[S]** secondary source; **[I]** inference. Not legal advice. Builds on `2026-10-24/research_shopping_leaflets.md`, `2026-10-24/research_shopping_offers.md` and `2026-10-28/research_more_deal_sources.md`; the rules there still apply (ADR-609: on request, official source, facts only, nothing stored, no shared index without a licence).

## 1. Chains and shops

| Chain | What came back | Data | Verdict |
|---|---|---|---|
| **Delikatesy Centrum** (~1,367 shops [S]) | `delikatesy.pl/gazetki` 200, Next.js [V]; robots.txt 404 (no rules) [V] | `__NEXT_DATA__` holds the dates and every page JPG (50 pages, ~190 KB, 593×1000, legible) and an age flag on the alcohol leaflet [V; session spot check: 142 JPG references in the page data] | **page images (model)**, best next leaflet chain |
| **Lewiatan** (3,255 shops in 2024 [S]) | FlowPaper on lewiatan.pl, 200 [V] | page JPGs 220 KB, 1022×1513 on its own domain; no text layer; national leaflet only, page count not in the HTML [V/I] | page images (model); a franchise, local shops may differ [I] |
| **Netto** (~696 shops [S]) | 200; Tjek image host allowed by robots [V] | the HTML lists every page image (width 700) on `image-transformer-api.tjek.com`; offers only through Tjek's API [V] | page images (model), **after Tjek's terms are read** |
| Stokrotka (~950–986 shops [S]) | 200; 4 page JPGs in HTML, the rest under `/IAJAX/`, which robots disallows [V] | PDFs 14.8 MB / 10.4 MB / 1.6 MB, images only [V] | ask the chain for access |
| POLOmarket (~256 shops [S]) | FlippingBook, 78 pages, ~700 KB each [V] | page images [V] | later, heavy |
| Twój Market, Jysk, Mrówka (per shop), Chata Polska | page JPGs on their own hosts [V] | — | later |
| Topaz, Prim Market | PDFs 21 MB and 16.5 MB; Topaz's images under a disallowed path [V] | — | costly |
| Intermarché | FlipHTML5 viewer whose page list sits in a file FlipHTML5's robots.txt disallows [V] | — | link only |
| Groszek, Euro Sklep, abc (mojesklepy.pl) | store picker, 18+ gate, data by JS with a login token [V] | — | link only |
| dm, TEDi, Dealz | empty script page, FlippingBook, Publuu iframe [V] | — | link only |
| **Lidl `/c/promocje`** | 200, robots allows it [V] | per product: price, discount, end date and "Najniższa cena z 30 dni przed obniżką" [V; session spot check] | **code, no model**: more Lidl offers beyond the leaflet |
| **Action** | 200 [V] | page JSON: 169 products with price, original price, unit price, deal flag, 28.10–03.11 [V] | **code, no model** (also in the 28 Oct doc) |
| **Natura** (drugstore) | 200 [V] | 12 leaflet products with promo price, regular price, 30-day lowest and unit price; 58 on the promotions category's first page (`?p=` disallowed) [V] | **code, no model** |
| Empik, Komputronik, MediaMarkt | 200; MediaMarkt's robots.txt names ClaudeBot, anthropic-ai and Claude-User as allowed [V] | prices and the 30-day price in page data (MediaMarkt's 30-day price not confirmed) [V] | code, no model (non-grocery) |
| Pepco (1,400+ shops [V]), Smyk | 200 [V] | names and prices only; Smyk headlines without prices [V] | code, weak data |
| Hebe, Super-Pharm, Decathlon, Bricomarché, Castorama, Leroy Merlin, OBI, Media Expert, RTV Euro AGD, KiK, Carrefour, Kaufland | Cloudflare, DataDome or CloudFront challenge, 403 or 503 [V]; Hebe's and Carrefour's robots.txt disallow ClaudeBot [V] | — | blocked: link only or ask the shop |
| Barbora | left Poland on 4 Mar 2024 [S]; barbora.pl redirects to barbora.lt [V] | — | out |

## 2. Aggregators, feeds and APIs

| Source | Access | Terms that matter | Verdict |
|---|---|---|---|
| **Skąpiec API** (Ringier Axel Springer PL) | free, through the MonetEasy partner programme, with a project description [V skapiec.pl/nowe-api-skapiec] | "Dostęp do API jest nieodpłatny, jednak zastrzegamy sobie prawo do odmowy" [V]; API terms page 403 [V] | **free contract to ask for first** |
| Frisco feed | the feed's address is in a robots.txt comment [V] | "for personal, non-commercial use"; promotion pages disallowed; the feed host's robots.txt is `Disallow: /` [V]. The agent read 3 KB of the feed before seeing that line, then stopped | needs Frisco's written consent |
| Blix | no API; `Disallow: /api/*` [V] | database rights reserved [V blix.pl/p/regulamin/] | licence |
| ding.pl (promoceny.pl redirects there [V]) | public RSS of the 25 newest leaflets [V] | personal use only, no copying (§12–14) [V] | licence |
| Gazetkowo, gazetki.pl, Tiendeo (ShopFully) | public pages [V] | own the content or database rights; express permission needed [V] | contract or licence |
| mojagazetka.com | `Disallow: /api/*` [V] | bans bots and copying [V] | out |
| Tjek | "The API is only available to customers" (the retailers) [V] | Bonial took a majority on 13 Oct 2026; no Bonial/kaufDA service in Poland [S] | contract plus Netto PL's consent |
| Glovo (incl. Biek), Wolt, Bolt Market, Lisek, Żabka Jush | merchant-only APIs [S]; Glovo forbids commercial reuse without consent [V] | — | out |
| Allegro REST API | product search needs a user token; rule 4.1c bars showing offers in competing services [V developer.allegro.pl/rules] | — | out for showing offers |
| Ceneo | robots.txt disallows `/;szukaj` for every bot [V; session spot check] | — | fine for links the person opens; no reading |
| eBay Browse API | free keys, `EBAY_PL` supported [V] | licence not read (403) | possible, little Polish stock [I] |
| Amazon Creators API | needs 10 qualifying sales in the past 30 days [V] | — | later |
| Open Prices (Open Food Facts) | public [V] | Poland: 157 shops, 2,199 prices [V] | too little data |
| GS1 eProdukty, dane.gov.pl, GUS | product data or nothing on prices [V/S] | — | not useful for promotions |
| **UOKiK, "Informacja o obniżce ceny"** (2023) | public PDF [V] | a service that shows reductions must give the 30-day lowest price and count a % only from it (§VI.1, §VI.4) [V] | **already how Doddy works**: `cut` is computed only against `lowest30d`, otherwise "not a real cut" (`deals/service.ts`, ADR-661). Open for the lawyer: whether a spoken summary counts as presenting a reduction |

## 3. Affiliate programmes

| Programme | Shops for Doddy | Commission | Deep links | App traffic | Restrictions | To join |
|---|---|---|---|---|---|---|
| **Tradedoubler** | Allegro.pl (programme 288386), RTV Euro AGD, Castorama, Empik | Allegro 0.21–3.55% by category (Supermarket 2.15%, Elektronika 0.93%) [V, `prowizje_allegro_2026.pdf`]; Euro by publisher type: price comparison 1.5%, content 2.5% [V]; Castorama 4% [V] | "DeepLinking: Dozwolone" [V; session spot check] | Allegro allows "Porównywarki cenowe" and "Aplikacje mobilne" [V; session spot check] | Allegro cookie "24h" in the text, "30 dni" in the table [V]; search ads and CSS forbidden [V] | free; each shop approves |
| **Ceneo Partner** (terms 17.06.2026) | Ceneo | about 0,35 zł per click-out to a shop, CPS on "Kup Teraz"; cookie 90 days [V/V\*] | links to "konkretnej strony" and rotators from a search phrase [V/V\*] | the ad space is a website; anything else needs Ceneo's consent [V] | AI content must be labelled (art. V.5) [V] | private person (PESEL) or company; 100 zł payout [V] |
| **Convertiser** | Decathlon (up to 4.5%), Morele [V\*] | per advertiser | REST API and feeds [V] | lists "Aplikacje" and offers its API for apps [V] | materials "bez jakichkolwiek modyfikacji" (§6.2j) [V] | private person or company [V] |
| **Awin** | Douglas PL 5%, Lounge by Zalando 12%/6% and "2% CPS APP", Temu PL; 30-day cookies [V] | — | universal deep links [S] | a "Serwis Wydawcy" can be an app [V] | §10.1 "bez modyfikacji" [V] | refundable deposit [V] |
| **Admitad** | x-kom (its only network since Nov 2024), Allegro PL [S] | per programme | deep-link generator [V\*] | mobile traffic invited [V] | no incentive traffic [V\*] | — |
| **Webepartners** | 3,000+ advertisers (list in the panel) | per advertiser; 100 zł payout [V] | "dowolnego produktu" [V\*] | "powierzchnie online" [V] | no brand bidding [V] | private person or company [V] |
| **Kelkoo Group** | Poland among its markets [V\*] | CPC [V] | deep-link pricing, Search API, Feeds API [V] | not checked | merchants may forbid "Price Comparison Website" traffic [V] | account manager |
| Allegro Affiliate Business (direct) | Allegro | per campaign [V\*] | not stated; no change to materials (§6.3) [V\*] | website or social profile [V\*] | "chatroom-type" requests count as artificial traffic [V\*] | company: Konto Firma, VAT status, VAT invoice [V\*] |
| Allegro Share | Allegro | points, ~1.67% as coupons [V\*] | single offers only [V\*] | social, websites | not "profesjonalnego charakteru"; ends 14.11.2026 [V\*] | **not usable** |
| x-kom SalesMasters, Media Expert (Performers), VIVnetworks (Super-Pharm 6%, Leroy Merlin 6%), Conversand (Hebe 4.2%, Carrefour [S]), CJ (Notino, Leroy Merlin [S]), Sovrn Commerce / Skimlinks (auto-linkers; apps allowed [V]), MyLead | various | — | — | — | — | later, per shop |
| Amazon.pl Associates | amazon.pl, 5–10%, 24 h [V] | non-product links count as indirect [V] | only an approved app, links through Creators API [V] | **no Amazon links in "ofertą przedstawianą ustnie"** (an offer made orally) [V]; 3 sales in 180 days [V] | last |
| Temu, AliExpress | Temu up to 35%, new users [V] | — | — | low fit [I] | — |

**Grocery:** no affiliate programme was found for any leaflet chain; claims for Carrefour, Auchan, Frisco and E.Leclerc are second-hand [S]. The practical grocery route is Allegro's Supermarket category (2.15% through Tradedoubler) [V]. User referral codes (Glovo, Bolt; Carrefour "Poleceni" in 2019 [S]) are personal to each user and are not affiliate links.

## 4. Proposal, in order

1. **Code, no contract:** Lidl's `/c/promocje` page (more Lidl offers, with the 30-day price), then Action, Natura, Empik and Komputronik as on-request reads like Rossmann and Aldi. Pepco and Smyk are too thin.
2. **Page images, no contract:** Delikatesy Centrum first (all pages in one JSON, small images; the Żabka reader fits), then Lewiatan. Netto only after Tjek's terms are read.
3. **Affiliates, in sign-up order:** Tradedoubler (Allegro: deep links, apps and price comparison all allowed; plus RTV Euro AGD, Castorama, Empik), Ceneo direct (per click-out; ask for written consent for the app), Convertiser, Awin, Admitad (x-kom), Webepartners, Kelkoo. Amazon last; skip Allegro Share. The `AFFILIATE_LINKS` setting takes `allegro.pl` with Tradedoubler's template and `ceneo.pl` with Ceneo's.
4. **Ask for access:** Skąpiec API (register at panel.moneteasy.pl, then pp@skapiec.pl), Frisco (written consent for the feed), one leaflet licence for the chains Doddy can't read (kontakt@blix.pl and kontakt@ding.pl first, then gazetki.pl and Gazetkowo), Stokrotka directly.
5. **Out for now:** mojagazetka, quick-commerce apps, the Allegro API for showing offers, Barbora, and every blocked shop above (link only, or ask the shop to allow DoddyBot).

**Owner or lawyer, when applying:** who is the publisher (a private person can join Ceneo, Webepartners, Convertiser and x-kom; Allegro Affiliate Business needs a company with VAT); declaring the iOS app next to doddy.lol and getting written approval where a programme defines a website; confirming that links to `allegro.pl/listing?string=` and Ceneo search pages are tracked; whether a spoken summary beside a labelled link "modifies" a network's materials (Awin §10.1, Convertiser §6.2j, Allegro §6.3); which traffic type to declare (price comparison changes Euro's rate and can be forbidden at Kelkoo); Allegro's cookie length (ask Tradedoubler); Amazon's oral-offer clause; where Ceneo's AI notice goes in the app.
