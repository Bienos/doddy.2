# Doddy can book a table or an appointment by phone, on a separate agent that may accept only the booking on the card

- **Date:** 2026-11-12
- **Decided by:** owner: "create the book agent", after the "book" agent of `2026-11-09-restaurant-calls-one-tap` (step 2, decision 2) was explained to them.
- **Status:** server side, spec and the live ElevenLabs agent applied in the pull request that adds this file. Not live yet: the messaging server must be deployed with `ELEVENLABS_TASK_BOOK_AGENT_ID` set (owner queue 40), and the app's `call_places` card follows in its own pull request.
- **Replaces:** nothing; carries out decision 2 of `2026-11-09-restaurant-calls-one-tap`. The "ask" agent, its prompt and its hash are unchanged.

## Why
Doddy could phone places for the user but only ask ("do you have a table at 7?"). The owner wants it to book too, for restaurants and for salons on Booksy and similar, where an app can't book online without a partner agreement (`2026-11-11-salon-booking-pages`).

## Decision
1. **A separate agent:** "Doddy 5 · Rezerwuje za Ciebie (restauracje, fryzjer itp.)", `agent_9401m76my4d4fwbvvjf7b3b6tgrd`, made from `voice-agent/task-call-book/` by copying the ask agent (same voice, Polish, phone audio, no voice recording, sign-in on, no per-call overrides, only `end_call` and `voicemail_detection`) and changing only the prompt, name and tags. The server checks it like the ask agent (`checkAgentSafety` against `TASK_BOOK_AGENT_SPEC`) and refuses booking calls while it differs; ask calls go on.
2. **The card is the booking.** A "book" task carries `booking`: the name it's under, the day (today to 60 days ahead, Warsaw), the time, and a service or the number of people. The server builds every sentence from it (`server/messaging/src/taskCalls/booking.ts`): the question, the lines the agent reads, and the **one confirmation sentence** ("Dobrze, proszę o rezerwację: stolik dla 2 osób, piątek 13 listopada, 19:00, na nazwisko Anna Kowalska."). A question written by the app or the model is refused for a booking. The card says what Doddy won't do: another day, time or service, a deposit, a card or account number, any other condition.
3. **What counts as booked, decided in code.** A place booked only when (a) Doddy said the confirmation sentence, found in the transcript, (b) the result step says the callee agreed to exactly that booking, (c) there is a quote of the callee's words from the transcript, and (d) Doddy said no other commitment word. Doddy saying the sentence without (b) to (d) stops the task as "unclear" for the person to read: never "no", and the next place is never called. Without the sentence a yes is not a booking.
4. **The same limits as every call:** one tap per task (the digest now covers the kind too), up to three places tried in turn until the first booking, calling hours 08:00 to 23:00 Warsaw, Polish numbers, the daily caps, the stop list. The result comes back by push and, if chosen, a text ("… potwierdza rezerwację: „…”").
5. **Off until set up.** Without `ELEVENLABS_TASK_BOOK_AGENT_ID` a booking is refused before anything is stored (503 `booking_not_configured`); `/v1/call-cases/availability` says `booking: false`.

## Consequences
- A booking by phone is a commitment in the person's name. The card is the only place its details come from; the confirmation sentence is fixed; the transcript and the quote are kept with the result, as for every call.
- Migration `028_book_calls.sql` only widens two CHECK constraints (`kind IN ('ask', 'book')`); existing rows are all `ask`.
- The live agent's dashboard test values are still the ask agent's (Serwis Laptop); they're used only for tests in the dashboard, never on a call.
- Before anyone but the owner uses it, the open questions of `calls.md` (a legal basis for transcribing the other side, a never-call-me list) still apply.

## Evidence
- `server/messaging`: `npm run build`, then the whole suite against a disposable Postgres 16 (`node --test --test-concurrency=1 dist/test/*.test.js`): 949 tests; the one failure in the first run (the new migration not yet listed in `migrationsFrozen.test.ts`) fixed and that file re-run, 3 of 3. New: `test/bookCalls.test.ts`, 10 tests (sentences, dates, the brief, the confirmation sentence in results, what counts as booked, the agent check, and four end-to-end runs with fake Twilio and ElevenLabs: not set up, booked at the second place, a yes Doddy never accepted, drift and a past day).
- `python3 -I scripts/voice_agent_spec.py check --agent task-call-book` and `--agent task-call`: PASS.
- `node scripts/setup-task-call-agent.mjs --agent book --dry-run`: prints the booking agent's request.
- The live agent, read back through the ElevenLabs connector on 12 Nov 2026: prompt 3,531 characters (the same as `instructions.md`, trimmed), first message `{{doddy_opening_line}}`, Polish, μ-law 8000 both ways, `record_voice` false, auth on, every override off, no knowledge base, MCP or custom tools, max duration 600 s. Not checked live by the server: the messaging server isn't deployed with the id yet.
- Not run: any real call. The app isn't changed; its card for bookings comes next.
