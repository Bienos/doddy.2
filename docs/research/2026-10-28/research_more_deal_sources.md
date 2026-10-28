# More leaflets, other promotions and student discounts (28 Oct 2026)

The owner asked (in Polish): which other leaflets, promotions and student promotions can Doddy connect? Checked on 2026-10-28 from a cloud session: the chains through Doddy's own fetcher (`server/messaging/src/deals/fetcher.ts`: User-Agent `DoddyBot/1.0`, robots.txt, block and challenge detection), the rest by two research agents with `curl -A "DoddyBot/1.0 (+https://doddy.lol/bot)"`, web search and spot checks. No block was worked around. Tags: **[V]** seen on the source that day, **[S]** secondary source, **[I]** inference. Not legal advice. What was built from it: ADR-658 (Aldi and Żabka). The rules that still apply: `research_shopping_leaflets.md` (24 Oct) and ADR-609 (read on request, nothing stored, no shared index without a licence).

## 1. Leaflets of other chains

| Chain | What Doddy's fetcher got | Data | Verdict |
|---|---|---|---|
| **Aldi** | `www.aldi.pl/oferty.html` 200, robots.txt allows it [V] | Next.js `__NEXT_DATA__` with 66 offers: name, pack, price, price per kg, conditions ("PRZY ZAKUPIE 2 SZT.", "CO DRUGA SZT.", "1+1 GRATIS"), regular price, the 30-day text, dates [V] | **Built (ADR-658)**: code only, no model |
| **Żabka** | `www.zabka.pl/gazetka-promocyjna/` 200; `gazetka.zabka.pl/{slug}/spreads.json` 200; page images on `view.publitas.com`; no robots.txt on either Publitas host (404) [V] | Żabka's own text for each of 72 pages; 12 pages carry the legal beer warning [V] | **Built (ADR-658)**: text picks pages, the reader reads prices; beer pages skipped |
| Stokrotka | `stokrotka.pl/oferta/gazetki-promocyjne/` and a link to mojagazetka.com [V] | not looked into | later |
| Intermarché | `intermarche.pl/gazetki-promocyjne/` 200, robots.txt allows [V] | no product data in the HTML [V]; probably images [I] | later |
| Delikatesy Centrum | `www.delikatesy.pl/gazetki` 200 [V] | PDFs of 18 MB on `static.delikatesy.pl` [V], over the fetcher's 3 MB cap | later, costly |
| POLOmarket | `polomarket.pl/gazetka/` 200 (Nuxt) [V] | online shop prices; leaflet format not checked | later |
| Netto | 200; leaflet in Tjek's viewer [V] | Tjek's API is for its customers [V, 24 Oct] | link, or a Tjek licence |
| Kaufland, Carrefour, Hebe | challenge or 403 [V] | — | link only |
| Auchan (leaflets) | 200 but a 2 KB script shell [V] | nothing in the HTML | link only |
| Spar | robots.txt unreachable, so nothing is fetched (RFC 9309) [V] | — | link only |
| Lewiatan, Topaz, Pepco, Stokrotka (guessed URLs) | 500 or 404 at the addresses tried [V] | — | find the right page first |

## 2. Promotions beyond the leaflets

| Source | Access | Terms | DoddyBot | Verdict |
|---|---|---|---|---|
| IKEA `/pl/pl/offers/` | page JSON: salesPrice, previous price, the 30-day text, dates, IKEA Family price [V] | — | 200, allowed [V] | on-request read, like Rossmann |
| Action `/pl-pl/promocja-tygodnia/` | page JSON: price, unit price, discount, the 30-day note [V] | — | 200 [V] | on-request read |
| Auchan online `zakupy.auchan.pl/promotions` | schema.org ItemList and "najniższa cena" [V] | robots.txt blocks `/offers`, not `/promotions` [V] | 200 [V] | on-request read |
| Pepco `/trendy/oferta-gazetkowa` | prices in HTML only [V] | Crawl-delay 1 | 200 [V] | possible, weak data |
| **Webepartners, Convertiser** (Polish affiliate networks) | voucher and promotion APIs/feeds [V] | publisher account; each advertiser approves; coupon model needs consent (Webepartners §2.27) [V] | — | **best licensed source of codes**; owner decision |
| Tradedoubler, Awin | Vouchers API; Promotions API with `regionCodes: ["PL"]` [V] | Awin PL terms §10.1: publish advertiser materials "bez modyfikacji" [V] | — | as above; check whether a spoken summary is allowed |
| Pepper.pl | public RSS (`/rss/...`) [V] | terms forbid copying and third-party use; coupons "wyłącznie do celów prywatnych i niekomercyjnych" [V]; robots.txt disallows ClaudeBot and anthropic-ai [V] | 200 for `*` [V] | out without a licence |
| Picodi/Kodyrabatowe, Rabato, Okazje.info | public pages | copying needs consent; aggregator database right [V/I] | 200 | out |
| Ceneo, Groupon | partner API only for partners [S]; Groupon `ai-train=no` [V] | — | captcha, 403 [V] | out |
| Media Expert, x-kom, Notino, Decathlon, Leroy Merlin, RTV Euro AGD | — | RTV Euro AGD's robots.txt welcomes AI bots but its promo pages show a block page [V] | challenge or captcha [V] | ask the shops; until then affiliate or link |
| Frisco promotions | — | disallowed in robots.txt [V] | — | out |
| Moja Biedronka, Lidl Plus, Żappka, Rossmann and Hebe apps | no public or partner API found [I]; coupons are personal [S] | — | — | link only |
| GUS, dane.gov.pl | GUS retail price series end in 2019 [V]; nothing on promotions | — | — | not useful |

