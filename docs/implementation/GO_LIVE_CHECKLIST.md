# Go-live checklist (living)

**Last checked 2026-10-18** at `754e5d6` (default branch). Stage A updated the same day on branch `claude/fervent-edison-3gnqpq`. This replaces `GO_LIVE_STATUS_2026-10-11.md`, which stays as the 11 Oct snapshot. The scope it gets ready is `docs/product/V1_SCOPE.md` (a proposal until the owner marks it up).

**How to keep it current:**
- Change a row's **Today** when its state changes, with the commit, ADR or link that shows it.
- Close a row only with evidence: a build log, a device result, a screenshot or a URL. Never close one from a doc or a mock.
- **Who:**
  - **Owner** needs your account, money or decision.
  - **Agent** is a code or doc change a coding agent can make.
  - **Both** needs your decision first, then an agent's change.

**How it was checked on 18 Oct:**
- read-only GETs to every server address;
- the GitHub Actions run list;
- the live ElevenLabs agent's settings;
- the names (never the values) of the voice token server's environment variables on Vercel;
- `scripts/check_forbidden_capabilities.sh` run on this branch.

Nothing was built with Xcode here.

## Stages

1. **A. Main works again.** Builds, passes its checks, and talks on the owner's phone. **Do this first; everything else waits on it.**
2. **B. The v1 build.** The marked-up scope applied to the code.
3. **C. External TestFlight beta.** People other than the owner.
4. **D. App Store 1.0.**

## A. Main works again

