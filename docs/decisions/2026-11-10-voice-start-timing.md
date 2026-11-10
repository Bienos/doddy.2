# The voice start logs how long each stage takes, before anything is changed to make it faster

- **Date:** 2026-11-10
- **Decided by:** owner (Pat, 10 Nov 2026): Doddy is slow "przy włączaniu"; asked for ways other than a faster model to speed up the start; "a co ten bilet jest wgl - nie da się tego inaczej zrobić"; then "ok" to this plan: measure first, fetch the token ahead only if the measurement shows it matters.
- **Status:** applied in the pull request of branch `claude/voice-token-prefetch`
- **Replaces:** nothing. Adds to ADR-686 (token fetched while the context loads).

## Why
After a press, several things run before the first word: restoring the voice login (which can refresh it over the network), loading the profile, the token request to the voice token server (login check, rate limit, ElevenLabs), joining the room. Nobody has a number for each. ElevenLabs' analytics show the answers themselves take 1.3–1.9 s to start (the model), which is a different delay from the start. Fetching a token ahead of time would only save the token request, and the token server counts every token against 30 an hour and 150 a day per person, so it shouldn't be added on a guess.

## Decision
- `VoiceStartTimeline` (DoddyCore) holds the stages `account`, `profile` and `connect` with seconds, from a monotonic clock. The Action Button / Back Tap / Siri start (`TalkInIsland.start`) logs one line when it ends, however it ends: `talk start timing: account 0.31 s · profile 0.02 s · connect 2.40 s · total 2.73 s`.
- `VoiceTokenClient.fetchToken` logs `voice token request took 0.84 s`.
- Both go to the `voice-audio` category of subsystem `com.bienos.doddy2.dev`, with `.public` privacy. Only fixed stage words and seconds can appear: no account, token, address, text, note or name.
- `VoiceSessionController.swift` is not changed (another change is editing its tool handlers).
- **Update:** the owner chose the token shelf before any numbers came; see `2026-11-10-action-button-start`. The timing line gained the stage `island` and a final `token shelf` / `token fetched`.
- **Next, from the numbers:** if `token` is a large share of `connect`, fetch the token ahead of time (reading rules already written and tested, kept out of this change: one use per token, same account and server, a few minutes' life, a cool-down after an unused one). If `account` is large, skip the refresh when the stored session is still valid. If `connect` without the token is large, the cause is the room and the first audio, and neither of those two changes would help.

## Consequences
No behaviour change and no new data leaves the phone. Console.app (device log, filter `voice-audio`) shows the lines after one press.

## Evidence
`VoiceStartTimelineTests` (5) pass on Linux; `swiftc -parse` on both app files. The app isn't compiled here (no Xcode); the hosted Mac job builds it. Nothing was run on a phone: the numbers come only from the owner's next press.
