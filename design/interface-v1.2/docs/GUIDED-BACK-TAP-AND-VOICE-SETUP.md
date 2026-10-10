# Guided setup before the personal introduction

Revision 1.2 · 8 October 2026 · design/engineering proposal, not native implementation.

## First-use sequence

1. “Two taps. A little help.” Explain Double Back Tap, with a Set up later route.
2. Choose voice guidance or written step cards. Request real microphone permission only after the user chooses voice in the future native app. The browser has no microphone/audio access.
3. Guide creation of a personal **Open Doddy** shortcut. Add Doddy's Open Doddy App Intent when available, or system Open App → Doddy. Save and run it once. Do not assume an automatic App Shortcut appears in the personal Back Tap list without checking the native workflow.
4. The user opens Settings and follows **Accessibility → Touch → Back Tap → Double Tap → Shortcuts → Open Doddy**. Guidance follows the page the user reports, not an assumed view of their screen.
5. **Optional: keep the taps quiet.** On the same Back Tap page, iOS shows a **Show Banner** switch. It is an iPhone system setting: Doddy cannot read, change or verify it. The guide explains it, shows an illustration (not an Apple screenshot) and records only the user's report (“turned off” / “leaving it on”). It is never required and never blocks the test. The same guide is reachable later from Settings → Double Back Tap.
6. Run a tap test. A received intent proves the shortcut handoff; the user separately confirms whether Double Back Tap triggered it. Another entry point must not be treated as Back Tap verification.
7. End setup guidance. Continue to the first hello/profile introduction; continuing a new voice conversation requires an explicit user action. Deferred setup leaves the app usable.

## What “conversation in the Island” means

The proposed app maintains a user-started, permissioned audio conversation. Dynamic Island/Lock Screen Live Activity displays its current state, short setup step and essential controls. Audio processing belongs to the native app's audio session/coordinator; the Live Activity is not a microphone, model host or chat window.

Compact/minimal presentation should give a small recognizable status. Long press may expose the system's expanded presentation; the app must not claim it can keep an expanded overlay pinned above Settings. The prototype's black panel is an illustration within the browser, not a native Island or Apple Settings screenshot. It uses unchanged supplied listening art, generic controls and typeset Doddy text; no missing approved compact logo was invented.

Pause/Stop must control the real coordinator through appropriate App Intents. Open must route to the current guide/session. The browser concept offers pause, stop, Open steps and expand/collapse; actual native Open/resume handoff is part of the implementation contract below. Keep controls readable and within measured native regions; the 148-CSS-pixel panel is not a certified point layout. With larger text, use a shorter status and open the app for full instructions.

## Voice and guidance contract

- Start the native voice session in the foreground after consent. Configure input/output and legitimate background audio for the active session; do not assume a visible activity keeps the process or microphone running.
- Capture-active → Listening; real audio output → Speaking; interruption/route loss → Paused or unavailable. A stale activity must not advertise active listening.
- Respect barge-in, stop, denied permission, interruptions, network/provider loss, backgrounding, screen lock and app termination. End the guide after the task; do not use silent playback to keep it alive.
- Use a validated step map with version/localization information. Treat the user's report as a report. Ask “Which page are you on?” when ambiguous. A future AI may paraphrase but may not invent settings labels, assignment success or screen observation.
- Guide “Where is Back Tap?” with the supported path; guide a missing shortcut back to personal Shortcuts creation. If Back Tap is absent, explain compatible-device/software checks and keep direct app access available.
- Do not include setup transcripts in personal memory. Personalization starts in the separate reviewed introduction. Do not add screen sharing to this scope.

## System behavior and source evidence

| Source reviewed 8 Oct 2026 | Supported fact / resulting design |
|---|---|
| [Apple: Back Tap](https://support.apple.com/guide/iphone/back-tap-iphaa57e7885/ios) and [shortcut assignment](https://support.apple.com/en-gb/guide/shortcuts/apd897693606/ios) | User selects Double/Triple Tap and a shortcut in Settings. Guide the actual path; do not auto-configure it. |
| [UIApplication.openSettingsURLString](https://developer.apple.com/documentation/uikit/uiapplication/opensettingsurlstring) | Public URL opens the app's own Settings page. Do not present it as a direct Back Tap/Accessibility link; use manual navigation and supported APIs only. |
| [AVAudioSession playAndRecord](https://developer.apple.com/documentation/avfaudio/avaudiosession/category-swift.struct/playandrecord?changes=_5) and [record](https://developer.apple.com/documentation/avfaudio/avaudiosession/category-swift.struct/record?changes=_1) | Recording requires user permission. An active audio session with the audio background mode can support background recording/playback; continuation remains subject to interruption and actual device validation. |
| [ActivityKit Live Activities](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities?changes=_6) | Activity view is a separate sandbox, with no direct network access; app/push updates carry state. Native controls can open or act on the associated task. Never treat ActivityKit display as proof of background audio. |
| [AudioRecordingIntent](https://developer.apple.com/documentation/appintents/audiorecordingintent?changes=_8) | If adopted for recording controls, Apple requires an active Live Activity while recording. Handle creation failure and activity end; do not promise this path can keep recording without it. |

No primary source here supplies a public Back Tap assignment-query API. The implementation proposal therefore stores “user-reported/tested,” not an automatically verified system preference. Hardware gesture origin is not proven by an ordinary Open Doddy invocation alone. Existing iOS system confirmations are not removed by this design.

## Native architecture proposal

`SetupCoordinator` owns step, reported page, shortcut/test state, setup nonce and completion/deferred markers. `VoiceSessionCoordinator` owns permission, audio/provider handles, actual capture/playback state and interruption/cancellation. `LiveActivityPresenter` consumes public session state; `AppIntentRouter` routes start/resume/pause/stop/open without duplicating sessions.

Use the existing foreground Open Doddy intent as the first entry. Plan recording-specific system intents separately, with availability gates and actual lifecycle tests. Duplicate invocations should focus an existing session, not start a second microphone stream. During a test, associate a real intent receipt with the active test window/nonce and ask the user to confirm the physical gesture. Persist no system-assignment claim beyond that evidence. The built-in Open App fallback may not provide a custom intent receipt: foreground return plus user report is weaker evidence, never a fabricated invocation receipt. Guide creating the custom intent before an intent-tested result when needed.

For no Dynamic Island, design the supported Lock Screen presentation and direct app route. For unavailable Live Activities or denied microphone, use step cards/foreground alternatives; do not claim the recording-intent path is available. App kill/interruption must leave the status truthful and provide explicit resume in the foreground.

## Required future validation

Native build/simulator and physical-phone tests remain separate. Before calling this functional: create/save/select the shortcut on target iOS versions; confirm the Back Tap invocation; keep real capture/replies working while switching to Shortcuts/Settings; interrupt with a call, route loss and app termination; validate Activity end/control routing; test non-Island/disabled activities/denied mic, VoiceOver, large text, captions, Reduce Motion and localization. Check current capabilities/eligibility without assuming a device model from a mockup.

No native app source, old repository, settings, permissions, shortcuts or deployment were changed in this design task.
