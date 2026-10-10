# Home and Lock Screen widgets status (ADR-226)
Date: 2026-10-10. Owner: "do all of them" (item 4) and "Yes, tick from widget (Recommended)": tap an item on the Lock or Home Screen widget to tick it; saved and read back like in the app, and Undo is in the app.

## What ships
**Four widgets** (add them from the Home Screen or Lock Screen gallery; Doddy can't place them):
- **Pinned notes** (small, medium, Lock Screen rectangular): the notes pinned in Doddy, in pin order, first line only. Tap a note to open it in Doddy. None pinned → "Pin a note in Doddy to see it here."
- **Next reminder** (small, Lock Screen rectangular and inline): the next time reminder with its day and time. The note's words are shown only when "Show note text in notifications" is on; otherwise "A note reminder". Place reminders aren't shown. The widget moves on by itself when a reminder's time passes.
- **List** (small, medium, large, Lock Screen rectangular): choose a list when editing the widget (the first list if none chosen). Open items in order, then ticked ones, struck through; "N to go" / "All done". **Tap an item to tick it, or a ticked one to untick it.** A list deleted in Doddy says "This list isn't in Doddy any more. Choose another." and is never swapped for another list.
- **Talk to Doddy** (small, Lock Screen circular): opens Doddy and starts a conversation (`TalkToDoddyIntent`, as the control does).

**How the widgets get data**
- The widgets never open the notes database. The app writes a small snapshot to a file in an App Group folder that only Doddy and its widget extension can open: up to 4 pinned notes, 3 next reminders and 8 lists of up to 12 items, each cut to its first line and 120 characters.
- The file is rewritten when notes, lists, pins, reminders or the two settings change and when Doddy goes to the background. Each write is read back. If a write fails, Settings › Widgets says the widgets may be out of date.
- The file is readable after the first unlock (Data Protection `completeUntilFirstUserAuthentication`), so Lock Screen widgets can draw. All note and list text is `privacySensitive`, so iOS hides it on the Lock Screen while the iPhone is locked.

**Ticking from a widget**
- A tap runs `ToggleListItemIntent`, a `LiveActivityIntent`. iOS performs those in the app's process, starting Doddy in the background if needed. This is the same mechanism as the Dynamic Island buttons (ADR-131), and the intent is pinned to the app on iOS 27.
- There, `WidgetSync.tick` re-reads the store and checks that the item is still as the widget showed it (`WidgetTick.wanted`). A stale widget never flips an item changed since. It then ticks or unticks through `MemoryStore.setDone`, the same path as the app, and the change is read back.
- The snapshot is then rewritten and the widgets reload, so the widget shows what is saved, not what was tapped.
- The tick sets the list's Undo (`listUndo`) like a tick in the app. Unticking from the widget also works.
- `authenticationPolicy = .requiresAuthentication`: ticking from the Lock Screen asks to unlock first.

**Settings › Widgets**
- "Show notes and lists in widgets" is on by default. Turned off, the snapshot holds nothing of the user's and the widgets say "Turned off in Doddy's Settings."
- A build without the App Group says that it can't share anything with widgets.

**Signing.** The App Group is off by default, like push. `BUILD_AND_TEST.md` covers the entitlement files and build settings. Without it the widgets say "Open Doddy to set up widgets".

## Files
- **Core:** `WidgetSnapshot.swift`, containing:
  - `WidgetSnapshot.make`, `shortened`, encode/decode with a version check;
  - `WidgetLink` (`doddy://open/<id>`);
  - `WidgetTick`.
- **Shared** (app and extension):
  - `Shared/Widgets/WidgetSnapshotFile.swift`;
  - `Shared/Widgets/ToggleListItemIntent.swift`.
- **App:**
  - `Features/Widgets/WidgetSync.swift`;
  - `DoddyApp.swift`: wiring;
  - `RootView.swift`: refresh triggers, the `doddy://open/<id>` route, and the `widgetsShowContent` key;
  - Settings › Widgets.
- **Extension:**
  - `DoddyWidgets/HomeWidgets.swift`, containing four widgets, `ListEntity`/`SelectListIntent`, and the gallery preview with made-up content;
  - `DoddyWidgetsBundle.swift`.
- **Config:**
  - `Config/Doddy-AppGroup.entitlements`, `Config/Doddy-Push-AppGroup.entitlements`, `Config/DoddyWidgets.entitlements`;
  - the `DoddyAppGroup` key in both Info.plists;
  - in `project.yml`: `DODDY_APP_ENTITLEMENTS`, `DODDY_WIDGET_ENTITLEMENTS`, and the extension now links `DoddyCore`.
- **Tests:** `WidgetSnapshotTests`, 6 tests in DoddyCore.

## Verified (Linux, Swift 6.2.1)
- `WidgetSnapshotTests` (6) pass. They cover:
  - pin order and deleted pins skipped;
  - past reminders and reminders of deleted notes left out;
  - reminder text hidden unless the setting is on;
  - list order and counts;
  - off leaves nothing of the user's in the JSON;
  - cutting on a word;
  - version and damage refusal;
  - links;
  - stale-tick refusal and the read-back outcome.
- `scripts/typecheck_app_logic.sh` type-checks `WidgetSnapshotFile.swift`.
- `swiftc -parse` on the widget, intent, sync, RootView, DoddyApp and Settings files.

## NOT RUN / UNVERIFIED
- No Xcode build. WidgetKit, AppIntents and SwiftUI code is parsed only.
- **Tick from a widget not run.** That a `LiveActivityIntent` from a Home/Lock Screen widget button is performed in the app's process, including from a cold start, is what ADR-131 relies on for the island. It has never been tried here for a widget. If iOS performs it in the extension instead, the tap does nothing (the extension has no store) and the item stays as it was. It must be checked on a device.
- Whether App Review accepts a `LiveActivityIntent` for a widget action is unknown.
- Lock Screen redaction of `privacySensitive` text, the unlock prompt on tick, widget reload timing, and App Group signing with a free team are all not checked.
- The gallery preview content is made up and shown only in the widget gallery.

## Decisions for the owner
- Keep "Show notes and lists in widgets" **on** by default (as built), or make it opt-in.
- If the tick path fails on a device, the fallback is to move the notes database into the App Group, so the extension can write itself. That is a larger change (a database move and cross-process locking) and needs approval.

## Constitution evidence log (docs/trust/config/doddy_rules.yaml)
| Rule | What enforces it here | Tests run | Gaps / claims to limit |
|---|---|---|---|
| DOD-08 verified_status_and_receipts | Tick goes through `setDone` (read back); `WidgetTick.outcome` checks the read-back item; the widget redraws from the rewritten snapshot, not from the tap | `testATickFromAStaleWidgetChangesNothing` | Intent path not run on a device |
| DOD-07 scoped_action_approval | Only a tick/untick of the exact item shown, only if unchanged since drawn; unlock required | same | — |
| DOD-11 observable_privacy | Snapshot holds only pinned notes, next reminders and lists, shortened; reminder text follows the notification setting; `privacySensitive` on the Lock Screen; off switch empties the file; App Group readable only by Doddy's own extension | `testOffLeavesNothingOfTheUsersInTheSharedFile`, `testPinnedNotesRemindersAndListsAreShortenedAndOrdered` | Redaction is iOS behaviour, not verified; the file is readable after first unlock |
| DOD-06 user_controlled_relevant_memory | Widgets show only what the user pinned, set or listed; nothing is inferred | — | — |

Don't claim: "tick from the Lock Screen works", "widgets are private on the Lock Screen", or that any widget was drawn or tested on a device.