| # | Item | Today | Evidence | Who |
|---|---|---|---|---|
| A1 | Hosted CI is blocked by billing again | **Closed 18 Oct** | Every run from 16 Oct failed in 2–6 s without running a step ("recent account payments have failed or your spending limit needs to be increased"). Jobs run again since 15:08 UTC on 18 Oct. The first full macOS run (39139146509) compiled `754e5d6` for the first time and found a missing `import DoddyCore` in `VoiceAccessGate.swift` and a macOS-only `LogSafeErrorTests` failure; two never-run app unit tests failed next. With those fixed, run 39143322850 on `739c2725` (`claude/fervent-edison-3gnqpq`) was the first green macOS run since `44f6934` on 14 Oct: the app builds and its unit, UI and DoddyCore tests pass | Done (owner fixed billing) |
| A2 | The capability guard fails on main | **Fixed on `claude/fervent-edison-3gnqpq`**, not on main yet | `scripts/check_forbidden_capabilities.sh` exits 1 at `754e5d6`: networking in `VoiceAuthSession.swift`, and `AuthenticationServices` imported in `VoiceAuthSession.swift` and `VoiceAccessGate.swift`. PR #84's fix (ADR-494) is merged into this branch (`c7ce9146`); on this branch `scripts/ci.sh --core-only` passes on Linux (18 Oct, Swift 6.1): the guard, 1,105 DoddyCore tests, the app logic type-check and every server's tests; only the messaging database tests were skipped (no test database). The iOS build needs CI or a Mac. The other branches with their own fixes (`sweet-albattani`, `upbeat-ride`, `awesome-cray`, `epic-wright`) can close once this or #84 lands | Agent: merge once CI runs (A1) |
| A3 | The app's voice server address is disabled | **Fixed on `claude/fervent-edison-3gnqpq`**, not on main yet (ADR-521) | The app hard-coded `https://doddy-voice-token.vercel.app`, which answers **402 DEPLOYMENT_DISABLED** (old team `bienos`), and `754e5d6` removed the public-agent fallback, so a build of main has no working voice. The app showed this as "Apple sign-in couldn't be verified". `VoiceConfig.tokenEndpointAddress` now points at `doddy-voice-token-beta.vercel.app`, the only domain of the `doddyyyy` project (commit `467f89b` from `epic-wright`, taken with `cherry-pick -x`). After the change the app will say "Voice isn't set up yet" until A4 is done | Agent: merge once CI runs (A1) |
| A4 | The live token server isn't configured for sign-in | **Partly**: `APPLE_BUNDLE_ID` = `com.bienos.doddy2.dev` set on 18 Oct (production) | The server running `754e5d6` is the Vercel project `doddy-voice-token` (team `doddyyyy`), domain `doddy-voice-token-beta.vercel.app`. On 18 Oct a sign-in `POST /api/voice-auth` and `POST /api/voice-token` both answer `503 server_not_configured`. Its environment has only `OPENAI_API_KEY`, `ELEVENLABS_API_KEY`, `ELEVENLABS_AGENT_ID` and `DODDY_ACCESS_CODES` (names read from Vercel). Still needed: an Upstash Redis database (`UPSTASH_REDIS_REST_URL`, `UPSTASH_REDIS_REST_TOKEN`); `DODDY_SESSION_SIGNING_KEY`, at least 32 random bytes (for example `openssl rand -base64 48`), which never goes in chat or the repo; Then redeploy production. (`APPLE_BUNDLE_ID` must match the build's bundle ID; without it sign-in fails as "Apple sign-in couldn't be verified".) Remove `DODDY_ACCESS_CODES` once sign-in works. Its 19 tests pass | Owner (your other session "Fix voice token test and capability guard failures" has a step-by-step guide) |
| A5 | Sign in with Apple on the App ID | **Open** (Debug builds can bypass it for testing since ADR-551; Release and TestFlight can't) | `754e5d6` added the entitlement to all four app entitlement files. The App ID needs the capability, which needs a paid team; `DEVELOPMENT_TEAM` is empty (`project.yml:40`) | Owner |
| A6 | `754e5d6` has no ADR, and three docs contradict it | **Closed on `claude/fervent-edison-3gnqpq`** | ADR-522 records it, superseding ADR-147 ("No login for now") for voice only. Updated to match: the privacy draft §5.2, `VOICE_TOKEN_SERVER_STATUS.md` (a note at the top, plus the current deployment from `467f89b`) and the Mac checklist (line 119, plus sign-in steps V0a–V0f in section 5) | Agent |
| A7 | Build main on a Mac and talk to Doddy on the phone | **Open** | `STATUS.md` names `ce02763` (11 Oct) as the last device build. The ElevenLabs logs show device calls on 14, 15 and 16 Oct from a newer build whose commit isn't recorded. Record the commit you build | Owner |
| A8 | `STATUS.md` is out of date | **Closed on `claude/fervent-edison-3gnqpq`** | It listed PR #44 and PR #61 as unmerged; both are on main. It named agent version `agtvrsn_5201…`; after the ASK-01 sync on 18 Oct the live one is `agtvrsn_6401m57e22qwepwtr1ywwe64x2k4` (85 tools, `43a94083`); it changed several times that day. Now it leads with A1–A4 | Agent |
| A9 | Duplicate ADR numbers | **Partly** | 218 and 458 each appear twice in `DECISIONS.md`; a note at its top now says to cite them by number and title. Still open on other PRs: #85 and #86 both claim 483, and #78 claims 444. Open branches have used numbers up to 496, so new work starts at 500 or above | Agent (on the PRs that claim them) |
| A10 | Vercel's free daily deployment limit is used up | **Partly**: preview deployments turned off on 18 Oct (owner's request) for `doddy`, `doddy-voice-token` and `doddy-gateway` (`previewDeploymentsDisabled`), so `claude/*` branches no longer create deployments; production from `claude/loving-dirac-uuxoux` still deploys. The limit itself still has to reset | On 18 Oct at 12:08 UTC, PR #88's previews on `doddy`, `doddy-voice-token` and `doddy-gateway` were refused with `api-deployments-free-per-day` ("more than 100"). Team `doddyyyy` is on the free plan, and every push from any of the ~127 branches creates an attempt on all three projects. Production isn't affected (`doddy-voice-token` still serves `754e5d6`), but the redeploy A4 needs waits until the limit resets (up to 24 hours). To turn previews back on (for example to review a site change before merging): Vercel → project → Settings → Git, or set `previewDeploymentsDisabled` to false | Owner (wait for the reset, or upgrade) |

## B. The v1 build

