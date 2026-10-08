# Single-agent implementation sequence, now including design

**Rule:** ONE code milestone at a time, one test report, owner review before advancing. The 42 browser screens are **reference evidence**, not a request to implement all states on day one.

## M0: native foundation + visual skeleton (first)

- Verify new repo target and baseline Xcode version; never write old repo.
- Create native SwiftUI project (iPhone, tentative iOS 17+), modular feature boundaries, dependency injection and test target.
- Adapt Pocket Notebook semantic tokens; import selected light/dark PNG imageset assets from `design/ios-ready-asset-catalog/` after rights review.
- Add Home/Memories/Settings static routes, faithful typography hierarchy, safe areas, no fake personal history, no real provider claims.
- Basic First Hello can offer Start/Skip; do not auto save preferences or force Back Tap wizard.
- Build and run actual simulator tests. Stop with evidence and open decisions.

## M1: real local memory and native core flow

- Implement transactional SQLite/GRDB store, migrations, provenance and recall; native capture/receipt, details/edit/delete/export, error states.
- Use `docs/design/SCREEN_TO_IMPLEMENTATION_MAP.md` as visual QA checklist.
- Add optional profile introduction only when product scope reviewed; never invent saved preferences.
- Unit and UI tests; physical iPhone data protection tests where needed; stop.

## M2: real AI and text conversation (approval required)

- Provider selection, gateway, retention/security, cite known memory ID, bounded costs and robust failure UX.
- No client-embedded secrets or public claims until verified.

## M3: actual foreground voice (approval required)

- Language, voice model, streaming and interruption decision; device tests; state-driven character motion.
- **Do not build live Dynamic Island guidance as part of this milestone by default.** Split separate ticket for manual shortcut wizard and ongoing audio background policies.

## M4: verified Reminders actions (approval required)

- Review-first typed tool proposals; date/time clarification, permission, verification and retry safety.

## M5: private beta and decisions

- Real external testers, instrumented privacy-safe metrics, competitor baselines, documented result.

## Separate optional UI build-out

- Animated personality/voice performance, Character-first Home experiments, v1.2 guided Back Tap wizard and ActivityKit, final production brand exports, advanced personalization, translation, richer tool integrations. These are not promised by M0 or M1.
