# Mac menu bar prototype status (ADR-435)
Date: 2026-10-11. Source: the owner's deck "Doddy-Watch-iPad-Mac-Review" (Google Slides), slide 09 ("Kliknięcie w pasku menu") and slide 13 ("Najpierw prototyp Maca w pasku menu i komplikacja Watch otwierająca Capture"). The deck marks every concept "requires device validation"; this is the first of them in code.

**Not compiled with Xcode and never run on a Mac.** Written and checked on Linux only.

## What ships
- **A macOS 14 app, `DoddyMac`,** that lives only in the menu bar (`MenuBarExtra`, window style, `LSUIElement`: no Dock icon).
- **A click on the icon opens one small window:**
  - "New note" and a text field;
  - **Save** (Return) and **Cancel** (Esc: clears the words);
  - "Saved on this Mac." after a confirmed save;
  - **Recent on this Mac**: the last five notes;
  - a line saying notes here stay on this Mac;
  - **Quit Doddy**.
- **How a note is saved:**
  - It is checked with the same rules as a note from the watch: not empty, at most 5,000 characters.
  - It is saved as a typed note in Doddy's own SQLite database on that Mac, in the app's sandbox container (`~/Library/Containers/<bundle id>/Data/Library/Application Support/Doddy/doddy-mac.sqlite`), using the iPhone's store code.
  - "Saved" comes only from the database's read-back.
  - If the save throws, the window says Doddy couldn't confirm it and to look at Recent before trying again. It is never shown as saved and never retried by itself.
  - If the database can't be opened, the window says so and offers no Save.
- **No sync.** Notes typed on the Mac are not on the iPhone, and the iPhone's notes are not on the Mac. The deck keeps sync and recording as separate tests.
- **Typing only.** The deck's "or choose voice explicitly" is not built: the app has no microphone, no voice and no network. Its only entitlement is the App Sandbox. The capability guard scans `DoddyMac` and fails on network, audio, speech, WatchConnectivity or CloudKit code there.

## Files
- **App:** `DoddyMac/DoddyMacApp.swift`, `MacCaptureModel.swift`, `MacCaptureView.swift`; `DoddyMac/Localizable.xcstrings`, generated with 7 Polish lines.
- **Core:** `Packages/DoddyCore/Sources/DoddyCore/QuickCapture.swift`; tests in `Packages/DoddyCore/Tests/DoddyPersistenceTests/QuickCaptureTests.swift`.
- **Config:** `Config/DoddyMac.entitlements` (sandbox only). `project.yml`: macOS 14 deployment target, the `DoddyMac` target (bundle id `<app>.mac`), the `DoddyMac` scheme. It is not a dependency of the iPhone app.
- **Guard and strings:** `scripts/check_forbidden_capabilities.sh`; `tools/build_strings_catalog.py` (Mac catalog); `l10n/pl.json`.

## Verified (Linux, Swift 6.1.2)
- `QuickCaptureTests` (3), on real SQLite:
  - a saved note is the one read back and is still there after reopening the file;
  - empty and too-long words write nothing;
  - a repository that throws gives "unconfirmed", never "saved".
- The full DoddyCore suite: 867 tests, 0 failures.
- `swiftc -parse DoddyMac/*.swift`: PASS.
- The capability guard: PASS. A planted `import AVFoundation` in `DoddyMac` made it FAIL as intended; the file was removed.
- The strings `--check`: PASS. `project.yml` parses.
- `xcodegen generate` with XcodeGen 2.44.1, built from source on Linux (`USER` set), writes the project. It has a `DoddyMac` scheme and target (`SDKROOT = macosx`, `MACOSX_DEPLOYMENT_TARGET = 14.0`, `INFOPLIST_KEY_LSUIElement = YES`), linked to the `DoddyPersistence` product. This proves the spec, not the build.