Starts when `V1_SCOPE.md` is marked up.

| # | Item | Today | Evidence | Who |
|---|---|---|---|---|
| B1 | Mark up `V1_SCOPE.md` and record it as ADR-520 | **Open** | Proposal written 18 Oct | Owner |
| B2 | A switch for "Hide" | **Open** | The app has no feature flags. Add one list in DoddyCore that removes each hidden feature's ways in (Settings rows, Home cards, widgets, quick actions) and leaves out its voice tools | Agent |
| B3 | The live voice agent's tools match v1 | **Open** | The live agent has 58 tools. `note_capability_gap` is marked `not_synced` in `voice-agent/tools.json` but is being called live. The 16 Oct `start_translator` change isn't on the live agent. Hidden features' tools must come off the agent. The owner changes the live agent, never the app | Both |
| B4 | Developer-only fields out of release builds | **Partly** | Gone since `754e5d6`: token server address, access code, agent ID. Still visible in release builds: Connected Apps server and session token (`SettingsView.swift:327-369`), gateway address and invite code (`:561-585`), the provider and model picker (`HomeView.swift:144-146`, `SettingsView.swift:996`), and "Development build" text | Agent |
| B5 | iPhone only, no Watch app embedded | **Open** | The app and extensions build for iPhone and iPad (`TARGETED_DEVICE_FAMILY "1,2"` in `project.yml`). Build v1 from `project-iphone.yml` with family `1` (V1 decision 4) | Both |
| B6 | Pending notifications can pass iOS's limit of 64 | **Fixed for note reminders and birthdays on `claude/fervent-edison-3gnqpq`** (ADR-523; tested on Linux, not on a device) | `NotificationBudget` keeps 14 slots for Doddy's own notifications; note reminders and birthdays share the other 50 and say the limit instead of being dropped. Still open: Doddy's own schedulers (routines, timers, nudges) don't consult it, so past 14 of those iOS can still drop some. Close after a device run with 50 slots in use | Agent |
| B7 | Remove the unused background mode | **Open** | The `remote-notification` background mode (`Doddy-Info.plist:48-53`) and `CKSharingSupported` (`:38`) are declared for iCloud sharing, which is off | Agent |
| B8 | Privacy manifests for the extensions | **Open** | Only `DoddyApp/Resources/PrivacyInfo.xcprivacy` exists. The widgets and Share extension have none | Agent |
| B9 | Export compliance key | **Open** | `ITSAppUsesNonExemptEncryption` isn't set. The backup file uses AES-256-GCM, so App Store Connect asks on every upload until it is | Both (owner confirms the answer) |
| B10 | "What leaves this iPhone" tells the truth | **Open** | `DataFlowView.swift:16,33` hard-codes `tokenServerSet: true`. The OpenAI row says its retention "isn't verified" (`DataFlow.swift:132`) | Agent |
| B11 | Voice sessions starting twice, and silent sessions | **Partly** | One conversation at a time is ADR-496 on PR #84 (not merged). Silent 30 s sessions still happened (four on 16 Oct, 04:42–04:47). Finding the cause needs a phone log (`docs/implementation/VOICE_SESSION_STARTS.md` on #84) | Both |
| B12 | Permission texts name the right provider | **Open** | The Contacts text still says "ElevenLabs" (`project.yml:129`). It must match the beta's provider (V1 decision 5) | Agent |
| B13 | The homepage says what the beta has | **Open** | The hero shows the plan card (ADR-482), which v1 hides | Agent |

## C. External TestFlight beta

