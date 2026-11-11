# Prepare the voice provider's network route before a press

- **Date:** 2026-11-11
- **Decided by:** owner: "Scal i zrób 1 albo coś lepszego", choosing network preparation on Home after the voice-token fix (#325).
- **Status:** accepted; native/device verification is recorded in the pull request.
- **Replaces:** nothing; extends `2026-11-10-action-button-start` and #325.

## Decision

While the app is active and voice access, provider consent and microphone permission are already granted, call LiveKit's public `Room.prepareConnection(url:token:)` for the pinned ElevenLabs media host, with **no token**. Never prepare while Pause all is on, a conversation is starting/running, or voice is unconfigured. Recheck these gates when the scheduled task runs. Permit at most one request per two minutes, independently of whether a voice token is held. A press awaits neither preparation nor any new permission prompt.

A signed-in owner is required separately from voice access: the Debug developer connection alone may authorise a press, but never an idle provider request while signed out. The gate test explicitly keeps voice access true and removes the signed-in owner.

This does not call `Room.connect`, start an ElevenLabs conversation, publish an audio track, record, or send notes/profile/conversation content. The SDK's live Room is created separately by ElevenLabs. Keep that integration and the pinned packages unchanged.

## What the pinned SDK actually does

- ElevenLabs Swift 3.3.1 (`5bb21c2cdb54bf465f6bb09ce52fc59b0e22aae5`) uses `wss://livekit.rtc.elevenlabs.io` (`Internal/Authorization/ConnectionConstants.swift`). `VoiceNetworkHostTests` compares our constant against `TokenService.fetchConnectionDetails` with a provided dummy token, an offline code path.
- LiveKit 2.19.0 (`43c1c0870e51eedbfd95b20b1b5c43a767886786`) `Core/Room+Region.swift`: this custom domain takes the non-Cloud branch, which schedules `HTTP.prewarmConnection` in a task. `Support/Network/HTTP.swift` sends a credential-free HTTPS HEAD to the host, with a 10-second timeout, swallowing network failures. `prepareConnection` returns before the HEAD finishes. Log only "preparation requested", never "ready", success, or a preparation duration.
- The HEAD uses LiveKit's HTTP session; its signaling WebSocket creates another session. This is the SDK's network preparation hint, **not** a held WebSocket or a reusable media room. DNS/TLS setup may benefit; no particular latency saving or elimination of three seconds is claimed. The full room join and agent readiness still follow the press.
- An SDK-owned HEAD already dispatched can finish after a background transition or consent withdrawal; it carries no credential or user content. New dispatches stay gated. The app cannot cancel that SDK-internal task through the public API.

## Measurement and verification

Log the SDK's actual `roomConnect` (includes microphone setup), `agentReady`, `conversationInit` and `total` durations on its active/failed startup event. Absent/invalid values say unavailable. Keep #325's Home-tap-to-first-speaking-event log separate: an SDK speaking event is not proof of audible playback.

Test every preparation gate, repeated foreground/settings triggers, the cooldown, invalid clocks and independence from token use/expiry. Run the real SDK-host parity test on iOS. Compare cold/warm starts on an iPhone, on Wi-Fi and cellular, including a quick tap while preparation is pending; confirm no pre-tap microphone indicator or provider conversation and unchanged cancellation/sign-out behavior. Device latency is not yet measured.

Constitution: DOD-01 (reduce startup work), DOD-08 (truthful timing and requested-vs-ready distinction), DOD-11 (permission gates and no pre-tap microphone/content transfer).
