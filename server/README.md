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
| Updates | `POST /v1/updates` `{text ≤640, channels:[push,sms], sendAt?, idempotencyKey}` · `GET/DELETE /v1/updates/:id` |
| Voice | `GET /v1/voice/token`: short-lived ElevenLabs conversation token (ADR-034) |
| Twilio webhooks | `POST /webhooks/twilio/sms` (STOP/START) · `POST /webhooks/twilio/status` (delivery receipts), signature-checked |
| Health | `GET /healthz` |

All `/v1` routes except account creation need `Authorization: Bearer <deviceToken>`.

## Rules built in
- SMS goes out only to a **verified** number with **explicit in-app consent** and no STOP since. Consent is re-checked when the message is actually sent.
- STOP cancels queued texts. Only an inbound START re-opens SMS, as carrier rules require.
- Outbox states: `queued → sending → sent | failed | unknown | cancelled`.
  - A timeout or dropped connection becomes `unknown` and is **never resent automatically**, so nobody gets a text twice.
  - A 429 or 5xx refusal is retried with backoff, at most 5 attempts.
- Message text is erased from the database as soon as a message reaches a final state.
- Logs carry ids and counts only. No message text, no phone numbers, no tokens.
- A missing provider configuration returns `503 not_configured`. It never fakes success.

## Run locally
```sh
cp .env.example .env            # fill what you have; empty blocks stay off
npm ci && npm run build
DATABASE_URL=... npm start      # applies migrations, then serves on $PORT
DATABASE_URL=... npm run worker # sends due updates every 2 s
TEST_DATABASE_URL=postgres://…/doddy_test npm test   # WARNING: drops that DB's public schema
```

## Before the first deploy (owner)
1. Apply `render.yaml` in Render. This creates **paid** resources: 2 × starter + basic-256mb Postgres.
2. Fill the `doddy-secrets` env group, then set `PUBLIC_BASE_URL` to the `doddy-api` URL.
3. Twilio:
   - Buy a number and create a Messaging Service with **Advanced Opt-Out** on.
   - Point the inbound webhook at `/webhooks/twilio/sms`.
   - Create a Verify service.
   - US numbers also need A2P 10DLC registration.
4. APNs: create a .p8 key and enable the Push capability on the app id.
5. ElevenLabs: turn on **authentication** for the Doddy agent, so tokens are required.
