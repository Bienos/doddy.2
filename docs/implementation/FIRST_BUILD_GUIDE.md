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
The new UI files were reviewed by reading them against the iOS 17 / watchOS 10 SDK APIs and the DoddyCore signatures. Every file passes `swiftc -parse`. The non-UI files are type-checked by `scripts/typecheck_app_logic.sh` (14 files; only the non-AlarmKit part of `AlarmScheduler.swift`). What the review found and fixed is in "Review fixes" below. It reduces the risk of a failed first build; it does not remove it.

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

### Next round (2026-10-11, ADR-255 to ADR-263): most likely to need a fix
Nothing from this round has been compiled with Xcode either. In order of risk:
- `Features/Sharing/*` (ADR-263):
  - Swift 6 Sendable checks on `CKRecord` and `CKShare.Metadata` reaching the main-actor controller;
  - the result tuple of `recordZoneChanges(inZoneWith:since:)`;
  - `UICloudSharingController` inside a SwiftUI sheet;
  - `ShareAcceptSceneDelegate` set from `AppDelegate.application(_:configurationForConnecting:options:)` in a SwiftUI app.
- `Features/Alarms/AlarmScheduler.swift` (ADR-260): every AlarmKit call. It needs Xcode 26 to compile at all; on Xcode 16 only the `#if canImport(AlarmKit)` fallback builds.
- `DoddyWatchWidgets` (ADR-262): XcodeGen embedding a watchOS app extension in the single-target watch app, and `.widgetLabel` on the corner complication.
- `Features/EveningWrapUp/EveningWrapUpViews.swift` (ADR-261) and the delete card (ADR-259): ordinary SwiftUI and EventKit (`remove(_:span:)`, `remove(_:commit:)`), lower risk.

### Round 3 (2026-10-11, ADR-280 to ADR-289): most likely to need a fix
**First build: still BLOCKED.** This session has no Xcode, and GitHub Actions doesn't start jobs for the account (billing; PR #25's checks ended within seconds). So nothing below has been compiled. Both ways above still apply.

In order of risk:
- **Alarms part 2 (ADR-283):**
  - In `Features/Alarms/AlarmScheduler.swift`:
    - the snooze, built with `AlarmConfiguration(countdownDuration:…)` and a secondary button with behaviour `.countdown`;
    - `typealias DoddyAlarm = AlarmEntry`.
  - In `DoddyWidgets/AlarmLiveActivity.swift`:
    - `ActivityConfiguration(for: AlarmAttributes<DoddyAlarmMetadata>.self)`;
    - the `AlarmPresentationState` mode switch;
    - its registration in the widget bundle under `#if canImport(AlarmKit)` plus `if #available(iOS 26, *)` inside a `WidgetBundleBuilder`. That may need a separate bundle body.
- **Shared-list push (ADR-284):**
  - `CKDatabaseSubscription` with silent `notificationInfo`;
  - `CKNotification(fromRemoteNotificationDictionary:)`;
  - the async `application(_:didReceiveRemoteNotification:) async -> UIBackgroundFetchResult` in a SwiftUI `UIApplicationDelegateAdaptor`.
- **"Added by" (ADR-285):**
  - reading `CKShare.participants` and `userIdentity.nameComponents`;
  - `userRecordID()` on `CKContainer`, under Swift 6 Sendable checks.
- **Birthdays (ADR-288):** `CNContactStore.enumerateContacts(with:usingBlock:)` off the main actor, with `CNContactBirthdayKey`. The `UNCalendarNotificationTrigger` with `repeats: true` is low risk.
- **Watch add-to-list (ADR-287):** `TextField` dictation on watchOS 10 inside `WatchListView`.
- **Photo list (ADR-286):** `PhotosPicker` with `loadTransferable(type: Data.self)`, same as photo notes. Low risk.
- **Repeats and event details (ADR-281, ADR-282):** `EKRecurrenceRule(recurrenceWith:interval:daysOfTheWeek:…end:)` and `EKRecurrenceEnd(end:)`, read back via `recurrenceRules`. Low risk.
- **Bulk card, offline note (ADR-280, ADR-289):** plain SwiftUI and `PendingAction` switches; the risk is a missed `switch` case in `VoiceView` or `VoiceSessionController`.

### Round 4 (2026-10-11, ADR-291 to ADR-298): most likely to need a fix
**First build: still BLOCKED.** There is no Xcode here, and Actions doesn't start jobs. In order of risk:
- **Shared place (ADR-298):**
  - In `ListCloud.setPlace`: CKRecord subscripts with `Double`, `Int` and `Bool` values, and `modifyRecords` with only a deletion.
  - `SharedPlaceRow` uses `@Environment(NoteReminderStore.self)` inside `ListViews`' `List`.
- **Ingredients card (ADR-296):** the new `PendingAction.ingredients` case with six associated values. Every `switch` in `VoiceView` and `VoiceSessionController` must still be exhaustive. Any one that Linux parsing can't check would fail here first.
- **Parking (ADR-292):**
  - `PlaceLocation.currentFix(within:)` returns a tuple from a `TaskGroup` of an optional tuple type.
  - The parking card reuses `contactAction`.
- **Reminder details (ADR-293):**
  - `EKReminder.priority` is an `Int`.
  - `eventStore.calendar(withIdentifier:)` and `calendars(for: .reminder)`.
  - The `case .changeReminder(...) where draft.changesDetails` pattern comes before the general case.
- **Weekly look-back (ADR-297):**
  - the `weekday` in `UNCalendarNotificationTrigger` components;
  - `Calendar.current.weekdaySymbols` in a `Picker`;
  - `ForEach(week.doneByApp.indices, id: \.self)`.
- **Currency (ADR-291):** `ExchangeRateClient` is an `actor` with a nonisolated `URLSession` delegate class. Same pattern as `AppHTTPTransport`, so low risk.
