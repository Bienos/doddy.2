# Mac

**Build:** `make project-mac`, then open `DoddyMac.xcodeproj`, scheme `DoddyMac` (macOS 14+). It is a separate project: nothing from the iPhone app is in it, only the `DoddyCore` package.

**State:** a prototype on PR #61 (ADR-433, 435, 438, 439, 451, 455). It has **never been compiled.** Logic tests pass on Linux.

## What it does
- **Menu bar app** (`DoddyMac/`):
  - a click on Doddy's face in the menu bar opens a small window: type a note, Save or Cancel, see the last five notes;
  - **"Open Doddy window"** gives a bigger window with every note on this Mac;
  - **"Palette"** in that window shows a small floating note field. It hides when you switch apps.
- **Desktop widget** (`DoddyMacWidgets/`): the number of notes saved on this Mac, never their words. It reads a count file the app writes in their App Group.
- **Storage:** its own SQLite database on that Mac (`DoddyPersistence`, sandbox container). "Saved" appears only after the read-back.
- **Not built:**
  - no sync with the iPhone (an owner decision);
  - no voice, no microphone, no network (enforced by the capability guard).

## Rules, tests, signing
- **Shared rules:** `DoddyCore/QuickCapture.swift`, `MacNoteCount.swift`.
- **Tests:** `QuickCaptureTests` (real SQLite), `MacNoteCountTests`.
- **Signing:**
  - The App Group needs a team, so choose one in Xcode.
  - To use "Sign to Run Locally", set `DODDY_MAC_ENTITLEMENTS` and `DODDY_MAC_WIDGET_ENTITLEMENTS` in `project-mac.yml` to the sandbox-only files. The widget then shows no count.
- **Status docs:**
  - `docs/implementation/MAC_MENU_BAR_STATUS.md`: what's NOT RUN;
  - `docs/implementation/MAC_SPIKE_REPORT.md`: why it's a native app.
