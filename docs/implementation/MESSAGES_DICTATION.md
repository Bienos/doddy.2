# Messages: dictation (the mic in the box)

Owner, 28 Oct 2026: "for 2 just add mic option to dictate what someone wants to say and transcribe". This replaces the idea of copying voice conversations into the thread; voice and typing stay separate (22 Oct decision, unchanged).

## What it does
- A mic button sits left of Send in the Messages box (`messages.mic`). Tap to talk, tap again to stop. The words appear in the box as they are heard, to read and fix. **Nothing is sent until the person taps Send.**
- Recognition is required to run on this iPhone (`requiresOnDeviceRecognition = true`, checked by `scripts/check_forbidden_capabilities.sh`). If this iPhone cannot do the language on the device, it does not listen and says so; there is no cloud fallback.
- Nothing is saved by dictation. The words are a draft; after Send they are an ordinary message (saved on the iPhone, sent to Doddy's server as before).
- It stops by itself after 120 s (`DictationRules.maxSeconds`), when a message is sent, and when the screen closes.
- It refuses to start while a conversation with Doddy, a voice memo or a Capture recording has the microphone, and says why.

## Files
- `Packages/DoddyCore/.../Messages/DictationRules.swift` (+ `DictationRulesTests`): how heard words join what was already typed; a later guess replaces the earlier one.
- `DoddyApp/Features/VoiceMemos/MessageDictation.swift`: AVAudioEngine and `SFSpeechAudioBufferRecognitionRequest`. It lives in the VoiceMemos folder because the guard allows audio and speech code only in Voice, VoiceMemos and Recordings.
- `DoddyApp/Features/Messages/MessagesView.swift`: the mic button and its wiring.
- Speech-recognition permission text (`project.yml`, English in `InfoPlist.xcstrings`) now mentions Messages.

## Not done / not checked
- **Fixed 29 Oct, after the first run on a device:** tapping the mic stopped the app (`EXC_BREAKPOINT` in `_dispatch_assert_queue_fail`, from `MessageDictation.authorizeSpeech()`). iOS answers the speech permission prompt on a background thread, and the callback, written inside the `@MainActor` class, was checked for the main thread. `authorizeSpeech()` and the microphone tap (which runs on the audio thread, same problem) are now `nonisolated` with `@Sendable` callbacks. Not compiled here (no Xcode); the owner's next device run is the check.
- **Not compiled and not run.** This session has no Swift or Xcode (Linux). `DictationRulesTests`, the app-logic type-check and the Mac CI job have not run. First compile is the pull request's hosted Mac job.
- **Not seen on a device:** recognition quality, Polish on-device support, interruption by a call, the system microphone indicator.
- The listening indicator (`MicrophoneHolders`, ADR-361) knows only conversations, voice memos and Capture; **dictation is not in it yet**, so "Stop listening" from outside the screen will not stop a dictation. iOS's own orange microphone dot does show.
- The error line under the mic is plain text in a narrow slot; its layout was not seen.
- New strings ("Dictate", "Stop dictating", the four failure lines) are not in `Localizable.xcstrings`, and the other nine languages of the speech-permission text still carry the old wording. Both need the usual translation pass.
- No UI test yet (the simulator has no microphone to dictate into).
