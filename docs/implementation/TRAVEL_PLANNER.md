# Travel, stage 2: the trip planner

**Status, 12 Nov 2026: built on the server and in DoddyCore and the app's screens; the server and DoddyCore are tested here, the SwiftUI views are not compiled here, and nothing has run on a device or against Doddy's live server.** Plan: `docs/implementation/TRAVEL.md` section 3 (points 1 to 6). Decision: `docs/decisions/2026-11-11-travel-agent-plan.md`.

## The owner's choices (12 Nov 2026)

| Question | Answer |
|---|---|
| Kiwi.com's terms for use inside another company's app are not published | "Od razu dla wszystkich": the planner is on for everyone without waiting for Kiwi. The risk that Kiwi blocks it stays open (owner queue: ask Kiwi). |
| Where planning starts | "Ekran, potem głos": a screen first (Trips › Plan a trip); a voice tool later (it needs the live agent, which changes only on the owner's word). |
| Stays | "Rozeznanie + linki": links to Booking.com and Airbnb with the dates and party filled in, and a button that hands Doddy's background task a request to research stays. |
| Package holidays | "Link do wakacje.pl": a link with the country, dates and party; no prices read until the TravelLead account exists. |

## What a person sees

1. Trips › **Plan a trip**. They type, or dictate with the keyboard's microphone: "Lisbon around 12 February, 4 nights, the two of us, no more than 2000 zł".
2. Doddy asks **one** question at a time for what is missing, in this order: where to, where from, when, how many nights, how many people.
3. It says what it **assumes** for the rest ("no checked bag", "stops are fine", "exactly that day").
4. Up to three flights: **cheapest**, **fastest**, **easiest** (fewest stops, then fewest warnings). Each shows the price **for the whole party with the checked bags counted**, both legs, the airlines, and its **warnings**.
5. Each option has **Book on Kiwi.com** (Kiwi's own booking link), **Booking.com** and **Airbnb** links with the dates and party filled in, a **wakacje.pl** link when a package was asked for, and **Have Doddy look at stays**, which shows the exact words and sends them as a normal background task only after "Yes, go".

Doddy never books or pays.

## Rules in code, not in the prompt

| Rule | Where |
|---|---|
| The model only turns words into a brief (`TripBrief`, a closed schema); an answer of the wrong shape changes nothing | `backend/src/tools/service.ts` `understandTrip`, `plan.ts` |
| What is missing, in what order, and what is assumed are decided by code | `plan.ts` `missing`, `assumptions` |
| A date in the past or more than 330 days ahead, a window longer than a month, nights back to front, or a trip to where it starts is dropped and asked again | `plan.ts` `cleanBrief` |
| A price, time and link are Kiwi.com's, as it answered; a link that isn't on kiwi.com is dropped; an unreachable or broken answer is an error ("Kiwi.com couldn't be reached"), never "no flights" | `kiwi.ts` |
| Labels are honest: an itinerary gets "fastest" only if it is the fastest of those returned; one that wins twice is shown once | `plan.ts` `pickOptions` |
| Warnings come from the itinerary: airport change, different airlines on one connection, overnight or 6 h+ connection, leaving before 6:00, landing after 23:00 or the next day | `plan.ts` `traps` |
| Stay and package links carry only the city, dates and party | `plan.ts` `stayLinks` |
| The stay task's words carry no link (ADR-703) and start only after a card with those words and a tap (ADR-716, kept by `2026-11-11-asked-for-runs-at-once`) | `TripsView.swift` (the planner is inline there since 13 Nov 2026), `TripPlanText.stayResearchWords`, `StaySearch.researchWords` |
| The log line carries counts only | `trip_search` |

## Server

- `POST /v1/travel/plan/understand {words, brief?, today}` → `{brief, missing[], assumptions[]}`. One Claude unit (the small model, `DODDY_CHAT_MODEL`). The brief so far goes back and forth, so the server keeps nothing between turns.
- `POST /v1/travel/plan/search {brief, today}` → `{brief, options[3], source: "Kiwi.com", checkedAt}`. One tool run. Kiwi.com is reached at `https://mcp.kiwi.com` with a JSON-RPC `tools/call` to `search-flight`, without a key (checked on 12 Nov 2026 from this session: initialize, tools/list, a Gdańsk–Lisbon search and a flexible Gdańsk–Barcelona search for two adults with a checked bag, in PLN, all answered). A request is cut at 15 s.
- Mock mode has three demo flights and a demo brief, so the screen can be tried without Kiwi or a model.
- Shared fixture: `schemas/fixtures/travel_plan_v1.json`, written by the server test and decoded by the Swift tests.

## App

`DoddyApp/Features/Trips/TripPlannerModel.swift` (the conversation, no views), shown inline in `TripsView.swift` since 13 Nov 2026 (decision `2026-11-13-feature-screens-in-doddys-colours`); the rules and words in `Packages/DoddyCore/Sources/DoddyCore/Travel/TripPlanner.swift`.

## Voice: `plan_trip` (14 Nov 2026)

The voice step of "Ekran, potem głos". **Built on the server and in DoddyCore; the server is tested here with stand-ins for the model and Kiwi.com; DoddyCore and the app half are not compiled here; no real model or Kiwi.com call was made; not on the live agent yet (its `voice-agent/tools.json` entry and the live agent are separate steps).**

- **One stateless call.** The voice model sends `words` (everything the person has said about the trip so far, in their words and language, answers included; at most 600 characters) and an optional `language`. The server keeps nothing between calls.
- **Same rules as the screen.** The words go through the same model step and code (`readBrief`: `UNDERSTAND_SYSTEM`, `TripBrief`, `cleanBrief`), with the brief so far empty and today's date in the person's own time zone (the run's `timeZone`; Warsaw's for one the server doesn't know). A link in the words is cut to its site first (research_now's rule).
- **Something missing:** the answer starts `ask:` with the one question the planner's code chose (`missing`, NEEDED order: to, from, when, nights, who), word for word the screen's (`TripPlanText.question`), in Polish for `pl` and English otherwise (the agent says it in the person's language), plus the brief and the assumptions so far. Nothing is searched.
- **Complete:** Kiwi.com is searched exactly as the screen's search does, and the answer is the brief in one line, the assumptions to say out loud, and up to three options (cheapest, fastest, easiest: the total for the party with the bags as asked, airlines, dates and times, stops, warnings, over budget), framed as Kiwi.com's data, web content, never instructions. No link is in the text. Every link (each option's Kiwi.com page, then its Booking.com and Airbnb searches and, for a package, wakacje.pl, each once, at most 12) is in the run's `links`.
- **On the screen:** the voice screen's flights card shows the Kiwi.com links as buttons (`VoiceSessionController.keepFlightLinks`). The Booking.com, Airbnb and wakacje.pl links are not shown there: that card is "Flights on Kiwi.com", and there is no card for stays yet. The answer tells the agent so, and points at Trips › Plan a trip or `hand_over_errand` for stays.
- **Gates and limits:** the same switch as `find_flights` (`FLIGHT_SEARCH_ENABLED`; off: "Flight search isn't switched on on this server.", which the app says as for `find_flights`), and the planner's model. The same daily counts as the screen's two routes: one Claude unit to understand, one tool run to search. ASK-01: the server's single-use approval for exactly these words, used at once by the app (a public look-up).
- **Time:** understand (15 s) and search (15 s) share a 30 s deadline (`PLAN_TRIP_TIMEOUT_MS`); the app waits 40 s for this run (`BackendOnlineAccountsClient.timeout(for:)`). A step that fails or runs out of time is an honest `failed:` naming the step (the planner or Kiwi.com), never half a plan and never "no flights".
- **Weather and calendar are not in it:** the agent calls `get_weather` and `read_calendar` itself.
- Code: `backend/src/flights/planTrip.ts` (input, card, every word the agent hears, the links), `backend/src/tools/service.ts` (`runPlanTrip`); tests `backend/test/plan-trip.test.ts`, DoddyCore `FlightToolsTests`.

## Not built, and known limits

- **Voice:** `plan_trip` (above) needs its `voice-agent/tools.json` entry and the live agent. Stays links are not shown on the voice screen.
- **Kiwi.com:** its terms for this use are unknown; it can refuse at any time (the screen then says it couldn't be reached). The searched flights include self-transfer connections Kiwi returns; the warnings say when a connection is between different airlines, but Doddy does not say whether the tickets are separate.
- **Prices:** Kiwi's total is for the party with the bags asked for. Seat fees, airport transfers and the stay are not in it; the screen says what the price covers.
- **Stays have no prices of their own** until the person has Doddy research them (a task) or opens Booking.com or Airbnb. Doddy reads no Booking.com or Airbnb prices.
- **Packages:** a link only. TravelLead prices need the partner account (owner queue 45).
- **Watching a plan's price** is stage 3; none of it exists yet.
- Only a flight to a place Kiwi.com can resolve from a city, airport or country name works; "anywhere warm" is not understood yet (it asks where to).