## 3. Student discounts

No student-discount platform has a public API or feed [V/I]. The facts that are safest to use are the legal ones.

| Offer | Discount or price | Who | Tag |
|---|---|---|---|
| PKP Intercity | 51%, combinable with promotions | students under 26; doctoral students under 35 | [V] intercity.pl |
| Regional rail | 51% by law | under 26 | [S] |
| Warsaw public transport | 50% | Polish students with a valid ID; foreign students under 26 with ISIC | [V] warszawa19115.pl (14.01.2026) |
| Kraków public transport | 50%; yearly student ticket 470 zł | as above | [V] ztp.krakow.pl |
| State museums | reduced ticket by law (museum act art. 10 ust. 3a) | students | [S] |
| Spotify Premium Student | 14,49 zł/month, first month 0 zł | approved universities, SheerID | [V] spotify.com/pl/premium (price also seen in a spot check) |
| Apple Music, student plan | 14,49 zł/month | verified students | [V] apple.com/pl/apple-music (spot check) |
| YouTube Premium Student | 18,99 zł | — | [S], not verified |
| GitHub Student Pack, JetBrains | free | verified students | [V] |
| Adobe Creative Cloud Pro | €19,99/month in year one | students, buyer 18+ | [V] |
| Orange Flex | 6 TB for students, via Uniperks | — | [S] |
| Amazon Prime Student | not offered on amazon.pl (`/primestudent` 404) | — | [V] |
| Allegro Smart! Student | closed to new sign-ups since 4.09.2024 | — | [S] |
| Grocery and drugstore chains | no student programme found (Biedronka, Lidl, Rossmann, Żabka, Netto, Auchan); Douglas 23% only through ISIC or Uniperks | — | [V] weak (script-loaded pages) |

Platforms: ISIC Polska (website, an SDK on request, info@isic.pl) [V]; Uniperks (website only; robots.txt blocks code pages) [V]; Student Beans (terms §9 no copying, §4 no sharing codes) [V]; UNiDAYS (website) [V]; EURO<26 (not reachable from here); ESNcard (Cloudflare). All link-only until a written agreement.

## 4. What to connect, in order (proposal)

1. **Aldi and Żabka** as leaflet chains: built, ADR-658.
2. **Student discounts as a short list kept in code**: the legal discounts (rail, city transport, museums) and the brand student plans, each with its official address and the day it was checked; a price is read from the brand's own page when the user asks, and when it can't be, Doddy says it couldn't confirm the price and gives the link. Doddy never checks student status itself: the user says they are a student, and Doddy says where to verify (SheerID, UNiDAYS, ISIC, the university email). Kept as a memory only with consent and a confirmed write.
3. **IKEA, Action, Auchan online** as on-request promotion pages (code reads their data, as Rossmann).
4. **Codes from Webepartners and Convertiser**, if the owner opens publisher accounts: licensed, so a cache is allowed within the licence; a code nobody tested is said as untested; ranking before any affiliate link (ADR-612).
5. Ask ISIC, Uniperks and Pepper for a partnership; ask RTV Euro AGD, Media Expert, x-kom, Hebe and Notino to allow DoddyBot.

**Owner or lawyer:** whether the affiliate networks need a company (NIP); whether licensed content may be summarised by voice (Awin's "bez modyfikacji"); whether Doddy saying "−25%" is announcing a price cut under the Omnibus rule (art. 4 ust. 2); the partnership requests.
