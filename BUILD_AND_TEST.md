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
swift test --package-path Packages/DoddyCore -Xswiftc -DSQLITE_DISABLE_SNAPSHOT -Xlinker --allow-shlib-undefined   # both flags on Linux only
```

### Generated files (string catalogs, site pages, blog, web assets, tokens)

```sh
scripts/regen.sh                 # rewrites every generated file; after a merge conflict, instead of merging by hand
scripts/ci.sh --only checks      # each generator's --check, and scripts/test_regen.sh
```
One `regen.sh` run is enough: `tools/build_site_i18n.py` runs last, because it translates the English
pages that `build_blog.py` and `build_day.py` write. `scripts/test_regen.sh` checks that on a copy of the
checkout (stale English pages, one regen.sh run, every --check), and that `regen.sh` and the `checks`
group list the same generators.

### Gateway (Node, no Xcode, no network, no keys)

```sh
cd gateway && npm install && npm test && npm run typecheck   # 63 tests; see gateway/README.md
```
Needs Node 22+. `ci.sh` runs these when `node` is on the PATH (typecheck only if `npm install` was done).
The gateway has never been deployed or called against the real OpenAI API.

`scripts/ci.sh` **without** flags needs Xcode too; if it cannot run a step it prints `NOT RUN` and exits
non-zero (exit 2 = blocked, 1 = failure, 0 = everything passed). `--core-only` exits 0 only for its own
narrower scope and still prints the iOS step as `NOT RUN`.

### Messaging server (Node 22 + Postgres)
`scripts/ci.sh` also installs and tests `server/messaging/` (notifications, texts, phone calls, daily
news). Set `TEST_DATABASE_URL` to a **disposable** Postgres database (the tests drop its schema);
without it the database tests are listed as SKIPPED. The Linux CI job provides one. See
`server/messaging/README.md`. On a device, Settings → Messages from Doddy needs a deployed server
address (https).

## Needs a Mac (UNVERIFIED)

```sh
brew install xcodegen
make project                   # xcodegen generate --spec project.yml  -> Doddy.xcodeproj (iPhone/iPad; Watch and Mac are paused, ADR-572)
xcodebuild -list -project Doddy.xcodeproj
xcodebuild test -project Doddy.xcodeproj -scheme Doddy \
  -destination 'platform=iOS Simulator,name=iPhone 17'   # pick any installed iPhone simulator
