# DODDY Capture: technical audit (22 Oct 2026)

**Written before the build, as the first deliverable. What was then built, and what it still lacks, is in `CAPTURE_STATUS.md`.**

Scope: iPhone first. The web app is not in this slice (see "Not built"). Apple Watch and Mac stay paused (ADR-572).
Method: read `STATUS.md`, `docs/platforms/iphone.md`, `CLAUDE.md` rules, the capability guard, the Voice, VoiceMemos, widget and persistence code. **No Xcode and no SDK headers on this machine**, so every Apple API statement below is marked with where it comes from. Nothing native was compiled or run when this was written (the hosted Mac build has since compiled it and passed; see `CAPTURE_STATUS.md`).

## 1. What exists and what Capture reuses

| Need | Existing piece | Status | Decision |
|---|---|---|---|
| Start with one press, no app UI | `TalkInIslandIntent` (`AudioRecordingIntent` + `LiveActivityIntent`) and `TalkInIslandControl` (ADR-577) | Written; **never seen on a device**; STATUS says whether iOS allows the mic from a cold background start "is unknown" | Same intent family. Start differs (see section 3) |
| Live Activity + buttons that reach the running app | `DoddyVoiceAttributes`, `VoiceActivityActions`, `EndDoddyConversationIntent`, `allowedExecutionTargets = .main` (ADR-131) | Compiled in hosted CI; island behaviour on device partly verified | Copy the pattern into a **separate** `DoddyCaptureAttributes`. Not the voice activity: its orange cue means "Doddy is live and can hear you" (`isLiveCue`) and it ends with the conversation |
| Mic indicator above every screen + "Stop listening" | `ListeningPrivacy.swift` (DoddyCore, tested), `ListeningStop.swift`, `MicrophoneHolders` | Working, tested | Extend with a third user, `capture`. Stop listening must stop a recording too |
| One conversation at a time | `VoiceConversationGate`, `runningConversation` (ADR-496) | Working | Capture and a conversation are **mutually exclusive** (both reconfigure the one shared `AVAudioSession`) |
| Short recording | `VoiceMemoRecorder` (AAC 22 kHz, temp file, 5 min, one note) | Working | Not reused as the engine: temp folder, one file, deleted on relaunch (`deleteLeftovers`). Captures need durable, segmented files |
| On-device transcription | `VoiceMemoTranscriber` (`SFSpeechRecognizer`, `requiresOnDeviceRecognition = true`, guard-enforced) | Working for notes | Same API and same invariant, plus word timings. Guard extended to the new folder |
| Local database | `DoddyDatabase` (GRDB, migrations v1 to v15, FTS5 on memories, facts, procedures, `secure_delete`) | Working, 1,300+ tests | New migration `v16_recordings`, FTS5 on transcript segments. No second database |
| Verified writes | Every repository reads back before success | Convention | Same |
| Action permissions | ASK-01 (`AskFirst`, `docs/trust/ASK_FIRST.md`) | Enforced in code and CI | Any text leaving the phone needs a card and a tap |
| Longer-term memory | `memories` (notes, `source` column), `learned_facts` | Working | A recording is **not** memory. "Remember this" is an explicit tap that saves one note with provenance |
| Background audio | `UIBackgroundModes: audio`, `NSSupportsLiveActivities` already in `Config/Doddy-Info.plist` | Present | No new background mode |

**Missing:** recording coordinator and state machine; durable segmented storage; recovery after a kill; recordings tables; transcript segments with timings; library and detail screens; capture Live Activity; start/stop/pause/open intents; control; rundown and answer validation; a provider for the rundown.

## 2. iOS limits that shape the design

