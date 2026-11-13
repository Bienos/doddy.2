# Travel, stage 1: trips from booking emails

**Status, 11 Nov 2026: wired to Gmail and a model on the `doddy` server, with a Trips screen and a Home card in the app. Server and DoddyCore tested here; the SwiftUI views are not compiled here (the hosted Mac job builds them); nothing has run against a real mailbox, a real model or a device.** Plan: `docs/implementation/TRAVEL.md` section 3.10. Decision: `docs/decisions/2026-11-11-travel-agent-plan.md`.

## The owner's choices (11 Nov 2026)

| Question | Answer |
|---|---|
| When Doddy reads Gmail for bookings | "Tylko na żądanie": only when the person asks (the button on the trip screen; later "sprawdź moje rezerwacje" by voice). Under `2026-11-11-asked-for-runs-at-once` the request itself is the yes. Nothing reads the mailbox in the background and the server keeps nothing. |
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

## Wiring (built 11 Nov 2026)

**Server (`doddy`, `backend/`):**
- `POST /v1/travel/prepare` → the single-use approval for the search (`find_trips_in_gmail`; its preview text is unused by the app since `2026-11-11-asked-for-runs-at-once`). It runs the same gates as `read_email`: Gmail connected, grants fine, the user's **Read an email** switch on. A server without a model answers `live_not_configured`. Nothing is read.
- `POST /v1/travel/scan {approvalId}` → one search per yes (single use, 2 minutes, bound to the user, the Gmail connection and the fixed search). It runs `TRAVEL_GMAIL_QUERY` through Composio (`TRAVEL_GMAIL_FETCH` in `tools/catalog.ts`, not a voice tool), then reads every email at once with `ClaudeTravelReader`, each email cut at 14 s so the whole search fits the app's 20-second request. It answers `{emailsFound, emailsUnreadable, emailsNotTravel, bookings}`.
- **Model:** `DODDY_CHAT_MODEL` (Claude Haiku by default), else `DODDY_CLAUDE_MODEL`.
- **Limits:** one tool run, and one Claude unit per five emails against `DODDY_LIMIT_USER_DAILY_CLAUDE`.
- **Kept:** a receipt with counts. Nothing from the emails is kept. The log line has counts and tokens only.
- **Mock mode:** one demo Ryanair email and a demo reading, so the screen can be tried without a mailbox.

**App:**
- **Trips screen:** Home's ••• menu › Trips (`DoddyApp/Features/Trips/`). Since 13 Nov 2026 the page opens on the trip planner (`TRAVEL_PLANNER.md`) and the Gmail search is in the page's ••• menu › Import bookings from Gmail (`TripsImportSheet.swift`; owner: the Gmail block "jest bez sensu" on the planning page). The tap on "Find my trips in Gmail" in that sheet is the yes (owner's decision `2026-11-11-asked-for-runs-at-once`: what the person asks for runs at once). The app asks for the server's single-use approval and uses it straight away for one search; there is no in-app card. What leaves the iPhone is written under the button.
- **Storage:** the result is saved in `Application Support/Trips/trips-v1.json` and read back before the screen says it is saved (`TripStore`).
- **What the screen shows:** under the planner, "Your trips" (a card per trip with the countdown, opening the trip's bookings and "Before you travel"), "Earlier trips", and low down "Not going ahead"; each booking's newest email is a link to Gmail. "Forget my trips" is in the ••• menu and is checked.
- **Home card:** while a trip is under way or starts within 60 days; the cross hides it for that trip.
- **Plain refusals:** Gmail not connected, Read an email off, not set up, daily limit, expired yes, or couldn't search.
- **What leaves this iPhone:** the Doddy server row now names the trip search.

## Not built yet

1. **Reminders and calendar entries from a check.** Today the checks are information with their sources. A tap should open the existing reminder or calendar card.
2. **Voice:** a `check_my_trips` tool. It needs `voice-agent/tools.json` and the live agent, which change only on the owner's word.
3. **Privacy policy page:** the site's policy needs the same line before real users.
4. **More than 25 emails,** or emails older than 400 days.

## Known gaps

- A host's message that quotes cancellation words, read as "cancelled" by the reader, would cancel the booking in Doddy's view. The app should show a cancelled booking with "z maila od …" so the person can check.
- Two sellers using the same reference would merge. This is unlikely, and the app shows each booking's sources.
- The airport and country tables are hand-written and partial.
- No real email has been read end to end by a model yet; the tests use a scripted reader.
