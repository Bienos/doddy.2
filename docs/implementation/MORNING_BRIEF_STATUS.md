# Morning brief — status

Date: 2026-10-10. Owner request: "build the morning brief next". Decision: `DECISIONS.md` ADR-212.

## What the user gets
| Where | Behaviour |
|---|---|
| Settings → Morning brief | **Off unless turned on.** Time picker (default 07:30). Turning it on asks iOS for notifications if it hasn't yet. The status line says "On…" only after iOS lists the daily notification at that time; otherwise it says what happened (not confirmed, notifications off, failed). Off removes it and checks iOS no longer lists it |
| Lock Screen, every day at that time | "Morning brief — Your day at a glance is ready in Doddy." The same words every day: no titles, notes or names. Tapping it opens Doddy on Home |
| Home, from that time for 5 hours | A **Morning brief** card above Today, e.g. "Good morning, Patryk. 3 events left today: all day, Marta's birthday; first Dentist at 10:00. 2 reminders due: Pay rent and Call Adam. One is from an earlier day. A note reminder today: at 14:00, “Bring the spare key”." Buttons: **Read aloud** / Stop, **Close for today** |

## Where the content comes from
- **Calendar and Reminders:** exactly what Home → Today reads, through the same Connections switches, iOS
  permissions and Pause all (`TodayReading`, now shared by both cards). Event and reminder notes and locations are
  not read. If something is off or paused, the brief says so in one plain line instead of guessing.
- **Doddy's note reminders:** time reminders that fire later today, with the note's current words. Place reminders
  have no time, so they are left out.
- **Name:** the nickname from Doddy's personality settings, else the approved name from About you, else none.
- **Not included** (each would need its own decision): weather (the app has no weather source of its own), the
  daily news digest (server), Todoist or Gmail (cloud reads).

## Wording rules (`Packages/DoddyCore/Sources/DoddyCore/MorningBrief.swift`)
Counts, titles and times only. Up to 3 items named per line, then "and N more". Old reminders are "from an earlier
day", never "overdue". No exclamation marks, praise or "should/must". Long titles are shortened in the brief only.

## Privacy
Composed on the iPhone; nothing is sent anywhere. The notification text is fixed, so it is scheduled once and never
recomputed in the background. Read aloud uses the iPhone's built-in speech voice on the device; it never speaks
during a voice conversation and stops when Doddy leaves the screen. UI-test launches never touch notifications.

## Code
| Where | What |
|---|---|
| `Packages/DoddyCore/Sources/DoddyCore/MorningBrief.swift` | `MorningBriefSchedule` (time, show window, closed day), `MorningBriefNotification` (fixed id and text), `MorningBrief.compose` |
| `DoddyApp/Features/MorningBrief/MorningBriefNotifications.swift` | Schedule with read-back, cancel with check, launch sync, tap router |
| `DoddyApp/Features/MorningBrief/MorningBriefCard.swift`, `MorningBriefSettingsSection.swift` | Home card, Settings |
| `DoddyApp/Features/Voice/BriefSpeaker.swift` | Read aloud (audio code stays in Features/Voice, guard script) |
| `DoddyApp/Features/Today/TodayCard.swift` | `TodayReading` shared with the Today card (its behaviour unchanged) |
| `DoddyApp/Infrastructure/Connections/NoteReminderNotifications.swift`, `App/RootView.swift`, `App/DoddyApp.swift`, `Features/Home/HomeView.swift` | Tap routing, launch sync, card placement |

## Verified (Linux, Swift 6.1.2)
- `MorningBriefTests` (12): full morning, empty day, one event, counts beyond the named items, not connected and
  paused, note reminders only later today, blank name and long titles, no pressure words, show window and close for
  today, late brief stops at midnight, invalid time, fixed notification text and id. `scripts/ci.sh --core-only`:
  PASS for core-only scope, 429 DoddyCore package tests, 0 failures (417 before).
- Every changed app file syntax-parses; guard script passes (audio stays in Features/Voice).

## Not verified (needs the Mac and an iPhone)
App compile of the new files (UserNotifications, AVFoundation, SwiftUI); that the repeating notification fires at
the local time and the tap opens Home; the read-back on a real device; read aloud; the Today card after the
refactor. Checklist B1–B7 in `MAC_VERIFICATION_CHECKLIST_2026-10-10.md`.
