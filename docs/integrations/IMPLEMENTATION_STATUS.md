# Implementation status — Connected Apps (Google Calendar via Composio)

Date: 2026-10-09. Branch `claude/keen-cray-g4g5vj`.

**Overall: mock milestone complete; live integration unverified/blocked.** Not native-build-verified, not
simulator-verified, not device-verified, not live-provider-verified.

## Environment used

Linux x86_64 (Ubuntu 24.04) cloud container. Node.js 22.22.0, npm 10.9.4, TypeScript 5.9.3, Swift 6.3.3 (swift.org
Linux toolchain, downloaded for this session). **No Xcode, no iOS SDK, no simulator, no device, no Composio API key,
no Google account consent.**

## Per-component status

| Component | Files | Status | Evidence |
|---|---|---|---|
| Config (fail-closed live mode) | `backend/src/config.ts` | implemented, tested | `config-auth.test.ts`; manual: live with nothing set → "Not starting… COMPOSIO_API_KEY is required…"; production live → refused |
| Session boundary (dev / signed) | `backend/src/auth.ts`, `mintSession.ts` | implemented, tested | `config-auth.test.ts` (valid/expired/tampered/wrong key/malformed) |
| Durable store (node:sqlite) | `backend/src/store.ts` | implemented, tested | transactions for nonce consumption, ownership, usage; in-memory DB in tests |
| Capability registry + confirmation policy | `backend/src/capabilities.ts`, `policy.ts` | implemented, tested | synthetic non-executing write capability test |
| Local-day window | `backend/src/time.ts` | implemented, tested | DST 23 h/25 h, skipped midnight (São Paulo 2018), skipped date (Apia 2011), offsets |
| Normalization | `backend/src/calendar.ts` | implemented, tested | all-day, recurring, cancelled, overlap edges, malformed, bounded titles, dropped fields |
| Mock adapter | `backend/src/providers/mock.ts` | implemented, tested | zero outbound sockets asserted |
| Composio adapter | `backend/src/providers/composio.ts` | implemented; type-checked against SDK 0.22.0; exercised with a **fake** SDK client | **never called Composio** — live-provider: blocked |
| Service pipeline + HTTP API | `backend/src/service.ts`, `http.ts`, `app.ts`, `server.ts` | implemented, tested | 73 backend tests; manual curl smoke run in mock mode |
| Opt-in live check | `backend/src/liveCheck.ts` | implemented | **NOT RUN** (no credentials); prints `NOT RUN` without config |
| Swift contracts, client, model | `Packages/DoddyCore/Sources/DoddyCore/ConnectedApps/` | implemented, tested on Linux | 17 new XCTest cases decoding shared fixtures |
| SwiftUI Connected Apps screen | `DoddyApp/Features/ConnectedApps/ConnectedAppsView.swift` | written | **syntax-parsed only**; never compiled or run |
| System auth browser | `DoddyApp/Features/ConnectedApps/SystemWebAuthenticator.swift` | written | **syntax-parsed only**; Swift 6 concurrency diagnostics unknown until a Mac build |
| URLSession transport, Keychain store | `DoddyApp/Infrastructure/URLSessionTransport.swift`, `KeychainSessionStore.swift` | written | **syntax-parsed only** |
| Settings entry, dev server/token fields, privacy copy | `DoddyApp/Features/Settings/SettingsView.swift` | written | **syntax-parsed only** |
| Guard script | `scripts/check_forbidden_capabilities.sh` | updated, run | PASS; verified it FAILs when a write slug and `URLSession` are injected |
| CI script | `scripts/ci.sh` | backend steps added | `--core-only` PASS (below) |

## Commands and results (2026-10-09)

```text
$ cd backend && npm run typecheck          # tsc --noEmit against installed @composio/core 0.22.0 declarations
(no output, exit 0)

$ cd backend && npm test
ℹ tests 73  ℹ pass 73  ℹ fail 0

$ swift test --package-path Packages/DoddyCore -Xswiftc -DSQLITE_DISABLE_SNAPSHOT
Executed 47 tests, with 0 failures (0 unexpected)        # 30 pre-existing + 17 new

$ for f in DoddyApp/**/*.swift DoddyTests/*.swift DoddyUITests/*.swift; do swiftc -parse "$f"; done
22 files, 0 errors                                        # parse only — no type-checking

$ scripts/check_forbidden_capabilities.sh
PASS: networking only in URLSessionTransport, web auth only in Connected Apps, …

$ scripts/ci.sh --core-only
PASS Imported pack integrity · PASS Forbidden-capability guard · PASS Swift package tests (DoddyCore)
PASS Backend type-check · PASS Backend tests · NOT RUN iOS app build + tests (--core-only requested)
RESULT: PASS for core-only scope; iOS app NOT verified
```

## Mock vs live outcomes

