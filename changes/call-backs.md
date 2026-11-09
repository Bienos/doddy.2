Call-backs reach the user (decision `2026-11-09-call-backs-and-contact-calls`).

- **What happens:** someone Doddy called on a user's behalf who calls Doddy's number back hears "Tu Doddy, asystent AI. Łączę z osobą, w której imieniu dzwonił Doddy." and is put through to that user's verified number. Doddy's number is the caller ID; nothing is recorded or transcribed; an unanswered call tells the caller so.
- **Server code:** `server/messaging/src/callbacks.ts`, `routes/twilioVoice.ts` (`/webhooks/twilio/voice`, new `/webhooks/twilio/callback-done`), the route written when a task call is claimed (`taskCalls/service.ts`).
- **Migration:** `024_callback_routes.sql`, a keyed hash of the number only. 023 is left for #282's `023_file_watches.sql`.
- **Contact policy:** `contact_policy.callback_inbound_calls`.
- **Tests:** `test/callbacks.test.ts` (8).
- **Needs:** a `doddy-messaging` deploy, and the Twilio number's "A call comes in" pointed at the server (U1). Until then callers still reach ElevenLabs directly.
