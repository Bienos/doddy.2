# The Mac menu-bar app (ADR-450)
Date: 2026-10-11. Owner request: "nav bar app from reference to build similar" (the macOS mockup: an icon in the menu bar with a small Doddy menu).

**Status: logic tested on Linux; the SwiftUI and AppKit files are written but have never been compiled or run.** There is no Xcode in the session that wrote this. Do not call the Mac app "built", "working" or "shipped" until `MAC_VERIFICATION_CHECKLIST_2026-10-10.md` section 18 has been ticked on a Mac.

## What the reference showed and what was built
| In the mockup | Built? | Notes |
|---|---|---|
| Doddy's face in the menu bar | Yes (unbuilt view) | A circle cut in code from the owner's `WholeDoddy_listening` pose. Falls back to a system symbol if the render fails |
| Menu header "Doddy" + "Listening…" + orange stop button | **No** | The app never listens and has no microphone entitlement. The header says "Ready. Not listening." There is no stop button |
| Open Doddy | Yes | Opens a window listing this Mac's notes (read-only) |
| Talk to Doddy | **Greyed out** | Says "Voice isn't on the Mac yet. Use Doddy on your iPhone." Not tappable |
| Remember something | Yes | Inline: type, Save (Cmd-Return). "Saved on this Mac." only after the repository committed the note |
| Find in my memories | Yes | Inline word search over this Mac's notes (the iPhone's `RepositoryRecallService`). No match gives the standard "I couldn't find that in your saved memories." |
| Translate | **Greyed out** | Same wording as Talk |
| Settings | Yes | A window of plain statements and the memory file's path; no toggles (nothing to switch) |
| Keyboard hints (⌘O, ⌥Space, ⌘⇧R...) and global hotkeys | **No** | Global hotkeys need system permissions and were not requested. Only Cmd-Return (Save) and Cmd-Q work, and only while the panel is open |
| "Your reminder is ready... added to your calendar" notification | **No** | No notifications or calendar on the Mac |
| The macOS main window (Home, Chat, Memories, Tasks, Calendar, Files, Places, Translate sidebar) | **No** | Out of scope; a separate, larger decision |
| The mockup's character drawings | **Not used** | Owner rule: only the numbered pack |

## Reality table
| Piece | Where | Reality |
|---|---|---|
| Menu rows, availability and status text | `Packages/DoddyCore/Sources/DoddyCore/MenuBarMenu.swift` (`MenuBarMenu`) | **Tested** (Linux, Swift 6.1.2): `MenuBarMenuTests`, 5 tests |
| "Remember" save with validation and failure path | same file (`MenuBarCapture`) | **Tested** against real in-memory SQLite and a failing repository: `MenuBarCaptureTests`, 4 tests |
| Mac memory model (opens the SQLite file, save, find, reload) | `DoddyMac/MacModel.swift` | **Type-checked** in Swift 6 mode against the real modules (`scripts/typecheck_mac_logic.sh`). Not run: the file path logic needs a Mac sandbox |
| Menu panel, windows, icon, theme | `DoddyMac/MenuBarContent.swift`, `NotesWindow.swift`, `MacSettingsView.swift`, `DoddyFace.swift`, `MacTheme.swift`, `DoddyMacApp.swift` | **Parsed only** (`swiftc -parse`). SwiftUI and AppKit do not exist on Linux, so nothing here has been type-checked or run |
| Xcode target, entitlements | `project.yml` (`DoddyMac`), `Config/DoddyMac.entitlements` | YAML parses and the target lists as expected. `xcodegen` was **not run** |
| Capability guard | `scripts/check_forbidden_capabilities.sh` | Passes; also proven to fail when `DoddyMac` gains a `URLSession` and when the entitlements gain `network.client` |
| ci steps | `scripts/ci.sh` | The Linux step (`typecheck_mac_logic.sh`) ran and passed in `--core-only`. The new `xcodebuild build -scheme DoddyMac` step is Mac-only and has not run |

