# The opening and "Start listening when I open Doddy" (ADR-225)
Date: 2026-10-10. Owner requests: "a very cool app opening every time … Doddy is playing basketball … the camera zooming in on him … he scores … then the normal UI shows up … very quick … you can turn it off in settings … ideally he says hey it's Doddy what's up mate and already has the microphone open … czy mogę ci pomóc", then "it must be more cartoony … quick animation drawing Doddy, he shoots and then a new version that is ready to speak shows up with other buttons and you can interact".

> **Current behavior (2026-10-16):** this document records the earlier repeated-opening design. The native basketball scene is now only a first-launch intro, never starts voice, and is marked seen after it plays or is skipped. Returning launches go straight to Home; the legacy opening opt-out is respected for older installs. Listening on open defaults off and remains an explicit, separate Settings choice.

**Status: DoddyCore tested on Linux; the app is written but not built.** The timeline, the SVG reader, the policy and the greeting pass their unit tests (Swift 6.1, Linux), and `OpeningModel` compiles against DoddyCore in the Linux check. The SwiftUI scene, Home's ready state, the Settings rows and the UI tests have **not been compiled or tried on a device**: no Xcode here. The Mac checklist (§4b) lists what to look at first.

Third request: "the animation must align with him when he finishes then when he starts to be static … and more this animation cooler". Fourth: "build it … but without that 'hey it's Doddy'": the text greeting is gone.

## The sequence (2.4 s; a tap skips to the hand-over)
| From (s) | What happens |
|---|---|
| 0.00 | A pen sketches Doddy (the dribble drawing), stroke after stroke |
| 0.42 | The ball pops into his hand; two quick bounces, flattened on the floor, a dust puff each |
| 0.78 | He gathers the ball and crouches (squash); the camera punches in |
| 0.94 | Up to the shooting hand, stretch, and a hop |
| 1.04 | Release; the arm follows through; the ball flies with a ghost trail |
| 1.32 | He lands from the hop: a dust puff |
| 1.40 | SWISH! with rays, confetti out of the ring, a camera shake, the ring wobbles, one light haptic |
| 1.58 | He pops up in the listening pose; the camera is back to 1:1 by 1.74 |
| 1.95 | He jumps along an arc into his exact place on Home; the court and paper fade, Home shows through, the buttons slide in |
| 2.25 | He lands on Home's spot with a squash |
| 2.40 | The opening goes; Home's own picture is already in the same place, so nothing moves |

## What was built
| Piece | Where | Reality |
|---|---|---|
| Timeline and layout | `Packages/DoddyCore/Sources/DoddyCore/OpeningScene.swift` | Pure functions of time: camera and shake, pose and cross-fades, per-stroke sketch progress, squash, stretch, hop, the ready pop, the ball (pop-in, bounces, gather, raise, arc with a trail, net), dust and confetti, the burst, the backdrop. `OpeningHandover` places the ready Doddy from the court into Home's measured box. A still variant for Reduce Motion. Tests: `OpeningSceneTests` (23) |
| Drawings | `OpeningArt.swift` (same package), `DoddyApp/Resources/Character/*.svg` | `SVGPoseReader` reads the four supplied v1.3-r1 basketball SVGs (copied unchanged) into strokes with every group transform applied. Tests: `OpeningArtTests` (8), against the real files |
| Rules | `OpeningPolicy.swift` | When it plays and when a conversation follows. Tests: `OpeningPolicyTests` (5) |
| Model | `DoddyApp/Features/Opening/OpeningModel.swift` | Launch vs return, background time, loading the drawings once, Home's ready state for eight seconds, the one way the opening may open a conversation (`ShortcutRouter.startListeningOnOpen`). In the Linux compile check |
| Scene | `DoddyApp/Features/Opening/OpeningSceneView.swift` | `TimelineView` draws `OpeningScene.frame(at:)`; Doddy as trimmed SwiftUI paths in the theme's ink and paper; ball, trail, hoop, net, dust, confetti, burst, "Tap to skip". One VoiceOver element; one light haptic |
| Home's ready state | `DoddyApp/Features/Home/HomeView.swift` | Under the opening: `UploadedDoddy_Listening` (Home's heading is unchanged), hidden while the opening's Doddy stands in for it; Home reports where it draws him. The four actions slide in at the hand-over (never hidden under Reduce Motion) |
| Same picture both ends | `DoddyApp/DesignSystem/MemoryJourneyComponents.swift` | `CharacterArtImage` draws the picture at an exact height with the dark-mode paper backing; `UploadedCharacterView` and the opening both use it |
| Settings | `SettingsView` | Appearance → "Doddy's opening" (on). Voice → "Start listening when I open Doddy" (on, owner decision) with a note. Privacy → the Microphone row follows the switch |
| Microphone usage string | `project.yml` | Covers both the button and the switch |
| UI tests | `DoddyUITests/LaunchSmokeTests.swift` (+ `-openingScene NO -listenOnOpen NO` in the other two files) | Play and skip; ends by itself and no replay on a quick return; off = Home at once; listening on by default opens the conversation (with no agent ID, so no microphone or network) |
| Preview | `design/opening-v0.1/index.html` | The same timeline in a browser, with the same SVGs inlined, a placeholder Home whose buttons slide in and answer taps, and review switches (quarter speed, Reduce Motion, dark). `?t=2.1` freezes a moment; `?home=1` shows Home after the opening |

