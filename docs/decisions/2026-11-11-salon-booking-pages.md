# Doddy offers a salon's own booking page (Booksy, Fresha and others); booking through the platforms waits for a partner agreement

- **Date:** 2026-11-11
- **Decided by:** owner. Asked whether the `cotletdev/booksy-api-mcp-server` MCP server could be used for Doddy, then "what else i can use for how i can use booksy to book sthings in poland", then "do everything leave email for now also other altrantibes to booksy like fresha ?"
- **Status:** step 1 applied in the pull request that adds this file; steps 2 to 4 wait on the owner (`docs/OWNER_QUEUE.md` 38).
- **Replaces:** nothing. This carries out step 5 of `2026-11-09-restaurant-calls-one-tap` (booking links) for salons, clinics and restaurants alike.

## Why
People in Poland book hairdressers, barbers, beauty and some doctors through Booksy and its competitors. What was checked on 11 Nov 2026:

| Option | What it is | Can Doddy use it? |
|---|---|---|
| `cotletdev/booksy-api-mcp-server` | Unofficial. Works inside a salon **owner's** Booksy Biz account, using that owner's Chrome session copied from the browser. Elastic License 2.0. | **No.** It manages a salon, it can't book at one. The licence forbids offering it to others as a hosted service. Copying a person's login session breaks the constitution's privacy and scoped-tool rules. |
| Booksy partner API | Official. Services, staff, appointments and webhooks. Docs need a partner login. | **Only after a partner agreement** (owner queue 38). |
| Booksy's app inside ChatGPT | Booksy's own, for customers. The listing found is Booksy US. | No: it runs inside ChatGPT, not in Doddy. |
| Booksy's customer API, reverse-engineered | Some voice-agent builders call it. | **No.** It likely breaks Booksy's terms and can stop working without notice. |
| Google's "Book" button (Reserve with Google) | Booksy has been a partner since 2017; Polish salons on Booksy can be booked from Google Maps. | Link only: Google has no API for an app to book for someone. |
| Fresha | Official public MCP server (`mcp.fresha.com/mcp`, launched 4 Aug 2026 for ChatGPT and Claude). It shows live availability, prices and reviews; the booking ends on Fresha's own pages. Needs sign-in. | **Maybe later.** It is a new outside service that would receive the user's words and location. It needs the owner's yes, a check of Fresha's terms for an app like Doddy, and a check that it covers Poland (owner queue 38). |
| Reservio | Public API (v2) for the business's own account. | Business side only; its public booking pages are linked. |
| Bookero | API key from a salon's own panel. | Business side only; its booking pages are linked. |
| ZnanyLekarz (Docplanner) | Doctor and clinic booking; integration API is for clinics. | Business side only; profile pages are linked. |

None of them lets an app book for a customer without an agreement with the platform.

## Decision
1. **Booking pages in search results (applied).** When a place search (`find_places`) or a web search returns a link on Booksy, Fresha, Reservio, Bookero or ZnanyLekarz, the result keeps it as "booking page (Booksy): https://…". Only https links whose host is the platform's own host or a subdomain of it count; a place's own website, a lookalike host or text in a listing never does (`backend/src/tools/bookingPages.ts`). The result tells Doddy that a booking page is where the person books themselves, that nothing has been booked, and that Doddy texts the link (`text_me`) only if the person asks.
2. **Asking a salon by phone works today** with `call_places` ("do you have a free slot tomorrow at 10?"). Booking by phone stays the "book" kind of `2026-11-09-restaurant-calls-one-tap` step 2, which needs its own task-call agent on ElevenLabs that only the owner can create. It isn't built here.
3. **Booksy partner API:** the owner asks Booksy for partner access. The email waits ("leave email for now").
4. **Fresha's MCP server:** the owner decides whether Doddy may send searches to it. If yes, it becomes a fixed, read-only tool on Doddy's server, like `find_places`, with its own card and daily limit. Booking would still end on Fresha's page.

## Consequences
- Doddy can point to the right page in one step instead of saying "look it up on Booksy". The person still books, so Doddy never claims a booking it can't see.
- The link from a listing comes from Google listings through Monid. The place search's listing fields were never seen live with a booking link (the header of `backend/src/tools/websearch.ts`), so the search may return none until a live run shows which field carries it. Web results on booksy.com and the other hosts do carry links.
- A new platform is added only by editing `BOOKING_PLATFORMS` after checking that its pages are public booking pages.
- Nothing new leaves the server: the links were already in the provider's answer.

## Evidence
- `cd backend && npm run build && node --test dist/test/booking-pages.test.js dist/test/monid-tools.test.js dist/test/websearch.test.js`: 28 of 28 passed (5 new). Whole backend suite (`npm test`): 719 of 719 passed.
- `scripts/ci.sh --only checks`: every check passed except one step NOT RUN on this Linux box (Studio skill renderers: reportlab and matplotlib aren't installed), so the script reports BLOCKED. That step doesn't touch this change.
- Not run: a live `find_places` or web search (both cost Doddy money and need the live Monid key). No call was placed and no text was sent.
- Sources read 11 Nov 2026: the `cotletdev/booksy-api-mcp-server` README and LICENSE (cloned, read only); Booksy's partner pages and Reserve with Google posts; Business Wire, 4 Aug 2026 (Fresha on ChatGPT and Claude); the Make.com Reservio page; the Bookero WordPress plugin page.
