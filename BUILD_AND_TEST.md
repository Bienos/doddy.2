# Build and test

How to build Doddy, run its tests and checks, and what CI runs. What is live is in [STATUS.md](STATUS.md); each
platform's page is in [docs/platforms/](docs/platforms/README.md).

**What runs where (7 Nov 2026).** Everything on this page runs in CI. The Linux jobs run the checks, the Swift
package tests and the servers' tests. The hosted Mac job (`ios-build`: macOS 26, Xcode 26.6) builds the app and runs
its unit and UI tests in the iPhone simulator. Nothing in CI runs on a real iPhone: device checks are recorded by hand
(`STATUS.md`, "On a phone").

## Prerequisites

| Need | For | Notes |
|---|---|---|
| Swift 6 toolchain | `Packages/DoddyCore` tests (any OS) | CI's Linux job uses the `swift:6.1-noble` image; macOS uses Xcode's Swift |
| Python 3, with PyYAML | the checks and generators (`scripts/ci.sh --only checks`) | without PyYAML, the platform-spec check is NOT RUN |
| Node.js 22 | `backend/`, `server/`, `gateway/`, `web/`, `site/`, `tools/secrets/` | `backend/` asks for ≥ 22.22.3 (`@composio/core`); `server/messaging/` for ≥ 22.12 |
| A disposable Postgres database | `server/messaging/` database tests | `TEST_DATABASE_URL`; CI uses Postgres 16. The tests drop its schema |
| macOS with Xcode 26.6 | building the app, unit and UI tests | the version CI pins (`.github/workflows/ios.yml`, `xcodeVersion` in `project.yml`) |
| [XcodeGen](https://github.com/yonaskolb/XcodeGen) | generating `Doddy.xcodeproj` | `brew install xcodegen`; a development tool, not shipped |

Deployment target: **iOS 17.0**, iPhone and iPad (`TARGETED_DEVICE_FAMILY 1,2` in `project.yml`). Swift language
mode 6.

## On any computer (no Xcode needed)

```sh
make test-core                 # the Swift package's tests; on Linux the Makefile adds the SQLite flags
scripts/ci.sh --only checks    # pack integrity, guards, voice agent specs, generated files up to date, CI scripts' own tests
scripts/ci.sh --core-only      # every Linux group: checks, swift, backend, node, messaging
# or a Swift package test by hand (both flags on Linux only):
swift test --package-path Packages/DoddyCore -Xswiftc -DSQLITE_DISABLE_SNAPSHOT -Xlinker --allow-shlib-undefined
```

`scripts/ci.sh` takes `--only` with any of `checks`, `swift`, `backend`, `node`, `messaging` and `ios`, comma
separated. Each hosted Linux job runs one group. `scripts/ci.sh` **without** flags needs Xcode too; if it cannot run a
step it prints `NOT RUN` and exits non-zero (exit 2 = blocked, 1 = failure, 0 = everything passed). `--core-only` exits
0 only for its own narrower scope and still prints the iOS step as `NOT RUN`.

The voice agents' specs are checked in the `checks` group, or by hand:
```sh
python3 -I scripts/voice_agent_spec.py check                     # the main agent (voice-agent/)
python3 -I scripts/voice_agent_spec.py check --agent phone       # voice-agent/phone/
python3 -I scripts/voice_agent_spec.py check --agent task-call   # voice-agent/task-call/
```

Generated files (string catalogs, site pages, blog, web assets, tokens) are never edited or merged by hand: run
`scripts/regen.sh`, then `scripts/ci.sh --only checks`. One `regen.sh` run is enough: `tools/build_site_i18n.py` runs
last, because it translates the English pages that `build_blog.py` and `build_day.py` write; `scripts/test_regen.sh`
(in the `checks` group) checks that.

Voice startup regression tests (no provider calls or microphone):
`swift test --package-path Packages/DoddyCore --filter 'VoiceTokenSupplyTests|VoiceTokenShelfTests|VoiceStartTimelineTests|VoiceNetworkPreparationTests'`
(on Linux add the same flags as `make test-core`). These cover an unfinished warm-up joined by a press,
single use under concurrent presses, late answers after clear/sign-out, different servers, refusal without
duplicate retries, and the existing expiry/cool-down rules. On an iPhone, test a tap just after opening,
after sign-in/consent and after ending a conversation; end while connecting and sign out while a token is
pending. Check `voice-audio`: one request when the tap joins a warm-up (`token warming`), then
`voice first speaking event after start`. Measure audible playback separately; an SDK speaking event can
arrive before audio. No device latency has been measured for this fix.

Action Button readiness: `TalkStartRulesTests` covers the pre-deadline wait, successful handoff,
actual failure and four-second timeout, including readiness/failure arriving at the deadline.
On an unlocked iPhone with voice already configured, press the **Talk to Doddy control** from
another app: check for a connecting popup before the greeting, then ask a question, request an
action and check that its approval card still requires approval. Test cold/warm starts, denied
microphone/Live Activities, an interrupted start and a second press to end. An unready timeout
must offer to open Doddy and must never start a delayed microphone afterward. Expansion and
background microphone behaviour require a device; simulator compilation alone cannot verify them.

Action Button audio session (decision `2026-11-12-action-button-audio-and-island`):
`swift test --package-path Packages/DoddyCore --filter ConversationAudioHoldsTests` covers who sets the session
up (LiveKit for every start but one without opening Doddy), a stale hold dropped by a newer start, and a late
release that must not switch off a newer conversation's session. On an iPhone, press the Action Button with
music playing in another app: the `voice-audio` connect line says `audio session held by Doddy … mixing with
other apps ON`, Doddy is heard and hears you, the music keeps playing, and after Stop the log says `audio session
given back to LiveKit`. The island faces come from `python3 -I tools/whole_doddy/cut_faces.py .`; a second run
must change nothing.

Provider network preparation: `VoiceNetworkPreparationTests` covers every permission/readiness gate,
the two-minute request budget and its independence from token use, plus content-free SDK timing formatting.
The native `DoddyTests/VoiceNetworkHostTests` checks our prewarm host against the pinned ElevenLabs
SDK using its offline provided-token path. On a device, compare cold/warm room and agent-ready timings
(`voice transport timing`) and separately measure audible speech; no room or microphone should start
before a tap. The prewarm log says requested, because LiveKit's internal HEAD runs asynchronously and
swallows network failures; it cannot establish that a connection was prepared or the HEAD succeeded.

### Gateway (Node, no network, no keys)

```sh
cd gateway && npm install && npm test && npm run typecheck   # see gateway/README.md
```
The app hasn't used the gateway since 22 Oct (ADR-586, ADR-587); it stays until the owner decides to delete it. It has
never been called against the real OpenAI API.

### Messaging server (Node 22 + Postgres)
The `messaging` group installs and tests `server/messaging/` (Messages, errands, leaflets, texts and calls, Studio, push).
Set `TEST_DATABASE_URL` to a **disposable** Postgres database (the tests drop its schema); without it the database
tests are listed as SKIPPED. The hosted Linux job provides one. See `server/messaging/README.md`. The app has the
live server's address built in (`DoddyApp/Infrastructure/Server/ServerConfig.swift`); a Debug build can point at
another one in Settings.

## On a Mac

```sh
brew install xcodegen
make project                   # xcodegen generate --spec project.yml  -> Doddy.xcodeproj (iPhone/iPad; Watch and Mac are paused, ADR-572)
make project-iphone            # or: the same app with no entitlements, for a free Apple team -> DoddyiPhone.xcodeproj
xcodebuild -list -project Doddy.xcodeproj
xcodebuild test -project Doddy.xcodeproj -scheme Doddy \
  -destination 'platform=iOS Simulator,name=iPhone 17'   # pick any installed iPhone simulator
# or all of the above plus the Linux-safe steps:
scripts/ci.sh                  # set DODDY_DESTINATION to override the simulator
```

`Doddy.xcodeproj` is generated from `project.yml` and never committed (`.gitignore`); `make project`, `scripts/ci.sh`
and Xcode Cloud's `ci_scripts/ci_post_clone.sh` generate it. TestFlight builds come from Xcode Cloud only (ADR-697,
`docs/implementation/XCODE_CLOUD.md`).

