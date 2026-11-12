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
| The stay task's words carry no link (ADR-703) and start only after a card with those words and a tap (ADR-716, kept by `2026-11-11-asked-for-runs-at-once`) | `TripPlannerView.swift`, `TripPlanText.stayResearchWords` |
| The log line carries counts only | `trip_search` |

## Server

- `POST /v1/travel/plan/understand {words, brief?, today}` → `{brief, missing[], assumptions[]}`. One Claude unit (the small model, `DODDY_CHAT_MODEL`). The brief so far goes back and forth, so the server keeps nothing between turns.
- `POST /v1/travel/plan/search {brief, today}` → `{brief, options[3], source: "Kiwi.com", checkedAt}`. One tool run. Kiwi.com is reached at `https://mcp.kiwi.com` with a JSON-RPC `tools/call` to `search-flight`, without a key (checked on 12 Nov 2026 from this session: initialize, tools/list, a Gdańsk–Lisbon search and a flexible Gdańsk–Barcelona search for two adults with a checked bag, in PLN, all answered). A request is cut at 15 s.
- Mock mode has three demo flights and a demo brief, so the screen can be tried without Kiwi or a model.
- Shared fixture: `schemas/fixtures/travel_plan_v1.json`, written by the server test and decoded by the Swift tests.

## App

`DoddyApp/Features/Trips/TripPlannerModel.swift` (the conversation, no views), `TripPlannerView.swift`; the rules and words in `Packages/DoddyCore/Sources/DoddyCore/Travel/TripPlanner.swift`.

## Not built, and known limits

- **Voice:** a `plan_trip` tool needs `voice-agent/tools.json` and the live agent.
- **Kiwi.com:** its terms for this use are unknown; it can refuse at any time (the screen then says it couldn't be reached). The searched flights include self-transfer connections Kiwi returns; the warnings say when a connection is between different airlines, but Doddy does not say whether the tickets are separate.
- **Prices:** Kiwi's total is for the party with the bags asked for. Seat fees, airport transfers and the stay are not in it; the screen says what the price covers.
- **Stays have no prices of their own** until the person has Doddy research them (a task) or opens Booking.com or Airbnb. Doddy reads no Booking.com or Airbnb prices.
- **Packages:** a link only. TravelLead prices need the partner account (owner queue 43).
- **Watching a plan's price** is stage 3; none of it exists yet.
- Only a flight to a place Kiwi.com can resolve from a city, airport or country name works; "anywhere warm" is not understood yet (it asks where to).
