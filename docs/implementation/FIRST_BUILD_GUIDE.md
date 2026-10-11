# First real build: guide (2026-10-10)
Owner: "do all of them" (item 1). This is the step that turns "written and checked on Linux" into "built". Until someone does it, **no app, widget or watch code has been compiled with Xcode**. Treat every iOS claim in the status docs as unverified.

There are two ways. Either is enough for a first build; both end with `scripts/ci.sh` printing `RESULT: PASS`.

## Way A: get GitHub's hosted runners going
The workflow `.github/workflows/ios.yml` already does the whole build. It has two jobs:
- `ci`: macOS, XcodeGen, then `xcodebuild test`;
- `core`: Linux checks.

**What happens now:** every run since the workflow was added ends within 2–6 seconds. Both jobs, including the cheap Linux one, finish without running a single step. On run 70 (2026-10-10, `core` 2 s, `ci` 6 s), no log was written. That is GitHub refusing to start jobs for the account, not a failure in the code. The usual causes are:
1. **Billing:** "The job was not started because recent account payments have failed or your spending limit needs to be increased."
   - Fix: GitHub → Settings → Billing and plans → Payment information. Then Spending limits / Budgets → Actions: set a budget above $0, or remove the $0 stop.
   - macOS minutes are billed at 10× Linux minutes on private repositories. A full `ci` run is roughly 20–40 macOS minutes.
2. **Actions turned off** for the account or the repository: repository → Settings → Actions → General → "Allow all actions".
3. **A private repository on a plan with no Actions minutes left** for the month.

**How to see which one:** open a failed run on the Actions tab (for example, run 70). The red banner at the top of the run, or the job's annotation, gives the exact reason. The API used from this session doesn't show the annotation text.

**After fixing:** on the pull request, use "Re-run all jobs", or run the workflow by hand (Actions → iOS build and tests → Run workflow). Then:
- the `xcode-test-results` artifact holds the `.xcresult`;
- the `core` job should pass at once, as `scripts/ci.sh --core-only` does here.

Cost note: ADR-123 approved a hosted macOS build. Its cost is the owner's call; nothing in this repository changes billing.

## Way B: a Mac with Xcode
Needs macOS 14+ and Xcode 16+ (iOS 17 and watchOS 10 SDKs). The iOS Simulator is enough for the first build; a device is needed later for the microphone, widgets, the watch, Back Tap and the Dynamic Island.

```sh
git clone https://github.com/Bienos/doddy.2 && cd doddy.2
git checkout claude/hopeful-fermat-1a63x0
brew install xcodegen node python
xcodebuild -version            # record this
make project                   # xcodegen generate --spec project.yml -> Doddy.xcodeproj
scripts/ci.sh                  # everything, including xcodebuild test on the first iPhone simulator
```
- To pick the simulator: `DODDY_DESTINATION="platform=iOS Simulator,name=iPhone 16" scripts/ci.sh`.
- To build only (faster first signal): `xcodebuild build -project Doddy.xcodeproj -scheme Doddy -destination "generic/platform=iOS Simulator"`.
- **The watch app** is a dependency of the iPhone app, so the build above compiles it too. On its own: `xcodebuild build -project Doddy.xcodeproj -target DoddyWatch -sdk watchsimulator`.
- **Signing for a device:** no team is committed. In Xcode, choose your team for Doddy, DoddyWidgets and DoddyWatch.
  - Widgets with content and the watch's companion pairing need the bundle ids to line up: `<app>`, `<app>.widgets`, `<app>.watchkitapp`.
  - The App Group is opt-in (see the comment at the top of `project.yml`).
  - Push is opt-in too.

## What to do with the result
1. **It builds:** tick §1 of `docs/implementation/MAC_VERIFICATION_CHECKLIST_2026-10-10.md`. Record the Xcode version and simulator, then go on to its device sections.
2. **It doesn't build:** copy the first errors (not the whole log) into a message. Most fixes are expected to be one line. The places most likely to need one, from this round's review, are listed below and in §1 of the checklist.
3. **Never** mark a status doc "built" or "tested" from this guide alone. Only from an actual `RESULT: PASS`, or a run of the specific test.

## Compile review of this round's Swift (no compiler available)
The new UI files were reviewed by reading them against the iOS 17 / watchOS 10 SDK APIs and the DoddyCore signatures. Every file passes `swiftc -parse`. The non-UI files are type-checked by `scripts/typecheck_app_logic.sh` (13 files). What the review found and fixed is in "Review fixes" below. It reduces the risk of a failed first build; it does not remove it.

### Review fixes (2026-10-11)
Two read-throughs found no certain compile errors. They checked:
- every `PendingAction` and `VoiceToolRequest` switch for exhaustiveness;
- every DoddyCore symbol and its access level;
- the EventKit and App Intents requirements;
- all 280 `NSLocalizedString` call sites.
Small Swift 6 stand-ins of the risky patterns type-check on Linux. Fixed after the review:
- `DoddyWatch/WatchLink.swift`: the `sendMessageData` reply and error handlers are now `@Sendable`. As written, they were main-actor closures that WatchConnectivity calls on its own queue, a likely crash on the first reply.
- `VoiceMemoTranscriber.swift`: the recognizer and its task are kept alive until the answer comes, with a 120-second limit. Before, a freed recognizer could leave "Writing it out…" on screen for good.
- `DeviceConnections.swift`: `.map { Self.summary($0) }` instead of passing the main-actor method itself, which some Swift 6.0 compilers reject.
- `project.yml`: `INFOPLIST_KEY_WKApplication: YES` for the single-target watch app.
- Smaller fixes:
  - recorder error messages now go through the Polish catalog;
  - oversized import files are flagged without allocating their size;
  - the speech languages are worked out once;
  - the watch's reminder list no longer risks duplicate ids.
- Left as is, but watch it in the first build: `OnDeviceEmbedder.swift` passes a fresh `NLContextualEmbedding` to `requestAssets()` from inside its actor. Swift 6.2 accepts this; Swift 6.0 may call it a data-race risk. The fix, if needed, is a `nonisolated` helper that creates and loads the model and returns it as `sending`.

### Most likely to still need a fix in Xcode
- `DoddyWatch/*`, `Features/Watch/PhoneWatchLink.swift`: `WCSessionDelegate` conformance from a `@MainActor` class with `nonisolated` methods under Swift 6; XcodeGen embedding the watch app.
- `Features/VoiceMemos/VoiceMemoTranscriber.swift`: Speech's `recognitionTask` callback and Sendable checking.
- `Features/VoiceMemos/VoiceMemoAudio.swift`: `AVAudioApplication.requestRecordPermission()` (iOS 17) and the main-actor polling tasks.
- `Features/Meaning/OnDeviceEmbedder.swift`: `NLContextualEmbedding` asset and result APIs.
- `Intents/ListIntents.swift`: the `AppEntity` / `EntityStringQuery` requirements and the `\(\.$list)` phrases.
- `Features/Import/NoteImportViews.swift`: `fileImporter(allowsMultipleSelection:)` and the tuple-array `@State`.
- The generated catalogs (`InfoPlist.xcstrings`, `AppShortcuts.xcstrings`, and the widget and watch `Localizable.xcstrings`): whether Xcode and XcodeGen pick them up as written.
