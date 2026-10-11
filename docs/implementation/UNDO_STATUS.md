# Undo for changes and imports: status (ADR-258)
Date: 2026-10-11. Owner: "do all of them" (item 4).

## What ships
- **Calendar and Reminders changes.** After a change by voice (ADR-229) is read back, the voice screen shows a receipt: "Changed “Dentist”: now 12 Oct, 15:00.", "Marked “Call mum” done in Reminders." or "“Pay rent” is now due …". It has **Undo** for 10 minutes.
  - **Event:** `EventChange.reversed(plan)` gives the change backwards. Its "before" is the event as Doddy left it, with the occurrence id it has at its new start.
  - **Reminder:** reopen a completed one, complete a reopened one, or put back the old due, cleared if there was none. An alarm Doddy moved with the due moves back, or goes when the due is cleared.
  - **The same checks as the change:** the item must still look exactly as Doddy left it, or nothing is written and the receipt says it was changed elsewhere. The result is read back. Doddy is told (an "(app)" message) that it was put back, or that the app couldn't confirm it.
  - **After 10 minutes,** the receipt says to change it in Calendar or Reminders.
- **Imports.** After an import (ADR-231), **Undo this import** asks first, then removes exactly the notes and lists that import added, and reloads to check they're gone ("Removed what this import added (12). Checked.").
- **Polish:** the catalog generator now accepts `%@` / `%lld` format strings from code, if the Polish line keeps the same placeholders in the same order. Its check fails otherwise.

## Files
- **Core:** `CalendarChanges.swift` (`EventChangePlan.init`, `ReminderChange`, `EventChange.occurrenceID`, `EventChange.reversed`, `undoUnconfirmed`).
- **App:**
  - `DeviceConnections.changeReminder(_:_:)` with `ReminderChange`, and `reminderSnapshot(id:)`;
  - `VoiceSessionController`: `ChangeReceipt`, `undoLastChange()`;
  - `VoiceView`: the receipt card;
  - `MemoryStore.removeImported(_:)`;
  - `NoteImportView`: Undo this import.
- **Tools:** `tools/build_strings_catalog.py` (format strings, `ProgressView`).
- **Tests:** `CalendarChangeTests.testUndoIsTheChangeBackwards`.

## Verified (Linux)
- `CalendarChangeTests` pass (7). The app-logic type-check (13 files, including `MemoryStore+Lists`) passes. `swiftc -parse` passes on the changed views.

## NOT RUN
- No Xcode build. Undo has never touched real EventKit data.
- Not known: whether a moved occurrence of a repeating event keeps its calendar item id (if not, Undo says "changed elsewhere" and writes nothing).
- Import undo has not been tried on a device.

## Constitution evidence log
| Rule | Enforcing code | Tests | Gaps |
|---|---|---|---|
| DOD-09 correction_and_recovery | Undo for every voice change and every import | `testUndoIsTheChangeBackwards` | Not run on a device |
| DOD-08 verified_status_and_receipts | Undo read back; "Put back as it was. Checked." only when verified; the agent is told the truth | — | — |
| DOD-07 scoped_action_approval | Undo writes only if the item is exactly as Doddy left it; import undo asks first | — | UI not compiled |
