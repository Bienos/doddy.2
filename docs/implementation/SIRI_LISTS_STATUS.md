# Lists from Siri and Shortcuts status (ADR-226)
Date: 2026-10-10. Owner: "do all of them" (item 3).

## What ships
- **Three actions** under Doddy in Shortcuts, Siri and the Action Button picker:
  - **Add to a list:** "Add to my shopping list in Doddy". Siri asks "What should I add?", and several items are separated by commas.
  - **Read a list:** "What's on my shopping list in Doddy?". Siri says up to 10 open items and counts the rest. Ticked items aren't read.
  - **Tick an item:** "Tick something on Shopping in Doddy". If the words could mean more than one item, nothing is ticked and Siri says which ones matched.
- **The same rules as voice and the list screen.** Lists are matched exactly (`ListMatch`), and changes go through `MemoryStore.addToList` / `setDone`, which read back. A tick or an add sets the list's Undo in the app. Siri's reply is built only from what the store returned (`ListSiri`), in Polish on a Polish iPhone.
- **Privacy:** every action requires the iPhone unlocked, so nothing is read out or changed from a locked phone. They run in the app's process; the widget extension and nothing else touch the database.
- **Phrases name the list.** Siri learns list names through `updateAppShortcutParameters()` whenever the names change.

## Files
- **Core:** `ListSiri.swift` (item splitting and the spoken replies).
- **App:**
  - `DoddyApp/Intents/ListIntents.swift`: `IntentStores`, `DoddyListEntity` and its query, and the three intents.
  - `DoddyShortcuts.swift`: three App Shortcuts.
  - `DoddyApp.swift` and `RootView.swift`: wiring.
- **Tests:** `ListSiriTests` (4).

## Verified (Linux)
- `ListSiriTests` pass. They cover:
  - commas split items but "and" doesn't;
  - replies name only stored items, in Polish and English;
  - reading stops at 10 and leaves out ticked items;
  - the tick wording.
- `swiftc -parse` on the intents, the shortcuts, `RootView` and `DoddyApp`.

## NOT RUN / UNVERIFIED
- No Xcode build. App Intents with parameterized phrases are the likeliest to need compile fixes.
- Never spoken to Siri. Unchecked:
  - Siri recognising list names in phrases;
  - the unlock prompt;
  - running in the background with Doddy closed;
  - Polish Siri phrases (task: localized `AppShortcuts.xcstrings`).

## Constitution evidence log
| Rule | Enforcing code | Tests | Gaps |
|---|---|---|---|
| DOD-08 verified_status_and_receipts | Replies built from `ListAddResult` / the `setDone` read-back only | `testRepliesSayOnlyWhatTheStoreReturned` | Intent path not compiled |
| DOD-07 scoped_action_approval | Only the named list, exact match; an ambiguous tick changes nothing | `testTickWordingNamesTheExactItem` | — |
| DOD-11 observable_privacy | `requiresAuthentication` on all three | — | Not tried on a locked iPhone |
