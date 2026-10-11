# Action status model: status (ADR-291, timers and alarms ADR-292, notes and lists ADR-293)
Date: 2026-10-11. Owner instruction: "start the action status model". This covers OP-012 (action receipts and status history) and OP-013 (recoverable failure and retry) from the research backlog.

## What was already there
- "What Doddy did" (`ActivityLog`) logged each change with an outcome: done, already there, not sure, didn't happen, declined, in progress.
- A change cut off mid-way became "not sure" at the next launch.
- Reminders already looked before writing, read back after writing, and looked again after a failed save (ADR-126).

## What this adds
- **Typed status** (`ActionStatus`): proposed, pending, confirmed, failed, unknown, declined, handed off.
  - Each outcome maps to one status; look-ups have none.
  - Only these moves are allowed:
    - proposed → pending, declined or failed;
    - pending → confirmed, failed, unknown or handed off;
    - unknown → confirmed or failed, and only through a check.
  - Final statuses never change.
  - "Check in Reminders" now changes an unsure entry only. Before, it would rewrite a confirmed or failed entry it was given.
- **Status history:** each entry keeps how its status moved, with times and how Doddy knows (for example "Found in Reminders when you checked").
  - The activity screen shows the history for entries that were ever unsure.
- **Receipts:** a confirmed reminder or event keeps what the app read back (title, time, list) and the app's own identifier.
  - Shown under the entry as "Read back from Reminders at 10:02".
  - A receipt passed in with an unsure or failed result is dropped, so there is no fake success.
  - The identifier is never sent to the voice agent; a test checks this.
- **Operation key:** a new reminder (the existing reminder key) or a new event (`EventIdempotency.key`: title, start, end, all-day) gets the same key when the same change is asked again.
- **Retry rule** (`ActionRetry`), read from the log before the card is shown:
  - An earlier try that is unconfirmed or still running: the add checks the app first, and the reply says so.
  - 3 tries in 24 hours where the app was asked to write and nothing was confirmed: Doddy stops. No card; the agent is told to ask the user to look. In a plan the step shows "Tried 3 times in the last day … Look in Reminders first."
  - A confirmed try resets the count. Clarifications, a switched-off connection and a "no" don't count, because nothing was written.
- **Calendar looks before it writes** (`EventAddAction`), as Reminders does:
  - An event already there counts as there. Same title (ignoring case and spacing), same start and end; for all-day events, the same day.
  - A failed save is looked for again before answering.
  - "Added" comes only from a read-back that matches the card.
  - A repeating event found after a failed save stays "not sure", because its repeat can't be seen.
- **Unsure replies:** for reminders and events, the agent is told the change may not have gone through, and that calling the tool again is safe because Doddy checks first.
  - The live agent prompt was **not** changed. Its rule ("say it may not have gone through and ask the user to check") still applies; the tool result adds that a retry is safe.

## Files
- **Core:**
  - `ActionStatus.swift` (new): status, receipt, history, `ActionRetry`, `EventIdempotency`, `CalendarEventWriter`, `EventMatching`, `EventAddAction`, and the replies.
  - `ActivityLog.swift`: operation key, receipt, attempted, history, `finished`, guarded `checked` and `recoverInterrupted`; "already in Calendar" is read as already there.
  - `ReminderAction.swift`: the receipt carries the reminder's identifier, a shared FNV hash, and the unsure reply.
  - `Plan.swift`: the `tooManyTries` block.
- **App:**
  - `VoiceSessionController.swift`: the retry check before the card, receipts and attempts on entries, and plan steps.
  - `DeviceConnections.swift`: `saveEvent` returns the read-back and the class conforms to `CalendarEventWriter`.
  - `ActivityView.swift`: receipt and history lines.
  - `ActivityLogStore.swift`.
- **Tests:** `ActionStatusTests.swift` (23 tests), and updated `ReminderActionTests`.
- `scripts/typecheck_app_logic.sh` now also type-checks `ActivityLogStore.swift`.

## Verified (Linux, Swift 6.2.1)
- `scripts/ci.sh --core-only`: **PASS for core-only scope**.
  - 695 package tests, 23 of them new.
  - Guards, pack, agent specs, Polish catalog, backend, gateway and messaging all pass.
  - Messaging database tests SKIPPED. iOS app NOT RUN.
- **Planted bugs**, each caught and then restored:
  1. A check allowed to rewrite any entry: `testACheckNeverRewritesAFinalResult` failed.
  2. The event add without its look-first step: 6 failures, including the double-add test.
  3. The retry counting clarifications: `testOnlyRealWritesCountAndAConfirmedTryClosesTheStory` failed.
