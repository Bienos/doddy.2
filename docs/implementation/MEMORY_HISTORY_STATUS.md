# Every version of a corrected note: status (ADR-236)
Date: 2026-10-10. Owner instruction: "move to 2", item #2 from the research backlog: OP-003 "Memory correction and history". Earlier, a correction overwrote the current wording, so only the original and the latest wording were kept.

## What the user gets
- **Note screen:** a corrected note shows, under its current wording:
  - "Edited <time>", as before.
  - **Earlier versions (N):** every wording between the original and the current one, newest first, each with "Version n · <time>".
  - **Original capture:** unchanged.
  - A line saying only the original and current wording are shown, when the note has no full history (see "Upgrade" below).
- **Search** still looks only at the current wording. A corrected-away wording is not offered as an answer.
- **Delete** removes every version. The message now says so. **Undo** brings every version back.
- **Exports:**
  - JSON carries a `corrections` list.
  - Text and Markdown show each earlier wording with its time.
  - **Restore** from JSON brings the history back.
- **Privacy:** "What stays on this iPhone" lists "Earlier wordings of notes you corrected, except in files you export".

## How it is stored
- **Table:** `memory_corrections`, created by migration `v9_memory_corrections` (named `v5_…` before the merge with the lists and photos line, whose `v5`–`v8` come first) in `DoddyDatabase.swift`.
  - One row per correction: note id, number from 1, text, time.
  - Primary key is (note, number). CHECKs refuse a number below 1 and blank text.
  - The note's foreign key cascades on delete, and `secure_delete` stays on.
- **Original:** stays in `memories.raw_text`.
- **Writing a correction:** the new current text and the correction row are written in one transaction, and both are read back before success.
- **Upgrade:** each note corrected earlier gets one row, its current wording at its edit time. Wordings in between were never stored, so they can't be shown.
- **Notes without trustworthy history** (restored from an export made before this): correcting one first records its current wording, then the new one, so nothing is lost.
- **Trust rule:** corrections count as a note's history only if they are numbered 1…n without gaps and end at its current wording (`MemoryHistory.consistent`). Otherwise they are not shown or restored.

## Files
- **Core:**
  - `MemoryHistory.swift`, new: `MemoryCorrection`, `MemoryVersion`, `MemoryHistory`.
  - `MemoryTypes.swift`: `invalidCorrectionNumber`.
  - `Ports.swift`: `corrections(of:)`, `allCorrections()`, `restore(_:corrections:)`.
  - `Search.swift`: JSON and text exports.
  - `MarkdownExport.swift`.
  - `MemoryRestore.swift`: reads corrections, `unreadableCorrection`, plan carries corrections.
  - `DeletedNote.swift`: carries corrections for undo.
  - `DataFlow.swift`.
- **Persistence:** `DoddyDatabase.swift` (v9), `SQLiteMemoryRepository.swift`.
- **App:**
  - `MemoryStore.swift`: loads corrections, `history(of:)`, delete/undo/restore pass them.
  - `MemoryDetailView.swift`.
  - `SettingsView.swift`: exports, restore, damaged-correction message.
- **Tests:**
  - `DoddyPersistenceTests/MemoryHistoryTests.swift`: 8 tests.
  - `DoddyCoreTests/MemoryHistoryCoreTests.swift`: 5 tests.
  - A new line in `DataFlowTests`.

## Verified (Linux, Swift 6.1.2)
- `swift test` on DoddyCore: 437 tests pass, 13 of them new. The new tests cover:
  - Three corrections kept in order with their times, and still there after reopening the file.
  - Only the current wording is searchable.
  - Delete and delete-all remove the history.
  - Undo and export → restore bring it back.
  - Corrections with a gap are not restored as history.
  - A note without history keeps its current wording when corrected again.
  - Upgrade from a real v4 database file (through v5–v8 of the lists and photos line).
  - The table refuses a correction for a missing note, number 0, or blank text.
  - The history model and its trust rule.
  - Text, Markdown and JSON exports, including reading an export made before this.
  - A damaged correction refuses the file.
- **Planted bug:** dropping the "keep the current wording first" step made `testCorrectingANoteWithoutHistoryKeepsItsCurrentWording` fail. The code was restored.
- `scripts/typecheck_app_logic.sh`: `MemoryStore.swift` compiles against DoddyCore.
- `swiftc -parse` on `MemoryDetailView.swift` and `SettingsView.swift`.
- `scripts/ci.sh --core-only`: PASS for core-only scope (437 package tests; guards, pack, agent specs, backend, gateway and messaging pass; messaging database tests SKIPPED; iOS build NOT RUN).

## NOT RUN / unverified (needs a Mac and an iPhone)
- The note screen's "Earlier versions" list, its VoiceOver reading and Dynamic Type. Settings exports and restore with history. Mac checklist items M12 and E6.
- An older Doddy build reading a new export: by design it should ignore `corrections` and restore the notes without history. This was not run against an older build.

## Constitution evidence log
| Rule | How it applies | Enforcing code | Tests run | Gap / claim to limit |
|---|---|---|---|---|
| DOD-06 user-controlled relevant memory | Every wording the user gave is kept, never invented; in-between wordings from before this update are not made up | `MemoryHistory`, `SQLiteMemoryRepository.update`, migration v5 | `MemoryHistoryTests`, `MemoryHistoryCoreTests` | Notes corrected before this show original + current only |
| DOD-08 verified status | A correction counts as saved only after the note and its history row are read back in the same transaction | `SQLiteMemoryRepository.update` | `testEveryCorrectionIsKeptInOrderAndSurvivesReopening` | — |
| DOD-09 correction and recovery | Corrections keep what they replace; delete is undoable with history | Repository, `DeletedNote`, `MemoryStore.undoDelete` | `testUndoAndRestoreBringTheWholeHistoryBack` | Undo bar UI not run on a device |
| DOD-11 observable privacy | History stays on the phone, is listed on the privacy screen, is deleted with its note, and is in every export | `DataFlow.staysOnPhone`, cascade + `secure_delete`, exports | `testDeletingANoteDeletesItsHistory`, `DataFlowTests` | iOS Data Protection on the file is unchanged and not re-tested here |
