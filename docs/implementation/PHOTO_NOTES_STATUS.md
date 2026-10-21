# Photo notes status (ADR-218)
Date: 2026-10-10. Owner: "do all of them" (item 3 of the proposed list).

## What ships
- **Add a photo** while writing a note (Capture). Apple's photo picker runs outside Doddy, so iOS asks nothing and Doddy gets only the one photo picked. No camera, no photo library access.
- **Reading the text on this iPhone.** The photo is scaled so its longer side is at most 2,048 px and kept as JPEG. Apple's Vision reads its text on the phone (accurate level, language correction off, so codes and passwords come back as printed). Lines are trimmed, empty ones dropped, and the text is cut at 3,000 characters on a whole line.
- **The user checks the words.** The read text is added to the editor after anything already typed, with "Reading photos makes mistakes, so check it before saving" (and "only the first part was added" when cut). No text found → "Add a few words so you can find the note later". The saved note is what the user accepted; its source stays `explicit_text`, so search, Doddy, reminders and export work on it like any note.
- **Saving.** The note is saved first. Then the photo file is written and read back, then linked to the note (`memory_photos`, read back). If the link fails the file is deleted. If the photo can't be kept, the receipt says "The note was saved, but its photo couldn't be kept on this iPhone".
- **On the note.** The photo shows above the type picker with "Kept only on this iPhone, never sent anywhere. Not in exports." and **Remove photo** (confirmation; the words stay). A missing file is said plainly.
- **Delete and Undo.** Deleting the note deletes its photo link (cascade). The file is kept while Undo is offered, put back on Undo, and deleted when the Undo bar goes or the next note is deleted. Delete all removes every photo file. Leftover files with no link are cleaned once per launch, only after the links were read.
- **Where files live.** A `NotePhotos` folder next to the notes database: protected until first unlock, included in iPhone backups like the database (ADR-028). UI-test fixtures and in-memory launches get their own folder, so they never touch real photos.
- **Never sent.** Photos and their pixels never go to ElevenLabs, the Doddy server or anyone. Only the words the user saved can reach the voice agent, as with any note.

## Files
- Core: `PhotoNotes.swift` (`PhotoLimits`, `MemoryPhoto`, `PhotoRepository`, `RecognizedText`); `SQLitePhotoRepository.swift`; migration `v7_memory_photos` in `DoddyDatabase.swift`.
- App: `Features/Photos/PhotoFiles.swift`, `PhotoTextReader.swift`, `PhotoViews.swift`; `CaptureView`, `MemoryDetailView`, `MemoryStore` (+Lists), `AppEnvironment`, Settings copy.
- Checks: `scripts/check_forbidden_capabilities.sh` (Vision and the picker only in `Features/Photos`; camera, `PHPhotoLibrary` authorization, `UIImagePickerController`, `AVCaptureSession`, camera/library permission keys refused); `scripts/typecheck_app_logic.sh` now type-checks `PhotoFiles.swift` and the photo code in `MemoryStore`.
- Tests: `PhotoNotesTests` (5, DoddyCore); `MemoryStoreTests.testPhotoFollowsItsNoteThroughDeleteUndoAndRemove` (Xcode only).

## Verified (Linux, Swift 6.2.1)
- `scripts/ci.sh --core-only`: PASS (DoddyCore tests incl. `PhotoNotesTests`, app logic type-check, capability guard).
- `swiftc -parse` on `PhotoViews.swift`, `PhotoTextReader.swift`, `CaptureView.swift`, `MemoryDetailView.swift`, `AppEnvironment.swift`, `MemoryStoreTests.swift`.

## NOT RUN / UNVERIFIED
- No Xcode build. SwiftUI, PhotosUI, UIKit and Vision code is parsed only, never compiled.
- Text reading never run: quality on receipts, handwriting, Polish diacritics and dark photos is unknown.
- HEIC/large photo decoding, memory use on a 48 MP photo, and the 40 MB refusal not run.
- `testPhotoFollowsItsNoteThroughDeleteUndoAndRemove` not run.
- Data Protection on the photo files and their presence in an iPhone backup not checked on a device.

## Decisions for the owner
- **Camera capture:** owner said no (ADR-224), then yes on 21 Oct (ADR-569): **Take a photo** next to Add a photo, and "take a photo" by voice, both through iOS's camera screen. The photo is prepared and kept exactly as a picked one; nothing is saved to the photo library.
- **Photos in the encrypted backup file** (ADR-219 work): included by default there, since that file is the user's own.

## Constitution evidence log (docs/trust/config/doddy_rules.yaml)
| Rule | What enforces it here | Tests run | Gaps / claims to limit |
|---|---|---|---|
| DOD-06 user_controlled_relevant_memory | Read text is only a draft in the editor; nothing is saved until Save, and the saved words are what the user accepted | `testAddingReadTextKeepsTheUsersWordsFirst`, `testReadTextIsJoinedTrimmedAndCutAtAWholeLine` | UI path not compiled |
| DOD-08 verified_status_and_receipts | File written and read back, link read back; "couldn't be kept" said when the photo fails after the note saved | `testAttachReplaceDetachAndCascade` | File write path only type-checked on Linux |
| DOD-11 observable_privacy | Picker only, no permission; Vision on device; files in the app's folder, never sent; Settings and the note say "not in exports"; guard refuses camera/library APIs | capability guard PASS | iPhone backups include the photos (stated in Settings) |
| DOD-02 honesty_over_agreeableness | "Reading photos makes mistakes, so check it"; language correction off; cut text is announced | — | Recognition accuracy is Apple's and cannot be guaranteed |

Don't claim: "Doddy understands your photos", "accurate text reading", "photos are backed up by Doddy", or that any of this was run on a device.
