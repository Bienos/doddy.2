# M4 — One reliable action: Apple Reminders (status)

Date: 2026-10-10. ADR-126. Milestone text: `MILESTONES.md` § M4; acceptance rows A-20 to A-23 in
`docs/quality/ACCEPTANCE_TESTS.md`.

**Status: code and Linux unit tests done. Native build and every device exit test are NOT RUN**
(no Xcode or iPhone in this environment). M4 is not exited until the device plan below passes on a
physical iPhone and the results are written into this file.

## What existed before M4 (V1 Connections, ADR-063)

- `create_reminder` voice tool → card with **Add** / **Don't add**; nothing written before the tap.
- Settings → Connections switch (off by default) and the iOS full-access Reminders permission,
  checked at the tap.
- Save to the default list, then an existence-only read-back (`calendarItem(withIdentifier:)`), and
  `added` / `unknown` / `failed` / `declined` replies for the agent.

## Gaps found and what M4 adds

| Gap (M4 bar) | Before | Now |
|---|---|---|
| No duplicates / idempotent recovery | None. A retried tool call (new id after the agent's 90 s timeout, or the user asking again) wrote a second reminder. | Before writing, Doddy reads the open reminders and skips the write if the same one is there: same **idempotency key** (stored in the reminder's URL field as `doddy://reminder/v1-<16 hex>`) or the same normalized title with the same due day and time. The key is FNV-1a 64 of the normalized title and the due wall clock; the tool call id is deliberately left out (a retry has a new id). |
| Recovery when a save's outcome is unknown | A throw from `save` was reported as `failed`. | A failed save is followed by a fresh read: found → `added` (verified); not there → `failed` with the reason; can't read → `unknown`. Asking again after `unknown` finds it by key, so nothing is added twice. |
| Verified write | Only "an item with that id exists". | Fresh read of the open reminders after the save; `added` only when the item with the new id has the same title, the same due day and time, the same zone (when both have one) and no other Doddy marker. Otherwise `unknown`. The receipt is built from what was read back, not from the draft. |
| Timezone / date clarification | `VoiceLocalDate` accepted past times, and silently turned a zone suffix like `18:30+02:00` into 18:00. Clock-change gaps were rejected as "not a date". | `ReminderDueRules` (DoddyCore): only `YYYY-MM-DD` or `YYYY-MM-DDTHH:MM` (optional `:SS`), local time, no zone. A bare time, a word, a zone suffix, Feb 31, a past time or day, a time the clocks skip (DST starts) or a time that happens twice (DST ends) is **not shown as a card**: the agent gets `failed: not added yet: <problem>. Ask the user <question>, then call create_reminder again…`. The time is checked again at the tap (it may have passed while the card waited). |
| Explicit time zone | Components built from `Calendar.current`, no zone on the reminder. | The draft carries the phone's zone id; a timed reminder is saved with that zone on its due components. A day-only reminder stays floating (as the Reminders app does for whole days). The card and receipt show the zone, e.g. `Mon 12 Oct 2026, 18:00 (Europe/Warsaw)`. |
| Receipt visible | Card disappeared on tap; only the agent's spoken reply. | A receipt card under the transcript: **Adding to Reminders…**, then **Added to Reminders** / **Already in Reminders** / **Not added** / **Couldn't confirm**, with title, day/time/zone and list name. It stays after the conversation ends (the agent may never hear the result if its wait timed out) until the user taps OK or starts a new conversation. |
| Denied permission | Card shown, tap → `failed`. | Checked when the agent proposes (no card; the access card "Allow Doddy to use Reminders?" asks for it in one tap, or offers iPhone Settings when iOS said no before, ADR-567) and again at the tap (switch and iOS). A denial at the tap shows **Not added** with the draft's title and time still visible, the access card, and `failed: Reminders isn't connected. Nothing was added.` |
| Timeouts | EventKit reads had no time limit. | Reading the open reminders gives up after 10 s. Before the write that means **Not added** (`failed`, nothing written); after the write it means **Couldn't confirm** (`unknown`). |
| Double tap | Already safe: the card is cleared before the first await. | Unchanged, plus the dedupe above covers a second card for the same reminder. |

## Outcomes

| Outcome (`ReminderOutcome`) | Screen headline | Agent reply starts with |
|---|---|---|
| `.added(receipt)` | Added to Reminders | `added: reminder "…" due 2026-10-12 18:00 (Europe/Warsaw).` |
| `.alreadyThere(receipt)` | Already in Reminders | `added: … was already in Reminders, so Doddy did not add it a second time.` |
| `.notAdded(.notAllowed)` | Not added | `failed: Reminders isn't connected. Nothing was added.` |
| `.notAdded(.couldNotCheck)` | Not added | `failed: the app couldn't read Reminders to check it isn't already there. Nothing was added.` |
| `.notAdded(.saveFailed(reason))` | Not added | `failed: <reason> Nothing was added.` |
| `.unknown` | Couldn't confirm | `unknown: the app could not confirm it was added…` |
| `.needsClarification(c)` | Not added (only if the time passed while the card waited) | `failed: not added yet: …` |