| Flow | Mock (backend mock adapter) | Live (Composio + Google) |
|---|---|---|
| Connect (demo tap, no sign-in page) / hosted link + system browser | tested (backend + model) | adapter tested with fake SDK; **not run** |
| Completion binding (callback / verifier) | tested with fake SDK | **not run**; verifier availability Plausible |
| Read tomorrow (events, empty, many/truncated, malformed, error, timeout, rate limit, expired) | tested | **not run** |
| Grants: read-only / missing / not read-only / unverifiable | tested | **not run** — whether Composio exposes Google's granted scope is unverified |
| Disconnect incl. remote cleanup failure | tested (fake SDK failure) | **not run** |
| Constructing the real SDK client | opens **0** sockets (after `disableVersionCheck: true`; before, it contacted registry.npmjs.org) | — |

## Native build / simulator / device

| Check | Status |
|---|---|
| `xcodegen generate` + `xcodebuild` app build | **BLOCKED / NOT RUN** (no macOS/Xcode) |
| `DoddyTests` (`AppEnvironmentTests`, incl. new `.limited` copy) | **NOT RUN** |
| `DoddyUITests` | **NOT RUN.** Note: `testThreeTabsAndHonestPlaceholders` expects Microphone "Not used", but since the V1 voice commit (before this milestone) Settings shows "Only while talking" — likely failing already; not changed here |
| SwiftUI states (loading, demo banner, denial, reconnect, error, receipt) | Logic tested in `ConnectedAppsModelTests`; **rendering not verified** |
| Simulator: `http://localhost:8787` reachable under App Transport Security | **Unverified** — if ATS blocks it, add a development-only ATS exception or use an HTTPS tunnel |
| `ASWebAuthenticationSession` custom-scheme callback, Keychain read/write | **Unverified** (needs simulator/device) |
| Physical iPhone | **NOT RUN** |

## Missing configuration / tooling

- Composio: development project, API key, Google Calendar auth config with `calendar.events.readonly`, pinned toolkit
  version, decision on OAuth callback verifier.
- HTTPS public URL for the backend (tunnel or host). No hosting was created; no paid resources.
- Session signing key + minted token for the owner's device.
- macOS + Xcode for the app build.

## Remaining manual steps (live)

1. Create the Composio auth config (read-only scope) and note its ID; pin the toolkit version.
2. Configure `backend/.env.local` from `backend/.env.example`; enable the verifier at `<public URL>/v1/oauth/verify`.
3. `npm run build && npm run start:env`; `npm run session:mint` → paste token in the app (Settings › Connected Apps server).
4. On a Mac: `make project`, run on a simulator/device, Settings › Connected Apps › Connect Google Calendar; a human
   completes Google consent.
5. Confirm the connection shows **Connected** (not "Needs attention"). If it shows `grant_unverifiable` or
   `grant_not_read_only`, fix the auth config scopes and reconnect — do not relax the check.
6. Tap **Tomorrow's events**; compare with Google Calendar for the same day. Then `npm run live-check`.
7. Disconnect; confirm reads are refused and Doddy's access is gone under Google Account › Security › Third-party access.
8. Record the results here with date, device, and receipt statuses.

## Independent security review (2026-10-09)

A read-only review of `backend/src` (separate reviewer agent) found one blocking defect: a malformed request target
(e.g. `GET //[`) made `new URL` throw outside the handler's `try`, and the unhandled rejection killed the process with
no authentication needed. Reproduced against `node dist/src/server.js`, fixed (parse inside `try` → 400; per-request
`catch` → close that socket; `unhandledRejection` logger), re-checked: 400 and the server keeps serving; regression test
added. Also fixed: refused event requests are now counted before any receipt is written (no unbounded receipt growth),
one user may use at most a quarter of the service's daily provider calls, reconnect stops if the previous remote
connection can't be removed, minted session lifetime default 7 days / max 30. Accepted and documented: tokens are not
individually revocable (rotate the signing key), custom-scheme return URL (use a universal link for release),
callback mode only in development, no HSTS (TLS terminates at a proxy, not this process).

## Known limitations

- One Google account, primary calendar, one local day per request, ≤ 100 events. No conversational routing (the
  ElevenLabs agent has no calendar tool).
- Concurrency limits are per process; run a single backend instance.
- Backend retention policy undecided; receipts are kept indefinitely.
- Monetary cost is estimated, not metered.
- Composio's hosted flow PKCE behaviour is undocumented in the pages checked.
- `@composio/core` declares Node ≥ 22.22.3; tests ran on 22.22.0.

## Next milestone

Run the live check above with the owner's account (gate for "live-provider-tested"), then the first Mac build of this
branch. After that, stage 3 of the roadmap: native Apple Calendar read and Apple Reminders follow-through, as its own
milestone with EventKit re-verification.
