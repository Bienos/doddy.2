# Travel: research and plan (11 Nov 2026)

**Status: a plan. Nothing here is built.** Decision: `docs/decisions/2026-11-11-travel-agent-plan.md` (proposal, owner approval pending). The research is web research done on 11 Nov 2026; no travel API was called, no account was opened and no terms were signed. Items marked *unverified* rest on third-party pages or on pages that could not be opened.

## 1. What the owner asked for

In the owner's words (Polish, 11 Nov 2026, shortened): connect Doddy to travel portals (Skyscanner, Kayak, Booking, Airbnb, Wakacyjni Piraci, "podróżnik"); a standby mode where Doddy keeps looking and tells the person when a matching offer appears; a planner the person talks to, where Doddy asks for what is missing and then writes a report; Doddy phoning a place for the person and reporting back; booking; and last-minute offers Doddy finds by itself and shows to people.

That is five features. They are planned as five stages because they differ a lot in risk: reading prices is cheap and safe, taking money for a trip makes Doddy a travel seller.

## 2. What Doddy already has (read in the code, 11 Nov 2026)

| Need | Already in the repository | State |
|---|---|---|
| Hand a trip over and get a report | Errands (`server/messaging/src/errands/`, ADR-570): one tap, a background researcher with web search and fetch, a result card whose prices keep only the links the run really opened. The researcher's prompt already has a travel paragraph. | Built; `ERRANDS_ENABLED` default 0; never run against the real API |
| Prices that come from code, not from the model | Shopping errands (`src/shopping/`, ADR-607): the runner calls tools the code runs, and every price, shop and link on the card comes from the code's record. | Built |
| Standby: check in the background, push when something matches | Price watches (`src/watches/`, 013), Radar alerts (`src/news/`, 026): a claimed worker loop, dedupe table, quiet hours, a daily push cap, the outbox. | Built; radar reported on, watches off |
| Phone a place and bring the answer back | Calls for you (`src/taskCalls/`, `call_places`): up to three places, one question, exact payload approved on a card, answer card. The first sentence is fixed in code: "Dzień dobry, mówi Doddy, asystent AI, dzwonię w imieniu …". Audio is never recorded. | Built; **Polish numbers only**, 8:00–23:00 Warsaw |
| Partner links with a notice | `src/shopping/affiliate.ts`, `AFFILIATE_LINKS` (empty by default), the partner-link wording of ADR-612/668. | Built, no partner signed |
| Places and their phone numbers | The `find_places` voice tool. | Live |

So the travel feature is mostly new **data sources** and one new **watch type** on machinery that exists. No new kind of infrastructure is needed for stages 1 to 4.

## 3. Research: which portals can be connected

### The portals the owner named

| Portal | Can Doddy connect? | How |
|---|---|---|
| **Skyscanner** | **No API for us now.** The Travel API is by approval: an established business with more than 100,000 monthly visits; start-ups without a finished product are excluded by name. | Affiliate links only (programme on Impact). Apply again once Doddy has traffic. |
| **Kayak** | **No API for us now.** Offered "on a limited basis" after Kayak reviews the site and traffic. No official MCP server; the "Kayak MCP" offers are third-party scrapers. | Affiliate deeplinks only. |
| **Booking.com** | **No search API for us.** The Demand API needs managed-partner status, a contract and an account manager. The direct affiliate programme closed to small partners in June 2025; new ones join through CJ (Europe) or Awin. | Deeplinks, through CJ or through Stay22 (below). |
| **Airbnb** | **No.** No public API, the affiliate programme closed in 2021, the terms ban bots and scrapers. | A plain link to an Airbnb search for the place and dates. No prices read. |
| **Wakacyjni Piraci, Fly4free** | No API, feed or partner documentation found (*unverified*). They are editorial deal sites: software proposes, editors pick. | Ask them for a partnership. Until then Doddy's own "finds" (stage 3) do the same job from sources we are allowed to read. |
| **e-podroznik.pl, Koleo, PKP Intercity** | No partner API. PKP Intercity accepts no new integrations until at least the end of 2027. | Links only. |

