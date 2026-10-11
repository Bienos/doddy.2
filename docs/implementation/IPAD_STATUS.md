# iPad status (ADR-337, ADR-430 to ADR-432)
Date: 2026-10-11. Owner: "forget iphone and continue" (after `prompts/APPLE_PLATFORMS_WATCH_IPAD_MAC.md` Phase 1 was BLOCKED), then chose "B: Sidebar + detail" for the iPad layout.

**Nothing here has been compiled with Xcode or run on an iPad or simulator.** It was written and checked on Linux only.

## What ships
- **Sidebar on a wide iPad screen (ADR-430).**
  - On regular width the tab bar becomes a `NavigationSplitView` sidebar: Home, Memories, Settings, then "Lists" with the user's lists in Home's order. The chosen screen fills the detail column, still one readable 760 pt column (ADR-337).
  - Both columns show from the start, in portrait too. The system button can hide the sidebar.
  - A list row opens that list on Home, the same route a widget or Spotlight result takes. Choosing Home while a list's row is highlighted goes back to Home itself; otherwise Home keeps its place, as a tab does.
  - Memories and Settings start at their top after switching away and back (the detail column shows one screen at a time). Home's place is kept.
  - iPhones keep the tab bar even in landscape on a large iPhone (also regular width), and keep the 760 pt cap there as before. Compact iPad windows (Slide Over, narrow Split View) keep the tab bar.
- **The opening fits (ADR-431).** On a wide screen the opening's stage is as wide as fits the height, centred, so the floor and Doddy stay on screen in landscape. A phone in portrait is unchanged.
- **iPhone-only parts hidden (ADR-432).** Shopping mode's menu item and Settings › Voice › Dynamic Island style are hidden on iPad (no Live Activities there). Back Tap was already hidden (ADR-337).
- **Tests run as iPad (ADR-432).** `DoddyTests` and `DoddyUITests` now target iPhone and iPad. The Back Tap UI test skips on iPad; `testIPadHasASidebarAndNoBackTap` checks the sidebar and that no Back Tap card or row appears.

## Files
- **Core:** `Packages/DoddyCore/Sources/DoddyCore/SidebarNavigation.swift`; `OpeningScene.swift` (`stageWidth`, `courtBox`).
- **App:**
  - `DoddyApp/App/SidebarLayout.swift` (new) and `RootView.swift` (`tabContent`, `selectedScreen`);
  - `DesignSystem/Components.swift` (`DeviceSupport.hasLiveActivities`, `hasSidebar`);
  - `Features/Opening/OpeningSceneView.swift`, `Features/Lists/ListViews.swift`, `Features/Settings/SettingsView.swift`.
- **Tests:** `SidebarNavigationTests` (5), `OpeningSceneTests.testOnAWideScreenTheWholeStageFitsAndIsCentred`, `DoddyUITests/LaunchSmokeTests.swift`.
- **Project:** `project.yml` (test targets `TARGETED_DEVICE_FAMILY "1,2"`).

## Verified (Linux, Swift 6.1.2)
- `swift test --package-path Packages/DoddyCore -Xswiftc -DSQLITE_DISABLE_SNAPSHOT -Xlinker --allow-shlib-undefined`: **863 tests, 0 failures**, including the 6 new ones.
- `swiftc -parse` on every changed app and UI-test file, and on `DoddyWatch/*.swift` and `DoddyWatchWidgets/*.swift`: PASS.
- `scripts/typecheck_app_logic.sh`: PASS (21 non-UI files; SwiftUI is not covered).
- `scripts/check_forbidden_capabilities.sh`: PASS.
- `tools/build_strings_catalog.py --check`: PASS. The sidebar's words ("Home", "Memories", "Settings", "Lists", "Doddy", "App navigation") already have Polish lines.
- `project.yml` parses as YAML.
- Later the same day, XcodeGen 2.44.1 (built from source on Linux) generated the project from this spec, with `SidebarLayout.swift` in the app target.