The Ubuntu 24.04 checks/Swift/Node/messaging jobs install the same dependency packages through
`scripts/ci_install_ubuntu_packages.sh`. If the default apt sources fail, it retries
with isolated package lists from the HTTPS kernel.org Ubuntu mirror, authenticated
by the runner's existing Ubuntu archive keyring. Release, updates, security and
backports stay on Noble; signature/TLS checks and all test commands stay enabled.
Both attempts are bounded and a failed fallback fails the job. The checks group
tests primary success, download/install failures, fallback failure and cleanup.

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
- Package versions: the app's two outside packages are exact in `project.yml` (ElevenLabs 3.3.1, LiveKit
  2.19.0). `Config/Package.resolved` is meant to lock every package they pull in too, but **it isn't committed
  yet** (7 Nov 2026). Until it is, `make project`, `scripts/ci.sh` and Xcode Cloud's `ci_post_clone.sh` print
  that there are no pins, and CI records "App package versions match Config/Package.resolved" as SKIPPED. Each
  Mac run keeps what it resolved as the `app-package-resolved` artifact; committing that file as
  `Config/Package.resolved` turns the check on, and from then on CI fails if resolution changes it. To move
  versions later: `make update-packages` on a Mac, then commit `Config/Package.resolved` (decision
  `docs/decisions/2026-11-07-reproducible-app-builds.md`).
