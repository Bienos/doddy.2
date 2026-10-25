# Reminders that ring like an alarm, the weekly plan, quiet hours (ADR-651)

Date: 2026-10-24. Owner (24 Oct, in Polish, after `docs/product/NOTIFICATION_IDEAS.md`): build "ring like an alarm" (A5), then the weekly plan (B1); quiet hours yes; a notification "out of nowhere" is limited, but a timer or anything that is an action item always shows. Follows ADR-650 (`NOTIFICATIONS_AND_TIMERS.md`). **Not compiled with Xcode; not seen on a device.**

## What comes when (the rule, in one place)

| Kind | Examples | When it may come |
|---|---|---|
| Action items | Timers, alarms, Apple Reminders, Doddy's reminders on notes, time to leave, before an event, focus done, an errand done | Always, at any hour. Nothing in ADR-651 touches them. |
| Routines the user turned on | Morning check-in, evening wrap-up, weekly plan, weekly look-back, tidy-up | At the time picked, never 22:00–07:00. A time in those hours moves to 07:00 (morning) or 21:30 (evening), in the time picker as well, so Settings shows where it really goes. |
| Doddy's own tips | Today only "Open Doddy faster" (ADR-559) | Never on a day a routine already comes; a week with a routine every day gets no tip. So Doddy says at most one thing a day on its own. |

Birthdays (09:00 on the day, people the user picked) are a routine the user set up and are unchanged.

## A5: Ring like an alarm

- **Where:** the reminder sheet on a note ("Ring like an alarm" switch, under Repeat) and the voice card for `remind_me_about_note` (the same switch). Shown only where AlarmKit can ring (iOS 26, alarms not refused). Monthly and place reminders can't ring; the switch is greyed out and says why.
- **What happens:** the note reminder is unchanged (its notification with Open note, In 1 hour and Done, Home's "Due now", the database row). In addition an AlarmKit alarm rings at the same moment, through Silent mode and a Focus, with Stop and "In 10 min" (the alarm's own snooze). One-off: `.fixed(date)`; every day, weekdays or every week: AlarmKit's weekly repeat at the reminder's clock time.
- **Kept in step:** `RingingReminderSync` (DoddyCore) runs on every `NoteReminderStore.reload()`: a new time (In 1 hour, a new date) moves the alarm, Done or deleting the note ends it, a missing alarm is set again, a changed note or "Show note text" setting re-sets it with the new words. An unreadable AlarmKit list touches nothing; a one-off that has passed is left alone, so a snoozed alarm keeps ringing.
- **The ringing screen's words:** the note's first line only with "Show note text in notifications" on (as the notification, ADR-190); otherwise "Przypomnienie" / "Reminder".
- **Said only when true:** the note shows "Rings like an alarm, even in Silent mode" only when AlarmKit lists the alarm; otherwise "Set to ring like an alarm, but the iPhone hasn't confirmed the alarm…". The voice reply says it rings only when confirmed (`noteReminderRingLine`).
- **Kept on the phone:** which notes want ringing and their alarm ids, in UserDefaults (`noteReminders.ringing`). Not in the encrypted backup: after a restore the reminder comes back as a notification, and the switch can be turned on again.
- **Voice:** `remind_me_about_note` has an optional `ring` in `voice-agent/tools.json` and a line in `instructions.md`. **The live ElevenLabs agent is not changed**; until it is, the agent can't send `ring`, and the user turns the switch on on the card. The OpenAI voice reads the bundled spec, so it has `ring` with the next build.

## B1: The weekly plan

