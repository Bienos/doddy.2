# Alarms by voice: status (ADR-260)
Date: 2026-10-11. Owner: "do all of them" (item 6).

## What ships
- **Voice tool `set_alarm`** (runs on the phone, needs a tap):
  - `time`: the first day and time, `YYYY-MM-DDTHH:MM`, local, later than now. A passed, skipped or doubled time goes back to the agent as a question (the reminder rules, ADR-127/128).
  - `repeat` (optional): `every_day`, `weekdays` or `weekends`.
  - `label` (optional): up to 60 characters.
- **Before a card:** on iOS older than 26, or in a build made with an SDK that has no AlarmKit, the agent hears "alarms need iOS 26 … offer a timer or a reminder". If alarms were refused in iOS Settings, it hears where to allow them. No card is shown in either case.
- **The card:** "Set this alarm?", the time, the date (or Every day / Monday to Friday / Saturday and Sunday), the label, and "It rings even in Silent mode or a Focus. Turn it off in Settings, Alarms." Buttons: **Set alarm** / **Don't set**.
- **At the tap:**
  1. The Timers switch is checked again, and a one-time alarm's time must still be ahead.
  2. AlarmKit permission is asked the first time.
  3. `AlarmManager.schedule(id:configuration: .alarm(schedule:attributes:))`: `.fixed(date)` for one time, `.relative(time, .weekly(days))` for a repeat.
  4. AlarmKit's list is read: "added … Checked." only when the new id is there; otherwise "unknown".
- **Settings › Alarms:** Doddy's alarms that AlarmKit still lists, each with **Turn off**, which is checked by reading the list again. Alarms that already rang once drop out.
- **What is kept:** the alarm's time text and label, in this iPhone's settings (UserDefaults), only to name it in that list. Nothing leaves the phone except what the voice conversation already carries (the time and label the agent proposed).
- **Connections:** alarms belong to **Timers** (one switch for both; Pause all covers it). The Connections card says so. The Calendar and Reminders cards, and their permission prompts, now also say Doddy can change or delete one item after a tap (ADR-229, ADR-259).

## Files
- **Core:** `Alarms.swift` (`AlarmDraft`, `AlarmRepeat`, `AlarmSupport`, `parseAlarm`, replies), `VoiceTools.swift`, `ActivityLog.swift`, `ConnectionPause.swift`.
- **App:** `Features/Alarms/AlarmScheduler.swift` (AlarmKit behind `#if canImport(AlarmKit)` and `@available(iOS 26.0, *)`), `Features/Alarms/AlarmsView.swift`; `VoiceSessionController` (`PendingAction.alarm`, `setAlarm`); `VoiceView` (card); `SettingsView` (link); `ConnectionsView` (copy).
- **Config:** `Config/Doddy-Info.plist` (`NSAlarmKitUsageDescription`, there because older Xcode has no build setting for it), `l10n/pl_infoplist.json`, `project.yml` (Calendar and Reminders prompts).
- **Guard:** `scripts/check_forbidden_capabilities.sh` (AlarmKit only in `Features/Alarms`; the alarm permission allowed).
- **Generator:** `tools/build_strings_catalog.py` also reads usage prompts from `Config/Doddy-Info.plist`.
- **Agent spec:** `voice-agent/tools.json`, `voice-agent/instructions.md`.
- **Tests:** `AlarmTests` (3).

## Verified (Linux)
- `AlarmTests` pass (3). `scripts/typecheck_app_logic.sh` now includes `AlarmScheduler.swift`, but only its non-AlarmKit path compiles on Linux. `swiftc -parse` on the new and changed views.

## NOT RUN
- No Xcode 26 build: the AlarmKit calls (`AlarmManager`, `Alarm.Schedule`, `AlarmPresentation.Alert(title:stopButton:)`, `AlarmAttributes(presentation:metadata:tintColor:)`) are written from Apple's iOS 26 documentation and have never been compiled. On iOS 26.1+, `stopButton` may be reported as deprecated; that is a warning, not an error.
- Never run on a device: whether the alarm rings through Silent and Focus as Apple describes, and what the system's alarm screen shows for the label.
- Whether Xcode 16 (no AlarmKit) builds the app cleanly with the `#if canImport` fallback.
- The live agent has `set_alarm` since version `agtvrsn_8201m4mf5fqhf9087wkrjz8kjenp`; never called from a real conversation.

## Constitution evidence log
| Rule | Enforcing code | Tests | Gaps |
|---|---|---|---|
| DOD-07 scoped_action_approval | Card first; set only on Set alarm; time and switch checked again at the tap | `testAOneTimeAlarmIsADayAndATimeLaterThanNow` | UI not compiled |
| DOD-08 verified_status_and_receipts | "added" only when AlarmKit lists the new id; Turn off checked gone | — | Not run on a device |
| DOD-09 correction_and_recovery | Settings › Alarms with Turn off; older iOS gets a timer or reminder offer | — | — |
| DOD-11 observable_privacy | Under the Timers switch and Pause all; logged in What Doddy did; label kept only on the phone | `testAlarmsAreServedByTimersPausedAndLogged` | — |
