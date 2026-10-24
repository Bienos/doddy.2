# Shopping mode: grocery leaflets ("gazetki") (24 Oct 2026)

Research for the shopping-mode proposal (`docs/strategy/TRYB_ZAKUPOW_2026-10.md`). Checked 2026-10-24 by a research agent in this session with one or two fetches per site and the App Store Search API. Tags: **[V]** seen on the source page, **[S]** secondary source, **[I]** inference. Nothing here is built or tested. Cloud vision calls would be a new use of cloud AI and need the owner's approval (CLAUDE.md rule 6). Not legal advice: a Polish lawyer for database rights must confirm section 3.

## 1. Where each chain publishes its leaflet

| Chain | Source | Format | Structured data |
|---|---|---|---|
| Biedronka | biedronka.pl/pl/gazetki → `/pl/press,id,{id},title,{slug}`; the reader calls `leaflet-api.prod.biedronka.cloud/api/leaflets/{uuid}?ctx=web` | image flipbook | page images only; no product data, no schema.org Product [V] |
| Lidl | lidl.pl/c/nasze-gazetki/s10008614 → `/l/pl/gazetki/{slug}/ar/0`; `endpoints.leaflets.schwarz/v4/flyer?flyer_identifier={slug}` | flipbook + downloadable PDF | partly: offer dates, page images, per-page `keyWords` / `altText` text and `pdfUrl`; only 7 linked products with prices, non-food [V] |
| Kaufland | kaufland.pl/gazetka-promocyjna.html | not checked | bot wall ("Dostęp zablokowany", 403) [V] |
| Auchan | auchan.pl/pl/gazetki (JS app) | Flipsnack reader + PDF | nothing in static HTML [V] |
| Carrefour | carrefour.pl/gazetki | not checked | Cloudflare 403 [V] |
| Dino | marketdino.pl/gazetki/lista/standard; PDFs under api.marketdino.pl/media/… | PDF + page images | yes: page hotspots carry EAN, name, price and position (e.g. "Napój gaz. Pepsi Cola zero 2,25l" 6.69); schema.org only Store/OfferCatalog [V] |
| Netto | netto.pl/gazetka-netto/?leafletid={id} | image flipbook hosted by Tjek | Tjek's API is "only available to customers" [V] |
| Rossmann | rossmann.pl/promocje + gazetka.rossmann.pl/{slug} (Publitas) | product grid + flipbook | yes: name, EAN, price, oldPrice, pricePerUnit, a "Cena z apką" filter [V] |

Żabka uses a Publitas flipbook [V]. Hebe, Intermarché, Pepco and Action returned 403, Cloudflare or a captcha [V]. The robots.txt files of Biedronka, Lidl, Dino, Rossmann, Netto, Auchan and Żabka had no rules naming AI bots in a quick check [V].

## 2. Aggregators

None publishes a public API, a price list or an affiliate programme for offer data; all sell advertising and accept partnership enquiries.

| Service | Owner | Data access |
|---|---|---|
| Blix | Grupa Blix Sp. z o.o., Poznań (also Qpony, Zdrowe Zakupy) | ads and reports, grupablix.pl/wspolpraca; terms §5.5 ban bots, §3.3 claims database rights [V] |
| Ding.pl, Okazjum (Promoceny.pl redirects to ding.pl) | INTERIA.PL sp. z o.o. | internal GraphQL, not public; terms forbid copying or compiling [V] |
| Gazetki.pl | Kingbee B.V., Amsterdam | terms 13.3: no selling or using any content [V] |
| Moja Gazetka | Moja Gazetka Sp. z o.o., Racibórz | b2b.mojagazetka.com: ads, heatmaps, list analytics; no API [V] |
| Gazetkowo | spun off from RTB House in 2025 | retail-media ads [S] |
| Kimbino / Gazetkonosz | Kimbino Green s.r.o. | b2b.kimbino.net exists, content unreadable [V] |
| Tiendeo | ShopFully (bought 2022) | drive-to-store ads [V/S] |
| Marktguru | DE/AT only | — [V] |
| Bonial / kaufDA | Bonial International | no public API found [S] |

## 3. Law

- **Database right** (Directive 96/9 art. 7; Polish ustawa o ochronie baz danych, Dz.U. 2024 poz. 1769) [V]. In *BHB v William Hill* (C‑203/02) money spent creating the data does not count, only obtaining, verifying or presenting it [V], so a chain's own prices may be weakly protected and aggregators that digitise leaflets have a stronger claim [I].
- ***Innoweb*** (C‑202/12, 2013): a dedicated meta search engine re-utilises the databases it searches [V].
- ***CV‑Online*** (C‑762/19, 2021): a specialised search engine that copies and indexes a substantial part of a public database extracts and re-utilises it, which can be prohibited where it risks the maker's return on investment [V]. **A central Doddy index of all leaflets fits this pattern** [I].
- ***Ryanair*** (C‑30/14, 2015): where a database is not protected, contract terms can still bind users [V]. Biedronka's terms §9.1: personal use only, copying needs consent; §2.4: browsing means accepting the terms [V].
- **Copyright:** bare prices are facts; photos and layout are works, so no storing or showing leaflet images without a licence [I].
- **Text and data mining** (DSM art. 4): Poland's art. 26³ of the copyright act and art. 8a of the database act, in force since 20.09.2024 (Dz.U. 2024 poz. 1254), allow reproduction for automated analysis unless reserved in machine-readable form; copies kept only as long as the analysis needs [V]. It covers copying for analysis, not serving the content to the public [I].
- **Bot blocks:** never get around them; link out instead [I].