- **Settings › Check-ins and reminders › Weekly plan:** off by default; Monday 08:00 to start; day and time; "Open the plan now". Read back from iOS like the look-back.
- **The notification:** "Nowy tydzień · Zerknąć, co Cię czeka?" ("New week · Take a look at what's coming?"). No names, no counts: nothing private on the Lock Screen, and nothing that can be out of date when it arrives (iOS doesn't promise the app time to refresh it). No sound, never through a Focus, never in quiet hours.
- **The screen ("Your week ahead"):** the next seven days from today, day by day, built when it opens: Calendar events and Apple Reminders due (each only when its connection is on, and the screen says when one is off), Doddy's reminders on notes (every time a repeat fires; a private note shows as "A private note"), and the birthdays of the people picked in Settings › Birthdays. Untimed things first, then by time; more than 8 on a day shows "And N more". Overdue reminders aren't repeated: the plan is what's ahead.

## Files

- **DoddyCore:** `RingingReminders.swift` (`ReminderRing`, `ReminderRingPlan`, `RingingReminderEntry`, `RingingReminderSync`), `WeeklyPlan.swift` (`WeeklyPlanSettings`, `WeeklyPlan`), `QuietHours.swift` (`QuietHours`, `OwnNotificationDays`), `RingingTimers.swift` (`DoddyNotificationKind.weeklyPlan`), `MorningCheckIn.swift` (requests use quiet hours), `NoteReminderVoice.swift` (`rings`, `noteReminderRingLine`), `NotificationBudget.swift` (comment). Tests: `RingingRemindersTests` (17), `WeeklyPlanTests` (7), `QuietHoursTests` (5).
- **App:** `Features/Alarms/ReminderRinger.swift` (new), `Features/WeeklyPlan/WeeklyPlanViews.swift` (new: scheduler, screen, settings), `Features/NoteReminders/NoteReminderStore.swift` (sync on reload, `ringing`, `noteText`), `NoteReminderSheet.swift` (switch), `NoteReminderViews.swift` (label), `Features/Voice/VoiceSessionController.swift` and `VoiceView.swift` (card switch, reply), `App/DoddyApp.swift` (note text for titles), `Infrastructure/ShortcutRouter.swift` and `App/RootView.swift` (the plan's sheet), `Infrastructure/Connections/NoteReminderNotifications.swift` (the plan's tap), `App/LaunchWork.swift`, `Features/Settings/SettingsScreens.swift` (the plan's section and the rule in one sentence), the four routine schedulers and time pickers (quiet hours), `Features/Setup/OpenWaysReminderScheduler.swift` (tip days).
- **Shared:** `Shared/Alarms/DoddyAlarmMetadata.swift` (`Kind.reminder`).
- **Spec and text:** `voice-agent/tools.json`, `voice-agent/instructions.md`, `l10n/pl.json` (21 lines), regenerated catalogs, `scripts/typecheck_app_logic.sh` (adds `ReminderRinger.swift`).

## Verified (Linux, Swift 6.1.2)

- DoddyCore: the full suite (see ADR-651 for the count), with the 29 new tests.
- `scripts/typecheck_app_logic.sh`: `ReminderRinger.swift` (outside `#if canImport(AlarmKit)`), `NoteReminderStore.swift` and `ShortcutRouter.swift` type-check in Swift 6.
- Capability guard, string catalogs, voice agent spec.
- Found on the way: adding a method to the `NoteReminderCoordinator` actor made the Linux test binary crash in `swift_getErrorValue` (Swift 6.1.2), in a test that never called it; the method was dropped and the note text comes from `MemoryStore` instead. Not investigated further.

## NOT RUN

- No Xcode build: the AlarmKit code, the SwiftUI screens and switches, and the wiring are uncompiled until the hosted Mac job.
- No device. Checklist (iOS 26):
  1. On a note: Remind me › tomorrow 08:00 › Ring like an alarm › Set. Silent mode on, phone locked: at 08:00 the alarm screen rings with Stop and Za 10 min, and the notification arrives too.
  2. The note says "Rings like an alarm, even in Silent mode". Tap Za godzinę on the notification: the alarm moves to 09:00. Mark it Done: no alarm is left (Settings › Alarms doesn't list reminder alarms; check the Clock/Lock Screen).
  3. Every day at 08:00 with ringing: it rings each day; "Done this time" leaves tomorrow's.
  4. Every month: the switch is greyed out and says why.
  5. "Show note text" off: the alarm says "Przypomnienie"; on: the note's first line.
  6. By voice (OpenAI voice, or the live agent once synced): "Przypominaj mi codziennie o 8 o lekach i niech zadzwoni": the card shows the switch on; the reply says it rings only after it was confirmed.
  7. Settings › Weekly plan on, Monday 08:00: the notification "Nowy tydzień" comes with no sound; tapping it opens Your week ahead with events, reminders, Doddy's reminders and birthdays on their days.
  8. Evening wrap-up at 22:30: the picker jumps to 21:30.
  9. Morning check-in every day on: the "Open Doddy faster" tip never comes.
- The Polish lines are agent-written.

## Live agent (applied 24 Oct 2026)

Tool `remind_me_about_note` (`tool_7401m4k84jjgf1ctk26vj03kextq`) on the live ElevenLabs agent now has the boolean `ring` and the added last sentence of its description, exactly as in `voice-agent/tools.json` (owner: "2 tak"; version `agtvrsn_9201m5q7ka50e5gbbrg1cftrt2zk`, rollback `agtvrsn_4701m5q787a7e9kvp21qvjza63t0`). The prompt sentence planned for the `remind_me_about_note` line was not added: the live prompt has no such line, and the tool description carries the rule. Record: `voice-agent/README.md`. Not checked: a real conversation asking for a ringing reminder.

## Constitution evidence log

| Rule | Enforcing code | Tests run | Gaps |
|---|---|---|---|
| DOD-07 scoped_action_approval / ASK-01 | Ringing is a switch on the card, set only at Set reminder; the agent's `ring` only pre-sets it | `testTheAgentCanAskForARingButOnlyAsAProposal` | UI not compiled |
| DOD-08 verified_status_and_receipts | "Rings" only when AlarmKit lists the alarm on the current plan (`isRinging`); the reply says so only then | `testAnAlarmAlreadyOnThePlanIsLeftAlone`, `testTheReplySaysRingingOnlyWhenTheAlarmIsConfirmed` | AlarmKit never read on a device |
| DOD-09 correction_and_recovery | A new time moves the alarm, Done ends it, a missing one is set again, an unreadable list touches nothing | `testANewTimeMovesTheAlarm`, `testDoneOrDeletedTurnsTheAlarmOffAndForgetsTheWish`, `testAMissingAlarmIsSetAgain`, `testAnUnreadableAlarmListTouchesNothing` | — |
| DOD-10 nonmanipulative_companionship | Routines never in quiet hours; Doddy's own tip never on a routine day; the plan has no counts, streaks or scores | `QuietHoursTests` | — |
| DOD-11 observable_privacy | The alarm and the plan's notification show no note text or names unless "Show note text" is on (the plan never); ringing wishes stay on the phone | `testTheRingingScreenShowsTheNoteOnlyWhenTheUserAllowsIt`, `testTheNotificationNamesNothing` | Polish lines not reviewed |

Claims to limit: don't say "reminders ring like an alarm" or "the weekly plan works" until checklist rows 1 and 7 pass on a device.