| Fact | Evidence | Consequence |
|---|---|---|
| `AudioRecordingIntent` is iOS 18+; adopting it tells the system the app records audio and iOS shows its recording indicator | [Apple docs](https://developer.apple.com/documentation/appintents/audiorecordingintent) | App minimum is iOS 17, so every use is `@available(iOS 18.0, *)`, as `TalkInIslandIntent` already is |
| Recording **cannot be started from a cold background** through the general audio APIs. A DTS reply says a privacy block stops recording sessions activating in the background. Developers report "Live Activity start failed … Target is not foreground" when an intent starts both | [Apple forums, thread 815725](https://developer.apple.com/forums/thread/815725) (forum reports, not SDK documentation; **not verified on a device**) | The start intent **opens Doddy** (`openAppWhenRun = true`). The recording then runs in the background and with the screen locked. We do not claim a no-UI start from a locked or suspended iPhone |
| A Live Activity must stay up while an `AudioRecordingIntent` recording runs, or iOS stops the recording | Developer write-up reported in the same search; **not found in Apple documentation** | Start refuses (with a sentence) if Live Activities are off, as Talk in the Island does. The activity is requested before capture is announced |
| A Live Activity lasts at most **8 hours**, then the system ends it; the Lock Screen copy can stay 4 more | [Apple docs](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities), [forum clarification](https://developer.apple.com/forums/thread/797676) | Hard cap of **4 hours** per recording, warning at 3 h 50 min. Raising it needs an owner decision |
| `SpeechAnalyzer` / `SpeechTranscriber` / `AssetInventory` are iOS 26+; models are downloaded by the system; locale support must be read at runtime (`supportedLocales`); no language auto-detection | [SpeechAnalyzer](https://developer.apple.com/documentation/speech/speechanalyzer), [AssetInventory](https://developer.apple.com/documentation/speech/assetinventory). "About 40 locales" is from a secondary source | Not used in this slice (see section 5). Polish support is **unknown** until read on a device. Mixed-language audio is not handled: one language per recording |
| File protection `complete` blocks writes once the phone locks | Standard iOS behaviour | Files use `completeUntilFirstUserAuthentication`, never `complete`, or a locked-screen recording fails |
| AAC in an `.m4a` container is finished only when the file is closed; a killed app can leave an unplayable file | General AVFoundation behaviour; **not tested here** | Capture uses short **segments** (10 min). Each is its own file, so a kill loses at most the segment in progress. Recovery tries to read what is there and reports what it could not |

## 3. Can recording start from each state?

| State | Result in this slice | Basis |
|---|---|---|
| Doddy open | **Supported.** Button in Doddy, the intent, Siri, control | Foreground start |
| In the background (alive) | **Not claimed.** The intent brings Doddy to the front first | Forum reports above |
| Suspended | **Via foregrounding.** iOS launches Doddy to the front for the intent | `openAppWhenRun`; unverified on device |
| Screen locked | **Needs unlock.** `authenticationPolicy = .requiresAuthentication`, then Doddy opens | Same; not verified |
| App terminated | **Cold launch via the intent**, then the same start. The start path needs only the database, the microphone permission and a folder, not the full app bootstrap | Design; not verified |

In every state the screen says "Recording" only after the recorder reports it is capturing **and** the Live Activity exists (`CaptureStateMachine`: `recording` is reachable only from `captureVerified`).

## 4. Architecture

```
Entry points ─ button · StartDoddyRecordingIntent · Siri · Control
                         │ (all call one function)
                         ▼
        RecordingCoordinator (@MainActor, the only owner of capture state)
          │ events                         ▲ state
          ▼                                │
  CaptureStateMachine  (DoddyCore, pure, tested on Linux)
          │ effects: start/rotate/pause/stop segment, update activity, persist
          ▼
  AVAudioRecorder segments (AAC mono 16 kHz, 10 min, .caf)  ──►  Application Support/Recordings/<id>/
  AVAudioSession notifications ─► InterruptionPolicy (DoddyCore) ─► gap ledger
  Live Activity (DoddyCaptureAttributes) ◄── CapturePresentation (DoddyCore)
          │ on stop
          ▼
  SQLiteRecordingRepository (row exists BEFORE audio starts; parts added per segment)
          ▼
  RecordingTranscriber (provider protocol) ─► SFSpeech on device ─► TranscriptAssembler ─► segments + FTS5
          ▼
  Library · Detail (player, transcript, search, excerpts) · Ask (retrieval) · Export · Delete
          ▼ (not wired; needs owner approval)
  RundownProvider contract ─► RundownValidator / AnswerValidator (quote-grounded)
```

Choices and why:
- **`AVAudioRecorder` over `AVAudioEngine`.** One extra moving part (an engine restart on every route change) buys gap-free rotation and a live tap Capture does not need. The cost of the recorder is a gap of milliseconds at each 10-minute rotation, recorded in the gap ledger. Next recorder is prepared before the old one stops.
- **Durable row first.** The recording row is written before audio starts, so a kill leaves something to recover from. Nothing is inferred from files alone.
- **One shared state machine** so a repeated Action Button press cannot start a second session, and the Live Activity, the indicator and the library read the same state.
- **Logic in `DoddyCore`.** Anything that is a rule (state transitions, interruption policy, recovery, chunking, grounding) is plain Swift, tested on Linux. The app layer is thin and is the part that cannot be compiled here (the hosted Mac build compiles it).

## 5. The rundown and "Ask Doddy": what is real and what is not

- **Retrieval is real and on-device:** FTS5 over transcript segments, per recording, with timestamps. "Find the part where we talked about pricing" works without any model.
- **A written rundown needs a model, and no existing path fits.** `ask_claude` (ADR-564) takes at most 6,000 characters of material, answers in 3 to 6 plain sentences, has an 18-second limit, and each call needs its own approval card. An hour of meeting is about 50,000 characters, and we need structured output (decisions, action items with timestamps). A new server endpoint, or Apple's on-device Foundation Models (iOS 26, Apple Intelligence devices, language coverage unverified), is a **cloud/AI decision that `CLAUDE.md` rule 6 reserves for the owner**. This slice therefore builds the contract and the part that must never be wrong, and wires **no provider**:
  - `RundownValidator` drops any item whose cited time is outside the recording or whose quote is not in the transcript near that time; a date or deadline is kept only if it appears in the cited text; a "decision" has to be marked agreed, proposed or unclear.
  - The screen says "No summary yet" and why. It never shows invented text.
- **ASK-01 holds:** transcript text never leaves the phone without a card and a tap. "Automatic" summaries are therefore a **setting the owner must approve** (a standing yes, like errands, ADR-570).
- **Transcription is on device only.** There is no cloud transcription in this slice. If a language is not supported on the device, the recording is kept with audio and the status says so.

## 6. Risks

1. **Nothing native could be compiled or run here** (no Xcode). The PR's hosted run did the first compile (it passed after two fixes); first real behaviour still needs a device.
2. **Cold start from the Action Button is unproven** (section 3).
3. **Kill recovery of audio files is unproven** (section 2). Segmenting bounds the loss; it does not remove it.
4. **Shared audio session:** the voice controller's `.playAndRecord`/`.videoChat` would silently break a recording. Mitigation: a guard in `VoiceSessionController.start` and in the coordinator. A voice file change can stop calls, so this is small and needs a conversation test after install.
5. **Legal:** recording other people needs their consent in many places, and Poland and the UK differ. Doddy shows a clear recording state and a first-use notice; it does not decide the law for the user. Needs the owner's wording.
6. **Storage and battery:** about 14 MB per hour at 32 kbps mono. Start is refused under 200 MB free; the recording stops and saves at 50 MB.
7. **Widget bundle limit:** the builder takes at most ten entries (ADR-331). Controls are grouped into one bundle to make room.
8. **Capability guard:** audio and speech code is allowed only in named folders. The guard is extended for exactly one new folder, with the same on-device assertion.

## 7. Dependencies and project changes

No new packages. What changed (the audit predicted this list before the work; `CAPTURE_STATUS.md` has what was actually built):
- `Config/Doddy-Info.plist`: nothing (the audio background mode and Live Activities were already declared).
- `project.yml`: only the microphone and speech permission texts (they said "voice memo" only), with all nine languages' translations in `l10n/` redrafted.
- `DoddyWidgets/DoddyWidgetsBundle.swift` (controls grouped into one entry, Capture's Live Activity added), `DoddyShortcuts.swift` (the tenth and last App Shortcut).
- `scripts/check_forbidden_capabilities.sh` (audio and speech allowed in one more folder, which may send nothing) and `scripts/typecheck_app_logic.sh` (its stand-in needed the new field).
- `DoddyDatabase` migration `v16_recordings`; `ListeningPrivacy.swift` and `DeepLink.swift` (one more case each).
- One guard in `VoiceSessionController.start` so a conversation cannot start under a recording.

## 8. Not built (and why)

| Item | Reason |
|---|---|
| Written rundown, answers to questions | Needs the owner's provider decision (section 5) |
| Cloud transcription | `CLAUDE.md` rule 6; on-device first |
| `SpeechAnalyzer` provider | iOS 26 only, cannot be compiled or checked here, Polish support unknown. The provider protocol is in place for it |
| Speaker labels | No reliable on-device diarization. Transcript segments carry no speaker |
| Import of existing audio files | Not in the first slice |
| Calendar, reminder, email actions from a recording | Reuse ASK-01 later; needs the rundown first |
| Web app | The repo has a landing site only (`site/`), no app to extend |
| Mixed-language recordings | `SFSpeechRecognizer` is one locale at a time; no detection is claimed |
