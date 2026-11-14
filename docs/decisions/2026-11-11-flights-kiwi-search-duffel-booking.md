# Doddy finds flights through Kiwi.com and can book a Duffel flight after a tap on the exact booking

- **Date:** 2026-11-11
- **Decided by:** owner, 11 Nov 2026: "add Kiwi MCP to Doddy and duffel but it will be used in poalnd", then, asked how far to build Duffel, chose "Kiwi + full Duffel booking" (exact-payload approval card, server-side Duffel order, confirmation only after Duffel says the order exists, test mode only, off by default).
- **Status:** accepted for test mode. Real (live-mode) booking waits on the owner steps under Consequences.
- **Replaces:** for flights only, point 10 ("No booking or payment inside Doddy") of the proposed `2026-11-11-travel-agent-plan.md` in the open pull request #346, which recorded the earlier answer "Przygotowuje, płacisz sam". The rest of that plan is untouched. If both merge, this file is the newer owner answer for flights.

## Why

- **Kiwi.com** runs a public MCP server (`https://mcp.kiwi.com`, tool `search-flight`). It was called on 11 Nov 2026 from this session: Warsaw → Barcelona on 10 Dec 2026 returned 15 itineraries in PLN with Polish airport names (`locale: "pl"`), the cheapest a Ryanair flight from Modlin. Ryanair has been an approved Kiwi.com partner since 2024. Kiwi only searches; every result carries a `bookingUrl` to finish on Kiwi.com.
- **Duffel** is the self-serve API that books and pays (`POST /air/orders`). Its airline page (read 11 Nov 2026) lists LOT Polish Airlines, but not Ryanair or Wizz Air, which carry most flights from Polish airports. So in Poland Duffel is useful for LOT and full-service airlines, and Kiwi for low-cost ones.

## Decision

1. **`find_flights`** (voice tool, runs at once): the app asks Doddy's server, the server calls Kiwi's `search-flight` with `currency: PLN` and `locale: pl`, and returns at most 5 itineraries. Each result says Kiwi.com and the time it was checked. Prices are Kiwi's, never the model's. Opening a result opens Kiwi.com; Doddy books nothing there.
2. **`find_bookable_flights`** (voice tool, runs at once): the same search through Duffel (`POST /air/offer_requests`), at most 5 offers, each with its Duffel offer id, price, airline and expiry.
3. **`book_flight`** (voice tool, tap only): the model proposes one Duffel offer and the passengers as the user said them. Doddy's server re-reads the offer (`GET /air/offers/{id}`) and builds the exact booking: flights, every passenger's name, birth date, contact, the total and currency. The card shows that exact booking. A tap approves its hash; the server books only a payload whose hash matches, so a changed price or passenger voids the approval.
4. **Done only on Duffel's word.** "booked" only after Duffel answers 201 with an order id and a booking reference. Duffel's 422 / 503 answers are "not booked" with the reason. 202, 500, 502, 504 and a timeout are "unknown": Doddy says it may be booked, never retries by itself, and the server keeps the attempt so a second tap on the same booking can't book twice.
5. **Off by default, test mode only.** The server refuses to book unless `FLIGHT_BOOKING_ENABLED=1` and the Duffel key is a test key (`duffel_test_…`). A live key is refused until the owner approves live booking in a new decision.
6. **Payment:** test mode pays from the Duffel test balance (`payments[].type = "balance"`). Nothing charges the user. Taking the user's money (Duffel Payments card collection or another provider) is a separate decision.

## Consequences

- **Owner steps** (`docs/OWNER_QUEUE.md`): a Duffel account and a test key (`DUFFEL_ACCESS_TOKEN` on the server); turning `FLIGHT_BOOKING_ENABLED` on; the voice-agent sync of the three tools; confirming Kiwi's terms for commercial use of the MCP server.
- **Before live booking:** how the user pays and who is merchant of record; the Polish and EU consumer-law position of selling flights (information duties, airline terms, EU261 handling); privacy text for passenger data sent to Duffel (name, birth date, email, phone). None of this is legal advice.
- **Privacy:** passenger details pass through Doddy's server to Duffel only after the tap; the server keeps the booking attempt (offer id, hash, state, order id, reference), not the passengers' details beyond what is needed to show the receipt.
- **Coverage:** Duffel has no Ryanair or Wizz Air, so a voice search for the cheapest flight from Poland will usually be a Kiwi link, not a Doddy booking.

## Where it runs

All four tools run on `doddy` (`backend/src/flights/`), on the same ASK-01 gate (`AskGate`) as web search and the account tools. The booking needs no new table: its approval's account is `duffel:<offer id>`, and the `approvals` row already records the outcome and Duffel's order id and reference. The messaging server's job tables were considered and not used: a booking is one call, not a background job. The app waits 20 s; the server waits up to 16 s for Duffel and then answers `unknown`, while the booking goes on and its answer is recorded for `check_flight_booking`.

## Evidence

- Called: Kiwi MCP `initialize`, `tools/list`, one `search-flight` (11 Nov 2026).
- Read: Duffel API reference for orders (create order, response handling) and its airline list.
- Tests: `backend/test/flights.test.ts` (fake Kiwi and Duffel clients, offline) and `Packages/DoddyCore/Tests/DoddyCoreTests/FlightToolsTests.swift` (not compiled: no Swift toolchain in the session that wrote it).
- Not run: no Duffel call (no key in this session), no app build, no device.
