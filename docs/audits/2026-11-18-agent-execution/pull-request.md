# Authorize scoped requests, ground call reports and persist errand progress

## What changes for the user

Exact recent research instructions and single known inquiry-call requests can use the instruction as their scoped authorization. Call results gain source-checked structured reports, while errands retain real progress/history; native report/Markdown export and progress view wiring are included but not compiled here.

The nine root audit/design/evidence documents distinguish existing capabilities, tested changes and missing integrations. This branch makes no production or live-agent change. There are no native screenshots because Xcode/Simulator is unavailable.

## Area

- [x] voice
- [ ] messages
- [x] home / screens
- [ ] island / widgets / controls
- [x] servers
- [ ] CI / tooling
- [ ] docs only

## Risk

- [x] Sensitive paths: `voice-agent/instructions.md` and `voice-agent/tools.json` align repository wording with the new typed exception and default no SMS; neither is synced live. `server/messaging/migrations/042_errand_progress.sql` adds nullable metadata to the existing errand row. `docs/trust/config/doddy_rules.yaml` records the conditional scope as policy metadata, retaining conservative baseline tool values. These changes need the normal sensitive-path review/label on an actual PR.
- [x] Needs server/app rollout: migration 042 first, then compatible messaging/backend, then validated native build, then a separately instructed exact live-agent diff. Merging alone would ship the repository/server code through configured automatic production builds; do not merge before required native checks and rollout review.
- [ ] Behind a flag. Existing connection/pause/server gates remain; the new exception is narrowly conditional rather than a global autonomy switch.

`VoiceSessionController.swift` changes because authorization must use the app's user transcript and live structured lookup results, then preserve the compiled server payload and conversation attempt before dispatch. Open-PR collision inspection was attempted; GitHub API returned `Forbidden` in this environment, so repeat that read before integration.

## Evidence

- PASS: full backend (1,100 passed, one skipped); messaging (1,325 passed, no skips); static checks (56 steps); Node executed steps including 190 web unit tests/build. Optional voice Redis tests skipped: 40.
- PASS: clean full Core rerun (final totals in `DODDY_AGENT_TEST_RESULTS.md`); separate Linux app-logic/model/store/Island checks. The original package compile was invalidated by editing a source while it built; its clean replacement is recorded explicitly.
- Browser with system Chromium: 16 passed, four skipped, two failures at the existing `DEMO deck` text assertion against a PPTX download. No deck code/test was weakened.
- Native files pass Swift syntax parsing only. Native iOS/controller/SwiftUI/ActivityKit is **not compiled**; no simulator/device, carrier calls, live-agent tests or historical extraction study.
- Device acceptance: direct request/fallback/pause/correction/account paths, report reader/file picker, persistence after relaunch, notifications, VoiceOver/Dynamic Type. No new server-driven ActivityKit or general workflow scheduler is implemented.

## Decisions and rules

`docs/decisions/2026-11-18-scoped-requested-work.md`; constitution evidence table in `DODDY_IMPLEMENTATION_SUMMARY.md` covers DOD-01/02/07/08/09/11 and UX-02/03/04. A model never supplies authority; bookings/orders/payments retain their exact cards; unknown effects are not automatically retried. Report grounding is source attribution, not a guarantee of transcript truth/completeness. No dependency, service, secret or new financial obligation was introduced.
