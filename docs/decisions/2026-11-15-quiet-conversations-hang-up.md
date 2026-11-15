# A conversation nobody speaks in hangs up by itself

- **Date:** 2026-11-15
- **Decided by:** owner ("Bruh there is no way it was turned on for 2hours I think there is something that captures voice all the time and using credits because of it find it and fix it"); the limits below are the agent's proposal, the owner can change them
- **Status:** accepted. App half: the pull request on branch `claude/nifty-bell-dit0iu`. Live agents: applied 15 Nov 2026 (owner: "Set it now"), `voice-agent/README.md`

## Why
The owner's ElevenLabs export for 7 to 14 Nov 2026 shows 148.7 minutes of "Agents v0" and 15.7 minutes of "Agents (when silent)". Read on 15 Nov from the ElevenLabs conversation list (all agents, every conversation started from 9 Nov, read only):

- **Nothing ran for hours.** 300 conversations, 157.9 minutes in all; the longest was 9 min 27 s (a translator conversation). The live main agent and the translator both have `max_duration_seconds` 600, so ElevenLabs cuts any conversation at 10 minutes. 288 ended with the app's own close (`Client disconnected: 1000`), 7 with Doddy's `end_call`, 4 with the caller hanging up (phone agent), 1 with an error.
- **153 of them (39.5 minutes) were not the phone.** Initiation source `unknown`, all on 12 Nov between 15:00 and 18:00 Warsaw time, one or two typed lines each ("Nearest pharmacy", "Nearest ATM", "Bus ticket"): the live checks of the translator agent, typed over the agent's WebSocket (decision `2026-11-12-translator-more-languages`, "Live checks"). That is most of 12 Nov's 50 minutes.
- **The iPhone app (`swift_sdk`) made 143, 111.4 minutes.** 57 of them ended within 10 seconds with nobody speaking (greeting only, often several in a minute: starts that were tried and stopped).
- **The leak: a conversation never ended by itself.** The live agents have `silence_end_call_timeout` -1 (they never hang up on silence), and the app had no quiet limit, so a conversation stayed open until End, Doddy's `end_call` or the 10-minute cap. The iPhone has the `audio` background mode, so after Doddy opened another app, or with the screen locked, the microphone stayed open in the background and heard the room. Example, 14 Nov 02:19 (`conv_2701m7bt77g9f8e9mwk0vvxre7v3`): the person asked for a route at 0:02, Doddy opened Apple Maps at 0:16 and spoke his last line at 0:17; the microphone then heard a television's English at 1:20 ("Everything is safe. It's safe. Beautiful."), and the conversation ran until 4:39: 81 seconds of audio sent for transcription, 3.8 minutes billed as silence.

## Decision
The app ends a conversation in which nothing has happened for the limit of its situation, as `VoiceSessionEnd.quiet` (code `quiet`, which Logbook and Doddy's server already name "Went quiet").

- **Limits** (`VoiceQuietWatch` in DoddyCore): 60 s with Doddy on screen; 30 s with Doddy in the background (another app on screen, the screen locked, a conversation started from the island over another app); 120 s in translator mode or while a card waits for a tap or yes (also a long turn's draft). The most patient reason wins.
- **What counts as something happening:** a line from either side (translator lines too), and every change of the conversation's state (Doddy starts or stops speaking or working). While Doddy speaks or works on an answer (`.speaking`, `.thinking`, a tool still running) or the person records a long turn, the clock waits, but for at most 300 s with nothing else happening, so a state that never ends can't keep the microphone open either.
- **How:** `VoiceSessionController` starts the clock when Doddy is first ready (not while connecting), looks at most every 5 s, so leaving the screen counts within seconds, and ends with `stop(.quiet)`: the same path as End (the microphone, the island and the gate are freed, the transcript is kept, "Worth keeping?" and the learning card are offered as after End). It logs one line with fixed words and seconds: `conversation ended: quiet for 30 s (on screen false, …)`.
- **What the person sees:** the voice screen says "Conversation ended", as after End. `SessionRecovery.status(.quiet)` has the line "Nobody spoke for a while, so Doddy hung up. His microphone is off." (Polish: "Przez chwilę nikt nic nie mówił, więc Doddy się rozłączył. Jego mikrofon jest wyłączony."); no screen shows that line yet. It is not a drop: no recovery draft, no Home drop notice, and the next conversation is not told it was cut off.

## Consequences
- **Cost and privacy:** a forgotten conversation now costs at most about 30 to 60 seconds instead of up to 10 minutes, and the microphone stops hearing a room nobody is talking to Doddy in (DOD-11).
- **Builds without this change** are covered by the live agents' own `silence_end_call_timeout`, set on 15 Nov 2026 on the owner's word: 60 s on the main agent, 120 s on the translator (seconds since the user last spoke). It also covers any other client, typed checks included. The app's limit is shorter in the background (30 s) and also counts Doddy's own lines and cards.
- **What to watch:** someone who thinks for over a minute with Doddy on screen has to start again; a translator conversation with a pause of more than two minutes ends. If either happens often, raise the limit in `VoiceQuietWatch` (one constant each).
- **Not changed:** the 10-minute cap, ElevenLabs' turn and soft timeouts, the live prompt and tools, how a conversation starts, and the short greeting-only starts (they are starts, not leaks).
- **Live checks cost minutes too:** the 12 Nov translator checks were about 40 minutes. Typed checks against a live agent are billed like conversations.

## Evidence
- Read: ElevenLabs conversation list from 9 Nov 2026 (300 conversations), conversation `conv_2701m7bt77g9f8e9mwk0vvxre7v3`, the main agent's and the translator's `conversation_config.turn` and `max_duration_seconds`.
- Changed on the owner's word: `silence_end_call_timeout` on both live agents, read back (`voice-agent/README.md`). Not checked yet: a live conversation that reaches it.
- Ran: `make test-core` on Linux with Swift 6.1.2: 3700 tests, 0 failures, 2 skipped, including the new `VoiceQuietWatchTests` (10, one replays the 14 Nov Maps conversation and ends it at 0:47) and `.quiet` added to the end-reason tests in `SessionRecoveryTests` and `ActionStatusTextTests`. `swiftc -parse` on `VoiceSessionController.swift`.
- Not run: the app build (no Xcode here, so the controller change is **not compiled**), the iOS unit and UI tests, anything on a phone.
