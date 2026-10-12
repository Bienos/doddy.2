# Doddy voice token server

Gives the Doddy app a one-conversation ElevenLabs token in exchange for a tester's access code.
With it, the ElevenLabs agent can require authentication. The ElevenLabs API key then lives only here,
never in the app or this repository.

```
POST /api/voice-token
Authorization: Bearer <access code>
→ 200 {"token": "…"}            (Cache-Control: no-store)
→ 401 {"error": "invalid_access_code"}
→ 429 {"error": "rate_limited"}  (this tester's tokens for this hour are used up; Retry-After)
→ 503 {"error": "voice_busy"}   (ElevenLabs concurrency/daily limit reached)
→ 500 {"error": "server_not_configured"} · 502/504 upstream errors
```

### OpenAI test voice (ADR-265)

Home's test switch can run Doddy on OpenAI Realtime instead of ElevenLabs. The app then sends a body:

```
POST /api/voice-token
Authorization: Bearer <access code>
Content-Type: application/json
{"provider": "openai"}
→ 200 {"token": "ek_…", "provider": "openai", "model": "gpt-realtime"}
→ 400 {"error": "unknown_provider"}  (any other provider, or a body that isn't JSON)
→ 500 {"error": "server_not_configured"}  (no OPENAI_API_KEY)
```

The token is an OpenAI Realtime **client secret** that must be used within 120 seconds. It carries only the
model and the voice. Doddy's prompt, notes and tools go from the phone straight to OpenAI; this server never
sees them. A request with no body is the ElevenLabs request, unchanged. Either provider works without the other's keys.

Logs are one JSON line per request: status, error, tester label, upstream status and duration.
If any configured code is too short to use, one `voice_token_config` line per instance names those testers (labels only).
They never contain codes, tokens, keys, IP addresses or anything the user said.

## Environment variables (set in the host, never committed)

| Name | Value |
|---|---|
| `ELEVENLABS_API_KEY` | ElevenLabs API key; restrict it to Conversational AI if the dashboard allows |
| `ELEVENLABS_AGENT_ID` | the Doddy agent (`agent_0501m4et27vyeawrwqfdxxfszfa6` for the dev prototype) |
| `DODDY_TOKENS_PER_HOUR` | optional, default `30`: tokens one tester may get per clock hour. Counted per server instance, so it's a brake against one tester using up the shared agent limits, not a hard cap. A value that isn't a positive whole number refuses to serve |
| `OPENAI_API_KEY` | Optional. Only for the OpenAI test voice. Put a monthly spending limit on its OpenAI project: this server has no counters |
| `OPENAI_REALTIME_MODEL` | Optional, default `gpt-realtime`. Any Realtime model id OpenAI lists (e.g. `gpt-realtime-2.1`, `gpt-realtime-mini`) |
| `OPENAI_REALTIME_VOICE` | Optional, default `marin` (OpenAI recommends `marin` or `cedar`) |
| `DODDY_ACCESS_CODES` | `label:code,label:code`. Codes must be ≥16 characters (shorter ones are ignored). Generate with `openssl rand -base64 24`. Remove an entry to revoke that tester |

## Deploy on Vercel (not done yet; needs the owner)

1. New Vercel project from `Bienos/doddy.2`, **Root Directory `server/voice-token`**, no framework, no build command.
2. Add the environment variables above (Production). The three ElevenLabs/access-code ones are required; the OpenAI ones only for the test voice.
3. Deploy. The endpoint is `https://<project>.vercel.app/api/voice-token`.
4. In the app: Settings → Voice → Token server = that URL; Access code = your code → Save.
5. Check that Settings → Voice → Connection says "Private (token server)" and a conversation starts.
6. Only then, in ElevenLabs, turn on **authentication** for the agent. After that the public agent ID stops working.
   Also set the agent's **concurrency and daily call limits**; they are the spending cap (this server only has the per-tester brake above, per instance).

`src/handler.js` uses only web-standard `Request`/`Response`/`fetch`, so Supabase Edge Functions or Cloudflare
Workers need only a short entry file in place of `api/voice-token.js`.

## Test

```sh
npm test      # Node 22+, no dependencies
```

## Hosting (new Vercel team)

Vercel project `doddy-voice-token` on team `doddyyyy` (root directory `server/voice-token/`). It fails closed until `ELEVENLABS_API_KEY`, `ELEVENLABS_AGENT_ID` and `DODDY_ACCESS_CODES` are set.

Endpoint on the new team: `POST https://doddy-voice-token-doddyyyy.vercel.app/api/voice-token` with `Authorization: Bearer <access code>`.
