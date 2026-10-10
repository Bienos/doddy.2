# V3 status — Dynamic Island, double-tap start, background conversation
Date: 2026-10-10. Owner instruction: build the Dynamic Island Live Activity, and make it appear when double-tapping
the back of the iPhone while in another app such as Safari.

**Status: written without Xcode or an iPhone. Nothing here has been compiled or run.**

## What happens (intended behaviour)
1. One-time: Settings → Accessibility → Touch → Back Tap → Double Tap → **Talk to Doddy** (Doddy cannot do this for you).
2. Double-tap in Safari → the shortcut runs `TalkToDoddyIntent` → Doddy opens in front, asks for the microphone the
   first time, and starts the conversation. Doddy must be in front to start: iOS blocks starting a mic session from the background.
3. The Live Activity starts with the conversation. Swipe back to Safari: the **Dynamic Island** shows the real state
   (Connecting / Listening / Thinking / Speaking / Muted), elapsed time, **Mute** and **End**. The same card is on the Lock Screen.
4. End (Island, Lock Screen or in the app), a disconnect, an error or removing the activity all end the conversation and the activity.

So double-tap from Safari briefly brings Doddy forward; it cannot show the Island while staying silently in Safari.

## Safety rule
Background audio is allowed **only while the Live Activity is showing**. If Live Activities are off for Doddy, the request
is refused, or the user swipes the activity away, the conversation ends (VoiceView on leaving the app; controller when the
system removes the activity). The microphone is never open without a visible indicator.

## Files
| File | Role |
|---|---|
| `DoddyShared/VoiceActivity.swift` | `VoiceActivityAttributes`, End/Mute `LiveActivityIntent`s, bridge to the running conversation (compiled into app + extension) |
| `DoddyWidgets/*` | Widget extension: Island (compact, minimal, expanded) and Lock Screen layouts |
| `DoddyApp/Features/Voice/VoiceLiveActivity.swift` | Starts/updates/ends the activity; reports if the system removes it |
| `DoddyApp/Features/Voice/VoiceSessionController.swift` | Every phase change goes through `transition(to:)`, which syncs the Island |
| `DoddyApp/App/TalkToDoddyIntent.swift`, `VoiceLaunchRouter.swift`, `RootView.swift` | Shortcut → open voice screen (waits for First Hello; respects voice availability) |
| `project.yml` | New `DoddyWidgets` target; `NSSupportsLiveActivities`; `UIBackgroundModes = audio` |

## Verified
Linux only: capability guard passes (now also scans `DoddyShared` and `DoddyWidgets`), imported-pack integrity passes,
`project.yml` parses as YAML. **Not verified:** Swift compile (Xcode and Swift 6 strict concurrency with ActivityKit/App Intents),
XcodeGen generation of the extension, and everything below.

## Needs a Mac and a real iPhone (Dynamic Island hardware: iPhone 14 Pro or later)
1. `make project`, then build; confirm `INFOPLIST_KEY_NSSupportsLiveActivities` and `INFOPLIST_KEY_UIBackgroundModes` end up in the built Info.plist (if Xcode ignores them, put them in an Info.plist via XcodeGen `info:`).
2. Install on the phone, sign both targets with your team (the extension needs its own App ID `com.bienos.doddy2.dev.widgets`).
3. Talk to Doddy in the app, press Home: the Island appears and the conversation continues (audio keeps flowing).
4. Real test of the risk below: stay in Safari for 2+ minutes with Doddy talking.
5. Mute / End from the Island and the Lock Screen; Unmute shows "Listening" again; ending removes the Island.
6. Double-tap with Back Tap from Safari, from the Home Screen, and from the Lock Screen (a locked phone may ask for Face ID before the app opens).
7. Turn Live Activities off for Doddy: the conversation must end on leaving the app, with the on-screen notice.
8. Swipe the activity away mid-conversation: the conversation must end.
9. Cold launch (app killed) via double-tap; first run with microphone permission prompt and before First Hello.

## Known risks
- One developer report says apps were killed ~50 s into background recording on iOS 26.5 (anecdotal). If the conversation drops in the background, we will have to change approach; the app will show "Conversation ended".
- Whether the ElevenLabs SDK's audio connection survives backgrounding is untested.
- `openAppWhenRun` may be deprecated in newer SDKs (`supportedModes`); update if Xcode warns.
- Island buttons run inside the app's process; if iOS has killed the app, End only removes the stale activity.
- Back Tap from a locked phone, and the dev agent being public (ADR-034), are unchanged concerns.
