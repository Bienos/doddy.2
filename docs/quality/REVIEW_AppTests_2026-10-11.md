# Review — `DoddyTests` and `DoddyUITests` (2026-10-11)

Read-only review. No code changed.

**Scope:**
- All six files: 3 app-target unit test files (252 lines) and 3 UI test files (522 lines).
- How they run: `project.yml`, `.github/workflows/ios.yml` and `scripts/ci.sh`.
- Checked against the current app code (`DoddyApp`, `Shared`).

## Tests run

**None of these tests can run here** (Linux, no Xcode). **NOT RUN.** GitHub Actions has assigned no runners today, so they haven't run in CI either.

Static checks done instead:

| Check | Result |
|---|---|
| Every identifier, label and launch flag the UI tests use, searched for in the app sources and string catalogs | All found. Some are built at runtime (`profile.field.\(key)`, `"Hi, \(name)."`, `practice.step…`). Launch flags map to the `PreferenceKey` / argument names the app reads. |
| Every app type and function the unit tests call, searched for with its signature | All exist: `MemoryStore.save(text:category:source:)`, `attachPhoto`, `undoDelete`, `removePhoto(from:)`, `photo(for:)`, `VoiceLiveActivity`, the intents, `.testFixture`. |
| Defaults the UI tests rely on | Listening on open is on by default (`OpeningPreferences.listenOnOpenDefault = true`). There are three tabs (`home, memories, settings`). The Microphone row says "Only while talking". |

## What is solid

- **Fresh state:** the UI tests start with an in-memory store, or a per-run persistent store (`-memoryTestID <UUID>`), and synthetic data only.
- **Real restarts:** the persistence tests terminate and relaunch the app (save → restart → find → correct → restart → delete → restart).
- **Honest assertions:**
  - Ask Doddy is off and sends nothing.
  - Back Tap is never shown as "verified".
  - The practice plan card says "Nothing was done".
  - No fake microphone controls.
  - Pause-all stops reading Calendar and Reminders.
  - Removed introduction answers aren't stored.
- **The unit tests check the right promises:**
  - Unavailable storage never acknowledges a save.
  - A malformed test-store argument never falls back to the personal store.
  - A correction keeps the original.
  - A photo's file follows its note through delete, Undo and remove.
  - The island unit tests skip, rather than pass, when Live Activities are disabled.

## Findings (most severe first)

### High

