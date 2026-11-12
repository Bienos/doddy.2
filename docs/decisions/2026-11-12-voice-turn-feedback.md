# The voice screen names what Doddy is doing, and each turn is timed on the phone

- **Date:** 2026-11-12
- **Decided by:** owner ("ok rob 2 i 3", 12 Nov 2026, after the latency review in this session)
- **Status:** proposed; applied in the pull request that adds it
- **Replaces:** nothing. Extends ADR-604 (agent states on the voice screen and the island).

## Why
ElevenLabs' agent statistics (7 days to 12 Nov 2026) put the median answer at 2.18 s after the person's silence, p95 3.6 s, and about 70% of it is the model (`LLM_SERVICE_TTFB` p50 1.51 s). Tools that run on the phone or the web take 5–37 s on average (`ask_claude` 20 s, `look_at_screen` 15 s, `web_search` 7 s). Two things made that feel worse than it is:

1. The only wait text was "Working on it…", shown only once the provider said "thinking", and the SDK (3.3.1, `AgentStateManager`) says "listening" the moment any tool answers, so the screen read "Listening" while the model wrote its answer to the tool's result.
2. Nothing measured what the person experiences on the phone. ElevenLabs measures on its servers only.

## Decision
- `VoiceTurnWatch` (DoddyCore, tested on Linux) follows one conversation's turns from the provider's events: the person's final transcript, tool request/response (the app's own client tools and the provider's `agent_tool_request`, one count per call id), the agent starting to speak, interruptions.
- The "thinking" text names the tool that is really running ("Searching the web…", "Asking Claude…"), says "Still on it…" after 4 s, and is held for at most 6 s after a tool answered unless Doddy speaks first. A tool with no named activity keeps "Working on it…". Nothing is named that is not running.
- One soft haptic tap when the person's words arrive (not while Doddy speaks, not in translator mode); iOS drops it when System Haptics is off.
- The phone logs one line per turn: `turn 2.31 s to Doddy speaking · web_search 1.92 s`. Fixed words, seconds and the agent's tool names only; nothing said, saved or typed, nothing sent anywhere.

## Consequences
- Does not make Doddy answer faster. It makes the wait readable and gives the phone's own number for each turn, so later changes (shorter tool descriptions, a faster model) can be checked on the device.
- The turn starts when the person's final transcript reaches the phone, so the provider's end-of-speech wait before it is not in the logged number. The app has no speech detection of its own while unmuted.
- Polish strings added to `l10n/pl.json` by this change; other languages show English until translated. Native review applies (ADR-234).
- The live ElevenLabs agent is not changed.

## Evidence
`VoiceTurnWatchTests` (DoddyCore, Linux). The iOS app was not compiled here (no Xcode); the hosted Mac CI is the first build of `VoiceTurnFeedback.swift` and the controller edits. Not run: a call on a device, haptics, the island.
