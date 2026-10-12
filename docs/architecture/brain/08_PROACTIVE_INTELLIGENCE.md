# DODDY Brain 08: Proactive intelligence (design only)

## Exists
Morning check-in and evening wrap-up (`MorningCheckIn.swift`, `EveningWrapUp.swift`), note reminders as local
notifications (ADR-190), place reminders, leave-by reminders, and messaging-server push, texts, calls and daily news (`server/messaging`, needs a deployed server).

## ProactiveCoordinator (future; nothing built, nothing scheduled)
A proactive job is a **user-created record**: `{id, kind, scope, schedule|trigger, frequencyCap, expiresAt, status(active|paused|stopped), lastRun, lastNotifiedDigest}`.
- **Activation:** only from an explicit user action on a card that shows the scope and frequency. Never inferred from a preference.
- **On device first:** `UNUserNotificationCenter` time/location triggers and `BGAppRefreshTask` (best-effort, no guaranteed timing). iOS does not allow unrestricted background execution.
- **Server only where needed** (flight status, email watch). Each needs its own approved task: a scheduler, provider costs and credentials server-side.
- **Duplicate prevention:** `lastNotifiedDigest` per job. **Visible status** in Settings with pause, stop and delete. **Sources** are named in each notification.
- Results that would change something still go through the normal approval card. A proactive job never writes on its own.
