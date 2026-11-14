# The log times the first sound of Doddy's voice, not only the provider's "speaking" event

- **Date:** 2026-11-14
- **Decided by:** owner chose option D of the research review ("Tak, zrób D", 14 Nov 2026: time to the first sound Doddy's voice actually makes, measured in the app)
- **Status:** proposed in this pull request
- **Replaces:** nothing; adds to `2026-11-10-voice-start-timing`

## Why
Research 02 puts "measure tap-to-first-audible, p50/p95/p99" first (owner list R-01, test 1) and notes that the voice SDK's "speaking" event does not prove sound. The app logs only that event (`voice first speaking event after start`, `VoiceSessionController`), and `docs/platforms/iphone.md` says no start time has been measured on a device. A time that looks better than what a person hears would hide the very thing to be fixed.

## Decision
- `VoiceAudibleOnset` (DoddyCore, plain Swift, tested on Linux) finds the first run of sound in the per-buffer levels Doddy's audio track already hands `AgentVoiceMeter`: a level of at least 0.2 (about -42 dB, between a decoded line's hiss and speech) lasting at least 40 ms in a row. The press time is the start; the result is the time of the first buffer of that run.
- `AgentVoiceMeter` logs one line per conversation on the existing `voice-audio` category: `voice first audible sound after start: first sound … · listening from … · output latency …`. Only fixed words and seconds. The output latency is read from `AVAudioSession` off the audio thread.
- The press time comes from the two places that already record it: Home's tap (`HomeConversation.start`) and the Action Button (`TalkInIsland.start`), one line each. `VoiceSessionController`, a hot file with an open pull request (#453), is not touched.
- A press with no sound within 60 seconds is dropped, so it can't time a later conversation that has no press of its own.
- Not logged: a start from the voice screen or a Siri shortcut (no press time yet), and a conversation with no sound.

## Consequences
- The owner can read how long a press takes to become sound, next to the provider's event, and see when the two differ.
- **It is not "heard at the ear".** It is sound handed to the output; the iPhone's output delay comes on top and is logged beside it. No microphone is involved, so it can't see what the speaker did.
- **It can only be late.** The meter starts listening when Doddy's audio track appears, on the first speaking event. `listening from` says when; a `first sound` equal to it means the sound was already playing and the number is "no earlier than this".
- The threshold and the 40 ms are chosen, not measured on a device. Revisit them after the first logged starts.
- Reading the log needs Console.app on a Mac with the phone connected. A histogram in Logbook would let the admin page show the spread without a Mac, but the server's Logbook schema is strict: server first, then a deploy, then the app. Not done here.
- Privacy: no audio is kept, copied or sent; only seconds in the log, which stays on the phone.
- Platforms: the iPhone app only. DoddyCore's new type is unused by the paused Watch and Mac apps.

## Evidence
- Run: `swift test --package-path Packages/DoddyCore` (Swift 6.1.3, Linux): `VoiceAudibleOnsetTests` 13 tests, written first and seen red (the test target did not build without the type), then green. Three deliberate breaks (no rounding allowance, timing to where the run was confirmed instead of where it began, a quiet buffer not ending a run) were each caught by a test; the rounding one first needed an extra test, because ten 10 ms buffers sum to 0.09999999999999999.
- `swiftc -parse` on the three changed app files: syntax only.
- Not run: **the three app files are not compiled** (`AgentVoiceMeter.swift`, `HomeConversation.swift`, `TalkInIsland.swift`: no Xcode, no iOS SDK or LiveKit here); nothing on a device. The hosted `ios-build` job is their first compile.
- To check on a device: press Home's Doddy and the Action Button and find the line in Console.app (category `voice-audio`); a start with Doddy talking at once, and one with a Bluetooth headset (the output latency should be larger).
