# Doddy server (S1)

TypeScript / Node 22 + Postgres, deployed on Render (EU, `render.yaml` at repo root).
It holds provider keys so the iPhone app never does, and sends updates by **push** and **SMS**.
**Memories are not stored here.** They stay in the app's local SQLite database.

## What it does
| Area | Endpoints |
|---|---|
| Anonymous account (no email/name) | `POST /v1/accounts` → `{accountId, deviceToken}` · `DELETE /v1/account` erases everything |
| Push token | `PUT/DELETE /v1/device/push-token` `{token, environment: sandbox\|production}` |
| Phone (Twilio Verify) | `POST /v1/phone/verification` `{phone}` · `POST /v1/phone/verification/check` `{phone, code}` · `GET/DELETE /v1/phone` |
| SMS opt-in | `PUT /v1/phone/sms-consent` `{consent, textVersion}`: the app records which wording the user agreed to |
| Updates | `POST /v1/updates` `{text ≤640, channels:[push,sms], sendAt?, idempotencyKey}` · `GET/DELETE /v1/updates/:id` (the GET includes `lookup` for a text whose outcome was unknown) |
| Texts to Doddy (U3, ADR-494) | `GET/PUT /v1/texts/settings` `{inboundEnabled?, repliesEnabled?, repliesUseMemories?, language?, consentTextVersion?}`: each switch needs the one before it; texts arrive through `POST /webhooks/twilio/sms`. `GET /v1/phone/history`: the user's call and text status rows and waiting notes, as JSON. `GET /v1/call-notes` now says each note's `source` (call or text). |
| Approved texts (U2, ADR-493) | `POST /v1/texts` `{body ≤640, approvalHash, idempotencyKey}`: a text the user approved on a card, to their own verified number only. `approvalHash` is `src/approval.ts` over that number and the exact text; any difference is `409 approval_mismatch`. 20 per account per day, 300 across the server. Its status is read with `GET /v1/updates/:id`. |
| Twilio webhooks | `POST /webhooks/twilio/sms` (STOP/START) · `POST /webhooks/twilio/status` (delivery receipts) · `POST /webhooks/twilio/voice` (someone calls Doddy) · `POST /webhooks/twilio/voice/outbound/:callId` (the user answered Doddy's call) · `POST /webhooks/twilio/call-status` (how a call went), all signature-checked |
| Calls (S2, app) | `GET/PUT /v1/calls/settings` (inbound on/off, outbound consent `calls-v1`, the iPhone's `timeZone`; the GET also says `quietHours` and the `timeZone` the server holds) · `PUT/DELETE /v1/calls/pin` · `POST /v1/calls/outbound` ("call me now") · `GET /v1/calls` |
| Calls booked for later (U4, ADR-495) | `POST /v1/calls/scheduled` `{at (UTC, YYYY-MM-DDTHH:MM:SSZ), reason ≤200, timeZone, allowQuietHours, language, approvalHash, idempotencyKey}`: `approvalHash` is `src/approval.ts` over the verified number, `at`, the exact reason and the quiet-hours choice. 1 minute to 7 days ahead, 10 waiting, at most 3 calls in any hour and 10 in any day that holds it (made and booked, before and after). A repeat of the same key answers with the first request's call (409 `already_done` once it is over); the same time and reason already waiting is 409 `already_booked`. · `GET /v1/calls/scheduled` (the last 20, with the reason while it is kept) · `DELETE /v1/calls/scheduled/:id` (only while waiting) |
| Memory on calls (opt-in) | `PUT /v1/memory-copy` `{enabled}` (off deletes every copy) · `PUT /v1/memory-copy/snapshot` (replaces the copy) |
| Notes from calls | `GET /v1/call-notes` · `DELETE /v1/call-notes/:id` (after the user confirms or discards) |
| ElevenLabs (S2) | `POST /webhooks/elevenlabs/tools/{verify-pin,search-memories,save-note}`: the phone agent's tools; they need `X-Doddy-Tool-Secret` and `X-Doddy-Session` |
| News digests | `GET /v1/news/catalog` · `GET/PUT /v1/news/settings` (topics, own keywords, own feeds, time, zone, channels, language) · `POST /v1/news/feeds/check` · `POST /v1/news/send-now` · `GET /v1/news/digests` |
| Health | `GET /healthz` |

All `/v1` routes except account creation need `Authorization: Bearer <deviceToken>`.

## Rules built in
- SMS goes out only to a **verified** number with **explicit in-app consent** and no STOP since. Consent is re-checked when the message is actually sent.
- STOP cancels queued texts. Only an inbound START re-opens SMS, as carrier rules require.
- Outbox states: `queued → sending → sent | failed | unknown | cancelled`.
  - A timeout or dropped connection becomes `unknown` and is **never resent automatically**, so nobody gets a text twice.
  - A Twilio 429 or 503 is retried with backoff, at most 5 attempts: Twilio didn't accept the text.
  - Since U2 (ADR-493), any other Twilio 5xx is `unknown` too, as Twilio may have created the message. Two minutes later the worker looks for it in Twilio's message list for that number (by a hash of the text and the time, up to 3 tries): found means `sent` with Twilio's id, not found leaves it `unknown` with `lookup: not_found`. Then the hash is erased.
- An approved text (`POST /v1/texts`) is checked against its approval hash by the route and again by the worker just before Twilio; a mismatch is never sent. It needs `MEMORY_ENCRYPTION_KEY`: without it the route answers `503 sms_not_configured`, so an approved text is never stored readable.
- Delivery receipts only move a status forward (queued, sending, sent, then delivered, undelivered or failed).
- Texts to Doddy (U3, ADR-494): only the verified number with the switch on; anyone else gets empty TwiML and nothing is stored. A Twilio message id is handled once; 30 texts an hour. Without replies a text becomes an encrypted inbox note. With replies the worker asks Claude (`TEXT_REPLY_MODEL`, default `claude-opus-5-5`) with two tools, `save_note` and, only if allowed, `search_memories`; the answer goes through the outbox to the verified number, once per text, within 10 minutes, at most 3 SMS parts, 30 a day per account and $1 a day across the server (estimated from tokens). Any failure keeps the text as a note and sends one fixed text.
- Calls booked for later (U4, ADR-495): the worker takes one due call at a time and checks it again: more than 15 minutes late means missed; the number and consent; the approval hash against the number now; quiet hours (`QUIET_HOURS_START`/`QUIET_HOURS_END`, default 21:00–08:00) in the zone the iPhone last sent, unless the card allowed them; and the hourly and daily caps under the same lock as "call me now". A call whose outcome is unknown is never placed again. Each call that doesn't happen sends one notification (if the user has push on) with the time only. The reason is encrypted and erased when the call ends (Twilio's final status), 2 hours after a placed call whose end was never reported, or at once when the call won't happen or its outcome is unknown; the phone agent gets it as `doddy_call_reason` and its first sentence as `doddy_call_opening`. A new or removed number, or consent turned off, cancels waiting calls.
- Records at Twilio (messages both ways, calls) are deleted `TWILIO_RECORD_DELETE_AFTER_HOURS` after they are final (default 24; 0 = about 2 minutes). Only Twilio's id is queued for that.
- Message text is erased from the database as soon as a message reaches a final state. While queued it is encrypted with `MEMORY_ENCRYPTION_KEY` when that key is set (plain text otherwise).
- Logs carry ids and counts only. No message text, no phone numbers, no tokens.
- A missing provider configuration returns `503 not_configured`. It never fakes success.

## Phone calls (S2, through this server since ADR-490)
- **Route:** every call to Doddy's Twilio number reaches this server first (`src/routes/twilioVoice.ts`).
  - The server decides who reaches the "Doddy (phone)" agent and connects them with ElevenLabs `register-call`.
  - The number stays on Doddy's Twilio account and is **not** imported into ElevenLabs.
- **Who:** only a verified number whose owner turned calls on reaches the agent. Everyone else, including withheld numbers, hears one fixed sentence (Polish, then English, saying Doddy is an AI) and the call ends. No AI runs for them, and the log keeps only the reason, never the number.
- **When something is missing:**
  - No phone agent configured: a fixed "not connected yet" sentence.
  - The agent can't be reached: "I can't talk right now", and the call is recorded as failed.
  - The server can't check Twilio's signature: 503, so Twilio plays the number's fallback (a TwiML Bin).
- **PIN:** every call needs the user's PIN before memories are searched or notes saved, because caller ID can be faked.
  - The PIN is stored as an scrypt hash.
  - Wrong tries lock it, with escalating lockouts (ADR-175).
- **Session:**
  - Each call gets a random session key, passed as an ElevenLabs `secret__` variable through `register-call`. That kind of variable is only put in tool request headers, never shown to the language model.
  - The session ends when Twilio reports the call finished, or after 2 hours.
- **Encryption:** memory copies and call notes are encrypted with AES-256-GCM, bound to account and row, using `MEMORY_ENCRYPTION_KEY`. This is encryption at rest, **not end-to-end**: the server decrypts to answer.
- **Notes:** notes taken on a call wait in the app until the user confirms them. The push notification never contains the note.
- **Outbound ("Call me now"):**
  - goes only to the verified number, after consent (`calls-v1`), at most 3 per hour and 10 per day;
  - Twilio rings from `DODDY_PHONE_NUMBER`, and the session opens only when the user answers, once per call (consent is checked again then);
  - a timeout or Twilio server error is recorded as `unknown` and never redialled;
  - Twilio's status callbacks record ringing, answered, completed, busy, no answer, failed or canceled, and a status never moves backwards.
- **Recording:** none. No TwiML or Twilio request asks to record, and TwiML that would record is refused.
- **Agent setup:** run `node scripts/setup-phone-agent.mjs --dry-run` to see the requests, then run it for real after deploy. It prints the Twilio settings to use. The full steps are in `docs/integrations/PHONE_NUMBER_SETUP.md`, section "Unit U1".

## News digests
Once a day at the user's local time, the worker builds a short news message:
1. **Gather:** curated RSS feeds per topic, the user's own feeds, and GNews keyword search for their own topics. Fetches are cached 30–60 minutes and shared across users.
2. **Shortlist:** deterministic. Stories from the last 36 hours, not sent in the past 14 days, deduplicated by URL (tracking parameters ignored) and title, scored by topic fit and freshness, at most 3 per source.
3. **Write:** Claude Haiku (`claude-haiku-5-5`, structured output) picks up to 5 stories and writes one line each, using only the headline and feed summary.
   - Links and sources always come from the shortlist; lines pointing at unknown stories are dropped.
   - If Claude is unavailable, refuses, or returns nothing usable, the digest falls back to plain headlines.
4. **Send:** push (short list; links are in the app) and/or SMS (up to 3 stories with links, ≤640 characters), through the outbox. One scheduled digest per local day, guaranteed by a unique index.
- **Custom feed URLs** are fetched with protections against reaching the server's own network: private and reserved addresses are blocked, the address is checked at connect time (so a DNS change can't swap one in), redirects are re-checked, and size and time are capped.
- **Sent to Anthropic or OpenAI (whichever key is set, ADR-197):** topic labels plus public headlines and summaries. Never memories, phone numbers or account IDs.

