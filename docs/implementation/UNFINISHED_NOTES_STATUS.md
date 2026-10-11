# Unfinished notes: status (ADR-362)
Date: 2026-10-11. Owner instruction: "start OP-042" (resume interrupted user draft), from the research backlog. User story: "Continue what I was saving." → "Here is your unfinished note." Acceptance: crash/restart consistency.

## What was wrong
What the user typed on the capture screen lived only in the screen's memory. If Doddy was closed from the app switcher, iOS ended it in the background, or it crashed, the words were gone. Cancel offered only Discard or Keep editing.

## What it does now
- **Kept as typed:** while the capture screen has words, they are written to `Application Support/Drafts/unfinished-notes.json` 0.6 s after the last change, and at once when Doddy goes to the background or the screen closes.
  - Every write is read back and compared.
  - The file has iOS's complete file protection: it can only be read while the iPhone is unlocked.
  - Each capture screen has its own draft id, so two screens never write over each other's draft.
  - The note type and the shortcut flag are kept with the words.
- **A draft, never a note** (`UnfinishedNote`, core):
  - It isn't searched, sent to the voice agent, exported, backed up or shown in widgets.
  - It becomes a note only on **Save this detail**, through the same save as before; then the draft is removed.
  - **Discard** removes it, and so does **Delete all memories** (the confirmation now says "any unfinished notes" too).
- **Coming back to it:**
  - **Home:** shows **"Unfinished note"** with its first line and when it last changed, plus **Continue** and **Discard** (Discard asks first).
  - **New capture screen:** an empty one opens with the newest unfinished note: "Here is your unfinished note from … It isn't saved until you tap Save." It also offers **Start a new note instead**, which keeps the unfinished one for later.
  - **Shortcut text:** a capture screen opened with "Save to Doddy" text keeps that text. It only says another unfinished note is waiting, and never mixes the two.
  - **Cancel:** now also offers **Keep it for later**, but only when the copy on the iPhone is confirmed.
- **Limits:**
  - At most 5 unfinished notes; past that, the oldest goes.
  - One untouched for 30 days is removed when Doddy next opens.
  - Photos and recordings aren't kept with a draft. The words written out from a recording are, because they are in the text. A resumed draft says to add the photo or recording again.
- **Failures:**
  - A write that can't be confirmed shows on the capture screen: "Doddy couldn't keep a copy of this unfinished note on this iPhone (…). Save it before you leave." Keep it for later is then not offered.
  - A file Doddy can't read (damaged, or written by a newer Doddy) is set aside next to it, not written over or deleted. The screen says so.
- **Privacy screen:** the "stays on this iPhone" list now includes unfinished notes.
- **Polish:** every new line on the screens has Polish (16 entries). The privacy-screen list is still English-only, as before.

## Files
- **Core:**
  - `UnfinishedNotes.swift` (new): `UnfinishedNote`, `UnfinishedNoteBook`, `UnfinishedNoteResume`.
  - `DataFlow.swift`: one line in `staysOnPhone`.
- **App:**
  - `Infrastructure/UnfinishedNoteStore.swift` (new).
  - `Features/Capture/CaptureView.swift`: draft id, resume, Keep it for later, notices.
  - `Features/Home/HomeView.swift`: `UnfinishedNoteCard`.
  - `MemoryStore.swift` (Delete all), `RootView.swift` (write on background), `SettingsView.swift` (wording).
- **Checks:**
  - `scripts/check_unfinished_note_store.sh` with `scripts/checks/unfinished_note_store_main.swift` (new; in `ci.sh` on Linux).
  - `typecheck_app_logic.sh` now includes the store.
- **Tests:** `UnfinishedNotesTests.swift` (7).

## Verified (Linux, Swift 6.2.1)
- **Core:** `UnfinishedNotesTests` (7) and `DataFlowTests` pass.
- **The store on real files** (`scripts/check_unfinished_note_store.sh`), 8 checks PASS:
  - nothing is written before the delay;
  - a new store reads the same book back, which is the restart;
  - a typed change lands on its own;
  - saving removes the draft and the file;
  - an unreadable file is set aside and kept;
  - Delete all removes both;
  - a failed write is reported.
- **Planted bugs, each caught and then restored:**
  - an emptied screen keeping its draft;
  - a newer file format read anyway;
  - Save not removing the draft from disk;
  - leaving the app not writing a waiting change.
- **App code:** `swiftc -parse` on every changed app file; app-logic type-check PASS (20 files); guard script PASS; Polish catalog PASS (1206 of 1227).

## NOT RUN / unverified
- **Not built:** the app hasn't been compiled with Xcode; the capture screen and Home card are parse-checked only.
- **Not tried on a device:** a real crash or a kill from the app switcher (UN1–UN6).
- **File protection:** that iOS applies `.completeFileProtection` to the file isn't checked off a device.
- **Not covered:**
  - the voice screen's dropped-conversation draft (ADR-360 keeps it on screen only, by decision);
  - drafts on other screens (note edits, lists);
  - photos and recordings in a draft;
  - sync to other devices (the backlog leaves it for later).

## Constitution evidence log
| Rule | How it applies | Enforcing code | Tests run | Gap / claim to limit |
|---|---|---|---|---|
| DOD-06 user-controlled memory | A draft is never a note: only Save makes one; Discard and Delete all remove it; it isn't searched, sent or exported | `UnfinishedNoteBook`, separate file, `CaptureView.save()` removes the draft after the store's save | `testOnlyWordsAreKeptAndEachScreenHasItsOwnDraft`, `testSavedOrDiscardedIsRemoved`, store check "saved draft removed" and "delete all" | Screens not compiled |
| DOD-08 verified status | "Keep it for later" only when the write was read back; a failed write is said | `UnfinishedNoteStore.write()` read-back, `problem` | store check "a failed write is reported", planted bug 4 | — |
| DOD-09 recovery | Crash/restart keeps the words; an unreadable file is kept aside, not overwritten | `flush()` on background, `load()` | `testItSurvivesARestartExactlyAndAStrangeFileIsNotRead`, store check "restart reads back exactly" | No real crash tested |
| DOD-11 observable privacy | Drafts listed under "stays on this iPhone"; protected file; removed after 30 days | `DataFlow.staysOnPhone`, `.completeFileProtection`, `pruned` | `testThePrivacyScreenSaysDraftsStayOnThePhone`, `testAtMostFiveAndOldOnesGo` | Protection class not checked off a device |
