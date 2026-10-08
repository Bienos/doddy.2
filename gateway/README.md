# Doddy assistant gateway (M2)

Supabase Edge Function that holds the OpenAI key so the app never does. **Status: deployed to project
`sliondswemhneuzehpoq` (Frankfurt), not yet connected to the iOS app, real OpenAI call NOT yet tested.**

## Endpoints (`https://sliondswemhneuzehpoq.supabase.co/functions/v1/assistant`)
- `POST /register` → `{deviceToken, dailyLimit}`. Anonymous; the token is shown once, only its SHA-256 is stored.
- `POST /chat` with `Authorization: Bearer <deviceToken>`; body `{requestId, sessionId, taskType: chat|recall|capture,
  locale, turns:[{role,text}] (≤8, last is user, ≤5000 chars), memories:[{id,currentText,source}] (≤5)}`
  → `{text, citedMemoryIds, invalidCitations}`. Cited ids not in the submitted `memories` are dropped and flagged.
- Errors (`{error}`): `notAuthorized` 401, `invalidRequest` 400/405, `rateLimited` 429, `timeout` 504, `providerUnavailable` 502.

## Controls
Per-device daily limit (default 60), global daily limit (1500), registrations per day (100); atomic in Postgres.
No message text is logged or stored (logs: requestId, outcome, ms). `store:false` sent to OpenAI. Memory text is
wrapped in `<memory>` tags and declared untrusted in the system prompt. `verify_jwt` is off on purpose: auth is the
device token; RLS is on for all tables with no policies (service role only).

## Setup still needed (owner)
1. Revoke the OpenAI key that was pasted into chat; create a new one in the **EU-residency** project, restricted,
   with a monthly spend cap.
2. Supabase dashboard → project `doddy-gateway` → Edge Functions → Secrets → add `OPENAI_API_KEY`.
   Optional overrides: `OPENAI_MODEL` (default `gpt-6-luna`), `DEVICE_DAILY_LIMIT`, `GLOBAL_DAILY_LIMIT`.

## Verified (2026-10-08, curl against the deployed function)
GET → 405; no auth → 401; register → token; bad body → 400; unknown token → 401; valid request without key → 502.
**Not verified:** a real model reply, the model name `gpt-6-luna` and the `max_completion_tokens` /
`response_format` parameters for it, streaming, timeout path, rate-limit exhaustion, EU residency of the project.
