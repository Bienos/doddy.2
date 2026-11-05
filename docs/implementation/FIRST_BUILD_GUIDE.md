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
   - On a private repository a macOS minute costs about 10 times a Linux minute ($0.062 against $0.006). A full `ci` run took a median 52 macOS minutes on 12–14 October (BUILD_AND_TEST.md, ADR-497).
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
make project-iphone            # iPhone/iPad without the watch app -> DoddyiPhone.xcodeproj (ADR-457)
make project-mac               # Mac menu bar app and widget only  -> DoddyMac.xcodeproj
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

### Round 4 (2026-10-11, ADR-300 to ADR-307): most likely to need a fix
**First build: still BLOCKED.** There is no Xcode here, and Actions doesn't start jobs. In order of risk:
- **Shared place (ADR-307):**
  - In `ListCloud.setPlace`: CKRecord subscripts with `Double`, `Int` and `Bool` values, and `modifyRecords` with only a deletion.
  - `SharedPlaceRow` uses `@Environment(NoteReminderStore.self)` inside `ListViews`' `List`.
- **Ingredients card (ADR-305):** the new `PendingAction.ingredients` case with six associated values. Every `switch` in `VoiceView` and `VoiceSessionController` must still be exhaustive. Any one that Linux parsing can't check would fail here first.
- **Parking (ADR-301):**
  - `PlaceLocation.currentFix(within:)` returns a tuple from a `TaskGroup` of an optional tuple type.
  - The parking card reuses `contactAction`.
- **Reminder details (ADR-302):**
  - `EKReminder.priority` is an `Int`.
  - `eventStore.calendar(withIdentifier:)` and `calendars(for: .reminder)`.
  - The `case .changeReminder(...) where draft.changesDetails` pattern comes before the general case.
- **Weekly look-back (ADR-306):**
  - the `weekday` in `UNCalendarNotificationTrigger` components;
  - `Calendar.current.weekdaySymbols` in a `Picker`;
  - `ForEach(week.doneByApp.indices, id: \.self)`.
- **Currency (ADR-300):** `ExchangeRateClient` is an `actor` with a nonisolated `URLSession` delegate class. Same pattern as `AppHTTPTransport`, so low risk.

