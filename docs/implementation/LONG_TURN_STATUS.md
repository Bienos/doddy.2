# "Listen until I finish": status (ADR-364)
Date: 2026-10-11. Owner instruction: "do" (the next item on the list, OP-019, voice hold-to-talk mode). User story: "Doddy, listen until I finish." → "I'm listening. Tap when done." Acceptance: end of turn chosen by the user.

## What was wrong
- **The voice service decided when you finished.** In a conversation, the voice service (ElevenLabs, or OpenAI in the test voice) ended the user's turn after a silence. A pause to think, or a noisy room, could cut the user off, and Doddy answered half a sentence.
- **Mute didn't help.** Mute stops sending, but the turn still ended when the service decided.
- **Translator's hold-to-talk (ADR-215) is the same mute,** so it has the same limit.

## What it does now
- **"Listen until I finish"** is a button on the voice screen while a conversation is live (not in translator mode). It mutes the conversation's microphone and records the turn on this iPhone. The service hears nothing, so it can't end the turn.
- **While recording, the screen says so:**
  - The card shows "I'm listening. Tap Done when you've finished." with a running time (up to 3:00), **Done** and **Cancel**.
  - It also says: "Doddy hears nothing until you tap Done. The recording stays on this iPhone; only the words are sent."
  - The listening indicator (ADR-361) says "Listening until you finish", not "Microphone muted", because the iPhone is recording.
- **Done:**
  1. The recording is written out on this iPhone with the voice-memo transcriber (ADR-230). Recognition is on the device only. The language is the conversation's, or the iPhone's first that works on the device. A language that isn't on the device is never swapped for another.
  2. The words are tidied, and cut at 4,000 characters at a word, marked "…".
  3. They are sent as one message. They show as the user's line, and they're in the kept conversation log like any other line.
  4. The recording is deleted, and the microphone goes back to how the user had it.
- **At 3 minutes** it finishes as if Done was tapped.
- **Cancel** deletes the recording; nothing is sent.
- **Nothing is sent half-done or lost silently.** Each of these becomes a draft on the screen:
  - no words heard;
  - too short (under 0.7 s);
  - the language can't be written out on the device;
  - speech recognition is off;
  - writing out failed;
  - recording couldn't start;
  - the message couldn't be sent.
- **The draft card:**
  - It says what happened, has a text field ("What you said"), and **Send** / **Try again** / **Discard**.
  - Only a failed write-out keeps the recording to try again. Otherwise it is deleted at once.
  - Text that couldn't be sent stays in the field.
  - The microphone comes back on while a draft waits, so the conversation carries on.
- **Every ending drops it:** End, Stop listening (ADR-361), a drop, or a failure stops the recording and deletes the file and any draft.
- **Polish:** every line has Polish.

## Files
- **Core:**
  - `LongTurn.swift` (new): phases, the draft, limits, the message, language choice and the words on the screen.
  - `ListeningPrivacy.swift`: `MicrophoneSnapshot.Conversation.longTurn` and the indicator's kind.
- **App:**
  - `Features/Voice/LongTurnRecorder.swift` (new). It records with AVAudioRecorder into a temporary file, in the conversation's audio session, which it leaves as it is.
  - `VoiceSessionController.swift`: start, Done, Cancel, write out, send, draft, and dropping it on every ending. Mute is locked during the turn.
  - `VoiceView.swift` (`LongTurnPanel`).
- **Strings:** `l10n/pl.json` (1 entry; the rest come from core).
- **Tests:** `LongTurnTests.swift` (5).

## Verified (Linux, Swift 6.2.1)
- **Tests:** `LongTurnTests` (5) and `ListeningPrivacyTests` pass.
- **Planted bugs**, each caught and then restored:
  - writing out in the iPhone's first language when the conversation's isn't on the device: 1 failure;
  - the indicator calling it "muted": 2 failures.
- **App code:** `swiftc -parse` on the controller, the screen and the recorder.
- **Checks:** the guard script and the Polish catalog check pass (1314 of 1362).

## NOT RUN / unverified
- **Not built:** the app hasn't been compiled with Xcode.
- **Shared microphone:** that AVAudioRecorder can record while LiveKit's (or the OpenAI test voice's) audio engine holds the session with the conversation muted. If it can't, the screen says "Recording couldn't start" and nothing is sent.
- **ElevenLabs:** that a muted track keeps its turn-taking from ending the turn, and that `sendMessage` text gets an answer like speech.
- **OpenAI test voice:** the same, and whether it also echoes the message as a user line, which would show it twice.
- **Not spoken:** Doddy can't start this mode by voice ("Doddy, listen until I finish"). That needs a new agent tool and a live agent update, which is owner-side.
- **Checklist:** Mac checklist items LT1–LT6.

## Constitution evidence log
| Rule | How it applies | Enforcing code | Tests run | Gap / claim to limit |
|---|---|---|---|---|
| DOD-09 recovery | A turn that can't be written out or sent is a draft to retry, type or drop; never sent half-done or lost | `LongTurn.draft(for:)`, `draftLongTurn`, `retryLongTurn` | `testOnlyAFailedWriteOutCanBeTriedAgainAndEveryProblemHasPolish` | Screen not compiled |
| DOD-11 observable privacy | The recording stays on the iPhone and is deleted after sending or dropping; on-device recognition only; the indicator says the iPhone is recording | `LongTurnRecorder`, `dropLongTurn`, `VoiceMemoTranscriber` (`requiresOnDeviceRecognition`), `ListeningIndicator` | `testTheIndicatorSaysTheIPhoneIsRecordingNotMuted`, `testTheLanguageFollowsTheConversationAndNeverGuessesAnother` | Deletion not observed on a device |
| DOD-02 honesty | Only the user's own words are sent, tidied but not reworded; a cut is marked | `LongTurn.message` | `testOnlyWordsAreSentTidiedAndCut` | — |
