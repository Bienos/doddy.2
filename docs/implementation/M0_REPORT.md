# M0 report — what was done and what was actually verified
Date: 2026-10-08. Branch `claude/loving-dirac-uuxoux`. Repository `Bienos/doddy.2` only; `Bienos/AI-AGENT-DODDY` untouched.

## Environment (before coding)
| Item | Value |
|---|---|
| Host | Linux 6.18 (Ubuntu 24.04, x86_64), cloud container |
| Xcode / `xcodebuild` / iOS SDK / simulators | **None. Not available.** |
| Swift | none preinstalled; installed official **Swift 6.3.3** Linux toolchain (swift.org, tarball signature not verified) |
| Deployment target decision | **iOS 17.0, iPhone only**, per ADR-002. Could **not** be checked against a real SDK. |
| Consequence | The iOS app was **never compiled**. M0 "Definition of Done" items that need `xcodebuild` are **NOT RUN**. |

## What exists
- Pack imported at root (259 files hashed against `PACKAGE_MANIFEST.json`, incl. the second brand ZIP from Part 2); unmodified.
- `Packages/DoddyCore`: `MemoryRecord`, `NewMemory`, `MemorySource/Category`, validation; ports `MemoryRepository`, `RecallService`, `AssistantClient`, `ToolExecutor` (+ proposal/confirmation/receipt types); `Unavailable*` adapters; `CapabilityCatalog.m0`; `PrivacyDefaults.m0`; candidate colour tokens with contrast maths.
- `DoddyApp`: SwiftUI shell — First Hello (Start/Skip), Home, Memories placeholder, Settings (privacy summary, appearance, hide artwork, capability list). Candidate art labelled. No mic/AI/reminder/account UI.
- `project.yml`, `DoddyTests`, `DoddyUITests`, `scripts/ci.sh`, `scripts/check_forbidden_capabilities.sh`, `BUILD_AND_TEST.md`, `DEPENDENCIES_AND_LICENSES.md`, `DECISIONS.md`.

## Commands actually run and results
| Command | Result |
|---|---|
| `python3 -I scripts/verify_imported_pack.py` | PASS — 259 files match manifest; no font binaries |
| `python3 -I tools/verify_pack.py` (pack's own, on a clean extraction in scratch) | FAIL on Part-1 zip alone (second brand ZIP ships in Part 2); not re-run in repo because it rejects `.git` and any added file — replaced by the script above |
| `scripts/check_forbidden_capabilities.sh` | PASS; negative test (injected `URLSession`) → exit 1 as intended |
| `swift build --package-path Packages/DoddyCore` | Build complete, 0 warnings, Swift 6.3.3 / Linux |
| `swift test --package-path Packages/DoddyCore` | **26 executed, 0 failures, 0 skipped** (XCTest: 7 tokens + 13 memory model + 6 honesty); Swift Testing runner reports 0 tests (none written) |
| `scripts/ci.sh --core-only` | PASS for core-only scope; iOS step printed `NOT RUN`; exit 0 |
| `scripts/ci.sh` | `NOT RUN` iOS step → `RESULT: BLOCKED`, exit 2 (correct honest failure) |
| `swiftc -parse` on every `DoddyApp`/`DoddyTests`/`DoddyUITests` file | all parse (**syntax only**, not type-checked; SwiftUI/UIKit unavailable on Linux) |
| XcodeGen 2.44.1 (built on Linux) `generate --spec project.yml` | generated a project in scratch: 3 targets, local package, assets, privacy manifest resolved. Spec validity only; **never opened in Xcode** |

## Acceptance / DoD status
| Item | Status |
|---|---|
| A-01 fresh install & first launch honest, no fake network/audio | **NOT RUN** (UI test written: `LaunchSmokeTests`). Static guard passes: no network/audio code exists. |
| `xcodebuild -list` and target build | **NOT RUN — blocked, no Xcode** |
| Test target executes with counts | Package tests: **PASS 26/26 on Linux**. App `DoddyTests`/`DoddyUITests`: **NOT RUN** |
| UI never shows fake mic/reminders/accounts/AI | By construction and by source review; not verified on a device/simulator |
| No keys / production ids / user data committed | Verified by guard + review |
| App opens, shows AI identity + privacy summary, art labelled candidate | **Unverified** (needs simulator) |
| Docs consistent, no missing files | Pack integrity PASS; links in new docs written by hand — not link-checked |
| Light/dark, Dynamic Type, VoiceOver, 44pt targets | Colour contrast of tokens unit-tested; everything else **UNVERIFIED** (needs Xcode/Accessibility Inspector/device) |

## Unverified cases (full list)
1. Any Swift code in `DoddyApp/`, `DoddyTests/`, `DoddyUITests/` compiling under Xcode, Swift 6 mode, iOS 17 SDK.
2. Generated Xcode project opening/building; simulator destination name `iPhone 16` existing.
3. UI smoke tests (launch-argument defaults for `@AppStorage`, accessibility identifiers, tab/button queries).
4. Visual result: layout, safe areas, dark mode, Dynamic Type at AX sizes, VoiceOver order, artwork rendering and hide-artwork toggle.
5. `fullScreenCover` First Hello behaviour and dismissal; `Form`/`scrollContentBackground` rendering.
6. Asset catalog loading of the two imagesets (filenames with hyphens copied from the pack).
7. `PrivacyInfo.xcprivacy` acceptance by App Store tooling.
8. Physical-device behaviour of anything.
9. Swift toolchain tarball GPG signature (downloaded over HTTPS from swift.org; signature not checked).

## Risks
- Largest risk: first Mac build may need compile fixes in the unverified SwiftUI code (small surface, ~450 lines).
- Candidate artwork rights and the unresolved brand master (ADR-010) — nothing is claimed as final brand.
- `Unavailable*` adapters are not product behaviour; M1 must replace them with real tested ones.

## Next step
**Stop.** M1 (local memory) is not started. Run the "Needs a Mac" steps in `BUILD_AND_TEST.md`, record results here, then decide the items in `DECISIONS.md`.

## Mac verification — 2026-10-08 (owner's Mac, reported by owner)
| Item | Result |
|---|---|
| Environment | Xcode 27.0 (27A266a), Apple Swift 6.4, macOS 27 host, arm64 |
| Destination | first available iPhone simulator, auto-selected by `scripts/ci.sh` (owner's list began with iPhone 18 Pro) |
| `scripts/ci.sh` | **RESULT: PASS** — pack integrity, forbidden-capability guard, Swift package tests, `xcodegen generate`, `xcodebuild -list`, `xcodebuild test` (unit + UI): `** TEST SUCCEEDED **` |
| Fixes needed to get there | `ci.sh` bash 3.2 empty-array bug (2c860dd); no `AppIcon` set → `ASSETCATALOG_COMPILER_APPICON_NAME: ""` (58d6961). No Swift source changes were needed. |
| Not captured | per-test counts of the app targets (only the summary was pasted; the run's `.xcresult` is on the owner's Mac) |

Still unverified: manual visual/accessibility review (dark mode, largest Dynamic Type, VoiceOver), behaviour on a physical iPhone (Data Protection, backups, force-quit relaunch), and the share sheet exports.
