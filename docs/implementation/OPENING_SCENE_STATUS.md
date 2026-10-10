# The opening and "Start listening when I open Doddy" (ADR-207)
Date: 2026-10-10. Owner requests: "a very cool app opening every time … Doddy is playing basketball … the camera zooming in on him … he scores … then the normal UI shows up … very quick … you can turn it off in settings … ideally he says hey it's Doddy what's up mate and already has the microphone open … czy mogę ci pomóc", then, after a first version: "it must be more cartoony … quick animation drawing Doddy, he shoots and then a new version that is ready to speak shows up with other buttons and you can interact".

**Status: DoddyCore tested on Linux; the app is written but not built.** The timeline, the SVG reader, the policy and the greeting pass their unit tests (Swift 6.1, Linux), and `OpeningModel` compiles against DoddyCore in the Linux check. The SwiftUI scene, Home's ready state, the Settings rows and the UI tests have **not been compiled or tried on a device**: no Xcode here. The Mac checklist (§4b) lists what to look at first.

## The sequence (2.3 s; a tap skips it)
| From (s) | What happens |
|---|---|
| 0.00 | A pen sketches Doddy (the dribble drawing), stroke after stroke |
| 0.42 | The ball pops into his hand; two quick bounces, flattened on the floor |
| 0.78 | He gathers the ball and crouches (squash); the camera punches in |
| 0.94 | Up to the shooting hand, stretch, and a hop |
| 1.04 | Release; the arm follows through; the ball flies with a ghost trail |
| 1.40 | SWISH! with rays; the ring wobbles; one light haptic |
| 1.58 | He pops up in the listening pose; the hello in a speech bubble |
| 2.00 | The court fades; Home takes over: the hello is the heading, the listening pose is up, the buttons slide in |

## What was built
| Piece | Where | Reality |
|---|---|---|
| Timeline and layout | `Packages/DoddyCore/Sources/DoddyCore/OpeningScene.swift` | Pure functions of time: camera, pose and cross-fades, per-stroke sketch progress, squash, stretch, hop, the ready pop, the ball (pop-in, bounces, gather, raise, arc with a trail, net), the burst, the bubble, the hand-over. A still variant for Reduce Motion. Tests: `OpeningSceneTests` (16) |
| Drawings | `OpeningArt.swift` (same package), `DoddyApp/Resources/Character/*.svg` | `SVGPoseReader` reads the four supplied v1.3-r1 basketball SVGs (copied unchanged) into strokes with every group transform applied. Tests: `OpeningArtTests` (8), against the real files |
| Rules and greeting | `OpeningPolicy.swift` | When it plays and when a conversation follows; the hello's words. Tests: `OpeningPolicyTests` (10) |
| Model | `DoddyApp/Features/Opening/OpeningModel.swift` | Launch vs return, background time, loading the drawings once, Home's ready state for eight seconds, the one way the opening may open a conversation (`ShortcutRouter.startListeningOnOpen`). In the Linux compile check |
| Scene | `DoddyApp/Features/Opening/OpeningSceneView.swift` | `TimelineView` draws `OpeningScene.frame(at:)`; Doddy as trimmed SwiftUI paths in the theme's ink and paper; ball, trail, hoop, net, burst, bubble, "Tap to skip". One VoiceOver element; one light haptic |
| Home's ready state | `DoddyApp/Features/Home/HomeView.swift` | After the opening: the hello as the heading, `UploadedDoddy_Listening` popping in, the four actions sliding in (instant under Reduce Motion) |
| Settings | `SettingsView` | Appearance → "Doddy's opening" (on). Voice → "Start listening when I open Doddy" (off) with a note. Privacy → the Microphone row follows the switch |
| Microphone usage string | `project.yml` | Covers both the button and the switch |
| UI tests | `DoddyUITests/LaunchSmokeTests.swift` (+ `-openingScene NO` in the other two files) | Play and skip; ends by itself and no replay on a quick return; off = Home at once; the listening switch off by default |
| Preview | `design/opening-v0.1/index.html` | The same timeline in a browser, with the same SVGs inlined, a placeholder Home whose buttons slide in and answer taps, and review switches (quarter speed, Reduce Motion, dark, Polish) |

