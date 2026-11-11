# Travel is built in five stages on what Doddy already has, with referral links first and in-app booking last

- **Date:** 2026-11-11
- **Decided by:** proposal, owner approval pending. The request is the owner's (11 Nov 2026, in Polish, shortened): "będziemy teraz tworzyli funkcję podróż … podłączył do różnych portali podróżniczych … Wakacyjni Piraci, Booking … Skyscanner, Kayak … Airbnb … agent cały czas jest w trybie czuwania … jak coś wpadnie … od razu daje znać … planer … powinien dodać pytania, jeżeli czegoś mu brakowało … robi raport, rozpiskę … opcję zadzwonienia za ciebie … możliwość bukowania … last minute, sam z siebie szukać … Trzeba zrobić research, jak to trzeba zrobić i zaplanować to".
- **Status:** proposed
- **Replaces:** nothing. Builds on ADR-570 (errands), ADR-607 (shopping runner), `2026-11-10-radar-alerts`, `2026-11-09-restaurant-calls-one-tap`.

## Why

The research (`docs/implementation/TRAVEL.md`, 11 Nov 2026) found that the portals the owner named don't give a company of Doddy's size a search API: Skyscanner and Kayak approve by traffic, Booking.com needs a managed-partner contract, Airbnb has no API or affiliate programme and forbids bots, Wakacyjni Piraci and Fly4free publish no feed. Scraping them is ruled out by their terms and by court decisions. What can be used today is Kiwi.com's public MCP server (live flights with booking links), Travelpayouts (cached prices and partner links), wakacje.pl's TravelLead (packages), Stay22 (links into Booking.com and Expedia) and Viator.

The same research found that taking payment for travel, or bundling a flight and a hotel, makes a company a travel seller under the Polish package-travel act, while sending the person to the seller does not.

Doddy already has the engine: background tasks with a result card, a runner whose prices come from code, watches and radar alerts with pushes, and phone calls to places.

## Decision

1. **Five stages, in this order:** (1) the trip planner, (2) standby watches, (3) Doddy's own finds, (4) calls for a trip, (5) booking. Each is its own pull request or more; none starts before the owner says so.
2. **Sources:** only APIs, feeds and partner links whose terms allow our use. No scraping of Skyscanner, Kayak, Booking.com, Airbnb, Ryanair, Wizz Air or Google Flights. The named portals appear as partner or plain links until they grant access.
3. **Referral first:** through stages 1 to 4 the person books and pays on the seller's site. Doddy never says "booked" on its own authority.
4. **In-app booking (stage 5b)** needs a separate owner decision after a lawyer's opinion, and covers flights only.
5. **Prices** on cards and in pushes come from the code's record of a source's answer, with the source and the time; a watch push is sent only after a live re-check; wording states facts, never a percentage reduction.
6. **Calls abroad** stay off until the owner decides the countries and a lawyer confirms the rules; Polish places use Calls for you as it is.
7. **Every part ships behind its own switch, default off**, like errands and radar.

## Consequences

- The owner must open partner accounts and ask Kiwi about commercial use (owner queue 37). If Kiwi says no, stage 1 runs on Travelpayouts' cached prices, which are older and thinner for Polish routes, and the report must say "from about".
- Airbnb and Booking.com prices won't be read by Doddy; the person sees a link. That is less than the owner asked for, and it is what is obtainable.
- Standby needs an always-on worker (the free Render plan sleeps) and working APNs (owner queue 8).
- Cost per trip report is model tokens plus searches, as for errands; watches cost almost nothing on cached prices. Partner commission is possible but small (about 4% on packages, a few percent elsewhere) and not yet signed.
- Privacy: route, dates and party size go to the sources; the privacy policy and "What leaves this iPhone" need a travel section before a switch goes on.

## Evidence

- Read in the repository: `server/messaging/src/errands/researcher.ts`, `src/watches/`, `src/taskCalls/opening.ts`, `server/messaging/README.md`, `voice-agent/tools.json`, the decisions named above.
- Web research by two research agents on 11 Nov 2026; sources in `docs/implementation/TRAVEL.md` section 6. Several official pages refused to load and were read through search summaries; those points are marked *unverified* there.
- **Not run:** no travel API was called, no partner account exists, no code was written, nothing was compiled or tested. The legal points are not legal advice.