- Entries saved before this load unchanged, with a test on old JSON.
- `swiftc -parse`: `VoiceSessionController.swift`, `ActivityView.swift`, `DeviceConnections.swift`. `ActivityLogStore.swift` is type-checked against DoddyCore.

## NOT RUN / unverified (needs a Mac and an iPhone)
- The app wiring was not compiled with Xcode: the controller, `DeviceConnections.saveEvent` with EventKit, and the activity screen.
- Real EventKit behaviour is unchecked:
  - whether an all-day event reads back on the same day;
  - whether start and end read back to the second;
  - whether `event(withIdentifier:)` returns the event right after a save.
- English/Polish on a device. The new screen strings are not in the Polish catalog yet; they show in English.
- Mac checklist items AS1 to AS5.

## Timers and alarms (ADR-292)
Owner instruction: "extend it to timers and alarms".

- **Keys:**
  - A timer's key comes from its label and length.
  - An alarm's key comes from its label and time, plus its day, or its repeat for a repeating alarm.
  - Both get receipts, status history and the retry rule.
- **Alarms** (`AlarmSetAction`): Doddy always looks first, because the same alarm twice is never wanted.
  1. One of Doddy's alarms with the same key counts as already set. An alarm set before this has no key, so it is matched by time, day and label.
  2. Doddy notes the alarm, then asks AlarmKit to set it under an id Doddy chose.
  3. "Set" only when AlarmKit lists that id.
  4. After an error, a listed id still counts as set; otherwise the note is dropped. "Not allowed" or "needs iOS 26" drops the note too.
  5. A note AlarmKit doesn't list yet is kept for 10 minutes (`AlarmBook.keepOnly`), so a late-listed alarm is found on a retry.
- **Timers** (`TimerStartAction`): two identical timers can be wanted on purpose.
  - Doddy looks for a running copy only when an earlier try of the same timer is unconfirmed, and only for one that rings at least its length after that try.
  - The notification identifier is `doddy.timer.<key>.<uuid>`, and the ring time is stored in the notification. iOS's `nextTriggerDate()` for a time-interval trigger is used only as a fallback, because it is not trusted to give the original ring time (unverified on device).
  - "Started" only when iOS lists that identifier. A failed schedule is looked for again before answering.
- **Replies:** an unsure timer or alarm tells the agent a retry is safe because Doddy checks first. A copy found running or already set is logged as "Already there".
- **Plans:** a timer step goes through the same path, with receipt and retry.
- **Not covered:**
  - Turning an alarm off. Repeating it is already safe: an alarm that is gone is reported as not found.
  - Timers set before this have no key, so they are not found by a retry.
  - A timer that already rang before the retry is not found, so it is started again.
- **Files:**
  - `TimerAlarmActions.swift` (new);
  - `Alarms.swift` (`AlarmEntry.key`);
  - `ActivityLog.swift` (keys, "already set" / "already running" read as already there);
  - `VoiceTools.swift` (`durationText` internal);
  - `DeviceConnections.swift` (`pendingTimers`, `scheduleTimer`, `TimerWriter`);
  - `AlarmScheduler.swift` (`schedule(_:id:)`, `AlarmKitWriter`, the book keeps key and time noted);
  - `VoiceSessionController.swift`.
  - Tests: `TimerAlarmActionsTests.swift` (15).
- **Verified (Linux, Swift 6.2.1):**
  - `scripts/ci.sh --core-only` PASS for core-only scope, with 755 package tests. Messaging database tests SKIPPED; iOS app NOT RUN.
  - `AlarmScheduler.swift` outside `#if canImport(AlarmKit)` is type-checked against DoddyCore; the AlarmKit part and the controller are parse-checked only.
  - Planted bugs, each caught and restored:
    - a timer that always looks for a copy: 2 failures, including "two on purpose both run";
    - an alarm without its look-first step: 5 failures;
    - an alarm noted only once listed: the late-listing test failed.
- **NOT RUN:**
  - AlarmKit and notifications on a device;
  - whether `manager.schedule(id:)` keeps the id Doddy chose;
  - how late AlarmKit lists a new alarm;
  - Mac checklist items AS6 to AS9.

## Notes and lists (ADR-293)
Owner instruction: "extend it to notes and lists".

- **Why it differs:** notes and lists live in Doddy's own database, which is the truth about them. So Doddy settles an unsure entry itself instead of asking the user to check.
- **What each entry keeps:** each note or list change keeps an `ActivityCheck`:
  - a note: its key, a hash of its words by DuplicateNote's rule;
  - a list change: the list name and items as asked.
