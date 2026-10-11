# Several changes on one card: status (ADR-280)
Date: 2026-10-11. Owner: "do all of them" (round 3, item 1).

## What ships
- **`delete_calendar_events`** ("clear my Thursday afternoon"):
  - takes `from` and `to` in local time; a day alone as `to` means the whole day; at most 31 days;
  - covers events that **start** in the range; one that started earlier and runs into it is left alone;
  - a repeating event loses only the occurrence in the range.
- **`move_reminders`** ("move today's reminders to tomorrow"):
  - moves open reminders due on `due_by`'s day or earlier to `to`'s day;
  - each keeps its time, and a day-only reminder stays day-only;
  - a time the clocks skip or repeat on the new day isn't guessed; that reminder is left as it is and named on the card and in the answer.
- **One card:**
  - every item is listed, all ticked, because the user asked for all of them;
  - the user can untick any, and the button counts the ticked ones ("Delete 3", "Move 4");
  - nothing ticked means nothing to confirm;
  - the delete card says Doddy can't undo it.
- **At the tap:** each ticked item runs on its own through the single-item path (ADR-229, ADR-259). It must still look as on the card, then it changes, then it's read back.
- **The answer:**
  - "deleted" or "moved" only when every ticked item changed and read back;
  - "partly deleted" or "partly moved" when some did, naming the rest and why;
  - "unknown" or "failed" when none did.
- **Limits:** at most 20 items per card; more, and the agent asks for a shorter range. Nothing matching says so and changes nothing.
- **Other:** logged in What Doddy did, and paused with Calendar or Reminders.

## Files
- **Core:** `BulkChanges.swift` (`BulkItem`, `BulkResult`, `BulkChange`, parsing, replies); `VoiceTools.swift`; `ConnectionPause.swift`; `ActivityLog.swift`.
- **App:** `VoiceSessionController` (`PendingAction.bulk`, ticks, `runBulk`); `VoiceView` (card, labels, nothing-ticked state).
- **Agent spec:** two tools; the "cannot do yet" line is narrowed.
- **Tests:** `BulkChangeTests` (4).

## Verified (Linux)
- `BulkChangeTests` pass.

## NOT RUN
- No Xcode build, and never run against Calendar or Reminders.
- 20 changes in a row on the main actor haven't been timed on a device.

## Constitution evidence log
| Rule | Enforcing code | Tests | Gaps |
|---|---|---|---|
| DOD-07 scoped_action_approval | Every item listed and individually untickable; only ticked ones change | `testClearingAnAfternoonTakesOnlyEventsThatStartInIt` | UI not compiled |
| DOD-08 verified_status_and_receipts | The verb only when all read back; "partly" names the rest | `testTheAnswerSaysVerbOnlyWhenEverythingChanged` | Not run on a device |
| DOD-09 correction_and_recovery | Unchanged check per item; clock-change times left, not guessed | `testMovingTodaysRemindersKeepsTheirTimes` | Deletes can't be undone (said on the card) |
| DOD-11 observable_privacy | Paused with the connections; logged | `testBulkToolsArePausedServedAndLogged` | — |
