# Today card and event nudges — status
Date: 2026-10-09. Owner choice "1" (Today card and gentle reminders), rebuilt on the merged Connections code
(the earlier `upbeat-brown` V4a version was not merged; ADR-090). Decision: `DECISIONS.md` ADR-095.

## What the user gets
| Where | Behaviour |
|---|---|
| Home → **Today** | The rest of today from the user's iPhone Calendar (all-day first, then by time; events already over are left out) and incomplete Reminders due today or overdue ("Overdue" in red). At most 5 of each, then "And N more". Refreshes on open and when the app comes back to the front |
| Not connected | With Calendar and Reminders both off (the default) or blocked by iOS, the card says how to turn them on and offers **Open Settings**. Nothing is read |
| Nudges | A bell on each upcoming timed event: 10 minutes, 30 minutes or 1 hour before. iOS schedules a local notification; "Nudge set for 14:30: Dentist." is shown only after it was read back from iOS's pending list. Another lead time replaces the earlier nudge for that event; **Remove nudge** cancels and checks it is gone. If the event moved, the row says the nudge is at the old time |
| Permissions | Calendar and Reminders use the existing Connections switches and permissions. The first nudge asks iOS for notification permission (same as timers); if refused, the card says where to turn it on |

## Privacy
Read and scheduled on the iPhone only. Titles, times and due dates are shown on screen; nothing is sent to ElevenLabs,
a server or anywhere else. Event notes and locations, and reminder notes, are not read.

## Code
| Where | What |
|---|---|
| `Packages/DoddyCore/Sources/DoddyCore/Today.swift` | `ReminderSummary`, `TodayAgenda` (what is shown, order, cap, overdue), `EventNudgePlan` (fixed id per event + lead time, refuses past times and all-day events), `ScheduledNudge` (reads its event, notices a moved event) |
| `…/VoiceTools.swift` | `CalendarEventSummary.id` (optional, per occurrence; never sent to the agent) |
| `DoddyApp/Infrastructure/Connections/DeviceConnections.swift` | Event occurrence ids, `remindersDue(by:)`, `scheduleNudge` (read back), `pendingNudges`, `cancelNudge` (checked) |
| `DoddyApp/Features/Today/TodayCard.swift` | `TodayModel` + the card; on Home under the main buttons |

## Verified (Linux, Swift 6.1.2)
`scripts/ci.sh --core-only`: all core checks PASS; 140 package tests (4 new in `TodayTests`). App files syntax-parse; guard PASS.

## Not verified (needs the Mac and an iPhone)
App compile (EventKit reminder fetch callback marked `@Sendable`; notification APIs as the timers code uses them);
the card with real iCloud/Google calendars synced to the phone; a nudge firing on time with the banner while Doddy is
open; replace/remove; the moved-event note; Dynamic Type and VoiceOver on the card; the new UI-test line.
