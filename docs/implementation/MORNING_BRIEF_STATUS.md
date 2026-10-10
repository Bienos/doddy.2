# Morning brief — status

Date: 2026-10-10. Owner request: "build the morning brief next". Decision: `DECISIONS.md` ADR-230.

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
- **Daily news, Todoist, Gmail** (ADR-231): only when chosen under Settings → Morning brief → In your morning brief.
  See "Server sections" below.
- **Not included:** weather (the app has no weather source of its own).

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

## Server sections and choosing what's in it (ADR-231)
| Choice (Settings → Morning brief → In your morning brief) | Default | Where it comes from |
|---|---|---|
| Events left today, Reminders due | On | Calendar and Reminders on this iPhone (not read at all when both are off) |
| Doddy's note reminders | On | This iPhone |
| Today's daily news | Off | Today's newest digest with stories from the messaging server; up to 3 stories with source and a link that opens only when tapped |
| Todoist tasks for today | Off | `list_todoist_tasks` (today and overdue) through the Doddy server |
| Unread Gmail from the last day (+ "Only mail Gmail marks important") | Off | `check_email` (`in:inbox is:unread newer_than:1d`, max 5) through the Doddy server; **sender name and subject only** |

- Same reads the voice agent can make: the tool's switch in Online accounts, the connection, limits and a server
  receipt all apply. Read only, no approvals, never retried by the brief.
- The backend now also returns the listed emails and tasks as data (`RunResult.items`, no email previews), so the
  app never parses text written for the voice agent. An older server sends none: the brief says it can't list them.
- Fetched when the brief shows, all chosen sections at once, **at most once per day and choice** unless the user taps
  **Refresh**; kept in memory only and cleared by Close for today.
- Every section that can't be read says why in one line (not set up, switched off, not connected, couldn't be
  reached). Demo results from a test server start "Demo data, not your account:".

### Verified (Linux)
- Backend: `npm run typecheck`; `npm test` 123 pass (new: items for email and tasks, no previews, empty list, none
  for other tools). `contracts/online-accounts/run-result-email.json` gained `items` (only that change kept; the
  generator's fresh random ids were not committed).
- `scripts/ci.sh --core-only`: PASS for core-only scope; 439 DoddyCore package tests (429 before), 123 backend tests.
- DoddyCore: `MorningBriefOnlineTests` (10): defaults, left-out sections leave no line or notice, Todoist and Gmail
  wording, sender names, demo label, unavailable/failed, news lines with links, today's newest digest only, exact
  read arguments (no approvals), error mapping, older server without items; the email fixture decodes with items.
- The app's cache and fetch code type-checks in Swift 6 with stand-ins for the two server-settings helpers.

### Not verified
Card and Settings compile; real Todoist, Gmail and news against a deployed server. Checklist B8–B11.
