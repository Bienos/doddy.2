# Voice memos status (ADR-230)
Date: 2026-10-10. Owner: "9 ok" (voice memos approved, on-device recognition required), then "do all of them".

## What ships
- **Recording.** On Capture, "Record a voice memo" records up to 5 minutes (AAC, mono, 22 kHz) to a temporary file.
  - The microphone is on only between Record and Stop. It uses the same microphone permission as talking to Doddy.
  - It stops by itself at 5:00, or when iOS stops it (for example, a phone call).
  - A recording shorter than half a second is dropped as a mis-tap, and the user is told.
- **Writing it out on this iPhone.** Apple's Speech framework is used with `requiresOnDeviceRecognition = true`, punctuation on, and no partial results.
  - It uses the iPhone's first language that can be written out on the device. If the iPhone has several such languages, "Write it out in another language" offers them. The new text replaces the earlier written-out text only where that text is still unchanged in the editor; otherwise it is added after it.
  - If on-device recognition isn't available for the language, nothing is written out, nothing is sent, and the user is told so.
  - Other outcomes the user is told about: speech recognition off, no words heard, or a failure.
- **The user checks the words.** The written-out text is added to the editor after anything already typed, with "Speech-to-text makes mistakes, so check it before saving" (plus "only the first part was added" when cut at 3,000 characters on a whole word). The saved note is what the user accepted. Its source stays `explicit_text`, as with photo notes.
- **Saving.**
  1. The note is saved first.
  2. Then the recording is copied into a `NoteAudio` folder next to the database (protected until first unlock) and read back.
  3. Then it is linked to the note (`memory_audio`, read back). If the link fails, the file is deleted.
  4. If the recording can't be kept, the receipt says "The note was saved, but its recording couldn't be kept on this iPhone".
  The temporary file is deleted after saving, on "Don't keep this recording", and on Discard.
- **On the note.** Play/pause with position and length, and "Kept only on this iPhone, never sent anywhere. Not in exports; in a backup file only if you include it." **Remove recording** asks for confirmation; the words stay. A missing file is said plainly.
- **Delete and Undo.** As with photos:
  - deleting the note deletes the link (cascade);
  - the file is kept while Undo is offered, and put back on Undo;
  - Delete all removes every recording;
  - files with no note are cleaned once per launch, after the links were read.
- **Never sent.** Recordings never go to ElevenLabs, the Doddy server, Apple's speech servers or anyone. They are not in exports. They go in the encrypted backup file only when "Include voice memos" is on (ADR-234, on by default, like photos). Like the database, they are included in iPhone backups.

## Files
- **Core:**
  - `VoiceMemos.swift`: `VoiceMemoLimits`, `MemoryAudio`, `AudioRepository`, `VoiceMemoText`;
  - `RecognizedText.Result` now has a public init;
  - `SQLiteAudioRepository.swift`;
  - migration `v8_memory_audio`.
- **App:**
  - `Features/VoiceMemos/AudioFiles.swift`, `VoiceMemoAudio.swift` (recorder, player), `VoiceMemoTranscriber.swift` and `VoiceMemoViews.swift`;
  - `CaptureView`, `MemoryDetailView`, `MemoryStore` (+Lists), `AppEnvironment`;
  - Settings privacy text;
  - `project.yml`: the speech-recognition permission text, and the microphone text mentions memos.
- **Checks:** `scripts/check_forbidden_capabilities.sh`:
  - Speech only in `Features/VoiceMemos`;
  - every recognition request there must set `requiresOnDeviceRecognition = true`, and `= false` is refused (checked by flipping it: the guard failed as expected, then restored);
  - AVFoundation only in Voice and VoiceMemos; ElevenLabs only in Voice;
  - `NSSpeechRecognitionUsageDescription` is allowed.
  - `scripts/typecheck_app_logic.sh` now type-checks `AudioFiles.swift` and the recording code in `MemoryStore`.
- **Tests:** `VoiceMemoTests` (4, DoddyPersistenceTests).

## Verified (Linux, Swift 6.2.1)
- `VoiceMemoTests` pass. They cover:
  - file names;
  - duration limits and text;
  - cutting on a whole word;
  - writing out again only swaps untouched text;
  - attach, refuse (no note, bad name, too long), cascade on delete, and detach.
- `scripts/ci.sh --core-only` passes, including the capability guard and the app-logic type-check (13 files).
- `swiftc -parse` passes on the new and changed UI files.

## NOT RUN / UNVERIFIED
- No Xcode build. AVFoundation, Speech and SwiftUI code is parsed only, never compiled.
- Nothing recorded, played or written out on a device. Unchecked:
  - transcription quality in Polish and English;
  - which languages support on-device recognition on the owner's iPhone;
  - the "no speech" error code (1110);
  - behaviour when the voice conversation holds the audio session;
  - interruption by a call;
  - file sizes.
- Data Protection on the recordings, and whether they are in an iPhone backup, are not checked on a device.

## Decisions for the owner
- Owner, 2026-10-11 ("Yes add them"): voice memos go in the encrypted backup file as an option, like photos (ADR-234).

## Constitution evidence log
| Rule | Enforcing code | Tests | Gaps |
|---|---|---|---|
| DOD-06 user_controlled_relevant_memory | Written-out text is only a draft in the editor; nothing is saved until Save | `testWritingOutAgainSwapsOnlyTheUntouchedText` | UI not compiled |
| DOD-08 verified_status_and_receipts | File copied and read back, link read back; "couldn't be kept" said when it fails after the note saved | `testAttachDetachAndCascade` | File copy path only type-checked on Linux |
| DOD-11 observable_privacy | On-device recognition required and guarded; recordings in the app's folder, never sent; not in exports or backup files; stated on the note, in Settings and in the permission texts | capability guard PASS (and its FAIL when flipped) | iPhone backups include recordings |
| DOD-02 honesty_over_agreeableness | "Speech-to-text makes mistakes, so check it"; cut text announced; "can't write it out without sending it, so Doddy didn't" | `testTranscriptIsTrimmedAndCutAtAWholeWord` | Accuracy is Apple's and can't be guaranteed |

Don't claim: "Doddy transcribes perfectly", "works in every language", or that any of this was run on a device.
