# Repeating reminders and snooze status (ADR-211)
Date: 2026-10-10. Owner instructions:
- "yes design repeating reminders and snooze";
- then "approved, build it", which approves decisions R1–R4 as proposed.

Design: Doddy Notifications canvas, screens 15–21 and the rules board; `docs/design/NOTE_REMINDERS.md` → "Repeating reminders and snooze". Builds on note reminders (ADR-190), place reminders (ADR-196) and voice reminders (ADR-198).

## What ships
**Repeat (time reminders only)**
- **Repeat** on the sheet: Never, Every day, Weekdays, Every week on the chosen weekday, Every month on the chosen day.
  - Every month is offered only for days 1–28 (R1). Otherwise the sheet says why.
- The summary shows what will really happen: "Every Monday at 20:00 · Warsaw time · first on Mon 12 Oct, 20:00 · until you stop it".
  - A repeat starts at its next matching time. iOS repeating requests can't start later than that, so a weekly repeat picked three weeks ahead starts next week, and the summary says so.
- It fires at the same clock time in the zone it was set in, across clock changes. This is tested for 25 Oct 2026.
- **iOS requests:**
  - One repeating request per rule; weekdays uses five (`….w2`–`….w6`).
  - The 50 limit now counts iOS slots (R2). Settings shows "n of 50".
- **The note's card:** "Repeating reminder", the rule and zone, Next …, and "Done this time on …".
  - **Stop repeating** asks "Stop reminding you every Monday?" (Stop / Keep it). It's only offered on the note.
- **Done this time** (Lock Screen and Home) records `last_done_at`. Home's Due card clears until the next occurrence; the repeat stays.
- **Lock Screen title** is "Reminder · every Monday" (R3). The body stays private by default.

**Snooze**
- **Lock Screen actions:**
  - One-off: Open note, **In 1 hour**, Tomorrow 09:00, Done.
  - Repeating: Open note, In 1 hour, Done this time. There's no Tomorrow 09:00 (R4) and no Stop.
  - Place: Open note, Done.
- **Home's Later…:** In 1 hour, This evening (18:00, only before 17:00), Tomorrow morning, and Pick a time…, which opens the note.
- **What a snooze changes:**
  - A one-off moves to the new time and keeps "First set for …".
  - A repeat counts this time as handled, gets one extra request (`….snooze`), and keeps repeating.
- **Checking:** a snooze is checked like setting a reminder. If iOS refuses the new time, the reminder is unchanged and the receipt says "Couldn't move it. Your reminder is unchanged." A snooze from the Lock Screen shows its result the next time the note opens.

**Voice**
- `remind_me_about_note` gains `repeat` (daily, weekdays, weekly, monthly), only with `due`.
  - A place can't repeat. An unknown value is refused.
  - Monthly after the 28th goes back to the agent as a question; no card is shown.
- The card shows "Every Monday at 20:00", the zone, and the real first time.
- The reply says "every Monday at 20:00 (Warsaw time), first on …, until the user stops it on the note".
- Voice can't stop a repeat.

## Files
- **Core:** `NoteReminders.swift`.
  - Adds `ReminderRepeat`, `RepeatMatch`, `ReminderSchedule` (matches, next, previous, first occurrence, the 1–28 rule) and `NoteReminderCategory`.
  - `NoteReminderNotification.requests`.
  - On `MemoryReminder`: `repeats`, `lastDoneAt`, `snoozedUntil`, `firstSetFor`, `requestSlots`, `nextFire`, and repeat-aware `isDue`.
  - Coordinator: repeat scheduling, `markDone`, `snooze`, `snoozeForAnHour`, slot limit, reconcile of every request.
- **Voice core:** `NoteReminderVoice.swift`, `ActivityLog.swift`.
- **Persistence:**
  - Migration `v5_note_reminder_repeat`: new columns with CHECKs. A repeat is time-only, done and snooze need a repeat, and "first set for" is for one-offs only.
  - `SQLiteNoteReminderRepository.swift`.
- **App:**
  - `NoteReminderNotifications.swift`: repeating trigger, three categories, In 1 hour.
  - `NoteReminderStore.swift`: snooze, done, slots, messages.
  - `NoteReminderSheet.swift`: repeat picker.
  - `NoteReminderViews.swift`: card, Stop repeating, receipt wording, Home's Later menu, Settings count.
  - `VoiceSessionController.swift` and `VoiceView.swift`.
- **Agent:**
  - `voice-agent/tools.json` and `README.md`.
  - The live tool `tool_7401m4k84jjgf1ctk26vj03kextq` was updated in place. The prompt and the agent's tool list are unchanged.