# or all of the above plus the Linux-safe steps:
scripts/ci.sh                  # set DODDY_DESTINATION to override the simulator
```

**Hosted CI (`.github/workflows/ios.yml`, ADR-123, ADR-137, ADR-497, ADR-684)** runs these jobs side by side:
- `changes` (Ubuntu, seconds): `scripts/ci_needs_mac.sh` decides whether the pull request needs the macOS build
  (any changed file that can reach an Xcode target or its tests), and `scripts/ci_groups.sh` decides which Linux
  groups it needs. An unlisted path, or no list, runs everything.
- Linux groups, each `scripts/ci.sh --only <group>`: `checks` (Python generators, guards, specs; always),
  `swift` (package tests, app-logic type-check, model tests; SwiftPM `.build` cached), `backend`, `node`
  (gateway, web, site, voice token, secrets tool) and `messaging` (with Postgres). npm downloads are cached.
- `core`: one result for all the Linux groups, green when every group that ran passed (a skipped group is fine).
- `ios-build` (macOS; named `ci` until ADR-811; runner image `macos-26` and Xcode 26.6 pinned):
  `scripts/ci.sh --app-only`: the Swift package tests, then the Xcode part (build
  once with `xcodebuild build-for-testing`, unit tests, restart the simulator, UI tests: ADR-561; then the
  simulator restarted again and the native island test alone, under an 8-minute watchdog, because the hosted
  simulator sometimes freezes during it: ADR-764). It no longer
  waits for `core`, and no longer repeats the Node suites. Run the workflow by hand (Actions → iOS build and
  tests → Run workflow) and it always runs.
- Pushes to `main` (ADR-811) run every job, each commit in its own run that nothing cancels; pull requests
  keep the path selection above, and a newer push to a pull request cancels its older run.
- UI tests on pull requests are the smoke classes only (`DODDY_UI_TESTS=smoke`: `LaunchSmokeTests`,
  `WelcomeUITests`, `LegalAcceptanceUITests`, `PolishSmokeTests`, about 8 of the suite's 27 minutes on
  7 Nov 2026); pushes to `main`, runs by hand and pull requests labelled `full-ui-tests` run every UI
  test and the native island test. Locally `scripts/ci.sh` runs them all unless you set the variable.
- Package versions are pinned: `Config/Package.resolved` holds every Swift package the app resolves
  (LiveKit is also `exactVersion` in `project.yml`). `make project`, `scripts/ci.sh` and Xcode Cloud's
  `ci_post_clone.sh` install it into the generated project; CI fails if resolution changes it, and keeps
  what it resolved as the `app-package-resolved` artifact. To move versions: `make update-packages` on a
  Mac, then commit `Config/Package.resolved` (decision `docs/decisions/2026-11-07-reproducible-app-builds.md`).
- Pushes to `main` also compile Release for a generic iOS device, unsigned (`DODDY_RELEASE_BUILD=1`), so a
  Release-only error shows up before Xcode Cloud archives.
- `sensitive-paths` (`.github/workflows/pr-guard.yml`, ADR-811): fails when a pull request changes how Doddy
  is signed, configured, deployed or governed (`scripts/check_sensitive_paths.sh` lists the paths) and
  doesn't carry the owner's `owner-approved` label. Adding the label reruns it.

Locally: `scripts/ci.sh --only swift,backend` runs just those groups; `--app-only` is what the Mac job runs.

**Timings measured 1 Nov 2026** (runs 41330977302 on the Mac side, 41340906950 on the Linux side), before
ADR-684: `core` 14.5 min (backend tests 411 s, Swift package tests 214 s, messaging 40 s, the rest under 45 s each);
the Mac job 62 min (UI tests 40.7 min, unit tests 4.3, build 4.3, `xcodebuild -list` 1.3, and about 14 min of Linux
checks it repeated, 413 s of them the backend tests). With the Mac waiting for `core`, a pull request took about
79 minutes.

**Historical #166 run before reconciliation with #164** (first hosted run of the new workflow, run 41344675285, 1 Nov): all jobs green. The Linux side
finished in 7.5 min (`swift` 6.7 min on a cold SwiftPM cache, `backend` 4.0, `messaging` 0.8, `node` 0.6,
`checks` 0.3); the Mac job took 48.6 min (the historical `ci.sh --skip-node` path 47.4), so the whole pull request took 48.8 min
instead of about 79. The npm caches and the SwiftPM cache were empty on that run; the next run shows their effect.

**Cost:** the repository is now public, so standard hosted Actions runners are free (ADR-543). Historical private-repository costs follow. A macOS run took about 52 minutes
(34 of them UI tests) at $0.062 a minute, about $3.20, on 14 October; ADR-499 should take about 10 minutes
off the UI tests (not yet measured). From 12 to 14 October CI used about $250.

**When jobs end in seconds with no logs** (no runner assigned, `runner_id: 0`, both jobs), GitHub is
refusing to start them for the account: it happened on 10–11 October and again from 16 October. The
reason is shown only as a banner on the run page, not in the API. For a private repo it is usually
Actions billing: included minutes used up, a budget reached, or a failed payment (GitHub Settings →
Billing and licensing → Usage, Budgets and alerts, Payment information). Less often, an Actions policy
blocks the actions used (repo Settings → Actions → General). While it lasts, every iOS build is a manual
Mac build.

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
manager — `backend/.env.example` lists names with empty values.

**1Password (ADR-493).**
- **The record:** project secrets are recorded in 1Password. `secrets/manifest.json` lists each one and its hosts, and each service's `.env.op` holds 1Password references only.
- **Local runs:** `npm run start:op` (backend, messaging server) or `op run --env-file=.env.op -- <command>`.
- **Hosts:** the owner pushes changes with `tools/secrets/sync.mjs` (dry run by default; `--apply` needs the plan's code).
- **Checks:** `node tools/secrets/sync.mjs check` and `node --test "tools/secrets/test/*.test.mjs"` run in `scripts/ci.sh`. They need no 1Password account and no network.
- **Guide:** `docs/security/SECRETS_1PASSWORD.md`. No signing team, provider key, token or production identifier is committed;
`DEVELOPMENT_TEAM` is blank (choose your own team in Xcode to run on a device). The bundle identifier
`com.bienos.doddy2.dev` is a **development placeholder** pending an owner decision.

**App Group (on since 2026-10-11, owner has a paid Apple Developer account).** The widgets (ADR-219), the
watch complications (ADR-262), "Save to Doddy" in the Share Sheet (ADR-311) and the parking widget (ADR-315)
share a folder, the App Group `group.<bundle identifier>` (`group.com.bienos.doddy2.dev` by default).
`project.yml` signs the app, the widget extension and the share extension with it (the watch targets, paused, are in `project-watch.yml`; the
notification content extension, ADR-786, has no entitlements and needs only a team). Choose
your team in Xcode for each target; automatic signing adds the App Groups capability and registers the group.
If you also use push, set `DODDY_APP_ENTITLEMENTS = Config/Doddy-Push-AppGroup.entitlements`. To build without it
(a free Apple ID, whose support for App Groups isn't verified here), set `DODDY_APP_ENTITLEMENTS`,
`DODDY_WIDGET_ENTITLEMENTS`, `DODDY_SHARE_ENTITLEMENTS` and `DODDY_WATCH_ENTITLEMENTS` to `""`: the widgets then
say "Open Doddy to set up widgets" and the share extension says sharing isn't set up.

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
| Node.js ≥ 22.22.3 (tests ran on 22.22.0) | `backend/` (Postgres; PGlite in tests, ADR-525) |
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
swift test --package-path Packages/DoddyCore            # on Linux add -Xswiftc -DSQLITE_DISABLE_SNAPSHOT -Xlinker --allow-shlib-undefined

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
