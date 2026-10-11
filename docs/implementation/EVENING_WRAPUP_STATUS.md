# Evening wrap-up: status (ADR-256)
Date: 2026-10-11. Owner: "do all of them" (item 7).

## What ships
- **Settings › Evening wrap-up:** off by default; a time (21:00 to start with); "Open the wrap-up now". The setting is read back from iOS's pending notifications ("Set …", or why not).
- **The notification:** "Good evening · Anything to move to tomorrow?" (Polish: "Dobry wieczór · Coś przenieść na jutro?"). Nothing personal is on the Lock Screen.
- **The screen:**
  - the open reminders in the Reminders app that are due today or earlier, oldest first, at most 30;
  - undated reminders aren't offered, because moving them would give them a date they never had;
  - read on this iPhone only, with Reminders on in Connections and Pause all off; otherwise the screen says what to turn on.
- **Moving:** none is ticked to start with. **Move N to tomorrow** moves only the ticked ones:
  - each keeps its time, and a day-only reminder stays day-only;
  - "tomorrow" is the day after now, so an old overdue reminder also lands tomorrow;
  - written with `DeviceConnections.changeReminder(_:_:)` (ADR-229): only if the reminder still looks exactly as shown; an alarm at the old time moves with it; then it's read back;
  - a time the clocks skip or repeat tomorrow isn't guessed; that reminder stays and is counted as not moved.
- **The receipt:** "Moved 3 to tomorrow. Checked in Reminders.", or how many couldn't be moved and to check them in Reminders. The list reloads afterwards.
- Nothing is sent anywhere. No streaks, scores or reminders to do the wrap-up.

## Files
- **Core:** `EveningWrapUp.swift` (`EveningWrapUpSettings`, `EveningWrapUp.movable`, `EveningWrapUp.tomorrow`, notification words).
- **App:** `Features/EveningWrapUp/EveningWrapUpViews.swift` (scheduler, screen, settings section); `ShortcutRouter` (`isWrapUpPresented`, `eveningWrapUpOpened()`); `RootView` (sheet); `NoteReminderNotifications` (tap routing); `DoddyApp` (re-applies the notification's words at launch); `SettingsView`.
- **Polish:** 14 lines in `l10n/pl.json`.
- **Tests:** `EveningWrapUpTests` (4).

## Verified (Linux)
- `EveningWrapUpTests` pass (4), including a time Poland's clocks skip on 2027-03-28. `swiftc -parse` on the new and changed app files.

## NOT RUN
- No Xcode build; never run on a device. The notification, its tap routing and the move have never touched iOS or real Reminders data.
- Not known: how the Reminders app shows a reminder whose due Doddy moved but whose recurrence rule (a repeating reminder) stays; repeating reminders are moved like any other, this occurrence only as EventKit decides.

## Constitution evidence log
| Rule | Enforcing code | Tests | Gaps |
|---|---|---|---|
| DOD-07 scoped_action_approval | Nothing preselected; only ticked reminders move, each only if unchanged | `testOnlyOpenRemindersDueTodayOrEarlierAreOfferedOldestFirst` | UI not compiled |
| DOD-08 verified_status_and_receipts | Receipt counts only read-back moves; the rest are named as not moved | — | Not run on a device |
| DOD-09 correction_and_recovery | A clock-change time isn't guessed; failures say to check Reminders | `testATimeTheClocksSkipTomorrowIsNotGuessed` | — |
| DOD-10 nonmanipulative_companionship | Off by default; the notification asks, never nags; no streaks | `testSettingsAreOffByDefaultAndTheNotificationSaysNothingPersonal` | — |
| DOD-11 observable_privacy | Reads Reminders on the phone only, with the switch on and not paused; nothing sent | — | — |
