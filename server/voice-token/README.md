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

Logs are one JSON line per request: status, error, tester label, upstream status and duration.
If any configured code is too short to use, one `voice_token_config` line per instance names those testers (labels only).
They never contain codes, tokens, keys, IP addresses or anything the user said.

## Environment variables (set in the host, never committed)

| Name | Value |
|---|---|
| `ELEVENLABS_API_KEY` | ElevenLabs API key; restrict it to Conversational AI if the dashboard allows |
| `ELEVENLABS_AGENT_ID` | the Doddy agent (`agent_0501m4et27vyeawrwqfdxxfszfa6` for the dev prototype) |
| `DODDY_TOKENS_PER_HOUR` | optional, default `30`: tokens one tester may get per clock hour. Counted per server instance, so it's a brake against one tester using up the shared agent limits, not a hard cap. A value that isn't a positive whole number refuses to serve |
| `DODDY_ACCESS_CODES` | `label:code,label:code`. Codes must be ≥16 characters (shorter ones are ignored). Generate with `openssl rand -base64 24`. Remove an entry to revoke that tester |

## Deploy on Vercel (not done yet; needs the owner)

1. New Vercel project from `Bienos/doddy.2`, **Root Directory `server/voice-token`**, no framework, no build command.
2. Add the three environment variables above (Production).
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