**Scraping is not an option.** Ryanair has won in court against screen scrapers (CJEU C-30/14; a US jury verdict against Booking.com in 2024), Google sued SerpApi in December 2025, and Airbnb's terms forbid it. Doddy's rule (verify real platform APIs before advertising a feature) points the same way.

### What a small company can use today

| Source | What it gives | Access | Cost | Limits to respect |
|---|---|---|---|---|
| **Kiwi.com MCP server** (`mcp.kiwi.com`) | Live flight search with a booking link per result; includes low-cost carriers (Kiwi is an approved Ryanair seller). | Public, no key. | Free. | **Commercial terms and rate limits for a third-party app are not published. Ask Kiwi before shipping.** |
| **Travelpayouts** (Aviasales Data API + partner links) | Cached "from X" prices by route and month; partner links to Kiwi, Trip.com and others. | Self-serve. | Free; commission per sale. | Prices are 2 to 7 days old and come from other people's searches, so Polish routes may be thin. The live search API needs 50,000 monthly users. Good for watching, never for quoting an exact fare. |
| **wakacje.pl TravelLead** | Package holidays from most Polish tour operators: deep links, a product feed, a search widget. | Free sign-up with verification. | About 4% of the trip's value to us. | Feed format not stated (*unverified*). |
| **Itaka (Tradedoubler), eSky (direct)** | Deeplinks to named Polish brands. | Apply. | Commission. | Feeds *unverified*. |
| **Stay22 "Allez" links** | One link that sends the person to Booking.com, Expedia and others for a place and dates. | Self-serve, no key. | Revenue share (rate not published). | Links only, no prices. |
| **Viator, Tiqets** | Things to do: search plus a link to book on their site. | Viator basic is instant; Tiqets on request. | Commission. | |
| **Google Places** | Hotel facts, ratings, phone numbers. | Self-serve, paid per call. | Per call. | Only the place id may be stored; attribution required. |
| **Duffel** | Real flight booking (and hotels) inside the app, under Duffel's own IATA accreditation. | Self-serve test mode. | $3 per order + 1% + $0.005 per search over 1,500 searches per order. | **No Ryanair, no Wizz Air.** Booking makes us the seller. Stage 5 only. |