## Run locally
```sh
cp .env.example .env            # fill what you have; empty blocks stay off
npm ci && npm run build
DATABASE_URL=... npm start      # applies migrations, then serves on $PORT
DATABASE_URL=... npm run worker # sends due updates every 2 s
TEST_DATABASE_URL=postgres://…/doddy_test npm test   # WARNING: drops that DB's public schema
```

## Before the first deploy (owner)
For the owner's single-number setup, follow `docs/integrations/PHONE_NUMBER_SETUP.md` instead (one web service with `RUN_WORKER_IN_WEB=1`, no Blueprint). The general steps:
1. Apply `render.yaml` in Render. This creates **paid** resources: 2 × starter + basic-256mb Postgres. (It also creates the `doddy` backend, which may already exist.)
2. Fill the `doddy-messaging-secrets` env group, then set `PUBLIC_BASE_URL` to the `doddy-messaging` URL.
3. Twilio:
   - Buy a number and create a Messaging Service with **Advanced Opt-Out** on.
   - Point the inbound webhook at `/webhooks/twilio/sms`.
   - Create a Verify service.
   - Doddy's number is a Polish mobile number (ADR-490): Twilio's identity bundle, no A2P 10DLC. A US number would need A2P 10DLC registration.
4. APNs: create a .p8 key and enable the Push capability on the app id.
5. ElevenLabs: turn on **authentication** for the Doddy agent, so tokens are required.
