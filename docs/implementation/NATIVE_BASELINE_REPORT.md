# Doddy.2 native baseline — 10 October 2026

## Implemented

This work is local to `Bienos/doddy.2`, branch `codex/doddy2-native-baseline`, based on
Island revision `1d9b6437b6be288aac293a5fc80da1591fd36948`. It is not a replacement
for, or a change to, `Bienos/AI-AGENT-DODDY`. No commit, push, merge or public release
was performed. The diverged Connections branch was not merged.
The imported README and October 8 status snapshot remain byte-identical historical
documents; their empty-repository/no-Xcode statements are not the current local result.
Use this report for the baseline's executed build evidence.

The existing native SwiftUI app, SQLite memory and widget extension compile and run
on the iPhone 18 Pro / iOS 27 simulator. Existing appearance and artwork are unchanged.
This is native build evidence, not a claim that every supplied design screen is implemented.

Confirmed voice proposals now save with `explicitVoice`, rather than the typed-note
default. The saved original is the user-reviewed proposal text; it is not claimed to be a
verbatim speech transcript. Original text remains intact when a note is corrected.

Debug-only tests can use a dedicated UUID-scoped persistent database. Invalid fixture
arguments fail closed rather than fall back to personal memories. An offline native
ActivityKit fixture labels itself **Test activity / Test muted**; it does not open a
microphone, SDK conversation, provider connection or paid session.

The build-time bundle identifier is configurable. This run used
`com.bienos.doddy2.baseline`, separate from the owner's existing development install.
The normal `com.bienos.doddy2.dev` default is preserved.

## Files changed

- `project.yml`: isolated build identifier and derived widget/test identifiers.
- `AppEnvironment.swift`: dedicated persistent debug-test storage.
- `MemoryStore.swift`, `VoiceSessionController.swift`: explicit capture provenance.
- `RootView.swift`, `NativeIslandBaselineView.swift`, `DoddyVoiceAttributes.swift`:
  clearly labelled debug-only native activity fixture.
- `SettingsView.swift`, `LaunchSmokeTests.swift`: stable Back Tap status identifier
  and bounded scrolling to a lazily rendered Settings row.
- `MemoryStoreTests.swift`, `IslandBaselineTests.swift`, `MemoryBaselineTests.swift`:
  persistence, provenance, failure honesty, Activity lifecycle and native UI coverage.
- `Packages/DoddyCore/Package.resolved`: Xcode's resolved app dependency graph;
  GRDB remains 7.9.0, ElevenLabs 3.3.1, with resolved LiveKit/WebRTC dependencies.
- Implementation plan and this report. Imported reference packs remain unchanged.

## Tests executed

Environment: Xcode 27 (`27A266a`), Swift 6.4, Debug simulator build. No live
voice-service test was run.

| Check | Result |
| --- | --- |
| XcodeGen project generation | PASS |
| Native app + widget build, install and launch | PASS |
| `swift test --package-path Packages/DoddyCore --scratch-path /private/tmp/doddy2-core-tests` | PASS: 49 (40 core, 7 design-token, 2 SQLite) |
| Native `DoddyTests` | PASS: 11, zero failures/skips |
| Save → restart → search → inspect → delete → restart UI flow | PASS with a UUID-scoped synthetic SQLite note |
| Launch / onboarding / privacy / manual Back Tap UI checks | PASS: 4 |
| Actual compact and expanded Island rendering | OBSERVED: native system screenshots, explicitly labelled offline fixture |
| System Island Unmute → app handler UI check | FAIL: fixture remained muted after the system button press |
| System Island End button UI check | NOT REACHED after Unmute assertion failed; direct intent unit test passed |
| Imported pack integrity | PASS: all 259 files unchanged; no font binaries |
| Forbidden-capability guard | PASS |
| `git diff --check` | PASS |
| Physical iPhone, paid voice session, TestFlight/release | NOT RUN |

The first combined test run finished with one failing UI check: the Back Tap status
was below the initial Settings viewport. Its test now scrolls to the actual status row
and passes. The first combined tool request exceeded its 300-second response window,
but the completed Xcode result bundle supplied the full outcome. The subsequent full UI
run passed five of six checks. Strengthening the Island check exposed two test-harness
issues first (wrong accessibility element type and an eight-second cold-extension timeout).
After correcting those, the compact and expanded widgets rendered and Unmute was tapped,
but the fixture stayed **Fixture muted**. That final system-to-app assertion remains red;
the native Island integration is not signed off. The cause is not yet established, and
no speculative production intent workaround was applied.

Across the latest applicable runs: **49 package + 11 native unit + 5 UI tests passed;
1 strengthened Island UI test failed**. This is not an all-green release result.

Native unit coverage includes confirmation-state copy/payload, actual ActivityKit start,
update and immediate end, direct mute/end intent invocation, orphan dismissal, explicit
voice/typed provenance, correction retaining original text, deletion removing recall,
malformed fixture isolation and no false save acknowledgement on unavailable storage.

Initial native result bundle:
`/Users/popcorn/Library/Developer/XcodeBuildMCP/workspaces/g-p-6ac752264c9481919b0862f0903c0b9b-94afa6898ead/result-bundles/test_sim_2026-10-10T01-27-36-182Z_pid71416_236eb7b5.xcresult`.

Final strengthened Island UI result (one failing handoff assertion):
`/Users/popcorn/Library/Developer/XcodeBuildMCP/workspaces/g-p-6ac752264c9481919b0862f0903c0b9b-94afa6898ead/result-bundles/test_sim_2026-10-10T01-43-49-702Z_pid71416_c1dc544c.xcresult`.

