# S1 status — Doddy server: push, SMS, voice tokens
Date: 2026-10-10. Owner decisions on that date:
- Add a server.
- Phone and voice providers: Twilio + ElevenLabs.
- Update channels: push + SMS.
- Apply for Apple Messages for Business.

## Built (`server/`)
- TypeScript/Node 22 service + worker, Postgres schema `001_init.sql`, Render blueprint `render.yaml` (Frankfurt).
- Anonymous device accounts with hashed bearer tokens; full account erasure.
- APNs token-auth push sender (HTTP/2, ES256 JWT); dead device tokens are switched off.
- Twilio SMS (Messaging Service), Twilio Verify phone check, explicit SMS consent with wording version, STOP/START handling, delivery receipts, webhook signature check.
- Outbox with idempotency keys, SKIP LOCKED claiming, backoff on refusals, `unknown` instead of blind resends, message text erased after sending.
- ElevenLabs conversation-token endpoint (unblocks ADR-034's "token server" item).

## Executed (Linux container, Node 22.22.0, PostgreSQL 16.15)
| Command | Result |
|---|---|
| `TEST_DATABASE_URL=… npm test` (in `server/`) | **11 tests, 0 failures** (8 against real Postgres + HTTP layer + dispatcher; Twilio signature cross-checked with the official `twilio` library; APNs JWT verified with a generated key) |
| `node dist/src/index.js` + `worker.js` | Booted, migrated a fresh DB, `/healthz` → `{"ok":true}`, `POST /v1/accounts` → 201 |
| `scripts/check_forbidden_capabilities.sh` | PASS (server scanned for key values; planted key correctly fails) |
| `scripts/ci.sh --core-only` | Pack integrity PASS, guard PASS, server PASS; Swift tests **NOT RUN** (no Swift toolchain in this container) |

## Not run / not real yet
- **No real Apple, Twilio or ElevenLabs call has been made.** Those adapters are untested against the live services. Tests use stand-ins for exactly these three; everything else is real.
- Not deployed. Render resources are not created (paid; owner applies `render.yaml`).
- iPhone app side: built (see "App side" below) but **not compiled or run on a Mac/iPhone yet**.
- Phone calls (Twilio number ↔ ElevenLabs agent) are not built. That is the next server unit (S2).
- Apple Messages for Business: see `APPLE_MESSAGES_FOR_BUSINESS_APPLICATION.md`. It is an owner application with a live-agent requirement.

## Privacy / security notes
- Update text and phone numbers now leave the device (server, Twilio, Apple). Settings copy and the privacy policy must say so before the app uses S1.
- Account creation is anonymous and rate-limited by IP only; App Attest should gate it before public release.
- Rate limits are in-memory (one web instance). Move them to Postgres or Redis before scaling out.

## App side (2026-10-10, second unit)
**Built:**
- `DoddyCore/ServerClient.swift`: platform-agnostic client for every S1 endpoint, plus phone-number normalising, the SMS consent wording (`sms-v1`) and honest status copy.
- `DoddyApp/Infrastructure/Server/`:
  - URLSession transport, the only app networking (guarded);
  - Keychain token, this device only and not in backups;
  - APNs registration through an `AppDelegate` adaptor;
  - `ServerConfig`: https origin only, empty by default because no server is deployed.
- Settings → Updates (`Features/Updates/`):
  - turn notifications on or off, asking permission only on tap;
  - verify a phone number by SMS code;
  - texts toggle with the exact consent wording;
  - STOP explanation;
  - test notification and test text with live status;
  - delete server data (memories untouched);
  - development server-address field.
- The app re-uploads the push token at launch if notifications were turned on.
- `project.yml`: `aps-environment` entitlement. Privacy manifest: phone number and user ID (linked, app functionality).
- "What's built" shows notifications and texts as **"Built · needs setup: Doddy server not connected"** until a server address exists.
- Fixed a stale UI smoke assertion. Since V1 voice, the Microphone row reads "Only while talking", not "Not used".

**Executed (Linux, Swift 6.2.3, Node 22.22.0, PostgreSQL 16.15):**
| Check | Result |
|---|---|
| `swift test` (DoddyCore) | **39 tests, 0 failures**, incl. 9 new client tests |
| End-to-end: Swift `DoddyServerClient` → real Node server over HTTP → real Postgres + dispatcher (Apple/Twilio stand-ins only) | **10/10 PASS**: account, 409 before push token, push sent, wrong code, verify, consent on/off, text sent, voice 503 not configured, account deletion |
| `swiftc -parse` on every app/test Swift file | all parse (type-checking needs Xcode) |
| Guard | PASS; a planted `URLSession` outside `Infrastructure/Server` fails it |
| `scripts/ci.sh --core-only` | **PASS for core-only scope** |

**Not run:**
- Xcode compile of the app target (SwiftUI/UIKit/Security/UserNotifications code is unverified).
- Permission prompt, a real APNs token, a real push on an iPhone, Keychain behaviour.
- Real SMS code and text through Twilio.
- The UI tests.

**Known limits:**
- "What's built" re-reads the server address only at launch.
- Voice now uses `/v1/voice/token` whenever a server is connected (third unit, below).

## Voice tokens (2026-10-10, third unit)
- `VoiceAuthPolicy` (DoddyCore):
  - a connected server → always a short-lived token from `/v1/voice/token`, then `ElevenLabs.startConversation(conversationToken:)` (SDK 3.3.1 API, checked in the SDK source);
  - no server → the public agent ID, **debug builds only**;
  - release builds without a server show "Voice needs the Doddy server".
- A failing server is never silently replaced by the public agent.
- The SDK's own token URL is the same ElevenLabs endpoint the server calls (`/v1/convai/conversation/token`).
- Settings → Voice shows which sign-in is in use.
- **Executed:** 41 core tests (2 new); app files parse; guard PASS.
- **Not run:** a token-based conversation on an iPhone. That needs the deployed server with `ELEVENLABS_API_KEY` and `ELEVENLABS_AGENT_ID`.
- **Owner action once the server is live:** turn on authentication for the Doddy agent in ElevenLabs. Until then the public agent ID still works for anyone who has it.
