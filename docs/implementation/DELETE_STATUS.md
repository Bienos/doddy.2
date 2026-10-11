# Delete events and reminders by voice: status (ADR-254)
Date: 2026-10-11. Owner: "do all of them" (item 5).

## What ships
- **Two tools** for the voice agent, both run on the phone and both need a tap:
  - `delete_calendar_event`: `title` and `start` exactly as `read_calendar` returned them.
  - `delete_reminder`: an open reminder's exact `title`.
- **Finding it.** The same exact matching as changing (ADR-229): one match makes a card; none or several go back to the agent, which asks the user. Nothing is guessed.
- **The card.** "Delete this event?" with the title and time, "If it repeats, only this time is deleted. This can't be undone from Doddy." For a reminder: the title, its list and due. Buttons: **Delete** / **Don't delete**.
- **At the tap:**
  1. Calendar or Reminders permission and Doddy's connection switch are checked again.
  2. The item must still look exactly as it did on the card (occurrence id, title, start and end; or reminder id, title, due, still open). If not, nothing is deleted and the agent hears it changed elsewhere.
  3. An event is removed with `span: .thisEvent`, so a repeating series keeps its other times. A reminder is removed with `commit: true`.
  4. Calendar or Reminders is read again. The agent hears "deleted" only when the item is gone; otherwise "unknown", and it asks the user to check.
- **No Undo.** A deleted item can't be put back as it was (a re-made event would lose its guests, attachments and history), so the card says so up front instead of offering an Undo that would only make a copy.
- Logged in **What Doddy did** ("Delete event", "Delete reminder"), and paused with Calendar or Reminders (ADR-207).
- The agent's "cannot do yet" list now says deleting **several** at once isn't built.

## Files
- **Core:** `CalendarChanges.swift` (tool names, `parseEventDelete`, replies), `VoiceTools.swift` (requests, connection), `ConnectionPause.swift`, `ActivityLog.swift`.
- **App:** `DeviceConnections.deleteEvent(_:)`, `deleteReminder(_:)`; `VoiceSessionController` (`PendingAction.deleteEvent` / `.deleteReminder`, propose, confirm, decline); `VoiceView` (card, labels).
- **Agent spec:** `voice-agent/tools.json` (2 tools), `voice-agent/instructions.md`.
- **Polish:** 5 lines in `l10n/pl.json`.
- **Tests:** `CalendarChangeTests.testDeletingIsParsedPausedAndLogged`.

## Verified (Linux)
- `CalendarChangeTests` pass (8), with the rest of the DoddyCore suite. `scripts/ci.sh --core-only`: RESULT: PASS for core-only scope (524 DoddyCore tests, 0 failures). `swiftc -parse` on the changed app files.

## NOT RUN
- No Xcode build; the delete has never touched real EventKit data.
- The live agent has both tools since version `agtvrsn_8201m4mf5fqhf9087wkrjz8kjenp` (see the round report); never called from a real conversation.
- Not known: whether `remove(span: .thisEvent)` on a detached occurrence leaves EventKit's read-back exactly as expected on every account type (iCloud, Exchange, Google).

## Constitution evidence log
| Rule | Enforcing code | Tests | Gaps |
|---|---|---|---|
| DOD-07 scoped_action_approval | One card per item, exactly as matched; delete only on the tap, only if unchanged | `testDeletingIsParsedPausedAndLogged` | UI not compiled |
| DOD-08 verified_status_and_receipts | "deleted" only after reading back that it's gone; otherwise "unknown" | — | Not run on a device |
| DOD-09 correction_and_recovery | The card says up front Doddy can't undo it; Don't delete is always there | — | — |
| DOD-11 observable_privacy | Both tools paused with Calendar / Reminders; logged in What Doddy did | `testDeletingIsParsedPausedAndLogged` | — |