Final native app/widget rebuild and normal Home launch: PASS (69.6 seconds), isolated
bundle `com.bienos.doddy2.baseline`, PID 91450. The offline fixture was cleared on relaunch.
Launch used in-memory storage and an empty voice-agent override; no provider was contacted.
Build log:
`/Users/popcorn/Library/Developer/XcodeBuildMCP/workspaces/g-p-6ac752264c9481919b0862f0903c0b9b-94afa6898ead/logs/build_run_sim_2026-10-10T01-47-52-742Z_pid71416_5f842436.log`.

## Screenshots

- [Native Home, existing appearance](/Users/popcorn/.codex/.chatgpt-projects/g-p-6ac752264c9481919b0862f0903c0b9b/outputs/Doddy2-Native-Baseline/native-home.jpg)
- [Real note found after restart](/Users/popcorn/.codex/.chatgpt-projects/g-p-6ac752264c9481919b0862f0903c0b9b/outputs/Doddy2-Native-Baseline/native-recall-after-restart.png)
- [Actual expanded Island, offline test fixture](/Users/popcorn/.codex/.chatgpt-projects/g-p-6ac752264c9481919b0862f0903c0b9b/outputs/Doddy2-Native-Baseline/native-island-offline-fixture.png)

The Island screenshot proves rendering, not working Unmute or a real voice conversation.
Multiple unrelated Doddy icons already exist on this simulator; only the isolated baseline
bundle was used for this run.

## Known risks

- The Island's system Unmute handoff fails in the offline simulator fixture. Resolve this
  before signing off either system button; the End-button UI assertion was not reached.
  Apple documents that `LiveActivityIntent` executes in the app process, and the compiled
  app/extension metadata contains the intent. These facts do not prove actual delivery here.
  See [Apple's interactivity documentation](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities).
- An ActivityKit API lifecycle or directly invoked intent test does not prove a physical
  Island button, audio stream, interruption, Bluetooth route or background microphone.
- Real voice remains the pre-existing ElevenLabs integration. No paid three-minute
  conversation, provider retention/authentication audit or physical-iPhone test was run.
- Existing voice startup cancellation and overlapping proposals need a separate focused
  review; this task does not claim to harden the complete voice session lifecycle.
- Starting voice currently sends saved notes and, when enabled, recent conversations to
  ElevenLabs. A narrower context/consent policy is a separate owner/product decision.
- iPhone file protection, backup behavior, system-driven activity lifetime, manual Back Tap
  setup and release signing remain device/release gates.
- No TestFlight, App Store deployment, production signing or cloud service creation.

## Fix attempt for the red Island handoff (ADR-128, not yet re-run)

Written on Linux without Xcode; nothing below has been compiled or run on a simulator or device.

- **What the failure shows.** After the system Unmute tap the fixture label stayed "Fixture
  muted". That label follows the fixture's `isMuted` `@State`, which the registered
  `toggleMute` handler flips whichever `VoiceLiveActivity` it holds. So the handler in the app
  process most likely never ran. The earlier `@State island` change (commit `9ebd4f8`) keeps
  the fixture's controller stable but cannot explain the label.
- **Likely cause.** `ToggleDoddyMuteIntent` and `EndDoddyConversationIntent` live in `Shared/`,
  which `project.yml` compiles into both `Doddy` and `DoddyWidgets`. The widget extension has
  its own, empty `VoiceActivityActions.shared`, so an intent performed there is a silent no-op.
  Apple's iOS 27 App Intents docs say an intent is performed "using any available target" by
  default, and that `allowedExecutionTargets` restricts it
  ([IntentExecutionTargets](https://developer.apple.com/documentation/appintents/intentexecutiontargets),
  [allowedExecutionTargets](https://developer.apple.com/documentation/appintents/appintent/allowedexecutiontargets)).
  This run used the iOS 27 simulator. Older guidance says `LiveActivityIntent` runs in the app
  process ([interactivity docs](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities)).
  The two sources disagree, so the cause is inferred, not proven.
- **Change.** Both Live Activity intents, and `TalkToDoddyIntent` for the same reason, declare
  `allowedExecutionTargets` as `.main` on iOS 27 and later. The declaration is behind
  `#if compiler(>=6.4)` so older Xcode versions still build; they keep the old behaviour.

**The Mac re-run must check:**

1. `make project`, then build `Doddy` + `DoddyWidgets` with Xcode 27. A compile error on
   `allowedExecutionTargets` / `IntentExecutionTargets` means the API differs from the docs.
2. `DoddyUITests/MemoryBaselineTests/testNativeIslandOfflineFixtureCanStartMuteAndEnd` on the
   iPhone 18 Pro / iOS 27 simulator. It must pass end to end: system **Unmute** reaches the app
   ("Fixture active"), then system **End** reaches it ("Fixture ended", "0 native activities").
   This is the only proof of the fix. If Unmute still fails, add a log in
   `ToggleDoddyMuteIntent.perform()` that prints `Bundle.main.bundleIdentifier`. That shows
   which process ran the intent, or whether any did.
3. `DoddyTests/IslandBaselineTests`: all four tests still pass. They call `perform()` directly,
   so they do not test routing.
4. On a physical iPhone, later: TalkToDoddy control still opens Doddy and starts a conversation.

## Owner decisions needed / next task

Review this local baseline before publishing or merging. First diagnose and fix the red
system-button handoff test without provider usage. Then use a physical iPhone for the
existing voice/Island path with owner-authorized provider usage: start, confirm a note,
mute/unmute from the system surface, end, interrupt, lock, restart, search and delete.
Keep notes synthetic and record audio/permission receipts separately from screenshots.

For a visual rebuild, show candidate mockups from the supplied canonical Pocket Notebook
and owner-selected brand pack before integrating them. Do not equate the browser prototype
with native implementation or combine the divergent branches wholesale.
