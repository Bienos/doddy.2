# Place reminders status (ADR-194)
Date: 2026-10-10. Owner instruction: "build location reminders next". Design: `docs/design/NOTE_REMINDERS.md` → "Place reminders". Builds on note reminders (ADR-190, `M4A_NOTE_REMINDERS_STATUS.md`).

## What ships
- The reminder sheet has **At a time | At a place**. At a place: **Use where I am now** or **Search for a place** (Apple Maps), then a name, **When I arrive / When I leave**, and **100 / 200 / 500 m**.
- iOS watches the place and shows the same private notification on every arrival (or departure) until **Done**. Long-press: Open note, Done.
- Needs notifications plus location **While Using** with **Precise Location**. A two-permission explainer comes first; if either is off, nothing is stored and the receipt offers **Open Settings**.
- Note detail shows "When you arrive at …, within 200 m, each time, until you mark it Done". Settings → Reminders on notes shows location status and "At a place: n of 10".
- Privacy: the Settings paragraph and "What leaves this iPhone" now list Apple Maps place search; "stays on this iPhone" lists places and arrivals.

## Files
Core: `NoteReminders.swift` (`ReminderTrigger`, `ReminderPlace`, `LocationReadiness`, place scheduling, `ReminderFormat.summary/short/place`), `DataFlow.swift`; persistence: `v4_note_reminder_places` in `DoddyDatabase.swift`, `SQLiteNoteReminderRepository.swift`.
App: `Infrastructure/Connections/PlaceLocation.swift` (permission, one position, Apple Maps search, location trigger), `NoteReminderNotifications.swift` (place category and trigger), `Features/NoteReminders/NotePlacePicker.swift`, `NoteReminderSheet.swift`, `NoteReminderStore.swift`, `NoteReminderViews.swift`, `MemoryDetailView.swift`, `SettingsView.swift`; `project.yml` (`NSLocationWhenInUseUsageDescription`); `scripts/check_forbidden_capabilities.sh` (location code only in Connections; no "Always"/background location).

## Verified (Linux, Swift 6.2.1)
- `scripts/ci.sh --core-only`: PASS, 340 package tests. New: place reminder scheduled, private and kept pending by reconcile; no time snooze for a place; nothing stored without notifications or precise location (each readiness case); 10-place limit and switching a note between time and place; **upgrade from a real v3 database file keeps its time reminder**, then the rebuilt table still enforces one per note and cascades; place validation; data-flow row.
- Guard: passes, and fails on probes importing CoreLocation outside Connections or calling `requestAlwaysAuthorization`.
- `swiftc -parse` on every Swift file in the app, test, widget and shared targets.

## NOT RUN / UNVERIFIED (needs a Mac and an iPhone)
- App compile. Likely spots: `PlaceLocation` (main-actor `CLLocationManager` delegate, `CLLocationUpdate.liveUpdates()` inside a task group), `MKMapItem.placemark` (deprecated in newer SDKs, still available).
- On a device: the location prompt and Precise Location; "Use where I am now" indoors and outdoors; Apple Maps results; that arrival and departure fire at 100/200/500 m, repeat on later arrivals and stop after Done; behaviour with Doddy closed, after a restart and with Low Power Mode; that timers, nudges and time reminders still work beside it.

## Open
1. A map to see or drag the circle (loads map tiles from Apple; another privacy line).
2. Voice ("remind me when I get to the shop"): needs an agent tool and the same on-screen confirmation.
3. Polish copy for the new strings.
