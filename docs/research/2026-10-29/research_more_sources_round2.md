# More sources, round 2: other shops, fuel, bills, travel, and more affiliates (29 Oct 2026)

The owner asked "Find more sources" a second time. Round 1 is `research_more_sources_and_affiliates.md` (same day); this round covers what it left out. Three research agents checked on 2026-10-29 with `curl -A "DoddyBot/1.0 (+https://doddy.lol/bot)"`, robots.txt first, a 401/403 robots.txt counted as blocked (as `fetcher.ts` does); no block, challenge or captcha was worked around, and nothing was signed up for, logged into or filled in. The session spot-checked the daily fuel cap (one Monitor Polski notice and eli.gov.pl's robots.txt) and the Orange programme on Tradedoubler. **Slip:** in the spot check, api.sejm.gov.pl's robots.txt answered with a "Request Rejected" page in the same command that fetched one notice PDF from it; use eli.gov.pl, whose robots.txt allows everything, not api.sejm.gov.pl.

Tags: **[V]** seen on the source that day; **[V\*]** the source's own text through a search-index copy because the live page blocked DoddyBot; **[S]** secondary source; **[I]** inference. Not legal advice.

## 1. Other shops

| Chain | Type | Data | Verdict |
|---|---|---|---|
| **Komfort** | home | campaign cards with end dates; the leaflet on Publitas (`spreads.json`, 50 pages) has a text layer with product, size, old and new price, the old price being the 30-day lowest [V] | **code, no model** (the Żabka reader's Publitas path, ADR-660) |
| **CCC** | shoes | price, "Najniższa cena z 30 dni", first price, "-30% w koszyku" in the HTML of category sale pages [V] | code, no model |
| **Tania Książka** | books | price, regular price, 30-day lowest; robots.txt names ClaudeBot as allowed [V] | code, no model |
| **Maxi Zoo** (150+ shops [S]) | pets | 303 promo products: brand, saving %, price, unit price, previous price (not labelled 30-day) [V] | code, no model |
| zooplus | pets, online | price, bundle saving, unit price; `/specials/` disallowed [V] | code, no model |
| **Helios** (52 cinemas [V]) | cinema | per-cinema price list with the SuperWtorek price (18,90 zł in Bydgoszcz) [V] | code, no model |
| Deichmann | shoes | 1,833 promo results with prices and codes ("HALLO20, -20% pow. 319 zł") [V] | code, no model |
| House (LPP) | fashion | page JSON with price and final price; Crawl-delay 10 [V] | code; Mohito's page is 6.8 MB, over the 3 MB cap |
| Ziko Dermo | drugstore | price, 30-day lowest, regular price [V] | code, no model; cosmetics only (see §2) |
| **E.Leclerc** (43–45 shops [S]) | hypermarket | 7 leaflets, page JPGs on its own domain (~287 KB, 1047×1600), no text [V] | page images (model) |
| Spar | supermarket | robots.txt reachable now and allows; 8-page PDF, 2.2 MB, images only [V] | page images (model) |
| Duka | home | price only [V] | weak |
| Selgros | cash & carry | products load from a group API with a key in the page (not called); leaflets behind a consent page [V] | link only |
| Cinema City | cinema | one-off event news ("Święto Kina", 15 zł, over) [V] | link only |
| Sinsay, Reserved, HalfPrice, 4F, Świat Książki | — | 404, no prices, or JavaScript shells [V] | link only |
| Makro, Melissa, Dr.Max, Martes Sport, Kakadu, Agata, Black Red White, Homla, Multikino | — | 403, Cloudflare, connection reset; BRW's robots.txt blocks ClaudeBot and anthropic-ai and has `ai-train=no` [V] | blocked |
| Freshmarket | — | redirects to zabka.pl [V] | folded into Żabka [I] |
| DOZ, Gemini, Cefarm24 | pharmacy | product prices in HTML (DOZ short dates 143 products; Gemini a campaign with 183) [V] | **legal hold** (§2) |

## 2. Pharmacies: the advertising ban

- Art. 94a ust. 1 Prawo farmaceutyczne: "Zabroniona jest reklama aptek i punktów aptecznych oraz ich działalności" (location and opening hours aren't advertising) [S; ISAP not read]. Art. 129b: a fine of up to 50,000 zł for "ten, kto" runs such advertising, so anyone, not only the pharmacy [S].
- NSA II GSK 1232/18 (5.11.2020): a brochure comparing pharmacy prices was banned advertising; the test is intent to draw customers to a pharmacy [S]. NSA II GSK 3292/17: a loyalty programme counts [S].
- CJEU C-200/24 (19.06.2025) found art. 94a ust. 1 contrary to the e-Commerce Directive and the TFEU; the statute stands, and Warsaw's administrative court is annulling fines [S]. Sejm print 3002 would allow pharmacy advertising but ban purchase-linked benefits and comparative advertising, with fines up to 100,000 zł [V of the DZP alert]; not enacted as far as found [S].
- **For Doddy [I]:** no pharmacy source until a legal opinion and the bill's outcome. If anything, Ziko Dermo's cosmetics only. Never pharmacy promotions with mechanics ("3+1", "gratis"), price comparison between pharmacies, pharmacy affiliate money, or prescription and reimbursed medicines.

## 3. Fuel, bills, food, travel

| Source | Data | Access and terms | Verdict |
|---|---|---|---|
| **Daily legal maximum fuel price** (Minister of Energy notice in Monitor Polski) | Pb95, Pb98 and diesel cap per litre, with and without VAT, for the next day [V; session spot check of M.P. 2026 poz. 983: Pb95 6,39 zł net, 6,90 zł with VAT] | eli.gov.pl, robots.txt allows all [V]; gov.pl text CC BY-SA 4.0 [V]; the cap applies only while the reduced VAT runs (art. 34a ust. 1, Dz.U. 2026/415) [V]; the package runs to the end of 2026 [S] | **usable now**: it's a ceiling, not the pump price, and has no LPG |
| **EU Weekly Oil Bulletin** | Poland's weekly average (95, diesel, LPG), with and without taxes [V] | CC BY 4.0, credit the Commission [V] | **usable now** |
| **URE "Masz wybór" offer sheets** | about 475 household electricity offers: gross G11/G12/G13 prices, fees, dates, notice, penalties; sale price only, no distribution cost (16.10.2026) [V] | public xlsx, 1.1 MB [V]; no licence statement found, re-use of public information [I] | **usable now** |
| Google Places API (New) `fuelOptions` | per-station fuel price with `updateTime` [V] | billing; Enterprise + Atmosphere tier, 1,000 free a month, then $40 per 1,000 [V]; no caching or storing; Google attribution; EEA terms; in Poland the prices come from owners and users, at about half the stations [S] | only after a coverage test (~20 calls) [I] |
| Circle K `/promocje`, KFC `/kupony` | text offers, coupons with prices [V] | public; terms not read (KFC's are under a disallowed path) [V] | after a person reads the terms |
| PKP Intercity | discount rules (Rodzinny −30%, Senior −30%, students −51%) [V] | Super Promo prices only in the booking system; partner API applications "od IV kwartału 2027 r." [V] | rules usable now; prices later |
| FlixBus | — | Awin affiliate allows sites, blogs and apps [V]; API through online-distribution@flixbus.com [V] | affiliate now; API by contract |
| Ryanair, Wizz Air | fares | Ryanair: written licence for price comparison, its API [V\*]; Wizz: partner portal [S]; scraping prohibited [V\*] | contract or licence |
| Orlen wholesale JSON | refinery prices [V] | "Żadna część serwisu nie może być w celach komercyjnych kopiowana… bez uprzedniej pisemnej zgody" [V] | written consent |
| e-petrol.pl, Yanosik | averages, crowd prices | paid licence; B2B data sales [V\*/S] | contract |
| AutoCentrum, Wolt, Too Good To Go, Bankier.pl | — | terms forbid copying, robots or commercial use [V/V\*] | out (TGTG and Foodsi: ask for a partnership) |
| Apple MapKit, UKE telecom comparison | no fuel fields; no UKE tool live [V/S] | — | not available |

## 4. More affiliate programmes

| Programme | Pays | Fit | Watch out for |
|---|---|---|---|
| **Orange** (Tradedoubler 51374) | Flex 178,50 zł, AKW 221 zł, FTTH 300 zł per sale; 45-day cookie [V] | "Aplikacja mobilna", price comparison and cashback allowed [V; session spot check] | creatives can't be reworked; no search ads [V] |
| **nju mobile** (Tradedoubler 242338) | 161,50 zł per sale; 30 days [V] | mobile app and price comparison allowed [V] | content traffic "conditional" |
| **Komputronik** direct | 2%, up to 10%; 100 zł payout [V] | "aplikacja" is a listed channel; any product; private persons [V] | apps that overwrite source parameters excluded |
| **FlixBus PL** (Awin 110870) | % of the order; 60 days [V] | deep links [V] | no voucher reselling |
| **System Partnerski** (Bonnier) | per campaign; 50 zł payout [V] | product API with the rates banks send to Bankier.pl [V] | bank accounts and deposits only (§5) |
| **eSky Partners** | flights up to 80% of eSky's fee; hotels 50% of its margin [V, FAQ 2017–19] | deals API [V] | exclude its insurance (§5) |
| **Pyszne.pl** (Awin 12109) | 3%, 7 days [V] | in-app tracking only for selected publishers [V] | ask them to enable it |
| TUI PL (Tradedoubler 308388) | 3–8% [V] | — | **bans the words "rabat, przecena, zniżka"** [V] |
| Wakacje.pl / TravelLead | about 4% [V] | — | **§11 bans personal recommendations, naming chatbots and AI** [V]: hold |
| Skyscanner | share of its commission [V] | — | needs more than 5,000 monthly visitors [V] |
| Booking.com (CJ), Expedia (up to 4%), Trip.com (no Polish programme), Kiwi.com (invitation only), Play on Webepartners (56,25 zł [S]) | various | — | later |
| Payback, Goodie, Letyshops, Picodi | — | merchant-side or competitors | not usable |

## 5. Finance and insurance: the legal frame

- **Consumer credit** (Dz.U. 2025 poz. 1362) [V]: a "pośrednik kredytowy" (art. 5 pkt 3) earns a benefit for acts connected with offering credit; it needs entry in the KNF register before starting (art. 59da), with fines up to 100,000 zł (art. 59i). Credit adverts must give the rate, total and RRSO "co najmniej tak samo widoczny, czytelny i słyszalny" (art. 7a), which reaches a spoken answer. The new EU Consumer Credit Directive applies from 20.11.2026; Poland's act wasn't found passed [S].
- **Insurance distribution** (Dz.U. 2026 poz. 12) [V]: comparing policies by the client's criteria through websites "lub innych mediów", where the client can then buy, is distribution (art. 4 ust. 2); passing on information without further steps isn't (art. 6 pkt 4). Agency acts without authority are a crime (art. 89).
- **Unfair practices** (UPNPR art. 7 pkt 11a, art. 6 ust. 4 pkt 8) [V]: paid placement must be disclosed and the main ranking parameters published. Doddy's "never ranked by commission" rule should be published as that statement.
- **Verdict [I]:** bank accounts, deposits and savings as labelled links: allowed. Loans, credit cards, BNPL, payday loans and mortgages: avoid (or register with KNF and say the RRSO aloud). Insurance: one labelled link to a licensed comparison site with no ranking by Doddy is probably fine; Doddy comparing policies needs agent status, so avoid.

## 6. Proposal, after round 1

1. **Code only, no permission:** Komfort (Publitas text, as Żabka), CCC, Tania Książka, Maxi Zoo, Helios's SuperWtorek prices. Then Deichmann and House.
2. **New questions Doddy could answer:** "what's the maximum fuel price today" (the Ministry's daily notice on eli.gov.pl, credited, said as a ceiling), the weekly national average (EU Oil Bulletin), and "the cheapest electricity offer" (URE's sheet, saying distribution costs aren't included).
3. **Page images:** E.Leclerc, then Spar, after Delikatesy Centrum (round 1).
4. **Affiliates to add:** Orange and nju mobile on the Tradedoubler account (flat fee per contract, apps allowed), Komputronik direct, FlixBus on Awin, System Partnerski for accounts and deposits only, eSky without insurance, Pyszne.pl once in-app tracking is enabled.
5. **Hold:** pharmacies (legal opinion first), TravelLead (written consent), TUI (its banned words), loans and insurance comparisons.
6. **Ask for access:** a Google `fuelOptions` coverage test (needs a billing account), Ryanair's licence, Orlen's consent, partnerships with Too Good To Go, Foodsi and Yanosik.