| # | Item | Today | Evidence | Who |
|---|---|---|---|---|
| C1 | Production identity | **Open** | The bundle ID is the dev placeholder `com.bienos.doddy2.dev` (`project.yml:42`; the URL scheme name `com.bienos.doddy2.dev.links` in `Doddy-Info.plist:64` follows it). Version 0.1.0, build 1 (ADR-584). Decide before the first App Store Connect record: changing it later means a new app record | Owner, then Agent |
| C2 | Signed archive uploads | **Open** | No signed build is recorded. The App Group has never been provisioned | Owner |
| C3 | App icon from the owner's pack | **Done (ADR-565, 21 Oct; replaced ADR-557's wave frame of 20 Oct)** | Doddy's face, the open head of the pack's blink sheet 007, on orange `#FF6A00`, iPhone and Watch byte-identical, no dark variant; `tools/whole_doddy/make_app_icon.py`, provenance in `docs/design/UPLOADED_MEMORY_ASSETS.md`. Not yet seen on a device | Agent |
| C4 | Lock down the voice provider | **Partly** | Live ElevenLabs agent today: `enable_auth: false` (anyone with its ID can use it); `daily_limit: 10` for the whole agent across everyone; `record_voice: true`; `retention_days: -1` (kept forever). OpenAI: no spend limit recorded, and retention unverified (`VOICE_PROVIDER_TEST_STATUS.md:10,79`). Turning authentication on cuts off older builds that still use the public agent | Owner |
| C5 | Device pass of every Ship row | **Open** | `MAC_VERIFICATION_CHECKLIST_2026-10-10.md` has 48 sections; its result log has one blank row. It has no steps for the sign-in gate. An agent should cut it to the v1 Ship rows first | Both |
| C6 | Privacy policy published | **Partly** | Draft at `docs/legal/PRIVACY_POLICY_DRAFT.md` (15 Oct): not reviewed, not published. It needs the controller's legal name, address and contact. Cut it to v1 (§5.4–5.10 drop). A lawyer reads it. Publish on doddy.lol and link it from the app and App Store Connect | Both |
| C7 | A support address and "Report a problem" | **Open** | No support or privacy email exists. The waitlist promises deletion on request without an address (`site/README.md`, "Needs the owner" 2). Settings has no way to report a problem | Owner (address), Agent (Settings row) |
| C8 | Deleting the voice account revokes the Apple token | **Code on `claude/fervent-edison-3gnqpq`; waits on the owner's key** (ADR-524; server tested on Linux with Apple faked, app sign-in view NOT COMPILED) | Sign-in sends Apple's authorization code; the server keeps Apple's refresh token sealed and revokes it at `/auth/revoke` before deleting the account. Owner: make a Sign in with Apple key (Apple Developer › Keys, needs the paid team from A5), put the `.p8` in 1Password, set `APPLE_TEAM_ID`, `APPLE_SIGN_IN_KEY_ID` and `APPLE_SIGN_IN_PRIVATE_KEY` on `doddy-voice-token`. Close after a device sign-in and deletion where the log says `apple: revoked` and the app disappears from Apple ID › Sign in with Apple | Both |
| C9 | A beta plan | **Open** | Doesn't exist. It should cover: who (20–24 adults who aren't friends, from the waitlist), consent text for the research, how long (2 weeks), what you'll measure, and how feedback comes back (TestFlight feedback and crash reports; the app has no analytics) | Both |
| C10 | Pass/fail thresholds set before the beta starts | **Open** | Candidates are in `VALIDATION_AND_METRICS.md` and `MONETIZATION_MODEL_V2.md` §7 (activation, later-day retrieval, real cost per minute) | Owner |
| C11 | Security review of what changed | **Open** | `THREAT_MODEL.md` (17 lines) predates the servers. It says to rerun it before TestFlight. The voice token server's sign-in code (`voice-auth.js`) is new since the 11 Oct review. The 11 Oct critical and high findings for the app, DoddyCore and app tests are fixed and compiled, but not seen on a device | Agent |
| C12 | Website consent | **Open** | Google Analytics loads on every page with no consent choice (`site/analytics.js`); Google Fonts load before any choice; the waitlist has no retention period. The beta is recruited from this site's EU visitors | Both |
| C13 | Languages | **Open** | All nine translations are unread machine drafts (`l10n/REVIEW_NOTES.md`). Hide eight in v1 (V1 decision 2) or get a native read of each | Both |
| C14 | A one-page outage plan | **Open** | Nothing exists. It should say what to do when the token server or the voice provider is down, how to rotate a key, and how to switch voice off for everyone | Agent |
| C15 | TestFlight test information | **Open** | What to test, a feedback email, and sign-in notes for Apple's beta review | Both |