- The Mac job resolves the packages first, and tries again (4 attempts, waiting 30 s, 60 s, 90 s) when a
  download fails, such as the `badResponseStatusCode(504)` that github.com release downloads of the LiveKit
  binary frameworks gave on 8 Nov 2026 (`xcodebuild` exit 74). Any other error is not retried, and the step
  still fails after the last attempt. `CI_FETCH_TRIES` and `CI_FETCH_WAIT` change the numbers.
- Pushes to `main` also compile Release for a generic iOS device, unsigned (`DODDY_RELEASE_BUILD=1`), so a
  Release-only error shows up before Xcode Cloud archives.
- `sensitive-paths` (`.github/workflows/pr-guard.yml`, ADR-811): fails when a pull request changes how Doddy
  is signed, configured, deployed or governed (`scripts/check_sensitive_paths.sh` lists the paths) and
  doesn't carry the owner's `owner-approved` label. Adding the label reruns it.
- `Vercel blocked status` (`.github/workflows/vercel-blocked-status.yml`, decision
  `2026-11-09-vercel-blocked-status`): an old Vercel account still connected to the repository marks every push
  "Account is blocked."; on `claude/…` branches, which the live team doesn't build (ADR-498), this replaces that
  red with "Skipped". It never touches `main` or any other Vercel message (`scripts/vercel_blocked_status.sh`).

Locally: `scripts/ci.sh --only swift,backend` runs just those groups; `--app-only` is what the Mac job runs.

**Timings measured 7 Nov 2026** (49 finished runs, `docs/engineering/AUDIT_2026-11-07.md`): a run takes 50
minutes at the median, 59 at the 90th percentile. The Mac job takes about 34 minutes, 28 of them UI tests (the
motion, art and memory-journey classes about 20, the smoke classes about 8). The Linux groups finish well
before it. Older measurements (1 Nov, before the Linux groups split, ADR-684) are in the git history of this file.

**Cost:** the repository is public, so standard hosted Actions runners are free (ADR-543). If it goes private
again, a Mac run costs about $2 to $3 (about $0.062 a minute in October 2026).

**When jobs end in seconds with no logs** (no runner assigned, `runner_id: 0`, both jobs), GitHub is
refusing to start them for the account: it happened on 10–11 October and again from 16 October. The
reason is shown only as a banner on the run page, not in the API. For a private repo it is usually
Actions billing: included minutes used up, a budget reached, or a failed payment (GitHub Settings →
Billing and licensing → Usage, Budgets and alerts, Payment information). Less often, an Actions policy
blocks the actions used (repo Settings → Actions → General). While it lasts, every iOS build is a manual
Mac build.

## Layout