## What it does not do, on purpose
- Listening on open is on by default (owner decision, 2026-10-10). It is never hidden: the conversation that opens is the ordinary one, with the iOS microphone prompt the first time, the orange indicator, "Listening" only from real session events, and it ends only when the user ends it. The switch in Settings → Voice turns it off. It doesn't start after first-use onboarding, when iOS has refused the microphone, or on a return within 5 minutes.
- No text greeting: there is no speech bubble and Home's heading doesn't change. Doddy's only greeting is spoken by the live agent (its first message, `voice-agent/session.json`) when a conversation starts; change it in the ElevenLabs dashboard.
- No sound effect: an audio file and AVFoundation outside `Features/Voice` are forbidden by the capability guard.
- No new character art: the five drawings are the supplied ones. The motion is whole-drawing squash, stretch, hop and pop, quick cross-fades, and the pen effect.

## Checks run here (Linux)
| Check | Result |
|---|---|
| `swift test --package-path Packages/DoddyCore -Xswiftc -DSQLITE_DISABLE_SNAPSHOT` (Swift 6.1) | PASS: 407 tests, 0 failures; 36 for the opening |
| `scripts/typecheck_app_logic.sh` (9 files, including `OpeningModel`) | PASS |
| `swiftc -parse` on every changed app and UI-test file | PASS (syntax only; SwiftUI is not type-checked on Linux) |
| `scripts/check_forbidden_capabilities.sh`, `verify_imported_pack.py`, `voice_agent_spec.py check` | PASS |
| Preview in headless Chromium 1194, frames from 0.25 to 2.4 s, light and dark | Rendered as intended. Fixes made: the SWISH burst was clipped at the right edge (moved left of the hoop); the preview's own Home picture overflowed (preview CSS only). The last frame and Home after the opening were compared pixel by pixel in light and dark: same place and size; the remaining differences are image smoothing between canvas and `<img>` |
| `xcodebuild test` (app, `LaunchSmokeTests`) | **NOT RUN**: no Xcode here. The hosted macOS workflow (`.github/workflows/ios.yml`) was started on this branch (run 64, commit `044858a`) and failed in 8 seconds with no runner and no logs, like all 64 runs of that workflow so far, the Linux job included. That points to GitHub Actions being blocked for the account (billing or a spending limit), not to this code |

The Swift toolchain was downloaded into the session for these runs (`swift-6.1-RELEASE-ubuntu24.04`).

## Constitution evidence (DODDY AI Constitution V1)
| Rule | How this slice meets it | Enforcing code | Tests |
|---|---|---|---|
| DOD-11 observable privacy | Listening on open is on by default by owner decision; the usage string, Privacy row and switch note say when the microphone is on, and the switch turns it off | `OpeningPolicy.decide`, `ShortcutRouter.startListeningOnOpen`, `MicrophoneAccess` | `OpeningPolicyTests`; UI `testListeningOnOpenIsOnByDefaultAndOpensTheConversation`, `testOpeningPlaysOnLaunchCanBeSkippedAndWithListeningOffOpensNothing` |
| DOD-08 truthful status | The opening never says "Listening"; that word comes only from `VoiceSessionController` | `OpeningSceneView` has no text but "SWISH!" and "Tap to skip" | Mac checklist O1 |
| Accessibility | Still picture under Reduce Motion; none under VoiceOver or with artwork hidden; one element with a skip action; buttons never hidden under Reduce Motion | `OpeningScene.still`, `OpeningPolicy.decide`, `SlideIn` | `testReduceMotionIsAStillPictureOfDoddyReadyToTalk`, `testTheSceneGivesWayToAccessibilitySettings` |
| Gaps | Nothing above is verified on a device. The spoken greeting is the agent's dashboard setting. With listening on by default the microphone opens on every opening without a tap; the constitution's `minimum_needed_permissions` reading that shipped it off was overruled by the owner, and that is recorded here rather than claimed as compliant. | | |

## Owner decisions
1. Default of "Start listening when I open Doddy": decided, on (2026-10-10).
2. Whether to change the agent's spoken first message ("Hey, it's Doddy. What's on your mind?") in the ElevenLabs dashboard.
3. Timing (2.4 s), the replay threshold (5 minutes) and how long Home keeps the listening pose (8 s) are first guesses: `OpeningScene.Beat`, `OpeningPolicy.replayAfter`, `OpeningModel.readyFor`.