All prefixes are ones the live prompt already handles. The list name stays on the phone.

## Privacy

- New read: to avoid duplicates and to read back, Doddy reads **title, due, list name, completion
  and URL of every open reminder** on the iPhone (notes are not read). This stays in memory for the
  duration of one tap; it is not stored and not sent anywhere. The card says "Doddy checks your open
  reminders on this iPhone first, so it isn't added twice."
- The agent (ElevenLabs) receives only the title and due of the reminder Doddy wrote or found — the
  same text it proposed — and not the list name.
- Each reminder Doddy writes carries `doddy://reminder/<key>` in its URL field (visible in the
  Reminders app's details; tapping it just opens Doddy, `DeepLink` ignores it). The key is a hash of
  the title and due, not the title itself.

## Files

| File | Change |
|---|---|
| `Packages/DoddyCore/Sources/DoddyCore/ReminderAction.swift` | New. `ReminderDue`, `ReminderDueRules`, `ReminderClarification`, `ReminderIdempotency`, `ReminderWrite`, `ReminderSnapshot`, `ReminderStore` port, `ReminderMatching`, `ReminderAction.add` (look → write → read back / reconcile), `ReminderOutcome`, receipt and reply text. |
| `Packages/DoddyCore/Sources/DoddyCore/VoiceTools.swift` | `ReminderDraft.due` is now a `ReminderDue` (wall clock + zone); `create_reminder` parsing uses the strict rules; new `VoiceToolRequest.needsClarification`; old `reminderAdded` reply removed. Calendar parsing unchanged. |
| `DoddyApp/Infrastructure/Connections/DeviceConnections.swift` | Implements `ReminderStore` with EventKit: `incompleteReminders()` (10 s timeout), `save(_:)` (marker URL, explicit zone for timed dues). Old `addReminder` removed. |
| `DoddyApp/Features/Voice/VoiceSessionController.swift` | Permission check at proposal, clarification replies, `reminderStatus` receipt, `ReminderAction.add` at the tap. |
| `DoddyApp/Features/Voice/VoiceView.swift` | Card shows due with zone and the "checks first" line; receipt card. |
| `Packages/DoddyCore/Tests/DoddyCoreTests/ReminderActionTests.swift` | New, 23 tests (fake store with timeouts, write-then-throw, lost and altered read-backs). |
| `Packages/DoddyCore/Tests/DoddyCoreTests/VoiceToolsTests.swift` | Reminder parse/reply tests updated to the new draft. |
| `voice-agent/tools.json`, `voice-agent/instructions.md` | Wording for "already in Reminders" and "not added yet" results and the stricter `due` format. **Repo only: the owner must apply them to the live agent** (`voice_agent_spec.py elevenlabs`). The app works with the current live prompt too: every new reply uses an existing prefix. |

## Tests actually run (Linux, Swift 6.1.2, 2026-10-10)

- `swift test --package-path Packages/DoddyCore -Xswiftc -DSQLITE_DISABLE_SNAPSHOT` → 226 tests, 0
  failures (203 before this change; 23 new in `ReminderActionTests`). A deliberate mutation
  (skipping the look-before-write) made 10 of them fail, then was reverted.
- `swiftc -parse` on the three changed app files → OK. This is a syntax check only: the app target
  (EventKit, SwiftUI, ElevenLabs) is **not compiled** here.
- `scripts/check_forbidden_capabilities.sh` → PASS (EventKit still only in Connections).
- `python3 -I scripts/verify_imported_pack.py` → PASS. `python3 -I scripts/voice_agent_spec.py check` → PASS.

## Device test plan (M4 exit; all NOT RUN)

Record device, iOS version, account type (iCloud or local Reminders) and the result of each.

1. **Happy path.** Turn Reminders on in Connections, allow access. "Remind me to buy milk tomorrow at
   6pm" → card shows `… 18:00 (<zone>)` → Add → receipt **Added to Reminders** with list name → the
   Reminders app has exactly one "Buy milk" due tomorrow 18:00. Note whether the URL field shows the
   `doddy://reminder/…` marker (if iOS drops it, dedupe still works by title and due; record it).
2. **It actually alerts.** Wait for the due time with Doddy closed. Record whether iOS notifies. If
   it does not, the owner decides whether to add an alarm at the due time (not built).
3. **Day-only.** "Remind me to pay rent on the 31st" → day-only reminder, no time, receipt without zone.
4. **Denied permission.** iOS Settings → Doddy → Reminders off (or Don't Allow at first prompt) →
   asking for a reminder shows no card; the access card appears with **Open iPhone Settings**;
   nothing in Reminders. Then revoke while a card is waiting → Add → **Not added**, title/time still
   on screen, agent says it wasn't added.
5. **Switch off.** Connections switch off → no reminder card; the access card "Allow Doddy to use
   Reminders?" appears and the agent says "Allow it on screen and I'll carry on"; nothing written.
   Tap Allow (iOS asks first if it never has) → the agent asks for the reminder again on its own,
   and its card appears (ADR-567).
6. **Double tap.** Tap Add twice quickly → one reminder.
7. **Asked again.** After a successful add, ask for the same reminder again (same title and time,
   different wording/case) → card → Add → **Already in Reminders**; still one reminder. Same title
   at another time → a second reminder (expected).
8. **Agent timeout.** Let the card wait more than 90 s, then Add → reminder written and receipt
   shown even if the agent no longer reacts; ask again → **Already in Reminders**.
9. **Airplane mode.** Repeat 1 with airplane mode on during the tap (EventKit is local; the voice
   session will likely drop first). Record what happens and that no duplicate appears after
   reconnecting and asking again.
10. **Relaunch mid-write.** Tap Add and immediately force-quit Doddy (several tries). Reopen, ask for
    the same reminder → exactly one in Reminders.
11. **Clarifications.** "Remind me at 6" (no day), "remind me yesterday at 5", a time already passed
    today → the agent asks a question; no card, nothing written. Clock-change times (e.g. 2026-10-25
    02:30 in Europe/Warsaw) are covered by unit tests; on device, check the agent asks rather than adds.
12. **Time passes on the card.** Ask for a reminder 1–2 minutes ahead, wait until it passes, then Add
    → **Not added** "That time has already passed".
13. **No default list / read-only list.** If reproducible, the receipt says Reminders didn't save it.
14. **Large Reminders library.** Many open reminders: the check finishes well within 10 s.
15. **Time zone.** Change the iPhone's time zone, ask for a reminder → the card and receipt name the
    new zone; the Reminders app shows the expected time.

## Known limits

- Dedupe also skips a reminder the user made themselves with the same title and due (the receipt
  says "Already in Reminders"). An intentional exact duplicate has to be made in the Reminders app.
- Notes are not part of the key (the same reminder with different notes counts as the same).
- `calendarItemIdentifier` can change after an iCloud sync; Doddy only uses it right after the save.
- The receipt lives in memory; after a relaunch it is gone (the reminder itself is in Reminders).
- The M0 `ToolExecutor`/`ActionReceipt` ports are not used by this path; `ReminderStore` +
  `ReminderAction` replace them for Reminders.
- Fixed after M4 (ADR-127): `VoiceLocalDate.parse` read `2026-10-12T18:30+02:00` as 18:00 for
  `create_calendar_event` and `read_calendar`. It is gone; events follow the reminder rules,
  including "not already passed" (ADR-128), `read_calendar` uses `ReminderDueRules.wallClock` (no
  past check), and an event time that can't be read as meant, or has passed, is
  sent back to the agent as `failed: not added yet …, then call create_calendar_event again…`.

## Decisions for the owner

1. Accept that duplicates are detected by title + due (not only Doddy's own marker), including the
   user's own reminders (ADR-126).
2. Accept the URL-field marker being visible in the Reminders app.
3. Apply the `voice-agent/` prompt and `create_reminder` wording to the live agent.
4. After device test 2: add an alarm at the due time or not.