```
DoddyApp/                    the iPhone and iPad app (SwiftUI): App/, Features/ (one folder per feature, 60 of them;
                             the map is docs/platforms/iphone.md), DesignSystem/, Infrastructure/, Intents/, Resources/
                             (string catalogs generated from l10n/, asset catalog, PrivacyInfo.xcprivacy)
Shared/                      code built into the app and its extensions: Live Activity, island art, widget snapshot, intents
DoddyWidgets/ DoddyShare/    Home and Lock Screen widgets, controls and Live Activities; "Save to Doddy" in the Share Sheet
DoddyNotificationContent/    the expanded view of a long-pressed note reminder notification (ADR-786)
DoddyTests/ DoddyUITests/    the app's unit tests and UI tests (run by the hosted Mac job)
Packages/DoddyCore/          the shared Swift package, no UI, tested on Linux and macOS
  Sources/DoddyCore/           the app's rules: voice tools, memory, lists, plans, shopping, privacy, motion and more
  Sources/DoddyPersistence/    the on-device SQLite database (GRDB, FTS5); migrations in DoddyDatabase.swift
  Sources/DoddyDesignTokens/   colour tokens and contrast maths (no SwiftUI)
project.yml                  XcodeGen spec for the app (the source of truth for Doddy.xcodeproj)
project-iphone.yml           the same app with no entitlements, for a free Apple team
Config/                      Info.plists and entitlements for each target
ci_scripts/                  Xcode Cloud's scripts (TestFlight builds)
voice-agent/                 the voice agents' prompt, tools and settings (main, phone/, task-call/)
backend/                     the main server `doddy` (Node/TypeScript): accounts, connected apps, documents, Doddy Web
web/                         Doddy Web, the browser app (Vite, React), served by backend/
server/messaging/            the messaging server `doddy-messaging` (Node/TypeScript, Postgres)
server/voice-token/          the voice token server (Vercel)
gateway/                     an older assistant gateway, unused by the app since 22 Oct (ADR-586, ADR-587)
site/ blog/                  the website www.doddy.lol and its blog (Vercel)
l10n/                        translation tables for the app and the website
contracts/ schemas/fixtures/ JSON examples shared by the servers' tests and the Swift tests
tools/                       generators (catalogs, site pages, blog, web assets, tokens) and the secrets tool
scripts/                     ci.sh and the checks it runs, regen.sh
docs/                        status, platform pages, decisions, plans, research (docs/platforms/README.md maps the code)
design/ assets/              design references and brand files
DoddyWatch*/ DoddyMac*/      Apple Watch and Mac apps: paused, not built (ADR-572)
reference/ prompts/          the October 2026 pack's research and prompts: history, not instructions
```

## Secrets and signing

None are committed, and the app carries none: provider keys live on the servers. Each server lists the names of
the variables it needs in its README and its `.env.example`; for local runs keep values in ignored files such as
`backend/.env.local`, or use 1Password as below.

