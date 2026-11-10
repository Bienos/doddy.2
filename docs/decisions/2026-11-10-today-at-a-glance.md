# Today shows the day at a glance and can tick off a reminder

- **Date:** 2026-11-10
- **Decided by:** owner: "dzisiaj to jest jeszcze spoko, ten kalendarz taki po prostu mógłby też być trochę lepszy, bo ten kalendarz w razie nic nam nie daje", then "dzisiaj lepszy kalendarz, no mógłbyś to też fajniej zrobić". The layout below is the agent's design, owner review pending.
- **Status:** proposed
- **Replaces:** nothing; extends ADR-095 (Today card and event nudges) and ADR-545 (Today in Home's ••• menu)

## Why
Today (Home › ••• › Today, and the morning check-in) was one list: the rest of today's events and reminders due, five of each. It answered "what's left" but not "what's next, how long until, where, when am I free, what about tomorrow", and a reminder could only be looked at.

## Decision
Today shows, top to bottom (`DoddyApp/Features/Today/`, logic in DoddyCore `TodayGlance.swift`):
- **Header:** in the sheet, Doddy (`WholeDoddy_belly_reading`, or `WholeDoddy_crosslegged` when nothing is left) and the date; in the morning check-in, "Today". Under it one line worked out by code from the counts, e.g. "3 events left, the next at 14:00 · 2 reminders, 1 overdue" (`TodayGlanceText.summary`, Polish and English; no model writes it). It never mentions a source that is switched off.
- **All-day events** as small tags.
- **On now and Next up**, picked out with an orange edge: what has started and until when; the next timed event with the time to go ("in 25 min", counting down by the minute), its start and end, the nudge bell, and its location when Calendar has one, with **Open in Maps** only for a place (not for a web address).
- **Later today:** the remaining events (six, then "And N more in Calendar."), with **free time** of 30 minutes or more between events ("Free 11:00–13:30 · 2 h 30 min"), from the same gap rules as "When am I free?" (ADR-332), counting only gaps with an event on both sides.
- **Reminders** due today or overdue, each with a **tick**. The tick reads the reminder from Reminders again and writes only if it is still open with the title and due the row showed (`ReminderTick.stillAsShown`); it uses the existing `DeviceConnections.changeReminder(_, .complete)` (ADR-229), which reads it back. "Ticked off: X. Checked in Reminders." appears only when Reminders reads it back as done; otherwise the screen says it wasn't confirmed or wasn't ticked off. **Undo** reopens it the same way (ADR-258).
- **Tomorrow:** the first three things (all-day events, then events and timed reminders by time, then reminders due that day without a time), then "And N more tomorrow." Read only.
- A line naming a switched-off source with a Settings button, and "Read from Calendar and Reminders on this iPhone. Nothing here is sent anywhere."

The sheet moved from `HomeView.swift` to `Features/Today/TodaySheet.swift`. The card's accessibility identifier is now `today.card` (it repeated the ••• menu item's `home.today`; no test used it on the card).

## Consequences
- One write is new from this screen: completing a reminder (and reopening it by Undo), started only by the person's tap on that row. It is the same verified EventKit write the voice path already uses.
- Privacy: still nothing leaves the iPhone. New reads, on the iPhone only: tomorrow's events and reminders, and the next event's location (shown on this screen, never sent to the voice agent). The location goes to Apple Maps only when the person taps Open in Maps.
- A repeating reminder, when ticked, may be moved to its next date by Reminders instead of staying done; the read-back would then say "didn't show it as done", which is honest but unhelpful. To check on a device.
- The tick is not written to "What Doddy did": the person did it, not Doddy.

## Evidence
Linux, Swift 6.1.2: `swift test` on DoddyCore (2880 tests, 0 failures; 11 new in `TodayGlanceTests`), `scripts/ci.sh --only swift,checks` (all PASS except the known Studio renderers NOT RUN), `swiftc -parse` on the four app files, `tools/build_strings_catalog.py --check` PASS. Not compiled: the app (no Xcode here). Not run on a device: the screen, the tick and Undo against real Reminders, the Maps link, Dynamic Type, VoiceOver, dark mode.