Not available: Amadeus Self-Service (shut down in 2026; third parties give 17 July), Kiwi Tequila (closed to new partners since May 2024), Google Flights (no API), Expedia Rapid, Hotelbeds and RateHawk (contracts and certification), MerlinX (the Polish agents' booking system; built for agencies).

### Law that shapes the design (not legal advice; a Polish lawyer must confirm before stages 4 abroad and 5)

- **Selling travel.** Under the Polish act on package travel, an organiser or a trader who facilitates linked arrangements must be in the marshal's register and hold insolvency cover. Showing prices and sending the person to the seller is a referral: the seller takes the money and carries those duties. Taking payment in the app, or putting a flight and a hotel into one price or one checkout, is selling travel. The EU's revised directive (2026/1024) changes the definitions, but Poland has not transposed it yet.
- **Price notifications.** The Omnibus rule requires the lowest price of the last 30 days whenever a trader announces a reduction; UOKiK has fined shops for getting it wrong. Doddy states facts only ("412 zł now, 520 zł when you set this, checked 14:05, may change") and never writes "−20%", "sale" or "last chance".
- **AI phone calls.** EU AI Act Article 50 has applied since 2 Aug 2026: the person must be told at the start that they talk to an AI. Doddy's fixed opening already does this. A customer's question to a hotel is not marketing, so the Polish telemarketing rule (PKE art. 398) should not apply (*an inference; no official interpretation found*); the call must never advertise Doddy. Recording rules differ by country, and Doddy keeps no audio.
- **Paying for someone.** Under PSD2 the cardholder must authenticate each payment (3-D Secure). Card-network "agent payments" are early in Europe (Visa: live with some issuers since July 2026; Mastercard, Stripe/OpenAI and Google's AP2: not available). The low-risk design is a handoff to the seller's checkout.

## 4. The plan

### Rules for every stage (constitution)

- **Prices and links come from code** (DOD-02, DOD-08): a price on a card or in a push is one a source returned in this run, with the source's name and the time it was read. The model orders and explains; it never supplies a number.
- **One exact approval per thing that runs or leaves** (DOD-07, ASK-01): a trip search, a watch and a call each get a card showing exactly what will be sent, approved by a tap bound to its digest. A spoken yes starts nothing.
- **"Booked" only from the seller's confirmation** (DOD-08). In stages 1 to 4 Doddy never says booked; it says "open to book".
- **Portal text is data** (R-TOOLS): offers, pages and feeds never instruct Doddy.
- **No pressure** (DOD-10): no countdowns, no invented scarcity, quiet hours, a daily cap, and one tap to stop a watch.
- **Partner links are labelled**, and a partner never changes the order of results. Sorting is by the person's own priorities.
- **Privacy** (DOD-11): a search sends the route, dates and number of people to the source, never the person's name, account or notes. "What leaves this iPhone" and the privacy policy get a travel section before anything is switched on.

### Stage 1: the trip planner

*The person describes a trip by voice or typing; Doddy asks for what is missing; a report arrives.*

- **Trip brief** (new type in DoddyCore, shared fixture): from where, where to (a place, or "anywhere warm"), when (dates or a window, and how flexible), how long, who (adults, children with ages), budget and currency, what kind (flight + hotel on their own, or a package), must-haves (direct flight, all inclusive, near the beach, a pet).
- **Questions:** a new voice tool `plan_trip` fills the brief. Doddy asks only for the fields without which a search can't run (from, when, how long, who), one at a time, and states any assumption out loud ("I'll assume two adults from Gdańsk"). Budget and the rest are optional: Doddy asks once and goes on. Today's task mode allows one question; travel needs up to four, which is a change to `voice-agent/instructions.md`.
- **The run:** a new errand kind `travel`, built like the shopping runner. Tools the code runs: `search_flights` (Kiwi MCP, with Travelpayouts as the fallback and for "cheapest month"), `search_packages` (TravelLead), `stay_links` (Stay22 and a plain Airbnb search link), `things_to_do` (Viator), plus web search and fetch for weather, the area and what the place is like.
- **The report:** a travel result card: two or three complete options ("cheapest", "best fit", "most comfortable"), each with the flight, the stay or the package, the total as far as it is known, what is *not* included, the source and time of each price, an honest note on the place in that season, what Doddy couldn't find, and three follow-ups: **Watch this**, **Call and ask**, **Open to book**.
- **Tests:** brief validation and digest; a card never carries a price the code didn't record; a source that fails or times out is named on the card; a refusal when no source is set up.

### Stage 2: standby ("tell me when something comes up")

*A trip watch: Doddy's server checks, and pushes when an offer matches.*

- From a report ("Watch this") or by voice ("daj znać, jak lot do Lizbony w maju spadnie poniżej 600 zł", "jak pojawi się all inclusive w Grecji do 2500 zł za osobę").
- A new migration with `travel_watches` and `travel_hits` (new tables only, sorting after 026), encrypted content, a digest approved on a card, at most N open watches per account, an end date (the trip's date or 60 days).
- The worker copies the radar loop: claim with `FOR UPDATE SKIP LOCKED`, check the cached source 2 to 4 times a day, and **when the cached price crosses the person's limit, run one live search before any push**. A price that the live check doesn't confirm is not sent.
- The push states facts, respects quiet hours and a daily cap, and opens the offer in Doddy. Without a push token the hit waits in the app, as radar does.
- **Cost:** about 3,000 watches polled on the cached source cost nothing in API fees; the live re-check runs only on a crossing.
- **Needs:** an always-on worker. On Render's free plan the worker sleeps with the web service, so watches would only run while someone uses Doddy.

### Stage 3: Doddy's finds (last minute for everyone)

*Doddy looks by itself and shows what it found.*

- A scheduled server job reads the same sources for departures from Polish airports and for packages leaving in the next 14 days, keeps the lowest prices per destination, and stores a short list. No personal data is involved.
- A screen ("Okazje od Doddy'ego", working name) shows the list: the route or package, the price, the source, when it was read, and a partner-link label. A tap opens the offer; "Watch this" makes it a stage 2 watch.
- Pushes about finds are opt-in, off by default, with the home airport as the only setting.
- No "−40%" claims: Doddy has no price history at the start. After 30 days of its own readings it may say "the lowest Doddy has seen in 30 days", which is a fact it holds.

### Stage 4: Doddy calls for you

*"Zadzwoń do hotelu i zapytaj, czy mają parking i późne zameldowanie."*

- Reuses Calls for you unchanged for **Polish** places: the report's "Call and ask" opens the existing `call_places` card with the place's number from `find_places`.
- **Abroad is a separate owner decision.** Today's hard limit is Polish numbers. Opening other countries needs: a list of countries, the language of the call, that country's rules on AI calls and recording, calling hours in the place's time zone, the Twilio price per country, and a lawyer's yes.
- To add: a per-number "don't call again" list honoured when a business asks during a call.

### Stage 5: booking

- **5a, handoff (with stage 1):** "Open to book" opens the seller's page with the search filled in. The person pays there. Doddy offers to save the trip to the calendar and a note **after the person says it's booked**, and words it as the person's report, not Doddy's confirmation.
- **5b, booking inside Doddy (later, only on the owner's decision):** Duffel for flights: the exact itinerary, passengers and price on an approval card, the person completes 3-D Secure, and Doddy says "booked" only when Duffel returns a confirmed order; `unknown` is shown as unknown and never retried blindly. Before it: a lawyer's opinion on seller status, terms of sale, a support and refund process, and the fact that Ryanair and Wizz Air are not in Duffel. Packages and hotel + flight bundles stay handoff-only.

### Order and size

| Stage | Depends on | Size |
|---|---|---|
| 1 Planner | Kiwi's answer on terms, or Travelpayouts alone; TravelLead account; errands switched on | Server runner + card + one voice tool + one screen |
| 2 Standby | Stage 1's sources; always-on worker; APNs working | One migration, one worker loop, cards |
| 3 Finds | Stage 2's reading code | One job, one screen |
| 4 Calls | Stage 1's card; nothing new for Poland | Small |
| 5a Handoff | With stage 1 | Included |
| 5b In-app booking | Lawyer, owner decision, Duffel account | Large, and a standing duty |

Files only one agent may edit at a time are touched by stage 1 (`voice-agent/tools.json`, `VoiceSessionController.swift`) and by any new Home entry (`RootView.swift`); check open pull requests first.

## 5. What only the owner can do

Listed in `docs/OWNER_QUEUE.md` item 37: partner accounts (Travelpayouts, TravelLead, Stay22, CJ for Booking.com, Viator), the question to Kiwi about commercial use of its MCP server, a lawyer for stage 4 abroad and stage 5b, and the choices in the decision file.

## 6. Sources

Flights, packages, law: Skyscanner partner support (acceptance criteria; services and rate limits); Kayak affiliates (`affiliates.kayak.com/apis`, `developers.kayak.com/flights-price-insights-api`); Amadeus statement on the developers portal, Skift 3 Sep 2026, PhocusWire 9 Feb 2026; `duffel.com/pricing`, `duffel.com/flights/airlines`, `duffel.com/docs/guides/paying-with-customer-cards`; Travelpayouts support articles 203956163 and 30565016140434; Kiwi.com (`kiwi.com/ag/pages/mcp/`, its May 2024 partnerships article); `travellead.pl`; Tradedoubler on Itaka; `eskygroup.esky.com/for-partners`; `docs.merlinx.pl`; Pinsent Masons on CJEU C-30/14; IPWatchdog 26 Dec 2025 on Google v. SerpApi; the Polish act (Dz.U. 2017 poz. 2361, consolidated 2023 poz. 2211); Directive (EU) 2026/1024.

Stays, alerts, calls, payments: `developers.booking.com/demand/docs/getting-started/prerequisites`; Skift 30 May 2025 on Booking.com affiliates; `airbnb.com/terms`; `partner.expediagroup.com` (Rapid); `developer.hotelbeds.com`; `dev.stay22.com`; `docs.viator.com/partner-api`; Tiqets partner programme; `intercity.pl` (UWH conditions); Google Maps Platform service terms; `artificialintelligenceact.eu/article/50`; Goodwin alert, Aug 2026; `elevenlabs.io/agents-terms`; `twilio.com/en-us/legal/aup`; UOKiK on Omnibus price reductions; Visa press release on agentic commerce in Europe; Taylor Wessing, Feb 2026, on agentic AI in payments.
