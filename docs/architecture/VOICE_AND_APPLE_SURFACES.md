# Voice, iOS invocation and character state
## Sequence
**M1:** typed capture fallback first. **M3:** foreground microphone capture + transcription + optional synthesized speech and interruption lifecycle. No live voice promise until device test.

## Compare two voice paths on actual devices
A. Apple Speech/AVAudioEngine + native TTS + ordinary model text requests (potentially lower cost, less natural turn-taking).
B. Real-time provider speech-to-speech (different latency/interrupt and data costs).
Benchmark Polish/English accuracy, turn interruption, no-network fallback, mic/speech permissions, accessibility, noisy conditions, data transfer, real billed use, and low-end supported device performance. Document uncertainty; choose only after tests.

## Permission and audio lifecycle
User triggers microphone explicitly; ask permissions at point-of-use, never during unrelated onboarding. Identify listening/processing/speaking using actual engine events, not timers. Mic must stop on close, background/lock as required, interruptions, route changes, or denial. UI remains navigable by text. Audio is not written to durable memory unless user separately confirms saving the transcript.

## Apple surfaces
- iOS App Shortcuts / App Intents: a shortcut can open the foreground app; check `supportedModes` availability and modern API use. Existing `openAppWhenRun` may be deprecated in target SDK.
- Back Tap: user manually chooses a Shortcut under iOS Settings; an app cannot silently assign itself to Double Tap by installation.
- Action Button: user-configured, models/OS permitting.
- WidgetKit Controls/Control Center: later extension requiring platform availability checks; do not assume a universal iOS17 API.
- Dynamic Island/Live Activities: bounded platform surface, not a floating system-wide assistant or long-lived microphone entitlement. Only implement a legitimate live activity with actual eligible ongoing state.
- Screen awareness: no general-purpose access to other apps' screen; user-initiated share/import can be a future separately permissioned path.

## Character cues
Listening icon/animation requires actual mic, thinking requires outstanding model request, success requires persisted or externally verified outcome. Provide reduced-motion static state and no fake "Doddy is hearing you" signal. Avoid a character performance that adds delay or conceals uncertain results.

## Official verification links
https://developer.apple.com/documentation/appintents/
https://developer.apple.com/documentation/widgetkit/controls-collection
https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities
https://support.apple.com/guide/iphone/back-tap-iphaa57e7885/ios