**1Password (ADR-493).**
- **The record:** project secrets are recorded in 1Password. `secrets/manifest.json` lists each one and its hosts, and each service's `.env.op` holds 1Password references only.
- **Local runs:** `npm run start:op` (backend, messaging server) or `op run --env-file=.env.op -- <command>`.
- **Hosts:** the owner pushes changes with `tools/secrets/sync.mjs` (dry run by default; `--apply` needs the plan's code).
- **Checks:** `node tools/secrets/sync.mjs check` and `node --test "tools/secrets/test/*.test.mjs"` run in `scripts/ci.sh`. They need no 1Password account and no network.
- **Guide:** `docs/security/SECRETS_1PASSWORD.md`. No signing team, provider key, token or production identifier is committed;
`DEVELOPMENT_TEAM` is blank (choose your own team in Xcode to run on a device). The bundle identifier
`com.bienos.doddy2.dev` is **Doddy Beta**, the TestFlight app (ADR-812); the production identifier isn't registered
yet (`docs/OWNER_QUEUE.md`, item 21).

**App Group (on since 2026-10-11, owner has a paid Apple Developer account).** The widgets (ADR-219), "Save to
Doddy" in the Share Sheet (ADR-311) and the parking widget (ADR-315) share a folder, the App Group
`group.<bundle identifier>` (`group.com.bienos.doddy2.dev` by default). `project.yml` signs the app, the widget
extension and the share extension with it (the paused Watch targets, ADR-572, are in `project-watch.yml`; the
notification content extension, ADR-786, has no entitlements and needs only a team). Choose
your team in Xcode for each target; automatic signing adds the App Groups capability and registers the group.
If you also use push, set `DODDY_APP_ENTITLEMENTS = Config/Doddy-Push-AppGroup.entitlements`. For a free Apple
team, use `make project-iphone`: it sets `DODDY_APP_ENTITLEMENTS`, `DODDY_WIDGET_ENTITLEMENTS` and
`DODDY_SHARE_ENTITLEMENTS` to `""` and leaves the widgets and the share extension out (`project-iphone.yml`).

## Doddy's server (`backend/`) on your own computer

`backend/` is the server the app calls `doddy` (Render). It signs the phone in, runs the online-account tools through
Composio (Gmail, Outlook, Google Calendar, Drive, Notion, Todoist: anything that changes something waits for the
person's tap on the exact card), web search, Claude's answers and the documents Doddy makes, account deletion, and
Doddy Web (`docs/platforms/web.md`). On your own computer it starts in **mock mode**: demo data, no keys, a "Demo
server" banner. Live mode refuses to start while a setting it needs is missing, and never falls back to demo data.

It began on 9 Oct as a read-only Google Calendar view, which a Debug build still has (below). Background:
[IMPLEMENTATION_STATUS](docs/integrations/IMPLEMENTATION_STATUS.md) ·
[plan](docs/integrations/COMPOSIO_INTEGRATION_PLAN.md) · [capability matrix](docs/integrations/PROVIDER_CAPABILITY_MATRIX.md) ·
[security](docs/integrations/SECURITY_AND_PERMISSIONS.md) · [online accounts](docs/integrations/ONLINE_ACCOUNTS.md).

### Prerequisites
| Need | For |
|---|---|
| Node.js ≥ 22.22.3 (`@composio/core`'s minimum; Render uses Node 22) | `backend/` (Postgres; PGlite in tests, ADR-525) |
| Composio account, Google account, HTTPS URL | live mode only |

### Commands
```sh
cd backend
npm ci                    # installs the pinned versions from package-lock.json
npm run typecheck         # type-checks against the installed @composio/core declarations
npm test                  # builds, then 649 offline tests (8 Nov 2026, about 15 minutes here); no secrets, no network
npm run build && npm start   # mock mode on http://127.0.0.1:8787 (default; no secrets)
```
`scripts/ci.sh --only backend` runs the same install, type-check and tests.

### Mock walkthrough of the first calendar view (no accounts, Debug build)
1. `cd backend && npm run build && npm start` — prints `MOCK MODE … tokens: dev-user-a, dev-user-b`.
2. Run a Debug build in the iOS Simulator. Settings › Advanced › **Connected Apps server (development)**: address
   `http://localhost:8787`, session token `dev-user-a` (stored in the Keychain).
3. In the same section, **Connected Apps** › Connect Google Calendar → Continue → **Connect demo calendar**. No Google
   page is shown; the screen says **Demo data — Google Calendar is not connected**.
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
5. Connect from the app, read tomorrow, then optionally `npm run live-check` (read-only; prints counts only; it
   also needs `DODDY_LIVE_CHECK_USER_ID` and `DODDY_LIVE_CHECK_TIME_ZONE`, or it prints NOT RUN and exits 2).
6. **Disconnect** in the app. It blocks reads immediately and asks Composio to revoke and delete the connection; if that
   can't be confirmed the app says so — disconnect again or remove access in your Google Account.

### Flights (decision `2026-11-11-flights-kiwi-search-duffel-booking`)
Live mode only, each part off by default: `FLIGHT_SEARCH_ENABLED=1` (Kiwi.com's public MCP server, no key),
`DUFFEL_ACCESS_TOKEN=duffel_test_…` (Duffel search), and `FLIGHT_BOOKING_ENABLED=1` (Duffel test bookings; the server
refuses to book with a live key). Offline tests: `cd backend && npm run build && node --test dist/test/flights.test.js`
(fake Kiwi and Duffel clients; no network, no key).

### Troubleshooting
| Symptom | Likely cause |
|---|---|
| "Not set up" on Connected Apps | No server address or session token in Settings |
| "Doddy's server didn't accept this device's session" | Wrong/expired token, or a dev token against a `signed` server |
| "Needs attention" after connecting | Granted access isn't provably read-only (auth config scopes too broad, or scopes not reported). Fix the auth config and reconnect |
| Simulator can't reach `http://localhost:8787` | App Transport Security may block plain http (unverified); use an HTTPS tunnel |
| `Not starting. Invalid configuration: …` | Read the named variables; values are never printed |

### Messages local actions

Run `scripts/test_messages_model.sh` for pending-action/one-shot/account/cancellation behavior; `swift test --package-path Packages/DoddyCore --filter "LocalMessageActionTests|ServerAssistantClientTests"` for the allowlist, wire opt-in and compatibility fallback. The iOS `DeviceMessageActionsTests` uses in-memory SQLite for typed notes/lists, private-list exclusion, consent and stale-scope guards; it never writes EventKit. `server/messaging`: `npm test` with a disposable `TEST_DATABASE_URL` runs the real route and a local model stand-in, including opt-in/legacy behavior. No external model keys are needed. On a physical phone check reminder permission denial, allow, connection/Pause-all changes, duplicate/read-back and notifications; also test relative dates across DST and the deployed server with the eight user intents.
