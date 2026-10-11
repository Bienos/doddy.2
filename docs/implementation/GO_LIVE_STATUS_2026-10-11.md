# What stands between Doddy and going live — 11 October 2026 (ADR-336)

A read-only survey of the default branch at `3ec1155` (PR #52), the docs, `DECISIONS.md`, `project.yml`,
`Config/`, CI and the open branches. Uncertain points are marked. `README.md` and
`docs/00_START_HERE/DECISIONS_AND_STATUS.md` are from 2026-10-08 and out of date; `DECISIONS.md` and the
round reports are current.

## 1. Blockers for TestFlight
**Build and verification**
- The app hasn't been compiled since an early baseline (`NATIVE_BASELINE_REPORT.md`, 2026-10-10, which
  already had one failing island UI test). Since then everything was checked on Linux only; about 131 of
  324 ADR rows say not compiled / NOT RUN. App, widgets, share extension, watch app and watch widgets have
  never been built together (`FIRST_BUILD_GUIDE.md`).
- Hosted CI has never run a step: GitHub refuses to start jobs ("recent account payments have failed or
  your spending limit needs to be increased"), the Linux `core` job included. Fix in the account's billing.
- Watch app icon: added in ADR-336 (the iPhone's candidate icon). The icon itself is still a candidate (below).
- `PrivacyInfo.xcprivacy` exists only in the main app (ADR-118); Apple's upload checks never ran on it.

**Signing and accounts**
- `DEVELOPMENT_TEAM` is empty; no signed build is recorded.
- Bundle ID is the dev placeholder `com.bienos.doddy2.dev`, version 0.0.1 (ADR-023). Decide before the first
  App Store Connect record: changing it later means a new app record.
- The App Group (app, widgets, share extension, watch) has never been signed or provisioned. iCloud and
  push are off.

**Legal and privacy**
- No privacy policy exists. Needed for App Store Connect; very likely for external TestFlight review
  (uncertain). Also waited on by ADR-163, ADR-245 and `SECURITY_AND_PERMISSIONS.md` §3.
- No legal review (`PRIVACY_GDPR_AI_ACT.md`, Gate 5 in `RELEASE_GATES.md`); ADR-113's review pending.
- The ElevenLabs dev agent records voice with no retention limit (ADR-057: owner's phone only).

**Live services** (block as soon as anyone but the owner gets a build)
- Voice agent is public with authentication off (ADR-034: "must change before TestFlight"). The token
  server is deployed with one owner code; a real token through the app isn't verified.
- No ElevenLabs spending limits (ADR-068).

## 2. Further blockers for the App Store
- App icon: a candidate from the v1.3 art (ADR-050); CLAUDE.md now says new art comes only from the
  owner's pack, so the icon needs an owner decision. The watch uses the same icon.
- Store listing, screenshots, privacy labels (ADR-118), App Attest (ADR-143), real sign-in before live mode
  (ADR-077, ADR-147), own Google OAuth client and verification (ADR-099), licences (ElevenLabs Library
  voices ADR-038/122, Picovoice commercial plan, Composio terms).
- App Review risks not assessed: always-on "Hey Doddy" listening, background audio, a `LiveActivityIntent`
  as a widget action, developer-only fields in Settings (token server, gateway, Picovoice key, test voice).
- Services on free tiers (Render; free Postgres expires 2026-11-10); the OpenAI gateway isn't deployed
  (ADR-109, ADR-124, ADR-125); CloudKit schema to Production if shared lists ship (ADR-307).
- Threat model rerun, an independent security review of `backend/`, a universal link instead of
  `doddy-dev://`, a Polish catalog for the watch app.

## 3. Owner decisions still open
Identity (bundle ID, team, icon: ADR-023, ADR-050; committing `.xcodeproj`: ADR-013); brand (ADR-071,
ADR-056, ADR-061); early defaults (ADR-016, ADR-017, ADR-043, ADR-091); data and privacy (ADR-032, ADR-088,
ADR-118, ADR-149, ADR-158); voice and AI (ADR-108, ADR-111, ADR-077, ADR-099, ADR-068, ADR-082, ADR-124,
ADR-125, ADR-265); owner-only actions (ADR-309 shortcut link, ADR-317 CarPlay, ADR-145 Messages for
Business, shared lists' iCloud container, ADR-104, ADR-138 blog posts). `OWNER_REVIEW_CHECKLIST.md` has no
boxes ticked; `RELEASE_GATES.md` needs named sign-offs. From this session: weather (umbrella pose) and app
icon choices.

## 4. Built but never verified on a device
All of `MAC_VERIFICATION_CHECKLIST_2026-10-10.md` (its result log is empty): §1 build to §17, plus 4f–4l for
Doddy's art. Also round 5 (Face ID and private notes, share extension, Focus filter, memo to-dos, parking
widget, Gmail reply and Notion with real accounts) and AlarmKit alarms. One known open defect: Doddy stops
talking while Instagram is open (ADR-207). The live ElevenLabs agent has tools whose app support is only on
unmerged `affectionate-edison` (`undo_last`, `upcoming_birthdays`, `calculate`, `convert_units`).

## 5. Unmerged branches (27 on 11 October)
Open PRs: #36 `affectionate-edison` (undo; the live agent relies on it), #37 `zealous-lamport` (Swift review
fixes), #38 `zealous-lamport-xcode` (draft, not compiled), #43/#46/#48/#51 `admiring-curie-*` (first use:
quick start, onboarding fixes, Home's first visit, short intro; ADR-324 to 327), #44 `peaceful-hopper`
(action status, voice recovery, Stop listening). No PR: `hopeful-fermat` (ADR-330 to 339 features),
`lucid-johnson` (consent card), `sleepy-bell`, `sleepy-gates`. ADR numbers collide between some of them
(324, 330, 335). Fifteen old branches, 450+ commits behind, look safe to close once the owner confirms.

## 6. Suggested next five steps
1. Settle the branches: #36, #37, #38 first; then the first-use PRs, #44 and `hopeful-fermat`; renumber
   colliding ADRs; close the old ones.
2. The first real build: fix CI billing or build on a Mac until `scripts/ci.sh` passes; fix what breaks.
3. Owner identity: production bundle ID and team, an app icon from the pack, a privacy policy page.
4. Lock voice down for testers: a real token through the app, agent authentication on, ElevenLabs limits and
   retention, developer-only Settings fields hidden.
5. Internal TestFlight on the owner's team; run the Mac checklist on an iPhone and record results. Then
   external TestFlight and the App Store.
