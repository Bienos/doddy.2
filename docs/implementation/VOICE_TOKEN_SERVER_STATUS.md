# Voice token server: status
Date: 2026-10-09. Owner instruction: "build" (the step recommended after V2). Closes ADR-034's
"must change before TestFlight" **once deployed and the agent's authentication is on**. Neither has happened yet.

## Built
| Piece | What exists |
|---|---|
| Server `server/voice-token/` | `POST /api/voice-token`, `Authorization: Bearer <access code>` → `{"token"}` from `GET api.elevenlabs.io/v1/convai/conversation/token?agent_id=…` (same endpoint and reply shape the ElevenLabs Swift SDK 3.3.1 uses). Constant-time code check, POST only, fails closed when not configured, 10 s upstream timeout, `no-store`, content-free logs with the tester label only. Vercel entry `api/voice-token.js`. |
| App: connection mode (`VoiceConnectionMode`, DoddyCore) | A token server address in Settings → Voice switches to private mode. A non-https address or missing access code shows "not set up" and **never falls back** to the public agent. An empty address keeps the development public agent. |
| App: `VoiceTokenClient` + `VoiceAccessCodeStore` | One POST per conversation with an ephemeral session. The access code is in the Keychain (`AfterFirstUnlockThisDeviceOnly`). Errors map to plain messages (code not accepted, busy/daily limit, offline…). |
| App: start/close races | Closing the voice screen while the token is being fetched or the SDK is connecting no longer opens or leaves a live microphone. The started conversation is ended straight away. This also fixes the V1 race. Not-set-up no longer triggers the microphone prompt. |
| Settings → Voice | Connection row ("Private (token server)" / "Development (public agent)" / "Not set up"), token server address, access code (save/remove), agent ID field only in development mode. Privacy text names the token server. |
| Guard | Own networking (`URLSession`/`URLRequest`) is allowed only in `VoiceTokenClient.swift`; checked with a probe file. |

## Verified (Linux, 2026-10-09)
- `node --test` (Node 22.22): **6 server tests pass**. They cover the success path (agent ID and API key sent upstream; no token, code or key in logs); wrong, missing and too-short codes refused before any upstream call; GET refused; fail-closed config; upstream 429/401/bad body/timeout/unreachable mapping.
- Swift core: **35 tests pass** (2 new: mode resolution never falls back; token reply mapping). Changed app files pass `swiftc -parse`. Guard PASS.

## Not verified
- App compile with the iOS SDK (typed `throws(VoiceTokenError)` and `do throws(…)` need Swift 6 / Xcode 16+; Security framework calls).
- A real deployment, a real ElevenLabs token, and a conversation started with it on an iPhone.
- ElevenLabs agent with authentication on (currently **off**: dev agent is still public).

## Deployment (2026-10-09, owner approved "ok do it")
| Item | Value |
|---|---|
| Vercel project | `doddy-voice-token` (`prj_Zjw0sfhwCL9WIFhyxQEeYxZt1d0U`), team "bienos", Git `Bienos/doddy.2`, root `server/voice-token`, no framework, Node 22, functions in `fra1` (from the next deploy) |
| Endpoint | **https://doddy-voice-token-bienos.vercel.app/api/voice-token** |
| First deploy | `dpl_Cx43nr2JHHxfECDSSxZ3QeMUvZAB`, branch `claude/busy-mendel-cckm8b` @ `fc17931`, target production |
| Live check | `POST` → 500 `{"error":"server_not_configured"}` (correct: no key/codes yet); `GET` → 405 |
| Env set | `ELEVENLABS_AGENT_ID` (plain, not secret) |
| Protection | Vercel Authentication changed from "all except custom domains" to **previews only**, so the app can reach the production URL; the endpoint itself requires an access code |
| Note | Vercel's production branch is still `main`, which has no `server/voice-token` yet. Pushes to `main` will fail to build until this branch is merged; the live deployment is unaffected |

## Owner steps (in order; see `server/voice-token/README.md`)
1. ~~Choose the host and create the project~~ done (above).
2. Put `ELEVENLABS_API_KEY`, `ELEVENLABS_AGENT_ID`, `DODDY_ACCESS_CODES` into the host's environment yourself (Vercel → doddy-voice-token → Settings → Environment Variables; `ELEVENLABS_AGENT_ID` is already there), as type Sensitive, then **Redeploy**: env changes only apply to new deployments. The key must never be pasted into chat or the repo.
3. Set the URL + your code in the app, and confirm "Private (token server)" works.
4. Turn on agent authentication and set concurrency/daily call limits in ElevenLabs (the spending cap).
