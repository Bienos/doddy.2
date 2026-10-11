# Import from Google Keep and text files: status (ADR-231)
Date: 2026-10-10. Owner: "do all of them" (item 8).

## What ships
- **Settings › Import notes › Import from Google Keep or text files.** The user picks several files in Files:
  - Google Keep notes from Google Takeout (the `.zip` is unpacked in Files first; one `.json` per note);
  - `.txt` / `.md` files.
  Files are read once, on this iPhone. Nothing goes to the internet.
- **Review before anything is saved.** Every note is shown exactly as it will be saved, with "Made …" (or "Date unknown") and the file name. Each has a tick; Import saves only the ticked ones. The button names what will be added ("Import 12 notes and 1 list").
- **Google Keep:**
  - a note is its title, a blank line, then its text, unchanged apart from trimming the ends;
  - a checklist with a title becomes a Doddy list, and the ticked items are ticked;
  - an untitled checklist comes in as a note, one item per line with ✓ for ticked ones, instead of a made-up list name;
  - attachments (photos, recordings) and labels aren't imported, and the note says "Not imported: 1 attachment, labels";
  - notes in Keep's trash are listed, not imported;
  - the date is Keep's creation time; a date in the future is dropped.
- **Text and Markdown:** UTF-8 only (a BOM is accepted). The whole file is one note, or there is one note per paragraph if "One note per paragraph in text files" is on. Text files say nothing about when a note was written, so the date is unknown, never the import time.
- **Never cut, never guessed.** These are listed under "Can't be imported" with the reason:
  - notes longer than the note limit;
  - lists with more than 200 items, or an item over 200 characters;
  - a list name that is taken;
  - non-Keep JSON;
  - files over 2 MB;
  - empty files.
  Notes whose words are already in Doddy (or earlier in this import) show "Already in Doddy." and start unticked; the user can still tick them.
- **Saving and provenance:**
  - Notes go in through the same `restore` path as JSON exports: one transaction, each read back. If anything fails, nothing from that batch stays.
  - Each list is created and its ticks set, read back by the repository.
  - The receipt counts only what was read back.
  - Imported notes have the new source `imported_file`, shown as "Imported from a file".

## Files
- **Core:**
  - `NoteImport.swift`;
  - `MemoryTypes.swift`: `MemorySource.importedFile` (not a capture source; the date is optional);
  - `schemas/memory.schema.json`.
- **App:**
  - `Features/Import/NoteImportViews.swift`;
  - `MemoryStore.importList`;
  - Settings section;
  - `Components.swift`: display name.
- **Tests:** `NoteImportTests` (6, DoddyPersistenceTests).

## Verified (Linux)
- `NoteImportTests` pass. They cover:
  - Keep note words, date and what was left out;
  - a checklist becoming a list, and an untitled one becoming a note;
  - trash, non-Keep JSON, oversized, non-UTF-8 and too-long files;
  - whole-file and per-paragraph text;
  - duplicates and taken list names;
  - the `imported_file` source, with and without a date, restored and read back on SQLite.
- `MemoryRecordTests` and `MemoryRestoreTests` still pass. `swiftc -parse` passes on the new views and Settings.

## NOT RUN / UNVERIFIED
- No Xcode build and no device run. Not tested with a real Takeout export: the Keep fields used (`title`, `textContent`, `listContent`, `isTrashed`, `createdTimestampUsec`, `labels`, `attachments`) are from Google's documented export, not from a file in this repo.
- The file picker with many files, iCloud Drive files that aren't downloaded yet, and the security-scoped reads are not run.

## Gaps / follow-ups
- There is no one-tap "undo this import"; imported notes can be deleted one by one, or found by their "Imported from a file" mark.
- A list made by import is stored like a typed list. Its items have the `typed` source, because adding a new item source would need a table rebuild.
- In a Keep checklist with the same item both open and ticked, it comes in once, as ticked.

## Constitution evidence log
| Rule | Enforcing code | Tests | Gaps |
|---|---|---|---|
| DOD-06 user_controlled_relevant_memory | Full review; only ticked notes saved; duplicates unticked; exact words | `testKeepNoteKeepsTheWordsAndSaysWhatIsLeftOut`, `testDuplicatesAndTakenListNames` | UI not compiled |
| DOD-08 verified_status_and_receipts | `restore` reads back in one transaction; the receipt counts read-back results only | `testImportedNotesAreMarkedAndRestoredExactly` | List tick read-back is per repository call |
| DOD-02 honesty_over_agreeableness | No invented dates or list names; never cut; reasons shown | `testTrashOtherJSONAndBadFilesAreNotImported`, `testKeepChecklistBecomesAListWithTickedItems` | — |
| DOD-11 observable_privacy | Files read on device; nothing sent | — | — |
