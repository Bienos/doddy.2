# Repeating events and reminders by voice: status (ADR-282)
Date: 2026-10-11. Owner: "do all of them" (round 3, item 3).

## What ships
- **Voice:** `create_calendar_event` and `create_reminder` take two new arguments:
  - `repeat`: `daily`, `weekdays` (Monday to Friday), `weekly`, `every_two_weeks`, `monthly` or `yearly`;
  - `repeat_until`: a day (YYYY-MM-DD), not before the first date.
  The weekday or day of the month comes from the first date, as in Calendar, so "every Monday at 7" is a weekly event whose start is a Monday.
- **The card:** "Repeats every week until Thu 31 Dec 2026" under the time. Nothing is added until Add.
- **Writing:** one `EKRecurrenceRule` on the event (saved for future events) or the reminder. The end is the end of the last day, in this iPhone's time zone.
- **Reading back:** "added" needs the rule to read back the same. A rule Doddy doesn't write, two rules, or none doesn't confirm, and the agent hears "unknown". For reminders, this is part of `ReminderMatching.confirms`.
- **Limits:**
  - a reminder repeat needs a due;
  - an unknown `repeat` or an end before the first date is refused, and the agent asks again.
- **Plans:** editing a plan step keeps its repeat, which can't be changed on the form.
- **Not Doddy's note reminders:** these are Calendar's and Reminders' own repeats. Note reminders keep their own rules (ADR-200).

## Files
- **Core:** `CalendarRepeat.swift`; `VoiceTools.swift` (parsing, `CalendarEventDraft.repeats`, reply); `ReminderAction.swift` (`ReminderDraft`, `ReminderWrite`, `ReminderSnapshot`, `ReminderReceipt` and `confirms` gain the repeat); `ActivityLog.swift`; `PlanEdit.swift`.
- **App:** `DeviceConnections` (rule, read-back, reminder snapshot); `VoiceView` (card line, `repeatText`).
- **Agent spec:** `tools.json` and `instructions.md`.
- **Tests:** `CalendarRepeatTests` (4).

## Verified (Linux)
- `CalendarRepeatTests` pass, with the voice-tool, plan, reminder and activity tests.

## NOT RUN
- No Xcode build, and never run against Calendar or Reminders.
- Not known: whether EventKit reads back a weekly rule with `daysOfTheWeek` nil or set to the first date's day. Both are accepted.
- Not known: whether iCloud or Exchange calendars keep the end exactly. Only the day is compared.

## Constitution evidence log
| Rule | Enforcing code | Tests | Gaps |
|---|---|---|---|
| DOD-07 scoped_action_approval | The repeat is on the card; added only on Add | `testAnEventCanRepeatUntilADay` | UI not compiled |
| DOD-08 verified_status_and_receipts | "added" only when the same rule reads back | `testReadBackConfirmsOnlyTheSameRule` | Not run on a device |
| DOD-09 correction_and_recovery | An edited plan step keeps its repeat instead of silently dropping it | `testAPlanStepKeepsItsRepeatWhenEdited` | — |
