# M1 status — local memory loop
Date: 2026-10-08. Built on owner instruction "don't make unnecessary tests, just build stuff".
Still **no Xcode**: the iOS app has not been compiled or run. Storage was exercised on real SQLite (Linux).

## Built
| PRD M1 item | What exists |
|---|---|
| 1 First launch, no account, AI disclosure | First Hello + Home/Settings copy |
| 2 Explicit text capture, ≤5,000, no truncation, save only after durable success | `CaptureView` → `NewMemory` validation → transaction + read-back; draft kept on failure; receipt only with committed record |
| 3 Immutable raw text, editable current text, timestamps, source, type | `MemoryRecord` + `memories` table; type picker |
| 4 List + deterministic lexical search, diacritic-insensitive, source shown, no-match message | Memories tab list + `.searchable`; FTS5; matched terms and source on each row; `RecallCopy.noMatch` |
| 5 Edit, copy, export JSON/text, delete one, delete all with confirmation | Detail screen, `CorrectionView`, Settings export/delete-all |
| 6 Private session mode | **Not built** |
| 7 VoiceOver / Dynamic Type / 44pt / light-dark | Semantic headings, combined rows, 54pt buttons, token colours; **unverified on device** |
| 8 Content-free telemetry | **Not built** (no telemetry at all) |

## Executed
`scripts/ci.sh --core-only` → pack PASS, guard PASS, **28 tests, 0 failures** (incl. 2 SQLite tests: save/correct/search/reopen/delete/delete-all and export); app sources syntax-parse; XcodeGen generates the project with `DoddyPersistence` linked.

## Not run
Everything in the app target on iOS: compile, UI, Data Protection behaviour, backups, share sheet, force-quit relaunch on device, acceptance rows A-02…A-13 as UI flows.
