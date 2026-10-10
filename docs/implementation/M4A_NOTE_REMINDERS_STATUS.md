# M4a status — note reminders (local notifications)
Date: 2026-10-10. Owner instructions: "approved, build M4a with your recommendations", then "build" (Remind me while saving), then "port onto newest line". Design: `docs/design/NOTE_REMINDERS.md`. ADR-173.
First built on `claude/hopeful-fermat-1a63x0` from the old default branch (V1); this is the port onto `claude/elegant-knuth-hc1aql`, where M4 Apple Reminders, timers, event nudges, push Updates and daily news already exist.

## What ships
- **Memory detail → Remind me** and **after saving → Remind me about this**: the sheet "When should I bring this back?" (this evening 18:00, tomorrow 09:00, next Monday 09:00, or a picked date and time) with the resolved date and zone. Nothing is stored before Set reminder.
- **Permission:** one short explainer before the iOS prompt the first time it is undecided (`.alert`, `.sound`, the same options timers and Updates use). After that, Settings → Reminders on notes → Allow notifications.
- **Receipts:** "Reminder set for …" only after iOS lists the request as pending. Notifications off: "Saved in Doddy for …" + Open Settings. Failure: nothing kept, the earlier reminder restored, Try again.
- **Delivery:** "Reminder — A note you asked to see again." (note text only if turned on, max 140 characters). Long-press: Open note, Tomorrow 09:00, Done. Tap opens the exact note on Home.
- **Home → Due now**, **Settings → Reminders on notes** (iOS status, note-text switch off by default, count of 50, Cancel all).
- **Delete / edit:** deleting a note deletes its reminder (same database, cascade) and its notification; Delete all removes every note-reminder notification and nothing else. Editing updates pending text when note text is on.
- **Reconcile** on launch and every return to the foreground, limited to `doddy.note.` identifiers.

## How it sits next to existing notifications
- Identifiers: `doddy.note.<uuid>`. Timers (`doddy.timer.*`), event nudges and server pushes are never removed or re-added by note-reminder code (unit test `testOtherNotificationsAreLeftAlone`).
- Delegate: still the single `TimerBanners`; it gained `didReceive`, which forwards only note reminders to `NoteReminderRouter`.
- Categories: `DODDY_NOTE_REMINDER` is added to whatever categories are registered, not replacing them.
- Cap 50 (not 60): iOS allows 64 pending requests per app, shared with timers and nudges.
- Capability `.noteReminders`, separate from `.reminders` (which stays Apple Reminders). The app uses `CapabilityCatalog.shipping(serverConfigured:)` = `withMessaging` + note reminders, so existing catalog tests stay exact.
- Voice is unchanged: the live agent keeps using `create_reminder` (Apple Reminders). Whether voice should also offer note reminders is open.

## Files
Core: `Sources/DoddyCore/NoteReminders.swift`, `Capabilities.swift` (`.noteReminders`, `shipping`), `Sources/DoddyPersistence/SQLiteNoteReminderRepository.swift`, migration `v3_note_reminders` in `DoddyDatabase.swift`. Tests: `DoddyCoreTests/NoteReminderRulesTests.swift`, `DoddyPersistenceTests/NoteReminderCoordinatorTests.swift`.
App: `Infrastructure/Connections/NoteReminderNotifications.swift`, `Features/NoteReminders/` (store, sheet, views); wiring in `DoddyApp.swift`, `RootView.swift`, `AppEnvironment.swift`, `MemoryStore.swift`, `MemoryDetailView.swift`, `HomeView.swift`, `CaptureView.swift`, `SettingsView.swift`, `Components.swift`, previews in `MemoriesView.swift` / `CaptureView.swift`; `DoddyTests/AppEnvironmentTests.swift`.

## Verified (Linux, Swift 6.2.1, Ubuntu 24.04) — see the commit message for the exact run
- `swift test --package-path Packages/DoddyCore -Xswiftc -DSQLITE_DISABLE_SNAPSHOT`: all pass, 16 of them new (6 rules, 10 coordinator against real SQLite, incl. cascade after reopening the file and leaving timers/nudges alone).
- `swiftc -parse` on every Swift file in `DoddyApp`, `DoddyTests`, `DoddyUITests`, `DoddyWidgets`, `Shared`.

## NOT RUN / UNVERIFIED
- App compile and type-check (no Xcode here). Likely spots: `TimerBanners.userNotificationCenter(_:didReceive:)` added in an extension (must be picked up as the delegate method), Swift 6 isolation when it calls the main-actor `NoteReminderRouter`.
- App and UI tests; all device checks: permission prompt, Lock Screen content with and without note text, long-press actions from a locked phone and from a cold background start, tap routing, zone change and DST firing, Focus/Summary, reconcile after restore, and that timers and nudges still ring next to note reminders.

## Open
1. Voice: keep Apple Reminders for "remind me" by voice (recommended), or add a note-linked voice tool (changes the shared live agent).
2. D6 Polish copy; whether note reminders belong in the export.
3. Done separately (ADR-174): the voice agent prompt again says plainly that Doddy is an AI when asked.
