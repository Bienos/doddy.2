# Mac

> **PAUSED (ADR-572, 21 Oct 2026).** Mac development is on hold while iOS and the web come first. **Nothing here is deleted.** `DoddyMac/`, `DoddyMacWidgets/`, `Config/DoddyMac*`, `project-mac.yml` and `DoddyCore` `MacNoteCount` are unchanged. The Mac was never in `project.yml` or the CI build; what changed is that `make project-mac` now needs `ENABLE_MAC=1`, and changes to Mac folders no longer start the hosted Mac build (that job builds the iPhone app on a macOS runner).

## Re-enabling
1. `make project-mac ENABLE_MAC=1`, then open `DoddyMac.xcodeproj` (scheme `DoddyMac`).
2. To check it in CI again, add a Mac build step to `scripts/ci.sh` (none exists today; the Mac was never built in CI), and take `DoddyMac/*`, `DoddyMacWidgets/*`, `Config/DoddyMac*` and `project-mac.yml` out of the "no Mac build" list in `scripts/ci_needs_mac.sh` and its test.
3. Remove the `ENABLE_MAC` guard from the `Makefile` and this banner.

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
