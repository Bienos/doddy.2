# Home Screen and Lock Screen widgets — status

Date: 2026-10-10. Owner request: "build the widgets next". Decision: `DECISIONS.md` ADR-233.

## What the user gets
| Widget | Sizes | Shows | Tap |
|---|---|---|---|
| **Talk to Doddy** | Small, medium, Lock Screen circle | Small and circle: Talk. Medium: Talk and New note | Runs the same intents as Siri and the controls: opens Doddy and starts a conversation, or opens an empty capture screen. No data |
| **Pinned notes** | Small, medium | Newest pin (small) or up to 3 pins (medium), in the Memories list's order | Opens that note |
| **Next note reminder** | Small, Lock Screen rectangular, Lock Screen inline | Time of the next note reminder, "in 2 hours", and the note's words; moves on by itself as times pass; counts place reminders | Opens that note |

Settings → **Widgets**: whether note widgets work in this build, "Show note words in widgets" (on unless turned off)
and how to add them.

## How the note widgets get their data
The widget extension can't open Doddy's database. The app writes a small snapshot (`WidgetSnapshot`) to a file in an
App Group that only Doddy and its widgets can read, whenever notes, pins, note reminders or the words setting
change, and asks WidgetKit to redraw. The widgets only read it; they never write and never use the network.

The snapshot holds only what the widgets show: up to 3 pinned notes and the next 5 time reminders (words cut to 140
characters, line breaks as " · "), and a count of place reminders. Sample notes are never included. With note words
off, the words are not written at all. Deleting notes or everything rewrites it at once.

## Privacy
- Note words are `.privacySensitive()`: iOS hides them on a locked Lock Screen; times still show.
- The file stays on the iPhone, readable after first unlock (widgets draw while locked), and is never sent anywhere
  by Doddy. Whether iOS includes App Group files in iPhone backups is to be checked on a device, as for the notes.
- Talk and New note are intents, not links, so a web page can't start the microphone through a widget link.
- New link `doddy://note/<id>` only navigates; a deleted note shows "This memory no longer exists".

## The App Group is opt-in per build
Like Push, an App Group needs a team that can register one, so it is off by default and a free Apple ID can still
build. `BUILD_AND_TEST.md` → "Note widgets need an App Group" has the three build settings. Without it the Talk
widget works, and the note widgets and Settings say they aren't set up instead of showing anything.

## Not included (owner may decide)
Calendar events: the widget extension has no Calendar access of its own, and a copy written by the app would go stale
until the app is opened again.

## Code
| Where | What |
|---|---|
| `Packages/DoddyCore/Sources/DoddyCore/WidgetSnapshot.swift` | Snapshot rules, `NoteLink` |
| `Shared/Widgets/WidgetSnapshotFile.swift` | App Group file (app writes, widgets read) |
| `DoddyApp/Infrastructure/WidgetSync.swift`, `DoddyApp/App/RootView.swift` | Writing on change; `doddy://note/<id>` |
| `DoddyWidgets/DoddyHomeWidgets.swift`, `DoddyWidgetsBundle.swift` | The three widgets |
| `project.yml`, `Config/*.entitlements`, `Config/*-Info.plist` | `DODDY_APP_GROUP`, entitlements, DoddyCore in the extension |
| `DoddyApp/Features/Settings/SettingsView.swift`, `DoddyCore/DataFlow.swift` | Widgets section, privacy line |

## Verified (Linux, Swift 6.1.2)
- `WidgetSnapshotTests` (7): pin order like the Memories list, deleted and sample pins skipped, max 3; upcoming
  soonest first, past left out, places counted, "next" moves on; words off means not in the file; clipping; round
  trip and other versions refused; empty after delete all; note links. `scripts/ci.sh --core-only`: PASS for
  core-only scope, 454 DoddyCore package tests, 0 failures (447 before).
- Plists and entitlement files parse; `project.yml` parses; every changed Swift file syntax-parses; guard passes.

## Not verified (needs the Mac and an iPhone)
Everything that needs Xcode: the extension compiling with DoddyCore, the App Group with a real team, the widgets'
look and interactivity, redaction when locked, redraw timing. Checklist W1–W7 in `MAC_VERIFICATION_CHECKLIST_2026-10-10.md`.
