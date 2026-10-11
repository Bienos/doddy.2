# Audio privacy signal and stop: status (ADR-335)
Date: 2026-10-11. Owner instruction: "do the Polish pass then OP-024" (audio privacy signal and stop), from the research backlog. User story: "Stop listening now." → "Stopped." Acceptance: audio capture actually closed.

## What was wrong
- **No single stop.** A conversation, "Hey Doddy" and a voice memo each had their own off switch on their own screen. Nothing stopped all of them, and Siri had no "stop listening".
- **"Hey Doddy" listening was hard to see.** In the app it showed only on Settings › Hey Doddy. The island showed it only when Live Activities were allowed (a refused island was silent). iOS's orange microphone dot was the only sure sign.
- **Mute was not a stop.** In the OpenAI test voice, mute keeps the microphone running and drops what it hears. ElevenLabs mute turns LiveKit's microphone track off; whether the hardware stops wasn't checked.

## What it does now
- **Who has the microphone** (`MicrophoneSnapshot`, core): the conversation (connecting, listening or muted), "Hey Doddy" (its policy state, and whether Porcupine's recorder runs), and a voice memo (AVAudioRecorder's own `isRecording`). Each is read from its own state, never from what was asked of it.
- **Indicator** (`ListeningIndicator`, core; `ListeningIndicatorWindow`, app):
  - A small dark pill at the top centre, in a separate window above every screen and sheet (Settings, the note screen, the lock cover). Taps outside it reach the app.
  - It shows only while something has the microphone open, and says which: "Doddy is listening", "Microphone muted", "Recording a voice memo", "Listening for “Hey Doddy”", "Doddy is connecting". Tapping the words shows one line more (for "Hey Doddy": "On this iPhone only; nothing is kept or sent until you say it").
  - Muted still shows: "What you say isn't sent. Stop listening ends the conversation." It never says the microphone is off.
  - The voice screen has its own status and End, so the pill steps aside there.
  - Paused or waiting "Hey Doddy" doesn't show (it isn't listening). Stop listening still turns it off.
- **Stop listening** (pill button, or Siri: "Stop listening in Doddy", "Tell Doddy to stop listening"; works with the iPhone locked, the app doesn't open):
  1. "Hey Doddy" is turned **off** (the Settings switch), first, so the conversation ending doesn't hand it the microphone.
  2. The conversation ends (`stop(.stoppedListening)`); a "Save this note?" card that was showing is kept as a draft on the voice screen, with Save as note and Discard (ADR-330's card).
  3. A voice memo stops; what was recorded stays with the note being written as its draft, as when the 5-minute limit is reached. Nothing is saved.
  4. Each is read again. Only when none is still open does Doddy ask iOS to deactivate its audio session. iOS answering "busy" means it stopped something still running, which counts as released.
  5. **"Stopped. Doddy isn't listening."** only when every one says closed and iOS released the audio. Otherwise it names what is still on ("Doddy couldn't stop the conversation. Try again; if iOS's orange microphone dot stays on, close Doddy from the app switcher.") or that iOS didn't release the audio. "Doddy wasn't listening" when nothing was on.
- **How it ended:** the voice screen shows "Stopped listening" ("Doddy's microphone is off"); the conversation log records `ended: "stopped"`; the next conversation is not told it was cut off.
- **Polish:** every line above has Polish (core helpers with `NotificationLanguage`), plus the Siri phrases and the intent's title.

## Files
- **Core:** `ListeningPrivacy.swift` (new); `SessionRecovery.swift` and `ActionStatusText.swift` (`VoiceSessionEnd.stoppedListening`).
- **App:**
  - `Features/Voice/ListeningStop.swift` (new): `ListeningStop.stopAll`, `MicrophoneHolders`, `ListeningIndicatorModel`, `ListeningIndicatorWindow`, `ListeningIndicatorPill`.
  - `Intents/StopListeningIntent.swift` (new) and `DoddyShortcuts.swift`.
  - `VoiceSessionController.swift` (`current`, `microphone`, `stopListening()`), `WakeWordListener.swift` (`isEngineRunning`, indicator refresh), `VoiceMemoAudio.swift` (`isCapturing`, `stopFromOutside()`), `VoiceView.swift` (the draft card after a stop), `RootView.swift` (installs the window).
- **Strings:** `l10n/pl.json` (3), `l10n/pl_shortcuts.json` (3).
- **Tests:** `ListeningPrivacyTests.swift` (9); `ActionStatusTextTests` covers the new end.

## Verified (Linux, Swift 6.2.1)
- `ListeningPrivacyTests`, `SessionRecoveryTests`, `ActionStatusTextTests`: 24 tests PASS.
- `scripts/ci.sh --core-only`: PASS for core-only scope, 848 package tests; backend, gateway and messaging tests pass. Messaging database tests SKIPPED; iOS app NOT RUN.
- Planted bugs, each caught and then restored:
  - "Stopped" when iOS didn't release the audio: 1 failure;
  - the indicator hiding a muted conversation: caught;
  - "Hey Doddy" paused (switch still on) counted as stopped: 2 failures.
- `swiftc -parse` on every changed app file; `scripts/check_forbidden_capabilities.sh` PASS; Polish catalogs PASS (1191 of 1212).

## NOT RUN / unverified
- **Not built:** the app hasn't been compiled with Xcode; `ListeningStop.swift` and the intent are parse-checked only.
- **"Audio capture actually closed" is not proven on a device.** The code reads each recorder's own state and the audio session's answer; whether iOS's orange dot goes off at once, and whether LiveKit's capture stops after `endConversation`, need the device checks (LS1–LS8).
- **The window:** its position under the status bar, that it shows above sheets and that taps pass around it are untried. It may cover an inline navigation title while it shows.
- **Not changed:** the OpenAI test voice's mute still keeps capturing (its engine also plays Doddy's voice); the indicator says "isn't sent", not "off". Translator hold-to-talk is the same mute. Deactivating the session also stops Doddy's own sound playing at that moment (the brief read aloud).
- **Not covered:** Siri's own listening (Siri, not Doddy, has the microphone) and the phone agent (server calls).

## Constitution evidence log
| Rule | How it applies | Enforcing code | Tests run | Gap / claim to limit |
|---|---|---|---|---|
| DOD-08 verified status | "Stopped" only when each microphone user, read again, says closed and iOS released the audio | `ListeningStopReport.stopped`, `ListeningStop.stopAll` | `testStoppedOnlyWhenEachSaysItIsClosed`, `testHeyDoddyMustBeSwitchedOffNotJustPaused`, `testIOSNotLettingGoIsNotStopped` | The reads are the recorders' own; not checked against the orange dot on a device |
| DOD-11 observable privacy | One indicator while anything listens, never "listening" when nothing is, never "off" when muted | `ListeningIndicator.current` | `testTheIndicatorShowsOnlyWhileSomethingListens`, `testOnlyWhatIsActuallyOpenCounts` | Window never drawn on a device |
| DOD-06 memory only on explicit save | Stopping saves nothing; the note card and the memo stay drafts | `SessionRecovery.draft(.stoppedListening)`, `stopFromOutside` | `testStopListeningKeepsOnlyTheNoteCardAsADraft`, `testNothingOnSaysSoAndDraftsAreNamed` | Draft card after a stop not compiled |
| DOD-09 recovery | A stop that didn't close everything says what and offers Try again | `ListeningStopReport.reply` | `testStoppedOnlyWhenEachSaysItIsClosed`, `testEveryReplyHasPolish` | — |
