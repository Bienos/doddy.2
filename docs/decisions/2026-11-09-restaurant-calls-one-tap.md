# Doddy finds places, calls them and books after one tap, and texts the person's own number without asking

- **Date:** 2026-11-09
- **Decided by:** owner. Asked for: "doddy should send sms from his numbers on his own right … why not remove them [the call limits] and let doddy like find number and call restirant get info and then send message me or notfication in app with result and or like used booking servie instead if available". Then "ok" to the three choices below, as proposed in the same session.
- **Status:** accepted. Steps 1 and 2 (the server side) applied in #265; step 3 (texts without a tap) in #274; step 4 (calls from a conversation) in the pull request that changes this line; step 5 to follow.
- **Replaces:** for the steps below only, parts of ADR-500 to 507 (`docs/decisions/calls.md`: one callee per approval, "ask" only, never commits) and of ADR-752 (`text_me` needs a tap).

## Why
The owner's example: "Find an Italian restaurant in Warsaw city centre for a date at 7, book the best one that has a table, call them, and let me know." Today Doddy can find places (`find_places`), but:
- the place search drops the listing's phone number (`backend/src/tools/websearch.ts`, `normalizeMonidTool`);
- a call Doddy makes for you is started only from Settings, calls one number per approval card, asks one question and is told never to book (`server/messaging/src/taskCalls/`, `voice-agent/task-call/instructions.md` rules 2 and 10);
- a text to the person's own number needs a tap on a card each time (`text_me`, ADR-752).

## Decision
1. **One tap per task, not one per call.** Doddy shows one card for the whole task: the places (name, number and where the number came from), the exact question, the booking details if any, and how the result comes back. One tap approves exactly that card; the approval is bound to its digest, and anything that changes (another place, another time) needs a new card. A task with no tap at all is not allowed: it would break the constitution's exact-payload approval for writes to the outside world (`docs/trust/config/doddy_rules.yaml`, `external_write_default`), which this decision keeps.
2. **Doddy may book.** On a "book" task the card shows the name the booking is under, the date and time, and the party size. Doddy may say yes to a table that matches them exactly, and nothing else (no deposit, no card number, no other time without a new card). Booking runs on its own task-call agent with its own pinned prompt, so the existing "ask" agent and its prompt hash (`server/messaging/src/taskCalls/agentSpec.ts`) are untouched.
3. **Texts to the person's own verified number need no tap,** once they have turned on "Texts from Doddy" (consent `sms-v1`). Texts to anyone else still need a tap on the exact text, as before; `text_recipients: allowlist_only` stays.
4. **Results come back by notification and by text.** When a task ends, the person gets a push (no words on the Lock Screen, as today) and, if they chose it on the card, a text to their own number with the result.
5. **Booking services first, calls second.** Where a place takes online bookings, Doddy sends the booking link. Booking platforms such as TheFork or Google's "Reserve a table" don't let an app book without a partner agreement; that is a later step, not part of this decision.

**Limits that stay**, with the reasons given to the owner:
- at most 2 calls a day per person to the same number, 3 a day in all, 15 minutes apart (stops anyone using Doddy to harass a person or a business);
- calling hours 08:00 to 23:00 Warsaw time; Polish numbers only (the voice and the legal checks were done for Poland);
- the daily cost caps, which the owner can raise in the server's settings as use grows.

**Before anyone but the owner uses calls to businesses** (unchanged from `calls.md`, open questions 1 and 5): a legal basis for transcribing what the other person says, and a way for a number's owner to ask never to be called again.

## Steps
1. Place search keeps the listing's phone number when it looks like one (`listingPhone` in `backend/src/tools/websearch.ts`). Whether Doddy may dial it is still decided by the messaging server's allowlist (`taskCalls/phone.ts`).
2. Messaging server: a task of up to 3 places under one digest; places are called one after another and the task stops at the first yes; a structured yes/no answer; the result by push and by text to the person's own number (`server/messaging/src/taskCalls/tasks.ts`, migration `022_call_tasks.sql`). The "book" kind, on its own task-call agent with its own pinned prompt, is a later step: it needs that agent created on ElevenLabs, which only the owner can do.
3. App: `text_me` to the person's own number without a card when "Texts from Doddy" is on; the rules file and its tests follow. Exactly the same text isn't sent again within 10 minutes (`TextRepeat` in DoddyCore), and it still waits while driving: it leaves the iPhone, which the car rule of 11 Oct 2026 keeps for after the drive.
4. App: a voice tool that proposes a task from the conversation (`call_places`: up to three places with their numbers from `find_places`, one question, a goal, and whether to text the result), the one-tap card built from the server's preview of every place, and the result through the existing Calls for you sync (the recap in Files › Calls, the card in Messages). The user's first name for "dzwonię w imieniu …" comes from About you, as in Calls for you; without it Doddy says so and calls nobody.
5. Booking links: the place search or a web search keeps a place's booking page, and Doddy offers it before calling.

## Consequences
- Fewer taps: one per task instead of one per call, none for texts to yourself.
- Cost: every call and text is paid by Doddy (about $0.11 a minute for a call, about $0.05 a text, estimates in `docs/implementation/PHONE_SMS_MILESTONE.md`). The daily caps keep their meaning.
- A booking made by phone is a commitment in the person's name. The card is the only place its details come from, and the result says exactly what was agreed, quoted from the call.
- Restaurants see Doddy's Estonian number (+372) calling; some may not answer. A Polish number would help.
- A text to the person's own number now goes out without a second look. If a model proposes a wrong text, it reaches only the person who asked, within the daily cap.

## Evidence
- Step 1: `backend` build and `node --test dist/test/monid-tools.test.js dist/test/websearch.test.js`, 23 of 23 passed (two new tests).
- Step 2: messaging `npm test` against Postgres 16, 845 of 845 (10 new in `server/messaging/test/callTasks.test.ts`): one tap calls the places in turn, a yes stops the task, unclear stops it, no answer moves on, a call that couldn't be placed stops it, the text choice is part of the digest, cancelling stops it, calling hours end it.
- No call has been placed and no text sent by any of this; the app doesn't use it yet.