- **Tests:** `NoteReminderRepeatTests.swift` (new, 12 tests) and `NoteReminderVoiceTests.testRepeatArgumentIsCheckedBeforeAnyCard`.

## Verified (Linux, Swift 6.2.1)
- **361 package tests** pass.
- **New repeat and snooze tests:**
  - matches and next occurrence across the 25 Oct clock change;
  - start at the next matching time, and the 1–28 rule;
  - wording and identifiers;
  - a weekly repeat is one verified repeating request with "Reminder · every Monday" and a private body;
  - weekdays uses 5 slots, and the limit counts slots;
  - monthly on the 30th is refused;
  - Done this time keeps the repeat and clears Due until the next one, while a one-off's Done deletes it;
  - snoozing a repeat adds one extra request, which is reconciled and cleared by Done, and Stop removes every request;
  - a snoozed one-off moves and remembers its first time;
  - a refused snooze leaves the repeat unchanged;
  - places have no snooze, and SQLite refuses a repeat on a place;
  - the new fields survive a save and read.
- **Earlier tests still pass,** including the upgrade from a real v3 database file, which now runs through v5.
- **Live tool:**
  - ElevenLabs echoed the update back with the description and `repeat` parameter I sent, which were generated from `tools.json`.
  - `voice_agent_spec.py compare` reports no drift for this tool. That run used an export built from the spec text, not the live response, so it's a weaker check.
- `scripts/ci.sh --core-only` and `swiftc -parse` on every app Swift file: see the commit for this change.

## NOT RUN / UNVERIFIED (needs a Mac and an iPhone)
- **App compile.** Likely problem spots:
  - the `Picker` over an optional `ReminderRepeat`;
  - `Menu` inside the Due card;
  - `confirmationDialog` on the note section.
- **On a device:**
  - that a repeating `UNCalendarNotificationTrigger` with weekday or day fires as matched, and keeps firing after Done this time;
  - R5: a repeat set inside the clock-change hour (02:00–02:59, last Sunday of March);
  - the Lock Screen actions per category;
  - In 1 hour from the Lock Screen while Doddy is closed;
  - Home's Later menu;
  - VoiceOver on the new controls.
- **Agent:** using `repeat` correctly in Polish and English is not evaluated.

## Constitution evidence log (docs/trust/config/doddy_rules.yaml)
| Rule | What enforces it here | Tests run (Linux) | Gaps / claims to limit |
|---|---|---|---|
| DOD-07 scoped_action_approval | Nothing repeats until the user taps Set reminder on a sheet or voice card showing the rule, the zone and the real first time. Voice `repeat` is validated in typed code (`parseNoteReminder`). Stop repeating asks first. | `testRepeatArgumentIsCheckedBeforeAnyCard`, `testMonthlyAfterThe28thAndRepeatsTooSoonAreRefused` | Sheet and dialog UI not exercised (no Xcode). |
| DOD-08 verified_status_and_receipts | Set and snooze count only once every iOS request is listed as pending; a refused snooze restores the row. Receipts say "Moved to …" or "Couldn't move it. Your reminder is unchanged." | `testWeeklyRepeatIsOneVerifiedRepeatingRequest…`, `testRefusedSnoozeLeavesTheRepeatUnchanged`, `testSnoozingAOneOffMovesItAndRemembersTheFirstTime` | Pending ≠ delivered. Whether a repeat actually fires is device-only. |
| DOD-09 correction_and_recovery | Done this time keeps the repeat. Change and Stop are on the note. Reconcile re-adds missing repeat and snooze requests and removes stale ones. The migration keeps existing reminders. | `testDoneThisTimeKeeps…`, `testSnoozingARepeatAdds…`, upgrade-from-v3 test | No device test of reboot or restore. |
| DOD-10 nonmanipulative_companionship | Repeats only when the user picks one. No streaks, badges or "you missed" messages. "Done this time" never nags. The title shows the schedule, never the note. | — (no automated check) | A repeat continues until stopped, by design; there's no auto-expiry. |
| DOD-11 observable_privacy | Everything stays local: no server, no new data leaves the phone. The body stays private by default. | Private-body assertion in `testWeeklyRepeatIsOne…` | The Lock Screen title reveals the schedule ("every Monday"), as approved in R3. |
| DOD-06 user_controlled_relevant_memory | A repeat belongs to one note and is deleted with it (cascade, unchanged). | Existing cascade tests | Repeats and snoozes are not in the export. |

## Open
1. Polish copy for the new strings (decision D6 still open).
2. R5 device check (clock-change hour).
3. A "last day of the month" option was declined (R1); revisit only if asked.
