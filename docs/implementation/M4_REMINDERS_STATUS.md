# M4 status — one reliable action: Apple Reminders
Date: 2026-10-10. Built on the owner's instruction "do coding" while the device and server setup is pending.

## How it works (`docs/architecture/TOOLS_AND_ACTIONS.md`)
1. **Proposal.** A memory's **Remind me** button, or Doddy by voice (`create_reminder`), opens a review screen. A proposal writes nothing.
2. **Review.** The user edits the title and picks date/time. The screen shows the date in words and the time zone.
   - A voice-proposed time is accepted only as a local `YYYY-MM-DD` or `YYYY-MM-DDTHH:MM`.
   - Words, UTC offsets, impossible dates, times skipped by daylight saving, and past times all **need clarification**: "Add" stays disabled until the user picks a date (A-20).
3. **Confirm.** Tapping **Add to Reminders** stores the action as `user_confirmed`. Permission is checked now, at execution time.
   - If Reminders access is denied, the action becomes `verified_failed` with `permission_denied`, nothing is written, and the draft stays so the user can try again (A-23).
4. **Write.** `pending_external_write` is committed to SQLite **before** the EventKit call.
   - The reminder goes to the default list with an alarm at the due time.
   - Its URL field carries a marker, `doddy://reminder/<operationId>`.
5. **Verify.** The reminder is read back by its identifier. Only if the title and due match is it `verified_succeeded` (A-21).
   - A mismatch or missing reminder is `unknown_outcome`.
   - A write error is first checked by searching for the marker: found means success, not found means `unknown_outcome`.
6. **Reconcile.** Unknown outcomes are never retried blindly (A-22).
   - **Check again** only looks for the marker.
   - **Add it now** looks first and writes only if the reminder isn't there.
   - At launch, interrupted actions are finished:
     - `user_confirmed` becomes "interrupted before write" (nothing was written);
     - `pending_external_write` is reconciled by marker and **never re-created automatically**.
7. **Deletion.** Deleting a memory, or all memories, never deletes a reminder in Apple Reminders. Delete-all removes Doddy's local action records, which hold the reminder text.

## Built
- **DoddyCore `Reminders.swift`:**
  - `ReminderDue`, which rejects impossible and DST-skipped times;
  - `ReminderDueInput` (the strict parser);
  - `ReminderPayload` with canonical JSON;
  - the `ActionState` machine with the allowed edges only;
  - `ReminderAction`;
  - the `ReminderGateway` and `ReminderActionStore` ports;
  - `ReminderExecutor` (confirm, write, verify, reconcile, recover) and `ReminderCopy`.
- **DoddyCore `VoiceTools`:** `create_reminder` parsing and honest replies to the agent ("created … (checked)" / "unclear … do not say it was created" / "declined").
- **DoddyPersistence:**
  - migration `v2_outbox_actions` (the `outbox_actions` table from `MEMORY_AND_DATA.md`);
  - `SQLiteReminderActionStore`, where every write is read back;
  - `deleteAll` also clears the action records.
- **App:**
  - `EventKitReminderGateway` (the only EventKit code; iOS 17 full Reminders access);
  - `ReminderProposalView` (review, create, result);
  - `RemindersListView` (Settings → Reminders from Doddy, with Check again / Add it now / Try again);
  - **Remind me** on memory detail;
  - voice review card and sheet; the agent gets an answer even if the sheet is swiped away;
  - crash recovery at launch;
  - permission text in `project.yml`;
  - guard update: EventKit allowed only in the gateway file, and Reminders is the second allowed permission.

## Voice agent: tool already exists (checked 2026-10-10)
The dev agent `agent_0501m4et27vyeawrwqfdxxfszfa6` already has a client tool `create_reminder` (`tool_9901m4f2xyn1exfrx6as0kek55rk`, params `title`, `due`, `notes`, 90 s timeout). It was created from another branch line (e.g. `claude/magical-newton-ip0bx2`). **No second tool was created.**
- The app's replies now follow that tool's contract: `added:` / `declined:` / `unknown:` / `failed:`.
- `notes` is passed through to the review screen.
- Not supported from that contract: "already in Reminders" (repeat confirmations return the existing result as `added`) and "failed: not added yet" (unclear dates are clarified on screen instead).

### Original proposal (superseded by the existing tool)
Client tool `create_reminder`, **expects a response**, response timeout 120 s:
```json
{ "name": "create_reminder",
  "description": "Propose a reminder. The user reviews it on screen and decides; the result says whether it was really added.",
  "parameters": { "type": "object", "required": ["title"], "properties": {
    "title": { "type": "string", "description": "What to remind the user of, in their words." },
    "due":   { "type": "string", "description": "Local date 'YYYY-MM-DD' or local date and time 'YYYY-MM-DDTHH:MM' in the user's time zone. Leave empty if the user gave no time or you are unsure." } } } }
```
Prompt line: *"To set a reminder, call create_reminder. Only say it was added if the result starts with 'created'."*
Until this tool is added, voice simply can't propose reminders; **Remind me** works without it.

## Executed (Linux, Swift 6.2.3)
| Check | Result |
|---|---|
| `swift test` (DoddyCore) | **61 tests, 0 failures**, 12 new. Covers: strict due parsing incl. DST gap and past times, state machine edges, write-once + verified, empty title / past time rejected before storing, permission denied → nothing written → retry works, first-use access prompt, write error checked by marker, read-back mismatch ≠ success, crash recovery (written / lost / not started), due comparison across zones, voice tool parse + replies, SQLite round-trip + delete-all |
| Guard | PASS; a planted `import EventKit` outside the gateway fails it |
| App Swift files | parse |

## Not run
- Xcode compile.
- Real EventKit: permission prompt, write, read-back, marker search.
- The voice tool end to end.
- **On a device:** acceptance A-20 to A-23. Deny access → no reminder, draft kept. Force-quit right after "Add" → relaunch → correct state, no duplicate.

## Known limits
- Always the default Reminders list (no list picker yet).
- Searching by marker reads all reminders, which is fine for normal lists and slower for very large ones.
- No editing or deleting of reminders from Doddy, by design.