1. **`DoddyTests/IslandBaselineTests.swift:14`: this test will fail on its first run**
   - **Problem:** It asserts that the encoded `ContentState` has exactly the keys `["status", "isMuted", "savedCount"]`. Since ADR-239, `ContentState` has a non-optional `islandStyle: IslandStyle = .leanIn` (`Shared/VoiceActivity/DoddyVoiceAttributes.swift:40`). The synthesized `encode(to:)` (only `init(from:)` is custom) always writes it, so the keys are `status, isMuted, savedCount, islandStyle`.
   - **Failure scenario:** The first macOS CI run, or a run on a Mac, goes red on a stale expectation. Meanwhile the real question the test guards ("no note text on the lock screen") has no up-to-date check for the newer fields: `moment`, `greeting`.
   - **Fix:**
     - Expect `["status", "isMuted", "savedCount", "islandStyle"]`.
     - Add a case with `moment: .planWaiting(steps: 2)` and `.noteSaved`, asserting that the payload carries only kinds and counts.
     - Add a case with `greeting` showing it holds only the greeting line (it may contain the user's first name, never note text).

### Medium

2. **The app's riskiest code has no tests, and can't be faked**
   - **What has tests:** the app target has 14 unit tests: environment wiring, MemoryStore, and island lifecycle.
   - **What has none:**
     - `VoiceSessionController.swift` (2,535 lines): tool dispatch, confirmation cards, plan steps, write-then-read-back. This is where the iPhone app review found its critical H1/H2 (stale starts leaving a conversation open).
     - `SharedListsController` (critical F1), `MemoryCopySync` (E1) and `ListCloud` (I4).
     - The Watch and widget targets.
   - **Why it can't be faked:** `VoiceSessionController` creates `private let devices = DeviceConnections()` (line 237), so a test can't put in a fake Calendar or Reminders.
   - **What does exist:** `scripts/typecheck_app_logic.sh` type-checks 15 app files on Linux. That catches compile errors, not behaviour.
   - **Failure scenario:** a change that runs a calendar write the user declined, runs it twice, or reports `unknown` as done passes every test in the repo. DoddyCore tests the reply text but not the controller that sends it.
   - **Fix (M-L):**
     - Put a small `DeviceConnecting` protocol in front of `DeviceConnections` (the real class stays the default), and let `VoiceSessionController` take it in its initializer.
     - Then add app-target tests with a fake for:
       - an approved card runs exactly the approved payload once;
       - a declined card runs nothing;
       - a write that throws replies `failed: … Nothing was changed.`;
       - an unreadable alarm list replies `unknown:`;
       - a second start ends the first conversation (H1).
     - Do the same, in a later pass, for the iCloud lists controller.

3. **`DoddyUITests/MemoryBaselineTests.swift:51` (`testNativeIslandOfflineFixtureCanStartMuteAndEnd`): fails instead of skipping without Live Activities**
   - **Problem:** It drives SpringBoard's compact and expanded island, waiting up to 30 s and then 15 s. It has no skip when Live Activities are disabled or SpringBoard doesn't render them, unlike the unit tests' `requireActivities()`.
   - **Failure scenario:** On a CI simulator image where Live Activities are off, or slow to start the widget extension, the job goes red without a product bug. That teaches people to ignore red.
   - **Fix:**
     - Have the island fixture screen show whether `ActivityAuthorizationInfo().areActivitiesEnabled` is true (one label), and `XCTSkip` when it isn't.
     - Keep the 30 s for the cold widget launch.

### Low

4. **`LaunchSmokeTests.swift:231` (`testOpeningEndsByItselfAndIsNotRepeatedOnAQuickReturn`): tied to timing**
   - **Problem:** `waitForNonExistence(timeout: 4)` is "just over the timeline's length".
   - **Failure scenario:** A slow simulator misses it by a frame.
   - **Fix:** Allow the scene's duration plus a generous margin (for example 10 s). The test proves the opening ends by itself, not how long it takes.

5. **The setup that disables default-on features is repeated four times**
   - **Problem:** `LaunchSmokeTests.launch`, `MemoryJourneyTests.launch` and two inline argument lists in `MemoryBaselineTests` each list the switches that stop default-on features from covering the screen: opening, listen on open, Back Tap card, empty agent id.
   - **Failure scenario:** The next default-on feature has to be added in four places, and the island test already omits `-voiceAgentID ""` and `-backTapSetupStatus`.
   - **Fix:** One shared `UITestLaunch.app(...)` helper in `DoddyUITests`.

6. **No UI test runs in Polish**
   - **Problem:** 1,111 of 1,159 strings ship in Polish, which is longer than English, but every UI test runs in English.
   - **Fix:** One smoke test with `-AppleLanguages (pl) -AppleLocale pl_PL`: Home, capture, save and Settings, all reachable and hittable.

## Missing tests (summary)

- **Voice controller** behaviour with a fake connections layer (finding 2).
- **Island payload** for `moment` and `greeting` (finding 1).
- **iCloud shared lists:** a list edited during a sync isn't overwritten (F1). This needs a fake CloudKit layer, the same idea as finding 2.
- **Widget and Watch:** the snapshot written by the app is the one the widget reads.
- **A Polish-locale smoke test** (finding 6).

## Top fixes

| # | Fix | Finding | Effort | Risk |
|---|---|---|---|---|
| 1 | Update the island payload keys; add moment and greeting cases | 1 | S | Low |
| 2 | Skip the SpringBoard island UI test when Live Activities are off | 3 | S | Low |
| 3 | Make the voice controller fakeable; first five controller tests | 2 | M-L | Medium (touches the voice controller; uncompiled here) |
| 4 | Shared UI-test launch helper; generous opening timeout | 4, 5 | S | Low |
| 5 | Polish smoke test | 6 | S | Low |

All of these are app-target Swift that can't be compiled here. They would go on the uncompiled branch (draft PR) and need the macOS CI or a Mac.

## Constitution evidence log

- **DOD-06 (memory claims):**
  - **Tested on a real store:** save, restart, find and delete (`MemoryBaselineTests`, `MemoryJourneyTests`).
  - **Tested in the unit tests:** unavailable storage never acknowledges a save. Not run anywhere today.
- **DOD-07 (approval bound to payload):** no app-target test checks that a confirmed card runs exactly the approved payload (finding 2). DoddyCore tests the plan types only.
- **DOD-08 (unknown is never success):** tested in DoddyCore reply builders, not in the app's controller (finding 2).
- **DOD-11 (privacy):** the island payload test is meant to guard this, but its expectation is stale (finding 1).
- **Claims to limit:** none of these tests have run in this environment or in CI today. Nothing here may be called "tested" until the macOS job runs.
