Voice start: logs how long each stage takes (account restore, profile, connect, and the token request on its own) on the `voice-audio` log, seconds only. No behaviour change. Decision `2026-11-10-voice-start-timing`.
Ran: DoddyCore tests (new `VoiceStartTimelineTests`), `swiftc -parse`. Not run: app build (hosted Mac job), a press on a phone.
