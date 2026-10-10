# M1 status — local memory loop
Date: 2026-10-08. Built on owner instruction "don't make unnecessary tests, just build stuff".
Storage was exercised on real SQLite (Linux and macOS). The app built and its unit + UI tests passed on Xcode 27.0 / iPhone simulator — see "Mac verification" below.

## Built
| PRD M1 item | What exists |
|---|---|
| 1 First launch, no account, AI disclosure | First Hello + Home/Settings copy |
| 2 Explicit text capture, ≤5,000, no truncation, save only after durable success | `CaptureView` → `NewMemory` validation → transaction + read-back; draft kept on failure; receipt only with committed record. Since 2026-10-10 a note with the same words as a saved one gets a "You saved this already" warning first (ADR-184) |
| 3 Immutable raw text, editable current text, timestamps, source, type | `MemoryRecord` + `memories` table; type picker |
| 4 List + deterministic lexical search, diacritic-insensitive, source shown, no-match message | Memories tab list + `.searchable`; FTS5; matched terms and source on each row; `RecallCopy.noMatch`. Since 2026-10-09 also Polish/English counterparts, spoken numbers, word endings and typos (`RecallMatching`, ADR-093). Since 2026-10-10 the list can be filtered by note type (ADR-182) |
| 5 Edit, copy, export JSON/text, delete one, delete all with confirmation | Detail screen, `CorrectionView`, Settings export/delete-all. Since 2026-10-10 the reviewed profile and style settings have their own export (ADR-176), and a JSON memory export can be restored (ADR-178); deleting one note can be undone for 10 seconds (ADR-183); up to 10 notes can be pinned to the top of the list (ADR-187); memories can also be exported as Markdown (ADR-203) |
| 6 Private session mode | Built later as a Private toggle on the Talk screen (ADR-170); Ask was already never stored |
| 7 VoiceOver / Dynamic Type / 44pt / light-dark | Semantic headings, combined rows, 54pt buttons, token colours; the app's six animations follow Reduce Motion (ADR-201); **unverified on device** |
| 8 Content-free telemetry | **Not built** (no telemetry at all) |

## Executed
`scripts/ci.sh --core-only` → pack PASS, guard PASS, **28 tests, 0 failures** (incl. 2 SQLite tests: save/correct/search/reopen/delete/delete-all and export); app sources syntax-parse; XcodeGen generates the project with `DoddyPersistence` linked.

## Not run
Manual UI review, Data Protection behaviour, backups, share sheet, force-quit relaunch on a physical device, and acceptance rows A-02…A-13 as end-to-end UI flows (only smoke UI tests exist, by owner instruction).

## Mac verification — 2026-10-08 (owner's Mac, reported by owner)
| Item | Result |
|---|---|
| Environment | Xcode 27.0 (27A266a), Apple Swift 6.4, macOS 27 host, arm64 |
| Destination | first available iPhone simulator, auto-selected by `scripts/ci.sh` (owner's list began with iPhone 18 Pro) |
| `scripts/ci.sh` | **RESULT: PASS** — pack integrity, forbidden-capability guard, Swift package tests, `xcodegen generate`, `xcodebuild -list`, `xcodebuild test` (unit + UI): `** TEST SUCCEEDED **` |
| Fixes needed to get there | `ci.sh` bash 3.2 empty-array bug (2c860dd); no `AppIcon` set → `ASSETCATALOG_COMPILER_APPICON_NAME: ""` (58d6961). No Swift source changes were needed. |
| Not captured | per-test counts of the app targets (only the summary was pasted; the run's `.xcresult` is on the owner's Mac) |

Still unverified: manual visual/accessibility review (dark mode, largest Dynamic Type, VoiceOver), behaviour on a physical iPhone (Data Protection, backups, force-quit relaunch), and the share sheet exports.