- **How it settles** (`LocalCheck`):
  - a note with those words saved since the try (a minute's slack; sample notes don't count);
  - for an add, every item on the list; for a tick, every item ticked and none still open;
  - for a remove, none of the items left; for a new list, the list there.
  - Found means confirmed; not found means "didn't happen".
  - A remove from a list that is gone stays unsure.
  - Lists are found the way a voice request finds them (`ListMatch.list(named:)`), so "the shopping list" is "Shopping".
- **When it settles:** before any retry is decided for a note or list, and when What Doddy did opens.
  - Only after the store has reloaded without an error. An empty store must never read as "not there".
- **List changes without a card:** add, tick and remove are now written down "in progress" before they run, so one cut off mid-way shows and is then settled.
- **No double note:** if a note save is still unsure at the tap, a note with the same words saved since that try counts as already saved and isn't saved again. The same words saved twice on purpose are still two notes (DuplicateNote only warns).
- **Receipts:**
  - a note as the database returned it;
  - a list change as the list's own result: added, already on the list, too long, no room, ticked, removed;
  - plan steps that save a note or add to a list get the same.
- **Not covered:**
  - notes and lists changed on the app's own screens (they aren't in What Doddy did);
  - the remind-about-a-note card.
- **Files:**
  - `NoteListActions.swift` (new);
  - `ActivityLog.swift` (the `check` field, keys, and "already saved" read as already there);
  - `Lists.swift` (`nameKey` internal);
  - `VoiceTools.swift` (`timestamp` internal);
  - `ActivityLogStore.swift` (`settleLocal`);
  - `ActivityView.swift`;
  - `VoiceSessionController.swift`.
  - Tests: `NoteListActionsTests.swift` (9).
- **Verified (Linux, Swift 6.2.1):**
  - `scripts/ci.sh --core-only` PASS for core-only scope, with 764 package tests. Messaging database tests SKIPPED; iOS app NOT RUN.
  - Planted bugs, each caught and restored:
    - any older note with the same words settling a try;
    - a gone list counting as a done remove;
    - the no-double-note look ignoring when the try was.
- **NOT RUN:** on a device, and Mac checklist items AS10 to AS12.

## Constitution evidence log
| Rule | How it applies | Enforcing code | Tests run | Gap / claim to limit |
|---|---|---|---|---|
| DOD-08 verified status | Only a matching read-back or a check of the app is "confirmed"; a receipt is kept only then; unknown is never success | `ActionStatus`, `ActivityEntry.init` receipt guard, `EventAddAction`, `ActivityLog.checked` | `testAReceiptIsKeptOnlyOnAConfirmedEntry`, `testACheckNeverRewritesAFinalResult`, `testAReadBackThatDiffersIsNotConfirmed` | EventKit read-back not run on a device |
| DOD-04/05 external writes, approval | Retry is still a card the user taps; nothing runs without it; after 3 unconfirmed tries no card is shown | `mayTryAgain`, `PlanBlock.tooManyTries` | `testRetryChecksFirstAfterAnUnconfirmedTryAndStopsAfterThree`, `testAPlanStepTriedTooOftenIsShownBlockedAndLoggedAsNotDone` | Controller wiring not compiled |
| "unknown is never blindly retried" (CLAUDE.md) | An unknown add is repeated only through look-first adds that can't make a second copy | `EventAddAction`, `ReminderAction.add` | `testAnUnconfirmedEventIsFoundOnRetryNotDoubled`, ReminderAction tests | Timers, alarms, notes, lists and online accounts have no operation key yet |
| DOD-11 observable privacy | The app's identifiers stay in the on-device activity file; the agent never hears them | `VoiceToolReply.reminder`/`event` | `testTheAgentNeverHearsTheExternalID` | — |
| DOD-08 / "unknown never blindly retried" (timers, alarms) | An unsure timer is repeated only after a look for the running copy; an alarm always looks first and counts as set only when AlarmKit lists its id | `TimerStartAction`, `AlarmSetAction` | `TimerAlarmActionsTests` (15) | AlarmKit/notifications not run on a device |
| DOD-08 / DOD-06 (notes, lists) | An unsure note or list change is settled only from Doddy's own database, after it has loaded; a note isn't saved twice after an unconfirmed try | `LocalCheck`, `NoteIdempotency.savedSince`, `settleLocalEntries` guard | `NoteListActionsTests` (9) | The load guard is app code, not compiled here |
