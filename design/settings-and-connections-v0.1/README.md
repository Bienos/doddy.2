# Settings and Connections: design study v0.1

Date: 10 Oct 2026. Status: **proposal, not built.** Spec: `docs/design/SETTINGS_AND_CONNECTIONS.md`.

Open `index.html` in a browser. It is one self-contained file. The only network request is the Caveat display font from Google Fonts; without it the page falls back to a system handwriting face. No font files are committed.

## What it shows

A clickable phone in the Pocket Notebook style (tokens from `design/interface-v1.2/docs/DESIGN-SYSTEM.md`, character poses from `design/interface-v1.2/assets/`, recoloured through CSS so they follow light and dark):

1. Settings, regrouped (You and Doddy, Connections, Memories, Privacy, About)
2. Apps & tools hub: On this iPhone, Messages and email, Online accounts, Doddy in other places
3. Connect flow in four steps (what Doddy will do, what to share, iOS asks, try it)
4. Denied permission path
5. Connection detail (ask-first levels, Pause vs Disconnect, recent receipts)
6. The plan card: one request that uses Memories, Calendar, Weather and Reminders together, with per-step results (Done, Couldn't, Not sure)
7. What Doddy did (activity log), What leaves this iPhone, Ways to open Doddy

Review controls beside the phone switch the reminder-write outcome, phone appearance and text size.

## What it does not prove

Everything is fictional page state. There is no real iOS permission, EventKit, weather, calendar, account or network write. The iOS prompt is an illustration labelled as such; the real app must never draw its own copy of a system dialog. Native layout, Dynamic Type, VoiceOver and contrast after compositing still need testing in SwiftUI.

## Checked

Headless Chromium 1194 (Playwright 1.56.1), 10 Oct 2026: walked settings → hub → connect (allow and deny) → detail → plan (done, not sure → check) → activity → privacy, in light, dark and larger text, at 1400 px and 390 px wide. No console errors; no horizontal scroll at 390 px. This is a scripted browser check, not an accessibility audit.