## NOT RUN
- No Xcode build, no simulator, no iPad. In particular, nobody has seen:
  - `NavigationSplitView` with a `NavigationStack` inside its detail column (Home's and Memories' own stacks): whether there is one navigation bar or two;
  - `List(selection:)` with an optional `SidebarItem` binding: whether a tap selects, and whether the sidebar rows show up as `buttons` (the UI tests look them up with `descendants(matching: .any)` on iPad, but older tests use `app.buttons["tab.settings"]`);
  - resizing in Split View between compact and regular (tab bar ↔ sidebar), and the opening during that;
  - the opening on an iPad in either orientation.
- No screenshots in `VISUAL_REVIEW/ipad/` yet: they need a simulator.

## Open items from the iPad code audit
Fixed on 2026-10-11 after the owner chose "iPad fixes". All of these are NOT RUN.
- **More than one Doddy window:** one window only (ADR-436).
- **Confirmation dialogs as popovers:** each now hangs off the button or menu that opens it (ADR-437).
- **Full-screen covers with no width cap:** the voice screen and Ask keep a readable column (ADR-437).
- **"Call Doddy" (`tel:`):** hidden on iPad; the number stays (ADR-437).
- **Words that assume an iPhone:** the 78 strings that say "this iPhone" read "this iPad" on iPad, in English and Polish (ADR-437). Back Tap and Action Button copy is on screens iPad already hides. The Dynamic Island texts in Focus, Hey Doddy and voice remain.

Still open, needing a simulator:
- `ShareLink` inside a context menu and a toolbar menu, and `UICloudSharingController` in a `.sheet`, may anchor oddly or show blank.
- Home's background picture is sized by width and may look soft on a wide iPad.

## "New note" Home Screen widget (ADR-440, 2026-10-11)
- From the owner's deck, slide 05. A small widget, and a Lock Screen circle, on iPad and iPhone.
- A tap runs `NewNoteIntent` (the "New note" control's intent): Doddy opens on an empty capture screen. Nothing is typed or recorded in the widget.
- It shows Doddy listening (owner's pack) on full-colour Home Screens, and the pencil otherwise.
- **NOT RUN:** whether `Button(intent:)` with an intent that opens the app behaves on iPad as it does with the "Talk to Doddy" widget.

## Live Activities on iPadOS 26, Pencil (ADR-443, ADR-446, 2026-10-11)
- **Shopping mode on iPad:** offered again on iPadOS 26 and later, where Live Activities are reported to work. On earlier iPads it stays hidden. The Dynamic Island styles stay iPhone only.
- **Sources:** [Home Assistant iOS pull request 5733](https://github.com/home-assistant/iOS/pull/5733), merged, and [9to5Mac, June 2025](https://9to5mac.com/2025/06/13/live-activities-are-coming-to-ipad-and-mac-heres-how-theyll-work/). Not confirmed in Apple's documentation, so **check on a real iPad on iPadOS 26** that shopping mode starts and shows on the Lock Screen.
- **Slide 07's kitchen timer:** not built (see ADR-443).
- **Pencil:** Scribble writes into the capture screen's text field. Nothing in Doddy turns it off. A drawing canvas is the owner's decision.

## Constitution evidence log
| Rule | Enforcing code | Tests | Gaps |
|---|---|---|---|
| DOD-08 verified_status_and_receipts | Unchanged: the sidebar only navigates; lists open through the same `MemoryOrListView` | `SidebarNavigationTests` | SwiftUI not compiled |
| DOD-11 observable_privacy | The sidebar shows list names only, from the same store and order as Home; behind the same app lock overlay | — | Not seen on a device |
| Honest UI | iPad hides shopping mode and island styles instead of "turn them on in Settings" for a setting iPad lacks | UI test written, NOT RUN | Other iPhone wording remains (see open items) |
