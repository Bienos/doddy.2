# Travel: what people actually do, and the Doddy that fits it (11 Nov 2026, version 2)

**Status: a design and a plan. Nothing here is built.** Decision: `docs/decisions/2026-11-11-travel-agent-plan.md`. Version 1 of this page (the same day) planned by data source; the owner asked for something better for the people who will use it, so this version starts from how people plan trips today. All research is web research from 11 Nov 2026; no travel API was called and no partner account exists. Reddit could not be read by the research tools, so first-hand voices come from Wykop, the Fly4free forum, Hacker News, App Store reviews, the Rick Steves forum and the press. Points marked *unverified* rest on third-party pages or search summaries.

## 1. What people do today

### The journey

1. **Inspiration from the internet, friends and short videos.** Poles who flew abroad: internet 66%, family and friends 56%, social media 38%, AI 17% (eSky/NielsenIQ, n=600, 2026). Over half look at photos and videos of a place before choosing.
2. **A long, scattered search.** Expedia's measured path: 141 pages of travel content in the 45 days before booking, 71 days from first look to booking (2023; no newer edition found).
3. **Price first, often no destination.** Fly4free forum: "wpisuję skąd: Polska, dokąd: wszędzie, miesiąc: Listopad". Several home airports at once (Kraków and Katowice), open-jaw trips and flexible dates with an alert are what they ask for and don't get in one tool.
4. **Two markets.** City breaks are 82% self-organised; longer trips split about 54% DIY and 46% travel agency (eSky 2026). A package means a week, all-inclusive, in Turkey (28%), Greece (18%) or Egypt (14%); average 3,263 zł a person (PIT 2026). People compare "package or on my own" by hand: "z biurem opłaca się jedynie all-inclusive" (Wykop).
5. **Reviews checked by hand.** "sprawdzać opinie na tripie i google, ale z sortowaniem od najnowszych + drugi raz od najgorszych" (Wykop).
6. **Domestic stays by phone.** Guesthouse pages say "niższe ceny dostępne tylko przez telefon" and "rezerwacji można dokonać wyłącznie telefonicznie", with a deposit by transfer within days and Saturday-to-Saturday stays (nocowanie.pl and owners' pages; how common this is was not measured).
7. **Deal feeds as a habit.** Fly4free's app and channels, Wakacyjni Piraci's pushes "kilka razy w tygodniu", error fares. Last minute is real but not dominant: about a quarter book 10 days or less ahead, families earlier.
8. **Organising in email folders, Docs, Sheets and screenshots.** TripIt misses small hotels and details such as breakfast, prepayment and the cancellation date, so people keep a spreadsheet anyway.
9. **AI is now a normal planning step, not a booking one.** About one in five Poles use it regularly and one in three sometimes (Visa CEE, April 2026). In Europe 45% used AI to plan, 40% would let it compare prices, 12% would let it book (lastminute.com, Aug 2026). In the US only 8% said AI answers alone were enough.

### What hurts most (ranked)

| # | Pain | Evidence |
|---|---|---|
| 1 | Hidden and late fees | 61–63% name them their top frustration (US, UK surveys); Ryanair gate bag fees €46–75 |
| 2 | "The price went up when I came back" | People switch devices and IPs; a test found prices move with time, not cookies |
| 3 | Low-cost airline rules | "będę musiał zapłacić 55 euro na lotnisku jak nie odprawie się" (Wykop) |
| 4 | Agreeing with other people | The most stressful part for 31%, 37% of families (Booking.com DE, 2025) |
| 5 | Too much effort and choice | 31% name the effort itself, 30% choosing the stay and area |
| 6 | Alerts late or useless | "it's missed three $200-300+ price drops"; "when I click through … that price is gone" |
| 7 | Distrust of reviews and photos | One in five booked on a misleading review (UK PR survey) |
| 8 | Document mistakes | Turkey: passport valid 150 days or ID card; mObywatel not accepted (gov.pl); families miss flights over a child's expired passport |
| 9 | Splitting costs | "po tygodniu ludzie nie pamiętają gdzie i co brali" (Wykop) |
| 10 | Is the package really cheaper? | Low-cost packages may exclude checked bags |
| 11 | Confirmations scattered or lost | Messages vanish from Booking.com after a change |
| 12 | Unread cancellation terms | 67% never read them (Europe, 2024) |

### What goes wrong with AI planners

The same twelve failures recur: invented places ("There is no Sacred Canyon of Humantay!", BBC), closed venues, wrong hours (a couple stranded on Mount Misen by a wrong ropeway time), invented prices and discount codes (Fly4free's own test), buses that don't run, impossible routes, generic "top 10" plans, days stuffed too full (reviewers cut about 30%), no real availability, replacing hotels the person already booked, visa mistakes (a couple denied boarding without ESTA), and a plan that isn't saved. In a US survey (vendor) 55% got at least one wrong recommendation and one in six a place that does not exist. TOPR rescued tourists routed over Krzyżne in winter by ChatGPT (*Wykop summary only*).

What people do about it: they use AI for a draft, then check every place on a map, hours for the actual date, travel times, prices and visa rules on government sites.

### What the big products do, and the gap

ChatGPT's Booking, Expedia and Skyscanner apps search and link out, partly not in the EU. Google's Flight Deals work in Poland, but AI Mode price tracking and its agent tasks exclude the EEA. Mindtrip and Wanderlog have good maps and shared plans but weak in-trip use and tight free limits. TripIt organises confirmations but doesn't plan. Siri's new AI has no Polish. Airbnb's own agent is promised for 2027.

**Nobody covers the Polish traveller end to end in Polish**, from "where can we go in May" through the guesthouse phone call to the delayed flight.

### Eight jobs people want done

1. "Find somewhere cheap from my airports in my window."
2. "Tell me the real total."
3. "Watch it and only interrupt me when it matters, and when it's still there."
4. "Is this place really OK?"
5. "Get us to agree."
6. "Keep everything in one place."
7. "Don't let me make an expensive mistake."
8. "Make the call for me."

## 2. The idea: one trip, one companion, four moments

Doddy doesn't compete with Skyscanner on listing 200 flights. It is **the friend who knows how to travel cheaply, knows you, does the boring parts and doesn't lie about prices**.

Every trip is one **Wyjazd** (a trip): one place in Doddy that lives from the first idea to the way home. It passes through four moments, and Doddy behaves differently in each:

| Moment | The person says | Doddy does |
|---|---|---|
| **Marzę** (dreaming) | "Gdzieś ciepło w lutym, do 1500 zł" | Ideas with real prices from their airports, long-weekend tricks, a watch |
| **Wybieram** (choosing) | "Lizbona, 12–16 maja, z Kasią" | Three complete options with the real total, a check of each place, a call to a guesthouse |
| **Jadę** (going) | (nothing: the booking email arrives) | Fills the trip from the confirmation, deadlines, documents, check-in, packing, leaving time |
| **Jestem tam / wracam** (there, and after) | "Lot ma 4 godziny opóźnienia" | Today's plan, open nearby, translator, rights and the claim email, who owes whom |

### Doddy figures out the kind of trip (owner: "Wszyscy po równo")

From the first sentence Doddy recognises one of five kinds and changes its questions, sources and card:

| Kind | Recognised from | Main source | What the card shows first |
|---|---|---|---|
| **Okazja** (deal hunt) | "gdziekolwiek", "tanio", "w lutym", no fixed place | Cached fares from all the person's airports | A short list of places with "from" prices and the cheapest dates |
| **Wczasy** (package) | "all inclusive", "z biurem", "Turcja na tydzień", children | TravelLead package feed | Hotel, board, flight times, what's excluded, **and the same trip done on your own** |
| **City break** | a city, 2–5 days | Live flights, Stay22 links, things to do | Flight + area to stay + a light plan per day |
| **Polska** (domestic) | "nad morze", "w góry", "pensjonat" | Places, guesthouse numbers | A few guesthouses and "should I call them?" |
| **Konkret** (fixed trip) | dates and a place fixed, maybe a conference or a wedding | Live flights, stays | The best way there and back, and where to sleep |

Doddy says which kind it assumed ("Brzmi jak wczasy z dziećmi, szukam all inclusive") so the person can correct it in one word.

## 3. The ten things that make it better

### 1. Talk like to a friend; Doddy asks only what it can't know
- One sentence or one voice note is enough. Doddy fills the rest from what it already has, and says it:
  - **when:** free days from the calendar ("w maju masz wolne 9–17"), Polish public holidays, school holidays (*ferie* by voivodeship, if the person saved theirs);
  - **who:** "z Kasią i dziećmi" from saved notes (the children's ages, if saved);
  - **from where:** home airports saved once ("Gdańsk, a jak taniej, to Bydgoszcz");
  - **likes:** "nie lubię przesiadek", "max 3 godziny lotu", saved with the person's yes.
- It asks only what blocks a search, **one question at a time, at most three**, and states every assumption out loud.
- Nothing is saved to memory without the person's yes and a verified write (DOD-06).

### 2. An answer in seconds, by voice; the details on screen
- Doddy says the gist at once: "Lizbona w maju: loty z Gdańska od około 480 zł, najtaniej 12–19 maja. Rozpisuję trzy opcje."
- The detail goes onto the trip's screen, never as a wall of text in speech. The research shows voice works for the brief and the gist; comparing needs a screen.
- The full check (stays, reviews, things to do) runs in the background, using the existing errands machinery, and the trip fills in as each part arrives.

### 3. Three options, one recommendation, and why
- **Mój wybór** plus two alternatives with a clear difference ("najtaniej", "najwygodniej"), each with one line on why.
- Sorted by the person's own priorities. A partner commission never changes the order, and partner links are labelled.

### 4. The real total, door to door
For each option, as far as Doddy knows:
- the fare **for this party** with the bags they need (a family of four's checked bags, not one person's base fare);
- seats for children if the airline charges to sit together;
- the transfer from the airport (time and price);
- city tax and resort fees where the source states them.

Anything Doddy couldn't confirm is listed under **"Nie wliczone / nie sprawdzone"**, never guessed. For a package, Doddy builds the same trip on your own and compares like for like ("Itaka 3,450 zł/os. z transferem i bagażem; samemu 2,980 zł, ale bez transferu, hotel 2 km od plaży").

### 5. Every fact checked, with a time
- Every place, hour and price on a card comes from a source in this run, with the source and the time ("Sprawdzone 14:05, Kiwi.com").
- A place must resolve to a real place id before it can appear; otherwise it is dropped.
- Opening hours are checked for the actual date.
- Visa and entry rules are only quoted with a link to gov.pl or the destination's official page, and Doddy says to check there.
- Days are deliberately under-filled, with real travel times between stops.
- This is in code (as in the shopping runner), not only in the prompt.

### 6. "Is this place really OK?"
For a hotel or guesthouse, Doddy reads the newest and the worst reviews from sources it may read, and says what keeps coming up ("trzy osoby w październiku: hałas z baru obok"). It also gives the distance to the beach, the centre and the airport. Every point names its source.

### 7. Standby that only interrupts when it matters
- **Flexible watches:**
  - "ciepło w lutym, do 1500 zł za osobę, z Gdańska albo Bydgoszczy";
  - "Lizbona, któryś długi weekend w maju";
  - "all inclusive Grecja, 2+2, do 12 000 zł".
- **Before any push, a live re-check.** A price that is gone is not sent.
- **The push states facts only** ("Lizbona 412 zł, było 520 zł, gdy ustawiałeś, sprawdzone 14:05"). No "−20%" and no "last chance" (Omnibus, DOD-10).
- One tap to stop, quiet hours, and a daily cap.
- Watches end by themselves on the trip's date.

### 8. Doddy's ideas, once a week (owner: "Sam podsuwa pomysły")
- **What:** once a week, three ideas from the person's airports for their real free time.
- **Long-weekend maths:** "Boże Ciało: 4 dni urlopu = 10 dni wolnego. Z Gdańska: Malta od 390 zł, Neapol od 450 zł."
- **Settings:** on by default for people who use travel, one tap off, a chosen day and time, and no other unprompted pushes.
- **Price history:** after 30 days of its own readings Doddy may say "najtaniej, odkąd sprawdzam (30 dni)", which is a fact it holds.

### 9. The guesthouse phone call
- **Domestic stays:** "Znajdź mi coś w Jastarni na 12–19 lipca, 2+2, i zadzwoń." Doddy picks up to three guesthouses (`find_places`) and shows one card with exactly what it will ask: free dates, price for this party, the deposit, parking, dogs. After the person's tap it calls them, using Calls for you with its fixed AI greeting.
- **The answers:** one table ("Pensjonat Bryza: wolne, 2,800 zł, zaliczka 30% w 3 dni; Willa Ola: tylko od 13.07").
- **The deposit:** Doddy can prepare the transfer (`draft_blik_transfer` or a bank-transfer draft) for the person to send in their bank. Doddy never pays (owner: "Przygotowuje, płacisz sam").
- **Not in this version:** Doddy doesn't confirm a booking by phone in the person's name; the person calls back or answers the guesthouse's text.

### 10. After booking, Doddy takes over the boring part (owner: Gmail "ma dostęp do maila normalnie")
**Filling the trip from email:**
- When a confirmation arrives in the connected Gmail (airline, Booking.com, Airbnb, a tour operator, a train), Doddy reads it and fills the trip.
- It reads only messages that look like travel confirmations, and treats them as data, never as instructions (R-TOOLS).
- The trip shows "z maila od Ryanair, 3 maja".

**What it reads out of a confirmation:**
- flights and times, the booking reference, bags included;
- the stay, check-in and check-out, prepaid or paid on site;
- **the free-cancellation deadline**.

**Card proposals** (each change to the calendar, reminders or lists is a card the person approves; nothing is written silently):
- calendar entries;
- a reminder before the free-cancellation deadline;
- **online check-in** when it opens, for the airlines whose rules Doddy has checked (Ryanair's €55 airport fee is exactly the pain);
- **"when to leave"** for the airport (`remind_when_to_leave`);
- **documents per traveller**: which ID is needed for that country (with the gov.pl link) and whether the passports the person saved are still valid on the return date;
- a **packing list** sized to the bag allowance and the forecast (`create_list`, `get_weather`).

**Watching the price after booking:**
- With free cancellation, Doddy keeps an eye on the same room: "ten sam pokój jest teraz 300 zł taniej, darmowe anulowanie masz do 3 czerwca".
- Doddy doesn't rebook. The person does it if they want.

## 4. At the destination and when things go wrong

- **Jestem na miejscu:** Home shows today's part of the trip, what's open nearby (`find_places`), the weather, the translator in one tap, and the trip's booking references. The whole trip is kept on the iPhone, so it works offline.
- **Flight delayed or cancelled:**
  - Doddy explains the EU261 rights for that flight (distance band, compensation amount, care) with the regulation's link.
  - It drafts the claim email to the airline (`draft_email`) for the person to send.
  - It never says a claim was filed.
  - Automatic delay detection needs a flight-status source that is not chosen yet (**open**); until then it works when the person tells Doddy.
- **Lost documents or cards:** the existing `lost_wallet` checklist, with the embassy for the trip's country.
- **Afterwards:**
  - "Kto komu ile": the person says or photographs what they paid, and Doddy keeps a running split for the trip's people.
  - "Co Ci się podobało?": with a yes, it is saved for the next trip.

## 5. Planning together (later stage, needs an owner decision on sharing)

The trip gets a link (Doddy Web already exists). Companions open it without the app and:
- mark their dates;
- say their own budget, visible only to Doddy;
- vote on the three options.

Doddy finds the overlap ("wszyscy możecie 9–12 maja; budżet mieści się dla opcji B"). The group cost split lives in the same trip.

**Open:** does a companion need a Doddy account (today's rule says everyone signs in)? What does the link reveal?

## 6. Rules in code, not just in prompts

| Rule | ID | Enforced by |
|---|---|---|
| A price, place or hour appears only if a source returned it in this run, with source and time | DOD-02, DOD-08 | The runner's record (as in `src/shopping/`); card validation drops anything else |
| Every search, watch and call starts from a card with its exact content and a digest-bound tap | DOD-07, ASK-01 | Errand, watch and task-call approval as they exist |
| "Booked" is never said by Doddy; the email is the source, shown as "z maila od …" | DOD-08 | Trip state comes only from parsed confirmations or the person's own words, labelled as theirs |
| Email and page content is data | R-TOOLS | Confirmations are parsed into typed fields; no free text from email reaches a tool call |
| Calendar, reminder, list and memory changes are proposals | DOD-06, DOD-07 | Existing card tools |
| No pressure: facts only in pushes, quiet hours, caps, one-tap stop | DOD-10 | The radar/watch worker rules |
| Partner links labelled, never reorder results | DOD-02 | Sorting ignores the partner field; a test |
| Only route, dates and party size go to travel sources; no name, notes or email | DOD-11 | Request builders; a test with planted words; "What leaves this iPhone" gets a travel section |

## 7. Sources Doddy can use (from version 1's research, unchanged)

- **Flights:** the Kiwi.com MCP server, live and including low-cost carriers; its commercial terms must be confirmed with Kiwi. Travelpayouts cached prices for watches and "anywhere" searches.
- **Packages:** wakacje.pl TravelLead (a feed, about 4%); Itaka through Tradedoubler; eSky.
- **Stays:** Stay22 links into Booking.com and Expedia; a plain Airbnb search link. Doddy reads no Booking.com or Airbnb prices.
- **Things to do:** Viator, Tiqets.
- **Facts and reviews:** Google Places (only the place id may be stored); Tripadvisor content (status of its new API *unverified*).
- **Not available:** Skyscanner and Kayak APIs (traffic thresholds), the Booking.com Demand API, Airbnb (no API, no scraping), Amadeus Self-Service (closed 2026), Kiwi Tequila, Google Flights, Wakacyjni Piraci and Fly4free feeds (none found), PKP Intercity (no integrations until at least late 2027).
- **No scraping.** Court cases (Ryanair, Google v. SerpApi) and the sites' terms rule it out.
- **Law** (not legal advice): referral keeps Doddy out of travel-seller duties. Price wording follows the Omnibus rule. AI calls state they are AI in the first sentence (AI Act art. 50, in force since 2 Aug 2026). Calls abroad wait for a lawyer.

## 8. Order of work

Each stage is a pull request or more, behind its own switch (default off), started only on the owner's word.

| # | Stage | Why in this order | Needs |
|---|---|---|---|
| 1 | **The trip, and filling it from email** (section 3 point 10 and section 4's offline copy) | The most-wanted help that no portal blocks; works with any booking, made anywhere | Gmail connection (exists); confirmation parser with fixtures from real emails the owner shares; flight check-in rules table |
| 2 | **Talk, kind of trip, three options, the real total** (points 1–6) | The planner itself | Kiwi's answer or Travelpayouts; TravelLead; Stay22; Places; errands switched on |
| 3 | **Standby and weekly ideas** (points 7–8) | Reuses stage 2's sources | Always-on worker; APNs working |
| 4 | **Guesthouse calls and the deposit draft** (point 9) | Calls for you exist for Polish numbers | Small |
| 5 | **There and after: today view, EU261 email, cost split** (section 4) | Builds on stage 1's trip | A flight-status source for automatic detection (to research) |
| 6 | **Planning together** (section 5) | Needs an owner decision on sharing and accounts | Doddy Web |

**Not planned:** booking or paying inside Doddy (owner: "Przygotowuje, płacisz sam").

Files only one agent may edit at a time are touched by stages 1–2 (`voice-agent/tools.json`, `VoiceSessionController.swift`, `RootView.swift`); check open pull requests first. The live voice agent changes only on the owner's separate instruction.

## 9. Sources of the user research

Poland: eSky/NielsenIQ via turystyka.rp.pl and igryfino.pl (2026); "Podróże Polaków 2025" via podroze.gazeta.pl; PIT "Zagraniczne wakacje Polaków 2026" (pit.org.pl); Rankomat (July 2026); Travelplanet "Raport Podróżnika 2025"; Exim via waszaturystyka.pl; Visa CEE (mynewsdesk, April 2026); Wykop entries 83908437, 71875315, 33605105, 72566913, 78001863, 72327283; Fly4free forum threads "jak szukać taniego lotu" and "Google Flights"; fly4free.pl on AI-invented flights and codes; nocowanie.pl and guesthouse pages; gov.pl advice for Turkey; Dziennik Łódzki (2022); podroze.onet.pl on a ChatGPT London plan.

Elsewhere: Expedia Group/Luth "Path to Purchase"; Booking.com Germany (Nov 2025); Profitroom via HOSPA; Fullstory via ppc.land; YouGov UK; FitMont via Travolution; lastminute.com Travel Horizons 2026; Phocuswright 2026 updates; IATA 2026 passenger survey; Expedia/YouGov "AI trust gap" (2026); Accenture; Nuvei AI travel report 2026; Amadeus "Tailored Horizons"; Greetwell AI travel survey 2026 (vendor); BBC Travel 26 Sep 2025; CNN 28 Jan 2026; People (ESTA case); Hacker News item 48457120; App Store reviews of Mindtrip and Layla; Seattle Times; Skift 6 Jul 2026 hands-on test of ChatGPT apps; Google blog on AI Mode travel; Apple newsroom on Siri AI (Sep 2026); TechCrunch 5 Nov 2026 on Airbnb's agent; Rick Steves forum threads on documents and TripIt; ResetEra flight-tracker thread.