## What it does not do, on purpose
- It never listens without the user's own switch. Off as shipped. On, the conversation that opens is the ordinary one and ends only when the user ends it.
- The hello is text. Doddy's spoken greeting is the live agent's first message. To make it match, change the agent's first message in the ElevenLabs dashboard; `voice-agent/session.json` records the current one.
- No sound effect: an audio file and AVFoundation outside `Features/Voice` are forbidden by the capability guard.
- No new character art: the five drawings are the supplied ones. The motion is whole-drawing squash, stretch, hop and pop, quick cross-fades, and the pen effect.

## Checks run here (Linux)
| Check | Result |
|---|---|
| `swift test --package-path Packages/DoddyCore -Xswiftc -DSQLITE_DISABLE_SNAPSHOT` (Swift 6.1) | PASS: 405 tests, 0 failures; 34 for the opening |
| `scripts/typecheck_app_logic.sh` (9 files, including `OpeningModel`) | PASS |
| `swiftc -parse` on every changed app and UI-test file | PASS (syntax only; SwiftUI is not type-checked on Linux) |
| `scripts/check_forbidden_capabilities.sh`, `verify_imported_pack.py`, `voice_agent_spec.py check` | PASS |
| Preview in headless Chromium 1194, frames at 0.25, 0.88, 1.2, 1.5 and 1.9 s, light and dark | Rendered as intended; one fix made (the SWISH burst was clipped at the right edge, moved left of the hoop) |
| `xcodebuild test` (app, `LaunchSmokeTests`) | **NOT RUN**: no Xcode |

The Swift toolchain was downloaded into the session for these runs (`swift-6.1-RELEASE-ubuntu24.04`).

## Constitution evidence (DODDY AI Constitution V1)
| Rule | How this slice meets it | Enforcing code | Tests |
|---|---|---|---|
| DOD-11 observable privacy | Listening on open is off until turned on; the usage string, Privacy row and switch note say when the microphone is on | `OpeningPolicy.decide`, `ShortcutRouter.startListeningOnOpen`, `MicrophoneAccess` | `OpeningPolicyTests`; UI `testListeningOnOpenIsOffByDefaultAndSaysSo`, `testOpeningPlaysOnLaunchCanBeSkippedAndNeverListensByItself` |
| DOD-08 truthful status | The opening and Home's hello never say "Listening"; that word comes only from `VoiceSessionController` | `OpeningGreetingCopy` | `testEveryGreetingNamesDoddyAndNeverClaimsToListen` |
| DOD-03 AI character | The hello says who is talking; no claimed feelings | `OpeningGreetingCopy` | same |
| DOD-05 preferences | Tone, language and nickname from the user's settings | `OpeningGreetingCopy.render` | `testNicknameIsCleanedLikeEverywhereElse`, `testAutomaticLanguageFollowsTheIPhone` |
| Accessibility | Still picture under Reduce Motion; none under VoiceOver or with artwork hidden; one element with a skip action; buttons never hidden under Reduce Motion | `OpeningScene.still`, `OpeningPolicy.decide`, `SlideIn` | `testReduceMotionIsAStillPictureOfDoddyReadyToTalk`, `testTheSceneGivesWayToAccessibilitySettings` |
| Gaps | Nothing above is verified on a device. The spoken greeting is the agent's dashboard setting. | | |

## Owner decisions
1. Default of "Start listening when I open Doddy": off as shipped.
2. Whether to change the agent's first message to match the hello.
3. Timing (2.3 s), the replay threshold (5 minutes) and how long Home keeps the hello (8 s) are first guesses: `OpeningScene.Beat`, `OpeningPolicy.replayAfter`, `OpeningModel.readyFor`.
