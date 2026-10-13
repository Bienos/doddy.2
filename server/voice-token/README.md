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

### "Hey Doddy" key (ADR-328)

So a tester can turn on "Hey Doddy" with one tap instead of making a Picovoice account, the app asks once
for the owner's Picovoice AccessKey and keeps it in the iPhone's Keychain (Porcupine needs it on the phone):

```
POST /api/voice-token
Authorization: Bearer <access code>
Content-Type: application/json
{"provider": "picovoice"}
→ 200 {"accessKey": "…"}
→ 401 {"error": "invalid_access_code"}
→ 500 {"error": "server_not_configured"}  (no PICOVOICE_ACCESS_KEY)
```

It starts no paid conversation, so it isn't counted per hour. The key is never logged. Rotate it in the
Picovoice Console if a phone or code is lost; phones then need "Hey Doddy" turned off and on again.

### OpenAI Realtime voice (ADR-265, default since ADR-442)

Doddy's voice runs on OpenAI Realtime by default when a token server is set; Home's switch can still pick ElevenLabs. The app then sends a body naming the model it picked in Home (`gpt-realtime-2.1` or `gpt-realtime-2.1-mini`; without `model`, the server uses `OPENAI_REALTIME_MODEL`, else mini):

```
POST /api/voice-token
Authorization: Bearer <access code>
Content-Type: application/json
{"provider": "openai", "model": "gpt-realtime-2.1-mini"}
→ 200 {"token": "ek_…", "provider": "openai", "model": "gpt-realtime-2.1-mini"}
→ 400 {"error": "unknown_provider"}  (any other provider, or a body that isn't JSON)
→ 400 {"error": "unknown_model"}     (a model that is not on the allowlist; nothing is sent to OpenAI)
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
| `OPENAI_API_KEY` | Needed for the OpenAI voice (the default voice, ADR-442). Put a monthly spending limit on its OpenAI project: this server has no counters |
| `OPENAI_REALTIME_MODEL` | Optional, default `gpt-realtime-2.1-mini`. Used only when the app names no model (an older app build). The app can ask for `gpt-realtime-2.1` or `gpt-realtime-2.1-mini` only; the allowlist is `OPENAI_ALLOWED_MODELS` in `src/handler.js`, so a client can't pick a pricier model |
| `OPENAI_REALTIME_VOICE` | Optional, default `marin` (OpenAI recommends `marin` or `cedar`) |
| `PICOVOICE_ACCESS_KEY` | Optional. The owner's Picovoice AccessKey for one-tap "Hey Doddy" (ADR-328). Check the Picovoice plan's limits on active users and keyword-file expiry before giving it to testers |
| `DODDY_ACCESS_CODES` | `label:code,label:code`. Codes must be ≥16 characters (shorter ones are ignored). Generate with `openssl rand -base64 24`. Remove an entry to revoke that tester |

## Deploy on Vercel (not done yet; needs the owner)

1. New Vercel project from `Bienos/doddy.2`, **Root Directory `server/voice-token`**, no framework, no build command.
2. Add the environment variables above (Production). The three ElevenLabs/access-code ones are required for ElevenLabs; `OPENAI_API_KEY` for the OpenAI voice (the default).
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
