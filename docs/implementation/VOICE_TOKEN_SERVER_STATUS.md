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

## Owner steps (in order; see `server/voice-token/README.md`)
1. Choose the host (Vercel is ready: the connector is attached) and approve creating the project.
2. Put `ELEVENLABS_API_KEY`, `ELEVENLABS_AGENT_ID`, `DODDY_ACCESS_CODES` into the host's environment yourself. The key must never be pasted into chat or the repo.
3. Set the URL + your code in the app, and confirm "Private (token server)" works.
4. Turn on agent authentication and set concurrency/daily call limits in ElevenLabs (the spending cap).

## Current deployment (checked 2026-10-19)
The project has moved; the table below (2026-10-09) describes the first one.
| Item | State |
|---|---|
| Vercel project | `doddy-voice-token` (team `doddyyyy`), only domain `doddy-voice-token-beta.vercel.app` (production) |
| The app's address | `VoiceConfig.tokenEndpointAddress` = `https://doddy-voice-token-beta.vercel.app/api/voice-token`; `/api/voice-auth` on the same host. Until this change the app pointed at `doddy-voice-token.vercel.app`, the first team's project, which answers `402 DEPLOYMENT_DISABLED` |
| Code | Production deployment `dpl_9RPq2DvxtBbXELPGGuUYnLbhShUn` from `fc8a502` (PR #84 merged), Ready. Runs the Sign in with Apple server (`754e5d6`) |
| Env | All set for Production: `APPLE_BUNDLE_ID`, `DODDY_SESSION_SIGNING_KEY`, `UPSTASH_REDIS_REST_URL`, `UPSTASH_REDIS_REST_TOKEN` (added 2026-10-18/19), `OPENAI_API_KEY`, `ELEVENLABS_API_KEY`, `ELEVENLABS_AGENT_ID`. `DODDY_ACCESS_CODES` is retired; remove it once sign-in works on the iPhone |
| Live check | `POST /api/voice-auth` and `/api/voice-token` with a bad token → `401 {"error":"session_expired"}`: the signing key and the store settings are present. **Not yet verified:** that Upstash is reachable and that a real Sign in with Apple works; only the first sign-in from the app shows that |

## Deployment (2026-10-09)
| Item | State |
|---|---|
| Vercel project | `doddy-voice-token` (team `bienos`), linked to `Bienos/doddy.2`, root `server/voice-token`; created earlier the same day by a parallel session |
| Production | Deployed from `claude/brave-keller-f8h6uq` @ `882fe97`, region `fra1`. Endpoint `https://doddy-voice-token.vercel.app/api/voice-token` |
| Env `ELEVENLABS_AGENT_ID` | Set (plain, production + preview) |
| Env `DODDY_ACCESS_CODES` | Set (sensitive, production): one owner code, label `owner`. The code was given to the owner as a file, not in chat or the repo |
| Env `ELEVENLABS_API_KEY` | Set by the owner on 2026-10-10 (Sensitive, Production). Key scope: **ElevenAgents = Read, every other endpoint No Access**; switch Agents to Write only if a real token request fails with a permission error |
| Live check | Before the key: wrong code → `500 server_not_configured`. After the key and a production redeploy (2026-10-10, `dpl_6CbRFEZxwEJ3xU9Xo6ozmWCPPDaS`): wrong code → `401 {"error":"invalid_access_code"}`, `GET` → `405`. A real token (owner's access code from the app) is **not yet verified** |
| Previews | Behind Vercel Authentication (SSO), so only production is usable by the app |
| Ignored Build Step | Project setting (2026-10-10): `git diff HEAD^ HEAD --quiet -- .` (run in `server/voice-token`). A push that changes nothing under `server/voice-token/` skips the build, preview and production alike, so other work doesn't use up the Hobby plan's 100 deployments/day. Change the server's code to get a new deployment, or redeploy from the dashboard |
| Agent authentication | Still **off**. Turn on only after the app works in "Private (token server)" mode |