Options, safest last: (1) a licensed feed from an aggregator or Tjek; (2) permission from chains that already publish structured data (Lidl, Dino, Rossmann); (3) a single fetch triggered by the user, facts only, from the official source; (4) link out only.

## 4. Omnibus (lowest price in the previous 30 days)

Art. 4 ust. 2–5 of the 2014 price-information act: any announced price cut shows the lowest price of the previous 30 days (perishables: the price before the first cut); advertising is covered [V eli.gov.pl]. UOKiK guidance [V uokik.gov.pl/download/27128]: applies to leaflets and to discounts that need a loyalty programme or an app coupon; "2+1" and "best price" slogans are not price-cut announcements. CJEU *ALDI Süd* (C‑330/23): a "promo" at or above the 30-day low is a fake reduction [S]. UOKiK fined Zalando about 30.9M zł and Temu about 5.9M zł (12.01.2026) [V]; no grocery-chain decision found [I]. Doddy can read the printed 30-day price, compute the real discount and flag a promo at or above it; checking the printed figure itself would need its own price history [I].

## 5. Existing apps (Polish App Store, 24 Oct 2026) [V]

Moja Gazetka 4.74 (18,017 ratings); Blix 4.77 (6,393; crash reviews after a Dec 2025 update); Gazetkowo 4.83 (6,318); Okazjum 4.67 (4,157); Listonic 4.75 (27,040); Biedronka's own app 3.56. All browse-first [I]. **Koszyk Zakupowy** (ASM Group, Jul 2025): staff check a fixed basket in 13 chains weekly [S]; 2 ratings, no update since 8.07.2025 [V]. **Tańszy Koszyk** (web, tanszykoszyk.pl): 12 chains, conditions shown (card, app, quantity), coverage ("8 of 10 items"), flagged substitutes, price history [V]; it reports 42 live leaflets with 1,187 pages on 7.10.2026 and that **91% of leaflet products appeared in only one chain** [S], so comparison is usually by unit price and similar product, not the identical item [I]. Also seen: Do Koszyka (web), ZenKoszyk (receipt scanning), Wózek (not launched) [V].

## 6. Reading leaflets with vision models

Accuracy: arXiv 2408.15626 (GPT‑4o, 50 retail images): price 1.00, discount 0.72, unit price 0.46, product name 0.0 [V]. arXiv 2504.11838 (1,101 leaflet crops; GPT‑4o, 4o-mini, Gemini 2.0 Flash): price 88–92%, regular price 32–49%, relative discount 30–39% [V]. Single-page Japanese flyer tests (zenn.dev, Nov 2025): Gemini 3 Pro 10 of 20 items with 1 hallucination; Claude Sonnet 4.5 0 of 20 with 15 hallucinations [V]. No Polish benchmark exists [I]. **Headline prices are reliable; promo mechanics, unit prices, small print and dates are not**: crop pages, cross-check against text layers, validate the arithmetic, build a ~50-page Polish eval [I].

Cost: Claude Haiku 5.5 $0.10 / $0.50 per million tokens, batch −50%; image tokens ⌈w/28⌉ × ⌈h/28⌉, capped at 4,784 per image [V]. A Lidl page at 1420 × 2400 is about 4,386 tokens, so about **$0.0012 per page** with ~1.5k output tokens; a weekly pass of ~1,200 pages about $1.5–3 [I]. Alternatives [V]: Gemini 2.5 Flash-Lite $0.10 / $0.40; Gemini 3.1 Flash-Lite $0.25 / $1.50; gpt‑5‑nano $0.05 / $0.40; gpt‑5‑mini $0.25 / $2.00 (image token counting differs by vendor).

## Recommendation for v1

1. **Open chains only:** Lidl, Biedronka, Dino, Rossmann. Kaufland, Carrefour, Auchan and the rest: a link to the leaflet.
2. **User-triggered:** after the user asks, the official leaflet is fetched, candidate pages are narrowed with the published text (Lidl keyWords, Dino and Rossmann data) or on-device OCR, and only 1–3 cropped pages go through Doddy's server to Haiku 5.5: about $0.01 per question [I].
3. **Store nothing shared:** no images, no index across users. The answer gives the cheapest unit price, conditions, validity dates, the 30-day price, the source link, and which chains were not checked; failures are "unknown" [I].
4. **In parallel:** ask Grupa Blix, Interia (Ding/Okazjum), Moja Gazetka, Kimbino B2B and Tjek for licensed feeds for v2. Never scrape aggregators.
