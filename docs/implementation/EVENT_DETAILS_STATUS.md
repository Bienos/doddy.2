# An event's place and notes by voice: status (ADR-281)
Date: 2026-10-11. Owner: "do all of them" (round 3, item 2).

## What ships
- **Voice:** `change_calendar_event` takes `new_location` (a new place) and `add_note` (a line added to the notes). Either can come alone or with a new time or title.
- **Place:**
  - the place the event has now is read on this iPhone only to show it on the card ("Place: Old clinic → Marszałkowska 10") and for the stale check;
  - it is never sent to the agent; the reply names only the new place;
  - at the tap, the place must still be what the card showed, or nothing changes.
- **Notes:** only ever added to, as a new last line. Doddy never replaces or deletes an event's notes, and the card says so.
- **Undo** (ADR-258) puts the place back and takes the added line off again, but only if the notes still end with exactly that line.
- **Limits:** 200 characters for a place, 500 for a note. The same place again is no change.
- **Read-back:** the place and notes are checked along with the time and title before "changed".

## Files
- **Core:** `CalendarChanges.swift` (`EventChangeDraft`, `EventChangePlan` details, `notes(_:adding:)` and `notes(_:removing:)`, `reversed`, `eventChanged(plan:)`).
- **App:** `DeviceConnections.changeEvent` and `eventLocation(_:)`; `VoiceSessionController`; `VoiceView` (card); `ConnectionsView` (wording).
- **Agent spec:** `tools.json` and `instructions.md` (the "cannot do yet" line now names guests and replacing notes).
- **Tests:** `EventDetailsTests` (3).

## Verified (Linux)
- `EventDetailsTests` and `CalendarChangeTests` pass.

## NOT RUN
- No Xcode build, and never run against Calendar.
- Not known: whether some calendar accounts (Exchange, Google) rewrite notes on save, for example line endings. That would make the read-back report "unknown".

## Constitution evidence log
| Rule | Enforcing code | Tests | Gaps |
|---|---|---|---|
| DOD-07 scoped_action_approval | Card shows the old and new place and the added line; written only on Change | `testAPlaceOrANoteAloneIsAChange` | UI not compiled |
| DOD-08 verified_status_and_receipts | Place and notes read back before "changed" | — | Not run on a device |
| DOD-09 correction_and_recovery | Notes only appended; Undo removes exactly the added line | `testNotesAreOnlyAddedToAndUndoTakesTheLineOffAgain` | — |
| DOD-11 observable_privacy | Old place shown on screen only, never sent to the agent | `testAPlaceOrANoteAloneIsAChange` | — |
