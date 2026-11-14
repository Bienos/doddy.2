# Call-backs are put through only to one user, for 7 days, a few times a day; calls to Doddy's number have daily caps

- **Date:** 2026-11-12
- **Decided by:** owner, 12 Nov 2026 ("fix everything from the 12 Nov review": call-back routes per account, with an expiry and caps). It narrows two of the 9 Nov answers ("always", and the newest dial wins). The numbers are the owner's to change (`docs/OWNER_QUEUE.md` 53).
- **Status:** applied in the pull request that adds this file
- **Replaces:** in `2026-11-09-call-backs-and-contact-calls`, "How long: the row lasts as long as the account" and "Two users called the same number: the newest dial wins"

## Why
- A route was one row per called number, overwritten by whichever user Doddy dialled it for last. When two users call the same place (a clinic, a restaurant), the place's call-back reached the second user, who may be the wrong one.
- A route lasted as long as the account, and a call-back rang the user's phone with no daily limit, no time limit on the forwarded call, and even when the user had calls to Doddy turned off.
- Caller ID is not proof of who is calling, so call-backs should be limited in time and number, and go only to someone who chose to receive them.
- Calls to Doddy's number from a user's verified number had no daily cap per account or for the server, although each one runs the phone agent.

## Decision
- **One route per number and account** (`callback_routes`, migration 034), renewed by each new dial.
- **Put through only when exactly one account has a fresh route.** Fresh: dialled within `CALLBACK_ROUTE_DAYS` (7, 1 to 90). With two or more, nobody is put through.
- **Only to a user with calls on** (`inboundEnabled`). Routes are still kept for users with calls off, so a shared number is still recognised as shared.
- **Caller-ID attestation:** when Twilio sends `StirVerstat` (only for calls signed under SHAKEN/STIR, so not for Polish numbers), only `TN-Validation-Passed-A` or `TN-Validation-Passed-A-Passthrough` is put through.
- **Caps:** `CALLBACK_FORWARDS_PER_ROUTE_DAY` (3, 1 to 20) per route and UTC day; the forwarded call ends after 15 minutes (`<Dial timeLimit="900">`).
- **Calls to the phone agent:** `INBOUND_CALLS_DAILY_PER_ACCOUNT` (20 in 24 hours) and `INBOUND_CALLS_DAILY_PER_SERVER` (200 a UTC day, call-backs included).
- **What a refused caller hears:** a call-back that can't be put through hears "I can't put this call through right now" (Polish, then English), which says nothing about whom Doddy called for. A call past the agent caps hears "that's the limit of calls for today". Either way the call ends.
- **Task-call refusals:** the three per-number limits (2 a day from one user, 3 a day from all, 15 minutes apart) now answer with one code, `limit_destination`. A refusal no longer tells a user that someone else called that number lately; the server log keeps which limit it was.

## Consequences
- A place that calls back more than 7 days after Doddy's call reaches the stranger's line. So does a place two Doddy users called within those 7 days. Setting `CALLBACK_ROUTE_DAYS=90` gets closest to the old "always".
- A user who turns calls off stops getting call-backs.
- Old app builds show their generic "the server stopped this call" text for `limit_destination`; builds with this change show "Doddy has called this number enough for now".
- **Privacy:** the keyed hash of a called number now lasts 7 days, not the account's lifetime. One row per account that dialled it, deleted with the account.
- **Still open:** the user is not told that a call-back was refused; the PIN still guards memories, notes and recaps, and the attestation check covers call-backs only.

## Evidence
`server/messaging/test/callbacks.test.ts` (14 cases), `calls.test.ts` (inbound caps), `taskCalls.test.ts` and `taskCallsLimits.test.ts` (the one code), `callTasks.test.ts` (result text), `abuseUnits.test.ts` (settings), against PostgreSQL 16. Not tried on a real call.