## Tests actually run (2026-10-11, Linux x86_64, Swift 6.1.2)
- `swift test --package-path Packages/DoddyCore -Xswiftc -DSQLITE_DISABLE_SNAPSHOT -Xlinker --allow-shlib-undefined`: **929 tests, 0 failures**, including the 9 new ones. The repo's notes mention Swift 6.2 on Linux; 6.1.2 was what could be installed here.
- `scripts/typecheck_mac_logic.sh`: PASS.
- `scripts/check_forbidden_capabilities.sh`: PASS (and the two negative checks above).
- `scripts/ci.sh --core-only`: **PASS for core-only scope** (all 21 steps that ran passed, including the new "Mac app logic type-check" step; "Messaging server database tests" SKIPPED because `TEST_DATABASE_URL` is not set; "iOS app build + tests" NOT RUN by design).
- Not run: `xcodegen`, `xcodebuild` (the new `DoddyMac` build step in `scripts/ci.sh` included), any app launch, any UI test. There are no UI tests for the Mac app.

## Constitution evidence log
| Rule | What it requires here | Enforcing code | Test | Gap or claim to limit |
|---|---|---|---|---|
| DOD-06 user-controlled memory | A note exists only because the user typed it and pressed Save; source recorded | `MenuBarCapture.save` (`.explicitText`, nothing inferred) | `testSavedNoteIsStoredAsExplicitTextWithTheTypedWords` | No edit or delete in the Mac app yet, so "user can edit and delete" is **not** met on the Mac. Do not describe the Mac app as complete memory management |
| DOD-08 verified status | Never say "Saved" unless stored | `MenuBarSaveResult.saved` only after `MemoryRepository.save` returns (its contract: committed and read back) | `testFailedWriteIsNeverReportedAsSaved`, `testEmptyTextIsRejectedAndNothingIsStored` | The view shows the field and message from that result; the views themselves are untested |
| DOD-02 honesty / DOD-03 no false humanity | Unbuilt features say so; the AI doesn't pretend to listen | `MenuBarMenu` marks Talk and Translate unavailable with a reason; status text has no listening state | `testVoiceAndTranslateAreNeverAvailableOnTheMac`, `testStatusNeverClaimsListening` | A test on strings proves the model, not that a view could not be changed to show something else. Manual check X4 |
| DOD-11 observable privacy | Permissions minimal; the claims "no network, no microphone" stay true | Sandbox-only entitlements; guard scans `DoddyMac` | guard run and its two negative checks | The guard checks source patterns and the entitlements file, not the built binary. Manual check X11 (watch the network) before saying "makes no network connections" outside these docs |
| Recall grounded in stored notes | Find returns stored notes or an explicit no-match | `RepositoryRecallService` (existing) | `testSavedNoteIsFoundByTheMenusFind` | Word match only; no meaning search on the Mac |
| Not covered | DOD-07 (no actions here), DOD-09, DOD-10, DOD-12 | n/a | n/a | No external writes exist in this app |

**Claims to limit:** do not write that the Mac app "works", "is tested" or "keeps notes private/encrypted". It stores notes in the app container's SQLite file, **not** with the iPhone's file-protection settings or backup encryption, and it has no app lock.

## Manual verification pending
Section 18 of `MAC_VERIFICATION_CHECKLIST_2026-10-10.md` (X1 to X12), on a Mac with Xcode 16+ and macOS 14+, in light and dark, with VoiceOver, and a network check.

## Security and privacy risks
- Notes in the Mac's SQLite file are not encrypted by Doddy; they rely on macOS disk encryption (FileVault) and the sandbox container. The iPhone's "after first unlock" protection class has no Mac equivalent set here.
- No app lock, no export and no deletion in the Mac app.
- The memory file is separate from the iPhone's. Users may expect the two to match; the windows and Settings say they don't.

## Decisions required from the owner
1. Whether the Mac app should grow (edit and delete notes, export, a real main window like the mockup's, sync with the iPhone through an account or iCloud). Each is a new milestone; none is started.
2. Voice on the Mac (a microphone entitlement and the privacy copy that goes with it) and Translate.
3. Global hotkeys (they need an extra system permission).
4. A Mac app icon, and the production bundle identifier (`com.bienos.doddy2.dev.mac` while the development id stands).
5. Confirm ADR-450 as the number (other branches use up to 446).

## Next recommended step
Run section 18 on a Mac. If the first compile fails, send the first few errors; the likely places are listed in `FIRST_BUILD_GUIDE.md`.