### Round 5 (2026-10-11, ADR-310 to ADR-312, ADR-314 to ADR-318): most likely to need a fix
**First build: still BLOCKED** (no Xcode here; Actions doesn't start jobs). In order of risk:
- **Share extension (ADR-311):** a new target, so XcodeGen must embed it.
  - `ShareModel.extract(_ items: sending [NSExtensionItem])` is `nonisolated` and is called from `Task.detached`, because item providers aren't Sendable. Swift 6 region checks may still object; the fallback is to load the strings inside `viewDidLoad` with completion handlers.
  - `NSItemProvider.loadItem(forTypeIdentifier:)` with `async` and `as? URL` / `as? String`.
  - `Config/DoddyShare-Info.plist`'s `NSExtensionPrincipalClass` is `$(PRODUCT_MODULE_NAME).ShareViewController`.
  - The App Group is now on by default (owner, 2026-10-11). Signing needs the team chosen for every target, and the group registered (automatic signing does it). If a simulator `xcodebuild test` without a team refuses the entitlements, run it with the four `DODDY_*_ENTITLEMENTS` set to `""`.
- **Focus filter (ADR-312):**
  - `SetFocusFilterIntent` with `static var description: IntentDescription?`;
  - `@Parameter(default: false)` on a `Bool`;
  - an optional `DoddyListEntity` parameter.
  - `FocusFilterState` is `@MainActor`, and `perform()` awaits it.
- **App lock (ADR-310):**
  - `LAContext.evaluatePolicy` async;
  - the `.overlay` in `RootView`;
  - `@Observable` `AppLock.shared` read inside `MemoryDetailView`, `FindMemoriesView` and `MemoriesView`.
- **Memo to-dos (ADR-318):**
  - `MemoTodosCard` uses `Picker` with `Optional(list.id)` tags and `store.createList(name:items:source:)`;
  - `String(format:)` with `%lld` and an `Int`.
- **Parking widget (ADR-315):**
  - `RootView` gains `@Environment(\.openURL)`, used in `onOpenURL` for `doddy://parking`;
  - the widget's `Text(_, format: .dateTime.weekday(.abbreviated).hour().minute())`.
- **Reminder rename/repeat (ADR-314):**
  - `EKReminder.recurrenceRules` set and cleared;
  - `EKEvent.notes` replaced, with a stale check before the save.


### Round 6 (2026-10-11, ADR-330, ADR-332 to ADR-339): most likely to need a fix
**First build: still BLOCKED** (no Xcode here; Actions doesn't start jobs). In order of risk:
- **iPad (ADR-337):**
  - `TARGETED_DEVICE_FAMILY "1,2"` on the app, widget and share extension. Check that the Live Activities, AlarmKit and watch parts still build for iPad (they run only where iOS allows them).
  - `UIDevice.current.userInterfaceIdiom` is read in `DeviceSupport` (`@MainActor`).
- **Leave-by (ADR-335):**
  - `MKDirections.calculateETA()` async with `arrivalDate`;
  - `UNCalendarNotificationTrigger(dateMatching:)`;
  - the new `PendingAction.leaveBy` in every `switch` (Linux parsing can't prove they are exhaustive).
- **Spotlight (ADR-330):**
  - `CSSearchableIndex(name:protectionClass:)` and the delete-then-index completion handlers;
  - `onContinueUserActivity(CSSearchableItemActionType)` in `RootView`.
- **Quick actions (ADR-339):** the async `windowScene(_:performActionFor:)` on the existing scene delegate; `connectionOptions.shortcutItem` on cold launch.
- **Memories tags (ADR-333):** `MemoryTagRow` with `ForEach(tags, id: \.tag)` over tuples.
- **List templates (ADR-334):** `.swipeActions` inside a `Form` section in `NewListSheet`.

### Watch, iPad and Mac round (2026-10-11, ADR-430 to ADR-433): most likely to need a fix
**First build: still BLOCKED** (no Xcode here; the hosted jobs end in seconds with no logs, so no runner starts). In order of risk:
- **iPad sidebar (ADR-430), `DoddyApp/App/SidebarLayout.swift`:**
  - `struct SidebarLayout<Detail: View>` with a `@ViewBuilder var detail: Detail` stored property, built with a trailing closure in `RootView.tabContent`;
  - `NavigationSplitView(columnVisibility:)` with `.navigationSplitViewStyle(.balanced)`, and Home's and Memories' own `NavigationStack`s inside the detail column (check for a doubled navigation bar);
  - `List(selection: Binding<SidebarItem?>)` with `.tag(SidebarItem...)` on `Label`s; a `Binding(get:set:)` whose setter writes two `@Binding`s (same pattern as the Settings pickers);
  - `RootView.tabContent` is now `@ViewBuilder` with an `if`/`else`, and `selectedScreen` a `switch` over `AppTab`.
- **The opening (ADR-431):** `OpeningSceneView.stage` converts `OpeningScene.stageWidth(...)` (a `Double`) to `CGFloat`.
- **iPad tests (ADR-432):** `DoddyTests` and `DoddyUITests` now have `TARGETED_DEVICE_FAMILY "1,2"`. `LaunchSmokeTests.testBackTapCardCanBeDeferredAndNeverShowsAsVerified` is now `throws` (for `XCTSkipIf`). Run once on an iPad simulator: `DODDY_DESTINATION='platform=iOS Simulator,name=iPad Air 11-inch (M3)' scripts/ci.sh` (use a name from `xcrun simctl list devices available`).
- **Watch "New note" complication (ADR-434):**
  - `NewNoteComplication` with a nested `Entry` and `Provider` and `.widgetURL(...)` inside `StaticConfiguration`;
  - in `WatchRootView`, `.navigationDestination(isPresented:)` on the `List` and `.onOpenURL` on the `NavigationStack`.
- **Mac menu bar (ADR-435):** build with `xcodebuild -project Doddy.xcodeproj -scheme DoddyMac -destination 'platform=macOS' build`.
  - Likely fixes: the `DoddyPersistence` package product on a macOS target (GRDB builds for macOS); `MenuBarExtra(... systemImage:)` with `.menuBarExtraStyle(.window)`; `@FocusState` set in `.task`; signing with no team (choose "Sign to Run Locally").
- **iPad fixes (ADR-436, ADR-437):**
  - the explicit `UIApplicationSceneManifest` in `Config/Doddy-Info.plist` with generation off (check the app still launches and the share-accept scene delegate still gets links);
  - `confirmationDialog`s now on rows inside `Form` sections and on the list's toolbar `Menu` (SettingsView's body may need splitting if the type-checker times out);
  - `readableColumn()` in `Components.swift`;
  - the strings catalogs now carry `variations.device` entries (`ipad`/`other`) for English and Polish: check Xcode accepts them.
- **Mac icon and widget (ADR-438, ADR-439):**
  - `MenuBarExtra { } label: { }` with `Image(nsImage:)`;
  - the `DoddyMacWidgets` target and its embedding;
  - `$(TeamIdentifierPrefix)` in `Config/DoddyMac-Info.plist`, `Config/DoddyMacWidgets-Info.plist` and the App Group entitlements;
  - `WidgetCenter` in the Mac app;
  - `containerBackground(.background, for: .widget)` on macOS.
- **New note widget and the Mac window (ADR-450, ADR-451):**
  - `NewNoteWidget` in `DoddyWidgets/HomeWidgets.swift`: `Button(intent: NewNoteIntent())`, added to `DoddyHomeWidgets` (seven widgets in that bundle);
  - `Window(..., id:)` next to `MenuBarExtra`, and `openWindow(id:)`;
  - `HSplitView`, and `TextEditor` with `.scrollContentBackground(.hidden)`;
  - `NSApplication.shared.activate()`, which is macOS 14+.
- **Share extension (ADR-311), Swift 6:** `ShareViewController` no longer sends the main-actor `[NSExtensionItem]` to `Task.detached` or a `sending` parameter, which strict concurrency rejects. The items stay on the main actor, and each attachment is read with `NSItemProvider.loadItem(forTypeIdentifier:options:completionHandler:)` inside `withCheckedContinuation`; only a `String` comes back. Behaviour is unchanged: the first web link (never a file's address), else the plain text.
- **Smart Stack, palette, iPadOS 26 (ADR-453 to ADR-455):**
  - `DoddyToolLiveActivity.island(_:)` takes an `ActivityViewContext<DoddyToolAttributes>`;
  - `DoddyToolLiveActivityWithWatch` uses `.supplementalActivityFamilies([.small])` and `@Environment(\.activityFamily)`;
  - the bundle's `if #unavailable(iOS 18.0)`: if `WidgetBundleBuilder` rejects it, use `if #available { … } else { … }` or a nested bundle;
  - `NSPanel` with `NSHostingView`;
  - `if #available(iOS 26.0, *)` inside `DeviceSupport.hasLiveActivities`.
- **Per-platform projects (ADR-457):** `project-iphone.yml` uses XcodeGen `include:` and `dependencies:REPLACE`/`schemes:REPLACE`; `project-mac.yml` stands alone. Generated with XcodeGen 2.44.1 on Linux. Check that Xcode opens all three, and that `DoddyiPhone` builds without the watch app.
