# Call-backs reach the user; Doddy calls a contact by voice with a stated purpose

- **Date:** 2026-11-09
- **Decided by:** the owner, in the session that shipped #270, #273 and #275:
  - "Calling back should redirect them to the person who owns that's Doddy";
  - "I want to be able to tell Doddy by voice to call someone … but [he] should know what's purpose of that call";
  - answers to three questions: call-backs **always** (not 7 days or 24 hours); when someone says "don't call me again", **only notify the user**; I may **deploy the messaging server** myself once the code is merged.
- **Status:** call-backs applied in the pull request that adds this file; calling a contact by voice planned (below)
- **Replaces:** `contact_policy.unknown_inbound_calls` for one group of callers (see Decision)

## Why
Doddy's calls on a user's behalf (call cases, call_places) show Doddy's number. A person who calls it back reached the fixed line "This number only works for its owner" and was hung up on, so the person Doddy called for never heard from them. Separately, Doddy could only call businesses with one question, set up on a screen; the owner wants to say "call Michał and remind him we're going to Smolna today".

## Decision
**1. Call-backs (applied).**
- **Who gets through:** a caller whose number Doddy dialled for a user is put through to that user's verified number.
- **What the caller hears:** first "Tu Doddy, asystent AI. Łączę z osobą, w której imieniu dzwonił Doddy." (and the English).
- **What the user sees:** Doddy's number as caller ID, so the caller never learns the user's number.
- **No answer within 25 s:** the caller hears that the call couldn't be connected, and the call ends.
- **What is stored:** the match uses a keyed hash of the number (`callback_routes`, the same key as `call_attempts.destination_hash`), never the number, with the account and the time of the last dial.
- **How long:** the row lasts as long as the account (owner: "always"), and deleting the account deletes it.
- **Two users called the same number:** the newest dial wins.
- **Not changed:** no AI and no recording on this leg. Anyone Doddy never dialled still hears the fixed line. A verified user calling still reaches their own phone agent.

**2. Calling a contact by voice (next, after #281 and #282 free `VoiceSessionController.swift`).**
- **The voice tool:** it takes the contact, the purpose and the exact message.
- **The card:** the app finds the number in Contacts and shows the name, number, where it came from, the opening line, and what Doddy will say and must not do.
- **Nothing is dialled until the tap.**
- **On the call:** Doddy says it is an AI calling for the user, gives the message, may take one reply, and ends.
- **"Don't call me again":** Doddy says it will pass that on, and the user gets a notification. Nothing is blocked (owner's choice).
- **Limits:** the existing call-case limits, calling hours (8:00–23:00 Warsaw), Polish numbers and the blocked-numbers list all apply. It needs a TELL kind of call next to today's ASK, a matching change to the task-call agent's prompt (a live agent change, on the owner's go-ahead), and the app's card.

**3. "Call me now" by voice:** planned the same way. It waits for the same file.

## Consequences
- **For people Doddy called:** they can reach the user by calling Doddy's number. The user sees that call as coming from Doddy's number.
- **Owner steps for call-backs:**
  - **Twilio:** the number's "A call comes in" must point at the messaging server (`/webhooks/twilio/voice`, unit U1 in `docs/integrations/PHONE_NUMBER_SETUP.md`), not straight at ElevenLabs as on 9 Nov. Until then the server never sees the call.
  - **A separate task-call number:** if `TASK_CALL_FROM_NUMBER` is a different number, possibly on a Twilio subaccount, that number needs the same webhook. This code verifies only the main account's signature, so a subaccount number needs a follow-up.
- **Privacy:**
  - the called person's number stays as a keyed hash for as long as the user's account exists;
  - their call is connected through Twilio; nothing is transcribed or recorded on this leg.
- **Legal questions still open** for calling private people (`docs/decisions/calls.md`, "Open questions"): legal basis, notice, processors, an opt-out list. The owner chose to go ahead with "notify only" for opt-outs.

## Evidence
`server/messaging/test/callbacks.test.ts` (8 cases) against PostgreSQL 16; the whole messaging suite passes (853). With the route write removed, 3 of the 8 fail.
