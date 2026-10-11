# Action status model: status (ADR-291)
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

## Constitution evidence log
| Rule | How it applies | Enforcing code | Tests run | Gap / claim to limit |
|---|---|---|---|---|
| DOD-08 verified status | Only a matching read-back or a check of the app is "confirmed"; a receipt is kept only then; unknown is never success | `ActionStatus`, `ActivityEntry.init` receipt guard, `EventAddAction`, `ActivityLog.checked` | `testAReceiptIsKeptOnlyOnAConfirmedEntry`, `testACheckNeverRewritesAFinalResult`, `testAReadBackThatDiffersIsNotConfirmed` | EventKit read-back not run on a device |
| DOD-04/05 external writes, approval | Retry is still a card the user taps; nothing runs without it; after 3 unconfirmed tries no card is shown | `mayTryAgain`, `PlanBlock.tooManyTries` | `testRetryChecksFirstAfterAnUnconfirmedTryAndStopsAfterThree`, `testAPlanStepTriedTooOftenIsShownBlockedAndLoggedAsNotDone` | Controller wiring not compiled |
| "unknown is never blindly retried" (CLAUDE.md) | An unknown add is repeated only through look-first adds that can't make a second copy | `EventAddAction`, `ReminderAction.add` | `testAnUnconfirmedEventIsFoundOnRetryNotDoubled`, ReminderAction tests | Timers, alarms, notes, lists and online accounts have no operation key yet |
| DOD-11 observable privacy | The app's identifiers stay in the on-device activity file; the agent never hears them | `VoiceToolReply.reminder`/`event` | `testTheAgentNeverHearsTheExternalID` | — |
