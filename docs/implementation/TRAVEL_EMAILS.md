# Travel, stage 1: trips from booking emails

**Status, 11 Nov 2026: building blocks only, tested; nothing is wired to Gmail, to a model or to a screen yet.** Plan: `docs/implementation/TRAVEL.md` section 3.10. Decision: `docs/decisions/2026-11-11-travel-agent-plan.md`.

## The owner's choices (11 Nov 2026)

| Question | Answer |
|---|---|
| When Doddy reads Gmail for bookings | "Tylko na żądanie": only when the person asks ("sprawdź moje rezerwacje", or a button on the trip screen). Nothing reads the mailbox in the background and the server keeps nothing. |
| How a booking is read from an email | "AI ze sprawdzaniem": a model reads the cleaned text into a fixed schema; code keeps a value only if the email says it. |
| Sample emails | "Tak, tylko do wzorów": the owner's own confirmations were read in this session to learn their layouts. Only made-up emails with the same layouts are in the repository (`backend/test/travelFixtures.ts`). |
| Where trips show in the app | "Karta na Home, gdy jest wyjazd": a card on Home while a trip is coming up; the full list next to Tasks. |

## What real emails showed (layouts only)

| Seen in the owner's mail | What the code does |
|---|---|
| A Ryanair confirmation is about 100,000 characters of HTML around 4,000 characters of text; an agency's Wizz Air notice is tables full of 600-character tracking links | `emailToText`: HTML and tables become lines, every link goes. The real Ryanair email went from 101,274 to 4,114 characters with reference, dates and airport codes intact (checked here, not stored) |
| Booking.com puts the booking's PIN in the email ("can be used to modify or cancel your booking"); card endings appear as "•••• 9717" and as "z końcówką:" with the digits on the next line | `redactSecrets`: PINs, card numbers and endings and security codes become "[removed]" before anything reads the text. The real Ryanair card ending was removed |
| Ryanair sent a second confirmation for the same reference with a different flight | Grouped by reference; the newest confirming email's facts win |
| A check-in reminder carries the reference but not the airline's name | Grouping is by reference only, not by seller |
| Booking.com sends "awaiting confirmation", "failed" and a refund for one attempt, then "confirmed" for the next | `pending` → **waiting**, `failed` → **failed**; neither is planned around |
| A stay cancelled for an invalid card, then booked again under a new number | `cancelled` needs cancellation words in the email; the cancelled booking is listed apart from trips |
| Hosts' messages repeat the confirmation number | A `message` or `reminder` never changes a booking's state and never makes one alone |
| A restaurant table and concert tickets arrive as "reservation confirmed" | `not_travel`, left out |
| Ryanair's dates "08/12/2026", "1 lis"; Gmail's "Fri, 30 Oct 26"; Wizz Air's "02/Apr/2026"; Booking.com's "Sunday, 29 March 2026" | `readDate`, day first, Polish and English month names; a date without a year may be in the email's year or the next |
| A schedule change names the flight "1350", without the airline code | Values are copied, never completed: "W6 1350" would be dropped |
| City tax paid at the property, a €300 damage deposit charged 7 days before arrival, a cleaning fee, "non-refundable", "3rd floor without elevator" | `payOnSite`, `deposit`, `nonRefundable` (kept only next to words that say it), `notes` (copied word for word) |

## Server: `backend/src/travel/`

| File | Does |
|---|---|
| `emailText.ts` | Cleaning and secret removal; at most 12,000 characters are read |
| `schema.ts` | `TravelReading` (what the reader must answer: closed lists for kind and status; every date and amount with its exact words) and `TravelBooking` (what the app gets) |
| `evidence.ts` | Dates, times and amounts read from their words; `appearsIn` ignores case and line breaks |
| `ground.ts` | Keeps only what the email says; records what it dropped. "Confirmed" or "changed" without the reference in the email becomes "other"; "cancelled" and "failed" need words that say so |
| `merge.ts` | Many emails to one booking per reference: state from the newest decisive email, facts from the newest confirming one |
| `reader.ts` | The Gmail search (`TRAVEL_GMAIL_QUERY`, at most 25 emails, newer than 400 days), the reader's instructions, and `readTravelEmail` with an injected `TravelReader` |

