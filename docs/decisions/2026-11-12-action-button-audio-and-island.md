# The Action Button's conversation keeps Doddy's own mixable audio session, and the island stops growing and shrinking

- **Date:** 2026-11-12
- **Decided by:** owner (Pat, 12 Nov 2026): "zrób też review action button … w tym momencie dalej to nie działa … ta ikonka, która się wyświetla, jest jakaś taka dziwna … popraw ją … się przełącza z dużego jakby Dynamic Island na mały … zacina się i w ogóle nie można z nim gadać". The fixes below are the session's reading of that from the code; none of it was seen on a phone.
- **Status:** applied in the pull request of branch `claude/nifty-allen-vawcas`. Not verified on a device.
- **Replaces:** nothing. Follows `2026-11-10-action-button-start` and `2026-11-09-small-island-call-bars` (the face it keeps). The `allowOtherAppsAudio` note of ADR-207 is corrected, not changed.

## Why
Read from the code and the pinned packages (no phone, no Xcode in the session):

1. **Confirmed in the source: LiveKit replaces the Action Button's audio session with one iOS refuses in the background.** The start without opening Doddy takes the session itself inside the intent, `.playAndRecord` / `.videoChat` with `.mixWithOthers` (`takeAudioSessionWithoutOpening`), because iOS lets a background app switch on only a session that mixes. When ElevenLabs then connects, LiveKit's engine starts and LiveKit sets the session up again (`AudioSessionEngineObserver.configureAudioSession`): its own preset, then `setActive(true)`. In LiveKit 2.17.0 and later that preset has no `.mixWithOthers` (checked in the tags: 2.10 to 2.16 have it, 2.17 to 2.19 don't; the app pins 2.19.0 since 7 Nov). Switching on a session that doesn't mix while the app is in the background is what `AVAudioSession.ErrorCode.cannotInterruptOthers` (561015905) is for. When that happens, LiveKit's engine doesn't start and the conversation has no microphone or speaker, though the island is up: "you can't talk to him". `AudioManager.sessionConfiguration`, which `allowOtherAppsAudio` sets for ADR-207, is not read anywhere in LiveKit's set-up (not in 2.10 either), so it never prevented this.
2. **Confirmed: the face on the small island had stray marks.** `WholeDoddy_face_listening`, the face the compact island shows for the whole conversation (`2026-11-09-small-island-call-bars`), was cut as a circle 6 % wider than his head outline. In that pose his hand is cupped at his ear with orange sound marks, so the cut took in a sliver of the hand and an orange fleck on the right, and a stub of neck below. The yawn face was off-centre and took in his arms and neck. At 26 pt they read as glitches.
3. **Confirmed: the small island changed width with every turn.** iOS sizes the compact island to its content. Its right side was the 48 pt waves while Doddy listens or talks and a narrower sign while he thinks or connects (three dots, about 20 pt) or waits (a symbol), so the island shrank and grew on each turn.
4. **Confirmed in the SDK: Doddy's state flipped inside one answer.** ElevenLabs SDK 3.3.1 turns "speaking" into "listening" 0.5 s after the room reports the agent quiet (`AgentStateManager`, `speakingToListeningDelay`), which happens in the pauses between his sentences. Each flip springs Home's strip between 330 and 260 pt and re-sends the island's status and waves.
5. Not changed, noted: the open pull request #334 asks the island to open up on every press. That is the big island the owner turned off on 9 Nov and the "big to small" of this report; it should not merge as it is.

## Decision
- **Audio session.** A start without opening Doddy keeps the mixable session it took: from that moment LiveKit's automatic set-up is off (`AudioManager.shared.audioSession.isAutomaticConfigurationEnabled = false`), and Doddy asks for WebRTC's 20 ms buffer itself. When that conversation is over (End, a failure, a drop) and its SDK conversation has ended, LiveKit's set-up is turned back on and Doddy switches the session off, unless LiveKit's engine still runs (LiveKit then does it when the engine stops) or something else of Doddy's uses it (`AudioSessionOwner`). Every other start (Home, the voice screen, Siri, Back Tap) leaves the session to LiveKit as before. The rule, with a hold that a newer conversation's start drops and an older one's late end can't release, is `ConversationAudioHolds` (DoddyCore); the app side is `ConversationAudioSession`. The connect line in the log now says whose session it is and whether it mixes.
- **Face.** `tools/whole_doddy/cut_faces.py` cuts each face at the cream disc of his face plus a 3 px rim (at the 300 × 450 pictures), at 52 / 78 px for the compact island's 26 pt. The numbers are in `IslandPose.head`. Still the owner's pictures, cropped and masked, nothing redrawn. The same four faces as before; only the cut changed.
- **Island width.** In the voice Live Activity the compact right side is always the waves' 48 × 26 pt (`IslandVoiceCompactTrailingView`); the dots, symbols, time or language codes sit in the middle of it. Other activities (timers, tools) are unchanged.
- **State flips.** `AgentStateConfiguration(speakingToListeningDelay: 1.0)`: a quiet Doddy counts as listening after 1 s instead of 0.5 s. The user speaking, an interruption and a tool call still change the state at once.
- Not changed: the control's waveform symbol (iOS draws a control's symbol, not a picture; a Doddy symbol would have to be drawn, which the art rule doesn't allow without the owner), island expansion (still off by default), and the foreground start's session (LiveKit's, which doesn't mix: ADR-207's "other apps keep playing" hasn't held since LiveKit 2.17; a separate decision).

## Consequences
- A background start no longer depends on iOS accepting a session change it is documented to refuse. If the conversation still can't hear after this, the next suspect is iOS refusing to start the microphone after the intent returned (`2026-11-10-action-button-start` hands back before the connect); the log's connect line and LiveKit's own audio-session errors will tell the two apart.
- During a Doddy-held conversation other apps' sound keeps playing (it mixes), and the microphone can hear it, as ADR-207 meant. LiveKit notes that mixing can cost echo cancellation against other apps' audio and an engine start race it retries.
- The small island no longer pumps; "Listening" shows about half a second later after Doddy finishes.
- The faces are slightly larger in their slot (less black ring).

## Evidence
- `make test-core` with Swift 6.2 on Linux (Ubuntu 24.04): 2981 tests, 0 failures, including the 5 new `ConversationAudioHoldsTests`, `TalkStartRulesTests`, `TalkLaunchTests` and `AudioSessionPolicyTests`.
- `scripts/check_island_art.sh`: PASS (42 drawings; scene checks, including every face pose's head box).
- `swiftc -parse` on every changed app, widget and test file: OK. That is syntax only.
- `IslandScreenshotTests.testTheSmallIslandKeepsOneWidthThroughAConversation` (app unit tests: the right side is 48 × 26 pt in all eleven sample states) is written but **not run** here: it needs the app, which needs Xcode (the hosted Mac job).
- LiveKit sources read at tags 2.10.0 to 2.19.0 (`AudioSessionConfiguration.swift`, `AudioSessionEngineObserver.swift`, `AudioManager.swift`); ElevenLabs Swift SDK 3.3.1 (`ConversationAudioManager.swift`, `AgentStateManager.swift`, `AgentStateConfiguration.swift`).
- `python3 -I tools/whole_doddy/cut_faces.py .` twice: the second run changes nothing. Before/after rendered at 26 pt on a black island (in the pull request).
- `scripts/ci.sh --only checks`: every check PASS; "Studio skills: renderers" NOT RUN (no reportlab here).
- **The app and the widget are not compiled** (no Xcode): `ConversationAudioSession`, the controller's edits and the widget's view are checked only by parsing and by reading LiveKit's and ElevenLabs' sources. Nothing seen on a phone.

## How to check on a phone
Console, subsystem `com.bienos.doddy2.dev`, category `voice-audio`, one Action Button press with another app on screen:
- `audio session held by Doddy for this conversation: LiveKit won't set it up`;
- `connecting to ElevenLabs: attempt n, audio session held by Doddy: AVAudioSessionCategoryPlayAndRecord, mode AVAudioSessionModeVideoChat, mixing with other apps ON, …`;
- `conversation started`, then Doddy's greeting is heard and he answers;
- after Stop: `audio session given back to LiveKit, switched off: true` (or `… while its engine still runs`).
With music playing in another app, the music keeps playing under Doddy. The small island keeps one width through listening, thinking and speaking.
