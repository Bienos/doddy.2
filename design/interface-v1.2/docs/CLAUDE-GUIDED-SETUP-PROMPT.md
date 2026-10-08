# Claude Code prompt: first-first guided setup

This is an implementation handoff, not evidence of implemented native functionality. Use alongside the original DODDY V2 foundation package. User-added brand specifications override proposed visual treatments. Do not use the old repository as a write target.

## Master prompt — paste into Claude Code after safe bootstrap

Implement DODDY V2's optional first-first setup in the NEW iPhone SwiftUI repository, followed by the existing reviewed introduction and personalized Home. Before editing, print the absolute repository root and remote, verify it is the intended new repository, inspect its AGENTS.md and native app/test targets, and verify the foreground Open Doddy App Intent already in the foundation. Stop if the write target is Bienos/AI-AGENT-DODDY or synced reference sources. Never change that old repository, deploy, migrate old data or silently enable permissions.

Read this design bundle's README, GUIDED-BACK-TAP-AND-VOICE-SETUP.md, ONBOARDING-AND-PERSONAL-HOME.md, DESIGN-SYSTEM.md, ASSET-MAP.md and the source register. Treat screenshots as design studies, never functional system evidence. Verify current Apple documentation and API availability against the actual Xcode SDK and minimum deployment target. Do not invent missing brand assets or assume HTML SVGs can be imported directly into SwiftUI.

Deliver these phases in order. Build/test each phase before proceeding. Keep real audio, scripted demos and device results distinctly labeled. Work autonomously on reversible local implementation; report missing provider/device configuration precisely without requesting secrets in chat. Never claim background voice or physical Back Tap works based on a simulator or timer.

The end-to-end product flow is: Two taps. A little help → voice or step-card guide → create/save/test a personal Open Doddy shortcut → user navigates Settings → Accessibility → Touch → Back Tap → Double Tap → Shortcuts → Open Doddy → invocation receipt plus user confirmation → end setup session → first hello → optional preference conversation → review/edit/remove → explicit save → personal Home. Deferral, denied mic, unavailable activity and non-Island devices must leave the app usable.

## Phase 1 — setup model and written guide

Implement injected SetupCoordinator with a versioned/localizable step map and explicit events. Store only task state, not utterances or private profile details. Use `notStarted`, `guiding`, `deferred`, `userReportedTestPassed` markers; no `systemAssignmentVerified` state. Persist the walkthrough version/last reported page and optional completed/deferred marker. An unfinished resumed guide must not assume the microphone is active.

Screens: first setup, guide choice, shortcut preparation, reported Settings step, test, result, fallback. Respect Dynamic Type, VoiceOver, Reduce Motion, small screens, light/dark and approved brand assets. Show precise manual Settings steps. The public app-settings URL must not masquerade as a Back Tap deep link. Explain built-in Open App → Doddy if the custom intent is unavailable. Handle an existing Double Tap action without overwriting it. Use the user's reported page; ask when unclear. No cross-app screen observation is included.

Gate: build and unit-test step transitions, repeat/previous/deferral, unknown reports, missing shortcut, no false completion, resume with mic off, and profile separation. Written walkthrough must work before audio exists.

## Phase 2 — foreground invocation and real tap-test receipts

Expose a discoverable foreground Open Doddy App Intent/shortcut that routes to the right session/guide. Verify personal shortcut creation in Shortcuts, naming, run once and appearance in Back Tap's Shortcuts list on target iOS. Do not assume an App Shortcut is automatically a selectable personal shortcut.

During a test use an active test window, ID/nonce and invocation receipt timestamp. Associate a receipt with that test, reject stale/duplicate completion and ask whether the user actually double-tapped. Do not infer the trigger from ordinary foreground activation or a generic intent. Duplicate invocations must focus the existing guide instead of creating duplicate sessions. A system Open App fallback may not carry the custom receipt payload: treat resume plus self-report as weaker evidence, or guide creation of the custom intent before claiming an intent-tested result. Do not manufacture a receipt for this fallback.

Gate: unit-test expired/stale/duplicate/wrong-test/other-entrypoint cases. On a physical phone verify shortcut selection and Double Tap return. If no phone is available, preserve runnable instructions and mark physical verification pending.

## Phase 3 — actual foreground voice and exact guidance

Implement a single VoiceSessionCoordinator with injected speech/provider adapters, cancellable handles and session/turn IDs. Request permission only after explicit start. Configure the real input/output audio session and derive listening/speaking state from actual capture/playback. Verify all required permission descriptions with the chosen speech stack; do not use SDK secrets in the app. Use a secure server gateway if remote speech/AI is selected, with content-free logging and no saved setup transcript by default. Disclose that live voice goes to the chosen provider when applicable.

Feed reported location to the deterministic step map. Optional AI can understand/paraphrase the report but cannot invent settings labels, auto-assignment success or visual access. Answer one relevant instruction at a time. Ask which page when uncertain. Support repeat, slower, previous, pause, stop and barge-in. Stop/cancel must invalidate late replies and release the actual microphone.

Gate: foreground real capture and replies; permission denial; provider failure; timeout; stale-turn rejection; interruption; route change; pause/resume/stop. Scripted browser checks are not substitutes.

## Phase 4 — background voice and Live Activity controls

Implement the supported active-session background audio configuration only after Phase 3 works. Add ActivityKit/WidgetKit extension with compact, minimal, expanded and Lock Screen presentations, showing concise session truth/current setup step and controls. Dynamic Island is the display; the audio engine remains in the app. The system decides expansion; do not promise a pinned chat overlay above Settings.

Availability-gate recording-related App Intents. If using AudioRecordingIntent, satisfy Apple's requirement for an active Live Activity while recording; activity creation failure/end must stop or safely fall back rather than advertise a working recording path. Map pause/stop/open intents to the same coordinator. Use an appropriate minimal app-group/control bridge if required; never share secrets or raw transcripts through activity content. Avoid silent audio keep-alive. Starting/resuming a session requires explicit user intent. Open returns to the current guide without duplicating capture.

Gate: actual phone test while switching to Shortcuts and Settings, asking “I'm in Touch, what next?” and hearing the correct answer. Test lock screen, activity disabled/ended, no Island, app kill, call interruption, audio route loss, network loss, repeated shortcut entry and controls from system surfaces. Verify capture stops and visible status no longer claims listening. Test Activity region fitting with large text and VoiceOver. Keep simulator-only and device evidence separate.

## Phase 5 — intro transition and acceptance report

End the setup session, then enter the existing introduction. Continuing the conversation starts a new explicitly requested session; never carry setup utterances into profile storage. Preserve optional questions, explicit review/edit/remove before saving, usable Home without profile and truthful actual activity. Allow revisiting setup from Settings without discarding profile/memories.

Deliver code, test results, native build evidence, actual device matrix, source/API availability notes and remaining gaps. Claim completion only for observed outcomes. No deployment, old-repository write or old-data migration.

## Acceptance checklist

- First-first setup precedes introduction and can be deferred/revisited.
- Correct personal shortcut/manual Back Tap path; no private settings URL or auto-assignment claim.
- Receipt and physical-gesture self-report distinguish test evidence; fallback has no invented receipt.
- Explicit voice start, pause/stop/open, no stale listening status or duplicate capture.
- Real conversation continues through Settings on the tested supported phone when the approved session is active.
- Unsupported/denied/interrupted cases remain usable and truthful.
- Reviewed personalization remains separate from transient setup speech.
- Approved assets/tokens, native accessibility and physical device evidence are reported.
