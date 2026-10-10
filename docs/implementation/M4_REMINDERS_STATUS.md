# M4 status: Apple Reminders through the approval flow
Date: 2026-10-10. Owner instruction: "build the Apple Reminders integration next".
Builds on `ACTION_APPROVAL_SIMULATION.md`: ledger, exact-payload approval, persistence and crash recovery.

**First real action.** Unlike the message demo, this writes to the user's real Reminders. Nothing is written without an approval tap, and "Added" appears only after Doddy finds the reminder again in Reminders. **The EventKit code has not been built or run yet** (no Xcode here). The M4 exit criteria (a real reminder on a device, denied/timeout/duplicate checks on device) are **not met** until the Mac checks below are done.

## What you can do
Memory → **Add to Reminders…**:
1. **First time only:** an explanation, then the iOS prompt.
   - The explanation says iOS only offers full access and that Doddy uses access only for reminders you approve.
   - If access is off, the screen says so and offers Open Settings. If access is restricted, or there's no list, it explains that.
2. **Form:** the title (prefilled from the memory, editable) and an optional time (default tomorrow 09:00 in the device's time zone, editable, no past dates). The time zone and list are shown.
3. **Review:** this creates the draft. The approval screen then shows exactly what will be written: reminder, date and time, time zone, list, and that it can be deleted in Reminders. It also says Doddy adds a reference note. Edit sends it back to draft and clears any approval.
4. **Approve and add:**
   - **Added:** the reminder was found again by its reference.
   - **Couldn't confirm:** use "Check Reminders", which only looks and never adds again.
   - **Not added:** the reason is shown.
   - **Access turned off since drafting:** the draft and approval stay, and the screen explains how to turn access back on.

Settings shows the current Reminders access state and explains it. "What's built" lists Reminders as Available; built is not the same as permitted.

## How it is enforced
| Rule | Code | Test |
|---|---|---|
| Exact approval, any change voids it (DOD-07) | `ActionLedger` + `ActionPayload.reminder` (title, ISO 8601 time with offset, time-zone ID, list ID) | `testSameMomentInAnotherZoneIsADifferentPayload`, app `testEditingBlocksApprovalUntilTheDraftIsUpdated` |
| Permission checked before execution, without using up the approval | `ActionAdapter.readiness` → `ActionPolicyError.notReady`; the ledger re-checks the record after the await | `testNoAccessLeavesDraftAndApprovalUntouched`, `testCancelDuringReadinessCheckStopsTheWrite`, `testSecondExecuteDuringReadinessCheckIsRefused` |
| Permission checked again at the write | `RemindersActionAdapter.execute` | `testAccessRevokedBetweenCheckAndWriteFailsWithoutWriting` |
| "Added" only after the reminder is found again (DOD-08) | Marker = idempotency key in the reminder URL (`doddy://action/<key>`) and notes ("Ref: <key>"); `findReminder` after `create` | `testConfirmedOnlyAfterTheReminderIsFoundAgain`, `testSavedButNotFoundAgainIsUnknown` |
| A failed save is checked before it's called failed | Lookup in the `catch` path | `testFailedSaveThatActuallyWroteIsConfirmed`, `testFailedSaveWithNothingWrittenIsFailed` |
| No duplicates (DOD-09) | Lookup before writing; `unknown` → reconcile only (lookup) | `testExistingReminderWithSameKeyIsNotWrittenTwice`, `testFailedSaveAndFailedLookupIsUnknownAndNotRetried`, `testReconcileFindsTheReminderOrReportsItMissing` |
| Deleted list | `client.list(id:)` before writing | `testMissingListFailsWithoutWriting` |
| Ask only at point of use, after an explanation (DOD-11) | `ReminderFlowModel.requestAccess` only from "Continue" | app `testAsksOnlyAfterExplanationThenShowsForm` |
| EventKit confined, reminders only, two permissions | `scripts/check_forbidden_capabilities.sh` | Guard passes; 8 negative cases fail it (below) |

The marker is in both URL and notes so either survives if the user edits the other. Lookups search all reminder lists on the device. Doddy doesn't read anything else from your reminders.

## Tests executed (2026-10-10, Linux x86_64, Swift 6.3.3)
| Command | Result |
|---|---|
| `swift test --package-path Packages/DoddyCore -Xswiftc -DSQLITE_DISABLE_SNAPSHOT` (clean build) | **92 tests, 0 failures**, 0 warnings (18 new in `RemindersTests`) |
| Reminders + concurrency tests, 5 repeated runs | 21/21 each run |
| Mutation check: 7 broken versions (ledger skips readiness, no re-check after the readiness await, confirm without finding, failed without looking, no access check at write, no duplicate check, deleted list not checked) | each one fails tests |
| `ReminderFlowModelTests` (7) + `ActionDemoModelTests` (9) compiled against DoddyCore in a Linux scratch package | **16 pass**, no warnings |
| `swiftc -parse` on every changed Swift file (incl. `EventKitRemindersClient.swift`, `ReminderFlowView.swift`) | all parse |
| `scripts/check_forbidden_capabilities.sh` | PASS. It **fails** on each of: EventKit import outside `Features/Reminders`; `EKEventStore` in core; `EKEvent` (calendar events) inside Reminders; calendar permission key; legacy `NSRemindersUsageDescription`; location permission; `URLSession`; `AVFoundation` outside Voice |

**Linux build note:** after changing stored properties of `ActionLedger`, an incremental `swift test` crashed with signal 11 inside the test binary. `swift package clean` fixed it, and all tests pass on a clean build. Use a clean build if this happens again.

## Not verified (needs a Mac and an iPhone)
- The app compiles with `EventKitRemindersClient` (Swift 6 strict concurrency against the iOS 17+ SDK), and `INFOPLIST_KEY_NSRemindersFullAccessUsageDescription` lands in the generated Info.plist.
- The iOS prompt appears once, after "Continue". Denied → "access is off" + Open Settings; turning it back on in Settings is picked up on return.
- A real reminder appears in the default list with the right title, due date, alarm and time zone, plus the URL and note. Whether Reminders keeps the `url` field (the note is the backup marker).
- "Added" receipt; Check Reminders after deleting the reminder in Reminders → "Not added" on reconcile.
- iCloud-synced lists, a restricted device (Screen Time), and no-list states.
- VoiceOver, Dynamic Type and dark mode on the new screens.
- Updated UI test text in `testThreeTabsAndHonestPlaceholders` (it was stale since V1: the microphone row now reads "Only while talking").

## Not built (deliberate)
- Voice: the ElevenLabs agent has no `create_reminder` tool. `ActionProposalParser` still refuses it, so changing the live agent is a separate owner decision.
- Editing or deleting a reminder from Doddy. Deleting a memory doesn't touch its reminder.
- Choosing a list other than the default, recurring reminders, locations.
- A launch-time check of unknown reminders: today they're checked from the reminder screen ("Check Reminders").

## Privacy
- Reminders data stays on the device (and in the user's iCloud, as before); nothing is sent to ElevenLabs or anywhere else.
- The action history (reminder text, list, times) is stored in `actions.sqlite`, with 30-day retention for finished actions.
- `PrivacyInfo.xcprivacy` is unchanged: no new data leaves the device and EventKit is not a required-reason API. This should be re-checked against Apple's current list before submission.