The model behind `TravelReader` is not chosen or wired yet. Its answer is parsed with zod and checked; it never runs anything. Email content is data (R-TOOLS): the fixtures include an instruction inside an email and a host's message telling the reader to cancel the booking.

## Shared contract

`schemas/fixtures/travel_bookings_v1.json` is what the real server code makes of eight made-up emails (`backend/test/travelScenario.ts`). The backend test fails if the file differs. `WRITE_TRAVEL_FIXTURE=1` rewrites it. The Swift tests decode the same file.

## iPhone side: `Packages/DoddyCore/Sources/DoddyCore/Travel/`

| File | Does |
|---|---|
| `TravelBooking.swift` | The bookings as received; `TripDay` for the emails' local dates |
| `Trips.swift` | Bookings whose days touch (one day's gap allowed) become one trip; cancelled and failed ones stay out. Places, countries, home country, "in 27 days" |
| `TravelAirports.swift` | 253 airports with country and IANA time zone, so "(BRS)" gives the UK's rules and Bristol's clock. A missing airport gives no guess |
| `TripChecks.swift` | What a trip asks of the person: online check-in per flight, free-cancellation reminder two days before, deposit, what's paid on site, sentences from the email, waiting for the seller, documents per country. Polish and English words |

### Rules written down, with their sources (read 11 Nov 2026)

| Rule | Source |
|---|---|
| Ryanair: without a paid seat, check-in opens 72 h before departure; with one, 60 days; closes 2 h before | help.ryanair.com, "When can I check in?" |
| Wizz Air: without a seat, 24 h; with one, 30 days; closes 3 h before | wizzair.com, "Check-in and baggage drop-off times" |
| EU, EEA, Switzerland: a valid ID card or passport | europa.eu, Your Europe |
| UK: a passport (an ID card only with settled status or similar) and an ETA for each person, Poland included since 2 April 2025 | gov.uk, "Visiting the UK as an EU, EEA or Swiss citizen"; Appendix ETA National List |
| Türkiye: a passport valid 150 days from entry, or an ID card for the stay; mObywatel not accepted | gov.pl, advice for travellers to Türkiye |
| Every other airline or country | No time or rule is given; "check with the airline" or the gov.pl travel page |

Check-in times are worked out in the departure airport's time zone (8 Dec, 14:00 in Kraków → opens 5 Dec, 14:00). A free-cancellation deadline is in the property's time, which the email states but Doddy can't place, so the reminder is set by day.

## Not built yet (next pull requests)

1. **Wiring:** a backend route (or a read tool with the existing Gmail grant and ask-first card) that runs `TRAVEL_GMAIL_QUERY` through Composio, reads each email with a chosen model, and returns `TravelBooking[]`. Nothing is kept on the server. Needs: the model (Claude Haiku is the likely default), a per-request and daily cap, and the "What leaves this iPhone" and privacy-policy lines saying that booking emails go to Anthropic.
2. **App:** the trip card on Home, the trip screen with its checks, "Sprawdź moje rezerwacje", and the reminder and calendar cards made from a check on a tap.
3. **Voice:** a `check_my_trips` tool (the live agent changes only on the owner's word).

## Known gaps

- A host's message that quotes cancellation words, read as "cancelled" by the reader, would cancel the booking in Doddy's view. The app should show a cancelled booking with "z maila od …" so the person can check.
- Two sellers using the same reference would merge. This is unlikely, and the app shows each booking's sources.
- The airport and country tables are hand-written and partial.
- No real email has been read end to end by a model yet; the tests use a scripted reader.