## NOT RUN
- No `xcodebuild -scheme DoddyMac`: the generated project has never been built. Things nobody has seen yet:
  - **MenuBarExtra:** the window opens and closes; Esc cancels and doesn't just close the window; the text field gets focus when the window opens.
  - **Sandbox:** Application Support resolves inside the container.
  - **Signing:** automatic signing with no team. Use "Sign to Run Locally" for a first try.
  - **Concurrency:** Swift 6 strict concurrency on the `@MainActor @Observable` model that calls the repository.
- The menu bar icon is the SF Symbol `square.and.pencil`, a placeholder. The owner picks the final icon. Any Doddy art comes from the owner's pack (CLAUDE.md "Character art"), drawn as a template image for the menu bar.

## Menu bar icon and desktop widget (ADR-438, ADR-439, 2026-10-11)
- **Menu bar icon:** Doddy's face from the owner's pack, a byte-identical copy of the widgets' crop, drawn in colour at 18 pt. The pencil symbol shows only if the image can't load.
- **Desktop widget (`DoddyMacWidgets`, small):**
  - It shows Doddy's face, the number of notes saved on that Mac, "Saved on this Mac" and the time it was counted. Never a note's words.
  - The app writes the count to the App Group folder whenever it refreshes (window opened, after a save). It reads the file back, and only then reloads the widget.
  - The widget reads that file only: no database, no network. The guard enforces this, and a planted `import DoddyPersistence` made it fail as intended.
  - A click opens Doddy (system behaviour). A menu bar app can't open its own window from a widget.
- **Signing:**
  - The App Group (`<team prefix><app id>.mac`) is on by default, like the iPhone's, so a team must be chosen in Xcode.
  - For "Sign to Run Locally", set `DODDY_MAC_ENTITLEMENTS` and `DODDY_MAC_WIDGET_ENTITLEMENTS` to the sandbox-only files. The widget then says to open Doddy from the menu bar.
- **Verified (Linux):**
  - `MacNoteCountTests` (4): read back, an unwritable folder isn't reported as written, only a count and a time are stored, other versions and garbage are ignored;
  - 871 tests in all;
  - XcodeGen embeds `DoddyMacWidgets.appex` in the Mac app and compiles `MacGroupFolder.swift` into both.
- **NOT RUN:**
  - whether `$(TeamIdentifierPrefix)` is filled in in the Info.plist (if not, the group name starts with "." and the widget shows no count);
  - the widget on a real desktop;
  - the menu bar face at 18 pt in light and dark menu bars.

## The Doddy window (ADR-441, 2026-10-11)
- From the deck, slide 11. "Open Doddy window" in the menu bar window opens a separate window, about 720 × 480:
  - **left:** a larger note field (Save ⌘Return, Cancel Esc), with the same "Saved on this Mac." rule;
  - **right:** every note saved on that Mac, newest first, with its date; the words can be selected.
- Typing only, as before; no sync.
- **NOT RUN:**
  - On macOS 14 the window may also open by itself at launch. The modifier that stops this needs macOS 15. Check on a Mac, and decide whether to raise the minimum to macOS 15.
  - Whether `NSApplication.shared.activate()` brings the window to the front for a menu bar app.

## Not built from the deck (later, each a separate decision)
- Slide 12, a floating NSPanel.
- Voice on the Mac.
- Sync between the Mac and the iPhone.

## Constitution evidence log
| Rule | Enforcing code | Tests | Gaps |
|---|---|---|---|
| DOD-08 verified_status_and_receipts | "Saved on this Mac." only from `QuickCapture.saved` (read-back); a throw is `unconfirmed` with "look at Recent" | `testASavedNoteIsTheOneReadBackAndSurvivesReopening`, `testAFailedSaveIsUnconfirmedNeverSaved` | The view isn't compiled |
| DOD-07 scoped_action_approval | Nothing is saved until Save; Cancel clears the words | — | UI NOT RUN |
| DOD-11 observable_privacy | Own database on that Mac; sandbox only; no network or microphone (guarded); the window says notes don't reach the iPhone | Guard PASS, and a planted violation FAILS | Not seen on a Mac |
