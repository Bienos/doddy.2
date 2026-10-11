# Shopping mode status (ADR-257)
Date: 2026-10-11. Owner: "do all of them" (item 2).

## What ships
- **Starting it:** list menu › **Shopping mode** (only when the list has open items). A confirmation says the items will be readable by anyone who sees the iPhone, until every item is ticked or the user ends it.
- **What shows:** a Live Activity on the Lock Screen and in the Dynamic Island:
  - Lock Screen: the list name, "N left", up to 6 items (open first in list order, then the latest ticked, so a mis-tap is easy to undo), and "And N more in Doddy";
  - Dynamic Island compact: a cart and "N left"; expanded: up to 4 open items.
- **Ticking:** each item is a button that runs `ToggleListItemIntent` (ADR-219) in the Doddy app after Face ID or the passcode. It changes the item only if it still looks as shown, ticks it through the store, and reads it back. The activity is redrawn from the list as it now is, through the same refresh as widgets and the watch.
- **Ending:**
  - "End shopping mode" in the list menu, or End on the list's "Shopping mode is on" row;
  - every item ticked: an "All ticked" card for a minute, then it goes;
  - the list is deleted;
  - 8 hours without an update: iOS marks it stale, and the card says to open Doddy.
- **One list at a time.** Starting another list ends the first. After a relaunch, a running shopping mode is picked up again.
- **If Live Activities are off for Doddy,** the list says so and how to turn them on.

## Files
- **Core:** `ShoppingMode.swift` (`ShoppingModeState.make`).
- **Shared:** `Shared/ShoppingMode/ShoppingActivityAttributes.swift`.
- **Widgets:** `DoddyWidgets/ShoppingLiveActivity.swift`, registered in the bundle.
- **App:**
  - `Features/Lists/ShoppingModeController.swift`;
  - `ListViews.swift`: menu item, confirmation, "on" row;
  - `WidgetSync.refresh` also refreshes shopping mode;
  - `DoddyApp.swift`: store and re-attach.
- **Tests:** `ShoppingModeTests` (3).

## Verified (Linux)
- `ShoppingModeTests` pass: order and room, more-count, finished only when everything is ticked, cut text.
- `swiftc -parse` passes on all new and changed files.

## NOT RUN
- No Xcode build and nothing on a device. Not checked:
  - Lock Screen buttons running the intent;
  - the Face ID prompt;
  - updates while Doddy is in the background;
  - the 4 KB Live Activity content limit (6 items of up to 60 characters should fit);
  - Dynamic Island layout.

## Constitution evidence log
| Rule | Enforcing code | Tests | Gaps |
|---|---|---|---|
| DOD-11 observable_privacy | Confirmation before the list goes on the Lock Screen; ends when finished, deleted, or stale | — | UI not compiled |
| DOD-07 scoped_action_approval | A tick changes only the item as shown, through the checked intent | existing `WidgetTick` tests | Not run on a device |
| DOD-08 verified_status_and_receipts | Redrawn only from the read-back list | `testOpenItemsFirstThenRecentTicksWhileThereIsRoom` | — |
