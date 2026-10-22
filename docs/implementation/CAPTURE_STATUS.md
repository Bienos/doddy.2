# DODDY Capture: status (22 Oct 2026, ADR-579 to ADR-583)

Branch `claude/gifted-pascal-3e117c`. Audit and platform limits: `CAPTURE_AUDIT.md`. Owner brief: "DODDY Capture — Native iPhone Recording, AI Transcription, Conversation Intelligence & Personal Memory" (the pasted brief stopped in the middle of Part 10; what is below follows what was there).

## In one paragraph
The recording logic, the database and the transcript checks are built and **tested on Linux (1,511 tests, 0 failures)**. The iPhone layer (AVAudioRecorder, the Live Activity, the intents and control, Speech, the screens) is **written but has never been compiled or run: no Xcode here, so the native build is BLOCKED / NOT RUN**. It has a syntax parse and an independent read-through, nothing more. Nothing in the second group may be called "works", "tested" or "implemented" until a hosted Mac build compiles it and an iPhone has run the list in "Device test plan". The **written summary and the written answers are not built**: that needs an owner decision (ADR-582).

## What exists

| Area | State | Where |
|---|---|---|
| Recording state machine (idle, preparing, recording, paused, interrupted, finalizing, finished, failed), single-session rule, limits | **Tested on Linux** (39 tests, a 60,000-event random test, 3 rules broken on purpose to prove the tests notice) | `DoddyCore/Capture/CaptureStateMachine.swift` |
| Interruption policy, gap ledger, ten-minute parts | **Tested on Linux** | same, `CaptureModels.swift` |
| Crash recovery planner | **Tested on Linux**; never tried on real files from a real kill | `CaptureRecovery.swift` |
| Recordings, parts, words, full-text search, links to notes (`v16_recordings`) | **Tested on Linux** (26 tests on real SQLite, including killing and reopening a file, and checking the file's bytes after a delete) | `DoddyPersistence/SQLiteRecordingRepository.swift` |
| Transcript grouping, parts end to end, quality, corrections, Markdown export, search windows | **Tested on Linux** | `Transcript.swift`, `TranscriptRetrieval.swift` |
| Checks on a model's rundown and answers; prompts that fence the transcript; provider contract | **Tested on Linux with invented model output.** **No provider is wired.** | `RecordingIntelligence.swift` |
| Live Activity content (phases and numbers, never words), button words, the notice | **Tested on Linux** | `CapturePresentation.swift`, `CaptureNotice.swift` |
| Microphone pill and Stop listening cover a recording | **Tested on Linux** (the model); the pill itself is app code | `ListeningPrivacy.swift` |
| Recorder (`AVAudioRecorder`, parts, interruptions, recovery, permission, storage) | **Written, not compiled, not run** | `DoddyApp/Features/Recordings/RecordingCoordinator.swift`, `RecordingFiles.swift` |
| Live Activity: compact, minimal, expanded, Lock Screen; Stop, Pause, Resume | **Written, not compiled, not run** | `DoddyWidgets/DoddyCaptureLiveActivity.swift`, `Shared/CaptureActivity/` |
| Start intent (Siri, Shortcuts), `AudioRecordingIntent` and control (Action Button), Open Latest Recording | **Written, not compiled, not run** | `Shared/Shortcuts/StartRecordingIntent.swift`, `DoddyWidgets/StartRecordingControl.swift` |
| On-device transcription (`SFSpeechRecognizer`), one at a time, resumes at launch | **Written, not compiled, not run** | `RecordingTranscriber.swift` |
| Library, detail page (player, transcript, search, "find the parts", corrections, Remember this, export, delete) | **Written, not compiled, not run** | `RecordingsView.swift`, `RecordingDetailView.swift`, `RecordingPlayer.swift` |
| Capability guard (audio and speech in one more folder; nothing may be sent from it) | **Run, passes** | `scripts/check_forbidden_capabilities.sh` |

## Where a recording can start from
iOS is reported not to allow a recording to begin from a cold background (ADR-580), so every start **opens Doddy**; the recording then carries on in the background and with the screen locked. Open: supported. Background alive, suspended, locked (needs unlock), terminated (cold launch): handled only by opening Doddy first; **none of it seen on a device.** There is no start with no screen at all. The experiment is to set `openAppWhenRun = false` on `RecordWithDoddyIntent` and read the Console (subsystem `com.bienos.doddy2.dev`, category `capture`); if the first audio fails with "Target is not foreground" the finding stands.

## Tests actually run
Environment: Linux x86_64 (Ubuntu 24.04), Swift 6.1.2 (the version CI uses), no Xcode, no Apple SDK.

| Command | Result |
|---|---|
| `swift test --package-path Packages/DoddyCore …` (full) | **1,513 tests, 0 failures.** Baseline before any change: 1,371. The 142 new tests are 39 + 28 + 22 + 25 + 28 in five new suites |
| `scripts/check_forbidden_capabilities.sh` | PASS |
| `python3 -I tools/build_strings_catalog.py --check` | PASS (catalogs regenerated; Polish 1,731 of 1,810 UI strings; the rest of the languages show new screens in English) |
| `scripts/typecheck_app_logic.sh` | PASS, 25 app files (it failed first: my edit to `ShortcutRouter` needed a field in its stand-in; fixed) |
| `swiftc -parse -swift-version 6` on the 24 app, shared and widget Swift files I touched | all parse. **Syntax only** |
| Independent read-through of the app layer (a reviewing agent read every app, widget and shared file I added or touched) | **Done: no definite compile error found, 15 other findings** (table below). A read-through, not a compile |
| `scripts/ci.sh --core-only` (everything that runs without a Mac) | **PASS for core-only scope, run on the final tree** (exit 0). It prints `NOT RUN  iOS app build + tests`: the app is not verified by it |

### What the read-through found, and what was done
Fixes are **not compiled or run** either. Each was re-read and the files re-parsed.

| # | Finding | Result |
|---|---|---|
| 1 | Resume tapped twice started two recorders on one file; a late "started" could make the machine delete the whole recording | **Fixed in the app:** a start already in flight is ignored; a start the machine no longer waits for is stopped and never reported. The machine's own rule (a stray "started" while idle or mismatched means discard) is unchanged |
| 2 | Stop during a Pause's save could leave that part out of the save and remove its audio | **Fixed:** the save waits (up to 2 s) for any close in flight |
| 3 | The microphone stayed open while the "Saving…" update was sent | **Fixed:** the part is closed first |
| 4 | No stale date or heartbeat on the Live Activity; a card removed by iOS was never noticed | **Fixed:** while audio is written, a 60 s heartbeat keeps a 150 s stale date ahead (as the voice island does); an ended or dismissed card is reported to the machine. Paused and interrupted cards have no stale date |
| 5 | Voice memos, read-aloud, voice samples and call rehearsal could take the audio session from a recording | **Fixed:** each refuses while a recording runs; a recording refuses to start while a voice memo records. Not checked on a device; "Hey Doddy" listening was not audited |
| 6 | Background task ended after the expiration handler returned | **Fixed:** ended inside the handler |
| 7 | `InterruptionReason.routeDisconnected` might not exist | **Checked, no change:** Apple's documentation lists it from iOS 17.0, our minimum |
| 8 | Dragging the playback slider rebuilt the player and the audio session on every tick | **Fixed:** seeks in place; rebuilds the queue only across a part boundary |
| 9 | The page stopped following after "Write out again" | **Fixed:** the follow loop restarts when work starts |
| 10 | The orphan-folder sweep could delete the folder of a recording that began meanwhile | **Fixed:** skipped while a recording is active |
| 11 | A recorder that stopped for a call could be retried before iOS announced the interruption | **Mitigated:** 0.7 s grace before the machine hears "stopped by itself". The race is not proven or disproven |
| 12 | A rotation whose new part's row failed to save left audio unreachable | **Fixed:** retried at each checkpoint and before the save; if it still fails the save fails and the recording stays for recovery |
| 13 | A part already being written out kept running when a recording started | **Partly fixed:** no part starts while recording; one in progress finishes (its cost on a recording is unmeasured) |
| 14 | The island's three buttons would appear as Shortcuts actions | **Fixed:** not discoverable, like the other Live Activity buttons |
| 15 | "Open Latest Recording" did nothing with Recordings already open | **Fixed:** the screen watches for it |

**Not run, and why:** `xcodegen`, `xcodebuild` (no Xcode), any simulator or device test, UI tests, the hosted macOS CI. **The app, the widget extension and the UI tests have not been built with these changes.**

## Device test plan (nothing here has been done)
Run on an iPhone with Doddy installed from this branch, a free-team build is enough for items 1 to 9. Read the Console for `capture`.

| # | Do | Expected | What it settles |
|---|---|---|---|
| 1 | Home › ••• › Record, accept the notice | Pill "Doddy is recording", orange dot, Live Activity with a running time; Stop saves; the recording is in Recordings | The whole slice compiles and starts |
| 2 | Lock the screen for 2 minutes, unlock, Stop | Recording carried on while locked; length about right | Background audio with `.record` category |
| 3 | Lock Screen card: Pause, Resume, Stop | Each works; "Paused" shows the microphone is off | The island's intents run in the app |
| 4 | Action Button › Controls › Record with DODDY (also unlocked and locked) | Doddy opens, records; locked asks to unlock first | The control; the start rule (ADR-580) |
| 5 | "Hey Siri, record this meeting in Doddy" | Says "Recording." only after audio | Siri phrase; honest answer |
| 6 | Press the Action Button three times fast | One recording, the others say already recording | One session |
| 7 | A call, FaceTime, an alarm, Siri during a recording | Island says interrupted; after it ends, resumes if iOS allows, otherwise "Resume"; the transcript shows the gap; the audio before it is kept | Interruptions (`AVAudioSession` notifications) |
| 8 | AirPods on and off; another app takes the microphone; Control Center audio route switch | Carries on or says why; nothing lost | Route changes |
| 9 | **Force-quit Doddy 3 minutes into a recording, reopen** | "Doddy was closed while recording. N:NN was recovered", and the audio plays | **The `.caf` kill-recovery assumption: the most important test** |
| 10 | Record 25 minutes | Parts rotate at 10 and 20 minutes; no audible gap; one continuous transcript | Rotation |
| 11 | Fill the iPhone to under 200 MB, then under 50 MB while recording | Start refused with a sentence; recording stops and is saved | Storage guard |
| 12 | Start a voice conversation while recording; start a recording during one | Each refuses with a sentence; **then talk to Doddy normally and check the ElevenLabs log** | The guard in `VoiceSessionController.start` |
| 13 | Polish speech, English speech, a language this iPhone lacks on-device | Words appear / "can't write this language out"; nothing sent | On-device recognition; which languages |
| 14 | Mixed Polish and English in one recording; "Write the words out again" in the other language | Each pass writes its own language | The one-language limit |
| 15 | Remember this on a line | A note in Memories ending "From the recording …"; deleting the recording keeps the note | Provenance |
| 16 | Delete a recording | Gone from the list; storage freed; Memories search does not find its words | Delete |
| 17 | Swipe the Lock Screen card away while recording; then Stop in Doddy | Recording unaffected; saved | Island dismissed |
| 18 | Settings › Live Activities off, then start from the control | Refuses with a sentence; starting inside Doddy still works | Activity rule |
| 19 | VoiceOver on the Recordings page and the Lock Screen card | Controls and timer are spoken | Accessibility |
| 20 | Pause, then tap Resume twice quickly (also from the Lock Screen) | One recording carries on; the part plays back without a glitch | No double start |
| 21 | Pause, then Stop at once, ten times | Every recording keeps all its audio | The Stop-during-close wait |
| 22 | Force-quit Doddy while recording and watch the Lock Screen card for three minutes | The card turns "can't tell whether it's still recording" and drops its buttons | Stale date and heartbeat |
| 23 | While recording: start a voice memo, play a memo, Read aloud, a voice sample, a call rehearsal | Each refuses with a sentence; the recording is untouched | Audio session guards |
| 24 | Drag the playback slider while playing | Smooth, no gaps, no restart per tick | In-place seek |

## Security and privacy
- **Nothing leaves the iPhone** (audio, words, search, the notes made from them). The capability guard bans any networking in `Features/Recordings`. Not yet checked with a network proxy on a device.
- **Recording other people** is regulated differently by country and situation. Doddy shows the recording the whole time and makes the user read a notice once; it does not decide the law. **The notice wording needs the owner and a lawyer** (ADR-581). Apple's App Review reads the permission texts; they were changed (nine languages, machine drafts).
- **Deletion removes words from the search index and the file** (ADR-583). **Notes have the same gap** and it is not fixed here.
- Audio files are readable after the first unlock, so a stolen unlocked-once phone has them. They are marked out of device backups (set, not verified) and are not in the encrypted Doddy backup.
- A transcript or summary on the Lock Screen: never; the Live Activity carries only phases and numbers (a test checks the encoded keys).
- **Settings › Privacy and "What leaves this iPhone" were not updated** for recordings. Their claims stay true (nothing is sent), but they say nothing about recordings.
- Export writes the transcript to the temporary folder for the share sheet; iOS clears it later.

## Decisions needed (owner)
1. **The rundown and answers (ADR-582):** a server endpoint, Apple's on-device models, or neither; and whether summaries run on a tap or after a standing yes. Without this the page says "No summary yet".
2. **Notice wording** (legal), and whether Poland and the UK need more.
3. **Permission text translations** (nine languages) and the new Polish strings: native review (`l10n/REVIEW_NOTES.md`).
4. **The 4-hour cap** (Live Activity limit is 8 hours) and the 10-minute part length.
5. **Fix the notes' deletion gap** (separate task suggested).
6. Whether Doddy's orange should be `#EC803F` (island, cues, used here) or `#FF6A00` (candidate brand tokens); both exist in the repo.
7. Audio in the encrypted backup, and "delete the audio but keep the words".

## Known gaps (honest list)
- Not built: summary, written answers, action items, calendar, reminder and email actions from a recording, speaker labels, import of audio, audio export, "delete audio, keep words", `SpeechAnalyzer` (iOS 26), cloud transcription, the web app (the repo has no web app, only the landing site), the "Imported" tab, suggesting a recording type (the user chooses).
- Mixed-language recordings are written out one language at a time; no language detection.
- If a part's row cannot be written twice during a recording, the audio continues but that part has no row; the save at the end then fails and the files stay. They are **not** found by recovery in this slice.
- Transcription in the background gets about 30 seconds from iOS; a long recording finishes when Doddy is next opened.
- A Live Activity swiped away is not re-requested by itself (the machine can ask; the app does not watch for it).
- The detail page reads all the words (in pages of 500) into memory.
- The speech recognizer is unproven on 10-minute files, and the AAC-in-`.caf` recorder settings are unproven (two fallbacks are in place).

## Constitution evidence log

| Rule | Enforced by | Tests run | Gap / claim to limit |
|---|---|---|---|
| DOD-06 user-controlled memory; `memory_policy` (opt-in, visible provenance, edit and delete) | `CaptureMemory`, `linkMemory`, "Remember this" saves only on Save (`RecordingDetailView`) | `testARecordingIsNotMemoryUntilTheUserSaysSo`, `testANoteFromARecordingKeepsItsSourceAndSurvivesTheRecording`, `CaptureTranscriptTests` Remember this | The sheet itself has not been run |
| DOD-08 verified status | Machine enters `recording` only on a verified start; coordinator waits for audio (0.1 s); every repository write is read back; "saved" in Stop listening only if read back (`captureSaved`) | State machine and fuzz tests, repository tests, `testStopListeningStopsARecordingAndOnlySaysSavedWhenItWas` | The audio check is unproven on a device; do not say "recording is verified" in the product until item 1 to 8 pass |
| DOD-02 honesty over agreeableness | "No summary yet"; `RundownValidator` and `AnswerValidator` drop or lower what the transcript does not back up; "not in the recording" worded by Doddy | `CaptureIntelligenceTests` (25 tests), four guards broken on purpose | No provider is wired: the validators have only seen invented output. **Do not claim summaries or Q&A exist** |
| DOD-09 correction and recovery | Corrections keep the recognised text; `CaptureRecovery`; a failed save keeps the files | Recovery and repository tests, including close and reopen of a file database | Kill recovery on real audio untested (item 9) |
| DOD-11 observable privacy; `privacy_policy` | Notice before any start; pill; Live Activity; permission texts; guard bans networking in the folder | Notice, presentation and indicator tests; guard PASS | Legal review pending; Settings Privacy text and DataFlow rows not updated; nine translations are drafts |
| DOD-07 scoped approval; content is data | Prompts fence the transcript and strip angle brackets; no external action is built | `testTheTranscriptCannotCloseItsOwnFence` | Future actions from a recording must reuse ASK-01 |
| ASK-01 | Nothing leaves the phone in this slice; any future send needs a card and a tap | Guard | The provider decision (ADR-582) |
| `memory_policy.deletion_claim_requires_storage_confirmation` | Delete is read back; the index is compacted | `testDeletedWordsAreNotLeftInTheDatabaseFile` and one for corrected words (raw file bytes) | Same gap in notes, learned facts and procedures (not fixed) |

## Next
1. Open the pull request when asked; read the hosted Mac build; fix its compile errors (expect some: see CI_REVIEW_PENDING).
2. Run the device test plan, starting with items 1, 2, 9.
3. Owner decisions 1 and 2, then a milestone for the rundown and Ask with ASK-01 cards.
4. `SpeechAnalyzer` once a device shows which languages (Polish) it supports.
5. Settings › Privacy and "What leaves this iPhone" rows; audio export; the web.
