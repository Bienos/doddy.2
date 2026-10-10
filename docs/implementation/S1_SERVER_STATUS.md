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
- **iPhone app is not connected yet.** It still has no networking (guard enforces it). The app side is the next unit:
  - push permission + token upload;
  - phone verification and SMS consent screens;
  - Keychain device token;
  - "Updates" settings.
- Phone calls (Twilio number ↔ ElevenLabs agent) are not built. That is the next server unit (S2).
- Apple Messages for Business: see `APPLE_MESSAGES_FOR_BUSINESS_APPLICATION.md`. It is an owner application with a live-agent requirement.

## Privacy / security notes
- Update text and phone numbers now leave the device (server, Twilio, Apple). Settings copy and the privacy policy must say so before the app uses S1.
- Account creation is anonymous and rate-limited by IP only; App Attest should gate it before public release.
- Rate limits are in-memory (one web instance). Move them to Postgres or Redis before scaling out.
