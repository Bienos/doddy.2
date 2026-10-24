# Notifications that ring: timers, reminders, the Lock Screen (ADR-640)

Date: 2026-10-24. Owner (24 Oct, in Polish): timers and reminders make no sound at all; setting a timer ("stoper") and the Lock Screen notifications should work properly and not stutter; check everything; and think up other notifications (for example once a week), with examples of what they would say. The ideas are in `docs/product/NOTIFICATION_IDEAS.md`.

Everything below was found by reading the code. **Nothing here has been compiled with Xcode or seen on a device.**

## What was wrong

| # | What the user got | Why |
|---|---|---|
| 1 | A voice reminder ("remind me at 15:30 to call Mum") never alerted: no sound, no banner, nothing on the Lock Screen | `create_reminder` writes to Apple's Reminders app. `DeviceConnections.save` set the due date and time but **no `EKAlarm`**. Reminders lists such a reminder under its day and never alerts. (`changeReminder` already moved an alarm when the time changed; creation never added one.) |
| 2 | A voice timer was quiet | It was an ordinary local notification with the short default sound: in Silent mode it only vibrates, a Focus holds it back completely, and the scheduled summary can delay it. Nothing showed the time left. |
| 3 | Doddy's own reminders (on notes), "time to leave", "before this event" and "focus done" didn't get through a Focus | Interruption level `.active` (iOS's default). |
| 4 | A banner that came while Doddy was open disappeared from the Lock Screen and Notification Center | `willPresent` returned `[.banner, .sound]` without `.list`. |
| 5 | "Timer done" and "Focus done" in English on a Polish iPhone | Hard-coded English. |

"Stoper": Doddy has no stopwatch that counts up. "Nastaw stoper na 10 minut" means a countdown, which is `set_timer`; that is what this change fixes. A real stopwatch is a proposal (`NOTIFICATION_IDEAS.md`, B6).

"Zacina się" (the Lock Screen stutters): the timer's countdown on the Lock Screen and in the island is `Text(timerInterval:)`, which iOS draws and ticks itself, with no updates from the app, so the app can't make it stutter. The voice island's queued updates were ADR-604 (merged in #134).

## What changed

- **Timers ring like the Clock app's timer (iOS 26).** `set_timer` still needs the Start tap. At the tap, `DeviceConnections.scheduleTimer` hands the timer to AlarmKit (`Features/Alarms/TimerRinger.swift`): it rings through Silent mode and a Focus with Stop and Repeat (Repeat runs the same length again), and its Live Activity shows the label, the time left, **Pause/Resume** and **Stop** on the Lock Screen and in the Dynamic Island (`DoddyWidgets/AlarmLiveActivity.swift`, buttons in `Shared/Alarms/DoddyTimerIntents.swift`). iOS asks once to allow alarms and timers, at the first Start.
  - AlarmKit gets the UUID that was already in the timer's identifier (`TimerIdempotency.alarmID`), so "started" still comes only from reading the timer back (ADR-320), now from AlarmKit's list.
  - **Fallback:** iOS older than 26, or alarms refused, or AlarmKit failed and doesn't list it: the notification as before, now Time Sensitive and in Polish or English. A timer is never set twice.
  - The agent hears how it rings ("It rings like the Clock app's timer, even in Silent mode or a Focus" or "It comes as a notification: in Silent mode it only vibrates"), so Doddy never promises a ring the iPhone won't make. The Start card says "It rings even in Silent mode or a Focus…" only when that is true.
  - A timer no longer needs notification permission when AlarmKit can ring it (`timerAccess()`).
- **Apple Reminders alert again.** A reminder with a time gets one alarm at that time (`ReminderWrite.alertDate`), as the Reminders app does itself. A whole-day reminder gets none (Reminders' own "Today" notification covers those). Moving the time of a reminder that has no alarm at all (one an older Doddy wrote) adds one (`ReminderAlert.addOnMove`); a reminder's own alarm still moves with it.
- **Time Sensitive for what the user set for a moment:** timers (fallback), note reminders, time to leave, before-an-event nudges and focus done. Doddy's routines (morning, evening, weekly look-back, tidy-up, birthdays, "open Doddy faster") stay `.active` and never push through a Focus; the evening, weekly and tidy-up ones stay silent as before. One table for all of it: `DoddyNotificationKind` (DoddyCore). The entitlement `com.apple.developer.usernotifications.time-sensitive` is in the four app entitlement files of `project.yml`. `project-iphone.yml` (free team) has no entitlements, so there iOS treats Time Sensitive as an ordinary notification.
- **Banners while Doddy is open** stay in Notification Center and on the Lock Screen afterwards (`.list`).
- **Words:** timer and focus notifications in Polish or English (`TimerCopy`), like the other notifications (ADR-213). The alarm permission prompt now names timers too ("…an alarm or a timer only when you ask and tap Set alarm or Start…"), in all ten languages (the nine translations machine-drafted).

## How each one comes through now

| What | Sound | Silent mode | A Focus | Lock Screen |
|---|---|---|---|---|
| Timer, iOS 26 (AlarmKit) | Alarm sound until Stop | Rings | Rings | Countdown with Pause/Resume and Stop; full-screen when it rings |
| Timer, older iOS or alarms refused | Default notification sound | Vibrates only | Gets through where Time Sensitive is allowed | Banner, stays in Notification Center |
| Alarm (`set_alarm`, unchanged) | Alarm sound | Rings | Rings | System alarm screen; Snooze countdown |
| Apple Reminders reminder with a time | Reminders' alert | Vibrates only | As Reminders is set in the Focus | Reminders' banner |
| Note reminder, time to leave, before an event, focus done | Default sound | Vibrates only | Gets through where Time Sensitive is allowed | Banner |
| Morning check-in, birthdays, open Doddy faster | Default sound | Vibrates only | Held | Banner |
| Evening wrap-up, weekly look-back, tidy-up | None | — | Held | Banner |

Silent mode silences every app's notifications; only alarms and timers (AlarmKit) and Critical Alerts (an Apple entitlement for health and safety apps, not asked for) ring through it.

## What is kept, and where

- For each AlarmKit timer: its identifier (with the idempotency key), ring time and label, in this iPhone's UserDefaults (`timers.ringing`), only to find it again. Dropped once AlarmKit no longer lists it (10 minutes' grace, as for alarms). Nothing new leaves the phone. Settings › Connections › Timers says so.
- The timer's label shows on the Lock Screen and in the island, as the focus timer's label already did: it is the user's own words for that timer.

## Files

- **DoddyCore:** `RingingTimers.swift` (new: `TimerRing`, `RingingTimer`, `RingingTimerBook`, `TimerIdempotency.alarmID`, `NotificationUrgency`, `DoddyNotificationKind`, `TimerCopy`), `TimerAlarmActions.swift` (`PendingTimer.ring`), `VoiceTools.swift` (`timerAdded(…ring:)`), `ReminderAction.swift` (`ReminderWrite.alertDate`, `ReminderAlert`). Tests: `RingingTimersTests`.
- **App:** `Features/Alarms/TimerRinger.swift` (new), `Infrastructure/Connections/DeviceConnections.swift` (timers, reminders' alarm, `timerAccess`, `.list`, interruption levels), `Features/Voice/VoiceSessionController.swift` (three gates use `timerAccess`), `Features/Voice/VoiceView.swift` (the Start card's line), `Features/Connections/ConnectionsView.swift` (Timers card), `Infrastructure/Connections/NoteReminderNotifications.swift`, `Features/Focus/FocusController.swift`, `Features/LeaveBy/LeaveByScheduler.swift`, `Features/MorningCheckIn/MorningCheckInScheduler.swift`, `Features/EveningWrapUp/EveningWrapUpViews.swift`, `Features/WeeklyLookBack/WeeklyLookBackViews.swift`, `Features/TidyUp/TidyUpViews.swift`, `Features/Birthdays/BirthdayViews.swift`, `Features/Setup/OpenWaysReminderScheduler.swift`.
- **Shared and widget:** `Shared/Alarms/DoddyAlarmMetadata.swift` (`kind`, `language`), `Shared/Alarms/DoddyTimerIntents.swift` (new), `DoddyWidgets/AlarmLiveActivity.swift` (the timer card; the snooze card unchanged).
- **Config and checks:** four `Config/Doddy-*AppGroup*.entitlements`, `Config/Doddy-Info.plist` and `l10n/*_infoplist.json` (the alarm prompt), `l10n/pl.json` (four new lines), the regenerated catalogs, `scripts/check_forbidden_capabilities.sh` (AlarmKit also in `Shared/Alarms/DoddyTimerIntents.swift`), `scripts/typecheck_app_logic.sh` (adds `TimerRinger.swift`).
- The voice agent spec and the live agent are **unchanged**.

## Verified (Linux, Swift 6.1.2)

- DoddyCore tests, including `RingingTimersTests` (12) and the existing timer, reply and plan tests: see the run recorded in ADR-640.
- `scripts/typecheck_app_logic.sh`: `TimerRinger.swift` type-checks in Swift 6 outside `#if canImport(AlarmKit)`.
- `scripts/check_forbidden_capabilities.sh` and `tools/build_strings_catalog.py --check` pass.
- Every AlarmKit name used was looked up in Apple's documentation (developer.apple.com, 24 Oct): `AlarmConfiguration(countdownDuration:schedule:attributes:…)`, `AlarmPresentation(alert:countdown:paused:)`, `Countdown(title:pauseButton:)`, `Paused(title:resumeButton:)`, `Alert(title:secondaryButton:secondaryButtonBehavior:)` (iOS 26.1; the `stopButton:` form, deprecated in 26.1, is used before that), `AlarmManager.pause/resume/stop/cancel(id:)`, `AlarmPresentationState.alarmID` and `Mode.paused`'s `totalCountdownDuration` and `previouslyElapsedDuration`. Looked up is not compiled.

## NOT RUN

- **No Xcode build.** The AlarmKit code, the widget's timer card, the three intents, `DeviceConnections`, the views and the schedulers have never been compiled. The hosted Mac job on the PR is the first compile.
- **No device.** Checklist for the first build on an iPhone with iOS 26:
  1. "Nastaw minutnik na minutę", tap Start, lock the phone with Silent mode on: it rings like the Clock app's timer; the Lock Screen showed the countdown with Pause and Stop; the island showed it too.
  2. Pause on the Lock Screen: the card shows the time left, still; Resume carries on.
  3. When it rings: Stop ends it; Repeat runs it again.
  4. The first timer asks to allow alarms and timers. Answer Don't Allow: the timer still starts as a notification, and Doddy says it only vibrates in Silent mode.
  5. "Przypomnij mi o 15:30, żeby zadzwonić do mamy": Reminders alerts at 15:30 with its sound and banner.
  6. An old reminder Doddy made before this build: "przesuń na 16:00": it now alerts at 16:00.
  7. A note reminder, and "time to leave", with a Focus on: they come through as Time Sensitive (iOS may ask once whether to allow Time Sensitive for Doddy).
  8. A timer that ends while Doddy is open: banner and sound, and it is still in Notification Center afterwards.
  9. On iOS 18 (no AlarmKit): a timer is a Polish notification "Czas minął".
  10. Hide character artwork on: the timer card shows a timer symbol instead of Doddy.
- Whether a Personal (free) team can sign the Time Sensitive entitlement doesn't matter: `project-iphone.yml` has no entitlements.

## Constitution evidence log

| Rule | Enforcing code | Tests run | Gaps |
|---|---|---|---|
| DOD-07 scoped_action_approval | A timer still starts only from the Start tap (`timerResult` → `TimerStartAction` → `scheduleTimer`); the alarm permission is asked at that tap | `TimerAlarmActionsTests` (unchanged, pass) | UI not compiled |
| DOD-08 verified_status_and_receipts | "started" only when AlarmKit lists the id (`RingingTimerBook.pending`) or iOS lists the notification; a failed AlarmKit start that isn't listed falls back, one that is listed isn't set again | `testOnlyTimersAlarmKitListsArePending`, `testAJustNotedTimerIsKeptUntilAlarmKitListsItButAnOldOneIsDropped` | AlarmKit's list never read on a device |
| DOD-02 honesty_over_agreeableness | The agent hears whether the timer rings through Silent mode; the card says so only when it will | `testTheAgentHearsHowTheTimerRings` | — |
| DOD-10 nonmanipulative_companionship | Only what the user set for a moment is Time Sensitive; routines never push through a Focus | `testOnlyWhatTheUserSetForAMomentIsTimeSensitive`, `testEverythingTimeSensitivePlaysASoundAndTheQuietRoutinesStayQuiet` | — |
| DOD-11 observable_privacy | Timer notes kept only on the phone and named on the Timers card; the alarm prompt names timers in ten languages | catalog check | Nine prompt translations machine-drafted, not reviewed |

Claims to limit: don't say "timers ring in Silent mode" or "reminders work" until checklist rows 1 and 5 pass on a device.
