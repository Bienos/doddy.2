# Build and test — DODDY V2 (M0 shell + M1 local memory + V1 voice + M2 typed assistant)

**Status of this document: written without access to Xcode.** Everything under "Verified on Linux"
was executed (results in [docs/implementation/M0_REPORT.md](docs/implementation/M0_REPORT.md)).
Everything under "Needs a Mac" is **NOT RUN / UNVERIFIED** until someone runs it and records the result.

> **Connected Apps (2026-10-09):** see [Connected Apps](#connected-apps--google-calendar-read-only-2026-10-09) below.
> The root `README.md` is part of the imported pack and must stay byte-identical (ADR-024), so this V2 build guide is
> where the Connected Apps instructions live.

## Prerequisites

| Need | For | Notes |
|---|---|---|
| Swift 6.0+ toolchain | package tests (any OS) | authored/tested with Swift 6.3.3 (Linux, x86_64) |
| macOS + Xcode (see below) | app build, unit + UI tests | not available when M0 was written |
| [XcodeGen](https://github.com/yonaskolb/XcodeGen) | generating `Doddy.xcodeproj` | `brew install xcodegen`; dev tool only, not shipped |

Deployment target: **iOS 17.0**, iPhone only (ADR-002 in `docs/architecture/DECISIONS.md`; recorded in
`DECISIONS.md`). Use the current stable Xcode that ships an SDK your account can submit with; the
project uses Swift language mode 6 and needs Xcode 16 or newer at minimum.

## Verified on Linux (no Xcode needed)

```sh
scripts/ci.sh --core-only      # pack integrity + forbidden-capability guard + Swift package tests + gateway tests/typecheck
# or individually:
python3 -I scripts/verify_imported_pack.py
scripts/check_forbidden_capabilities.sh
swift test --package-path Packages/DoddyCore -Xswiftc -DSQLITE_DISABLE_SNAPSHOT   # flag needed on Linux only
```

### Gateway (Node, no Xcode, no network, no keys)

```sh
cd gateway && npm install && npm test && npm run typecheck   # 42 tests; see gateway/README.md
```
Needs Node 22+. `ci.sh` runs these when `node` is on the PATH (typecheck only if `npm install` was done).
The gateway has never been deployed or called against the real OpenAI API.

`scripts/ci.sh` **without** flags needs Xcode too; if it cannot run a step it prints `NOT RUN` and exits
non-zero (exit 2 = blocked, 1 = failure, 0 = everything passed). `--core-only` exits 0 only for its own
narrower scope and still prints the iOS step as `NOT RUN`.

## Needs a Mac (UNVERIFIED)

```sh
brew install xcodegen
make project                   # xcodegen generate --spec project.yml  -> Doddy.xcodeproj
xcodebuild -list -project Doddy.xcodeproj
xcodebuild test -project Doddy.xcodeproj -scheme Doddy \
  -destination 'platform=iOS Simulator,name=iPhone 17'   # pick any installed iPhone simulator
# or all of the above plus the Linux-safe steps:
scripts/ci.sh                  # set DODDY_DESTINATION to override the simulator
```

Why `Doddy.xcodeproj` is not committed: no Xcode could open or build a generated project when M0 was
authored, and the architecture notes forbid presenting an unverified project file as working. The
`project.yml` spec **was** run through XcodeGen 2.44.1 on Linux and generated a project (targets,
paths, local package, asset catalog, privacy manifest resolved), but that project has never been opened
in Xcode. After the first successful Mac build, the owner may decide to commit the generated project.

Open points the first Mac run will settle: SwiftUI/UIKit compile errors in `DoddyApp/` (the sources were
only syntax-parsed on Linux, never type-checked), Swift 6 strict-concurrency diagnostics in app code,
simulator name availability, and whether the UI tests' launch-argument defaults behave as written.

## Layout

```
Packages/DoddyCore/          platform-agnostic Swift package (tested on Linux)
  Sources/DoddyCore/           domain types, ports, Unavailable adapters, capability catalog, privacy defaults
  Sources/DoddyDesignTokens/   CANDIDATE colour tokens + WCAG contrast maths (no SwiftUI)
  Sources/DoddyPersistence/    SQLite memory store (GRDB 7.9.0, FTS5)
  Sources/DoddyCore/ConnectedApps/  Connected Apps contracts, client (transport-agnostic), view model
  Sources/DoddyCore/Assistant/ M2: wire types, error taxonomy, citation verifier, grounding selector,
                               assistant service (retry), gateway client + transport/credential ports
  Tests/                       XCTest cases (incl. contract fixtures shared with the gateway)
DoddyApp/                    SwiftUI app target (iPhone): App/, Features/{Home,Capture,Memories,Settings,Onboarding,Voice,Ask,ConnectedApps}/,
                             DesignSystem/, Infrastructure/ (+ Network/: the assistant transport), Resources/ (asset catalog, PrivacyInfo.xcprivacy)
gateway/                     M2 assistant gateway (Vercel functions, plain JS, node tests) - NOT deployed
schemas/fixtures/            wire-contract examples read by both the Swift and the node tests
DoddyTests/ DoddyUITests/    app-level unit and UI smoke tests (NOT RUN without Xcode)
project.yml                  XcodeGen spec (source of truth for the Xcode project)
scripts/                     ci.sh, check_forbidden_capabilities.sh, verify_imported_pack.py
backend/                     Connected Apps server (Node/TypeScript, Composio); server-side only, never in the app
contracts/connected-apps/    JSON fixtures shared by backend and Swift contract tests
docs/integrations/           Connected Apps research, plan, capability matrix, security, status (V2-owned)
docs/ schemas/ assets/ design/ reference/ prompts/   imported pack (read-only reference; not in the app target)
```

## Secrets and signing

None are committed. The app needs none. The Connected Apps backend needs secrets only in live mode
(`COMPOSIO_API_KEY`, `DODDY_SESSION_SIGNING_KEY`); keep them in the ignored `backend/.env.local` or a secret
manager — `backend/.env.example` lists names with empty values. No signing team, provider key, token or production identifier is committed;
`DEVELOPMENT_TEAM` is blank (choose your own team in Xcode to run on a device). The bundle identifier
`com.bienos.doddy2.dev` is a **development placeholder** pending an owner decision.

## Connected Apps — Google Calendar, read-only (2026-10-09)

**Status: mock milestone complete; live integration unverified/blocked; iOS app not compiled for this change.**
Details: [IMPLEMENTATION_STATUS](docs/integrations/IMPLEMENTATION_STATUS.md) ·
[plan](docs/integrations/COMPOSIO_INTEGRATION_PLAN.md) · [capability matrix](docs/integrations/PROVIDER_CAPABILITY_MATRIX.md) ·
[security](docs/integrations/SECURITY_AND_PERMISSIONS.md) · [research baseline](docs/integrations/CONNECTED_INTELLIGENCE_RESEARCH.md).

Doddy can show **tomorrow's events from one user's primary Google Calendar** through a small Doddy backend that uses
Composio. It cannot create, change or delete events. Events are shown, not stored; one tap saves a single event as a
memory. Settings › Connected Apps.

### Prerequisites
| Need | For |
|---|---|
| Node.js ≥ 22.22.3 (tests ran on 22.22.0) | `backend/` (uses `node:sqlite`) |
| Swift 6 toolchain | `Packages/DoddyCore` tests (any OS) |
| macOS + Xcode 16+ and XcodeGen | the iOS app (see `BUILD_AND_TEST.md`) |
| Composio account, Google account, HTTPS URL | live mode only |

### Commands
```sh
# backend
cd backend
npm ci                    # installs the pinned versions from package-lock.json
npm run typecheck         # type-checks against the installed @composio/core declarations
npm test                  # 73 offline tests (mock + fake Composio client); no secrets, no network
npm run build && npm start   # mock mode on http://127.0.0.1:8787 (default; no secrets)

# Swift package (from repo root)
swift test --package-path Packages/DoddyCore            # add -Xswiftc -DSQLITE_DISABLE_SNAPSHOT on Linux

# everything that runs without Xcode
scripts/ci.sh --core-only
# on a Mac, everything including the app build and app tests (UNVERIFIED for this change)
scripts/ci.sh
```

### Mock walkthrough (no accounts)
1. `cd backend && npm run build && npm start` — prints `MOCK MODE … tokens: dev-user-a, dev-user-b`.
2. Run the app in the iOS Simulator. Settings › **Connected Apps server (development)**: address `http://localhost:8787`,
   session token `dev-user-a` (stored in the Keychain).
3. Settings › **Connected Apps** › Connect Google Calendar → Continue → **Connect demo calendar**. No Google page is
   shown; the screen says **Demo data — Google Calendar is not connected**.
4. **Tomorrow's events** → three made-up events, source, checked time, receipt. Tap **Save** on one to keep it as a memory.
5. **Disconnect** → events disappear; reads are refused.

Without the backend you can drive the same flow with curl, e.g.
`curl -H 'authorization: Bearer dev-user-a' http://127.0.0.1:8787/v1/connected-apps/google-calendar`.

### Live configuration (a human completes Google consent)
1. In a **development** Composio project, create a Google Calendar auth config with scopes
   `https://www.googleapis.com/auth/calendar.events.readonly` (own Google OAuth client preferred). Note: Google
   OAuth "Testing" mode limits who can consent; public use may need Google verification.
2. Pin the toolkit version; expose the backend over HTTPS; enable the OAuth callback verifier at
   `<public URL>/v1/oauth/verify` (recommended).
3. `cp backend/.env.example backend/.env.local`, fill it in (`DODDY_MODE=live`, `DODDY_AUTH_MODE=signed`,
   `DODDY_SESSION_SIGNING_KEY=$(openssl rand -base64 32)`, Composio values). The server **refuses to start** if
   anything is missing; it never falls back to demo data.
4. `npm run build && npm run start:env`; mint a device token with
   `node --env-file=.env.local dist/src/mintSession.js` and paste it in the app.
5. Connect from the app, read tomorrow, then optionally `npm run live-check` (read-only; prints counts only).
6. **Disconnect** in the app. It blocks reads immediately and asks Composio to revoke and delete the connection; if that
   can't be confirmed the app says so — disconnect again or remove access in your Google Account.

### Troubleshooting
| Symptom | Likely cause |
|---|---|
| "Not set up" on Connected Apps | No server address or session token in Settings |
| "Doddy's server didn't accept this device's session" | Wrong/expired token, or a dev token against a `signed` server |
| "Needs attention" after connecting | Granted access isn't provably read-only (auth config scopes too broad, or scopes not reported). Fix the auth config and reconnect |
| Simulator can't reach `http://localhost:8787` | App Transport Security may block plain http (unverified); use an HTTPS tunnel |
| `Not starting. Invalid configuration: …` | Read the named variables; values are never printed |
| `ExperimentalWarning: SQLite` | Expected on Node 22 (`node:sqlite`) |