## D. App Store 1.0

| # | Item | Today | Evidence | Who |
|---|---|---|---|---|
| D1 | Store listing in English and Polish | **Open** | No listing text or screenshots. The homepage dropped its design-preview screens (ADR-481), so screenshots must come from the real app | Both |
| D2 | App Privacy answers | **Partly** | Draft in the privacy policy's Appendix C, with items marked [CONFIRM]. Redo it from the final v1 policy | Both |
| D3 | Age rating | **Open** | Not answered. The privacy draft §7 depends on it | Owner |
| D4 | Notes for App Review | **Open** | Explain the microphone, background audio (a conversation continues when the phone locks), full Calendar access, the island's buttons, and how to sign in | Agent drafts, Owner sends |
| D5 | Terms of Use | **Open** | None exist. Decide between Apple's standard licence and your own terms (AI answers, actions on your behalf) | Owner, with a lawyer |
| D6 | Legal read | **Open** | No legal review is recorded (`PRIVACY_GDPR_AI_ACT.md`, `RELEASE_GATES.md` gate 5). Covers the AI disclosure (EU AI Act Article 50) and the voice provider's data processing agreement | Owner |
| D7 | Paywall decision | **Open** | Free beta. At 1.0, decide paid or free from the beta's measured cost per minute and conversion (pricing v3). Only then StoreKit and the Small Business Program | Owner |
| D8 | Brand sign-off | **Open** | ADR-010 is open: colours, wordmark and character are candidates | Owner |
| D9 | Named sign-offs | **Open** | `RELEASE_GATES.md` needs a name and date per gate. `OWNER_REVIEW_CHECKLIST.md` has 0 of 9 ticked | Owner |
| D10 | Universal links (optional for 1.0) | **Open** | The app uses the `doddy://` scheme only; no associated-domains entitlement | Agent |

## Not needed for v1, but has a date

These matter only if cut features come back (`V1_SCOPE.md` §4).

| Item | Date or state | Evidence |
|---|---|---|
| The messaging server's free Postgres expires | **2026-11-10** | Render database `doddy-messaging-db`, behind `doddy-messaging` (accounts, push, texts, calls, memory on calls, news). `/healthz` answers 200 today. No real call, text or push has run on it, so there should be no user data to save; check before letting it lapse |
| `backend/` loses its data on every restart | Render free tier | Its SQLite file is on a disk that resets (`DEPLOY_RENDER.md`) |
| The typed-question gateway has no settings | Every call fails | `doddy-gateway.vercel.app` answers 402. The 12 Oct deployment on team `doddyyyy` has no environment variables (Vercel settings, read 18 Oct) |
| Picovoice licence | **Closed 20 Oct 2026**: Picovoice and Hey Doddy were removed (ADR-549) | none needed |
| Google OAuth verification, Composio terms, App Attest | Open | ADR-099, ADR-143; `docs/integrations/SECURITY_AND_PERMISSIONS.md` |
| iCloud container and Production schema for shared lists | Open | ADR-307 |

## Closed since 11 Oct

- **PRs merged:**
  - #36, #37 and #38 (11 Oct);
  - the first-use PRs #43, #46, #51 and #76, then #53 and #56–58 (13 Oct);
  - #44 and #61, through #79 (13 Oct).
  
  #67 was closed without merging. Together these were the open blockers in §5 of the 11 Oct doc.
- **CI:** compiled every iOS and Watch target and passed the unit and 26 UI tests on the simulator from `c8aff7a` to `44f6934` (13–14 Oct). It is blocked again now (A1).
- **Voice, app side:** `754e5d6` removed the public agent ID, the access code and the editable token server address from the app. The agent side is still open (C4).
- **Security review:** the 11 Oct critical and high findings for the iPhone app, DoddyCore and the app tests are fixed and compiled in CI (#38 and later).
- **ElevenLabs limits:** the live agent now has a daily limit (10) and concurrency 2. That's a start, not a beta setting (C4).
