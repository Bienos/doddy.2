# The island follows Doddy, and its updates no longer queue (ADR-604)

Owner, 23 Oct 2026: the Dynamic Island "zacina się" (stutters / sticks); scan the code and make it fast.
Static review on Linux (no Xcode, no device): **nothing here was measured or seen on an iPhone.**

## What was found

1. **The ElevenLabs "speaking / thinking" callback never fired** (most likely why the island stayed on
   "Listening" and never opened up, as the owner reported on 21 Oct). `VoiceSessionController` set
   `config.onAgentStateChange` but never `config.agentStateConfiguration`. In ElevenLabs Swift SDK 3.3.1,
   `Conversation.setupAgentStateManager()` returns at once when that is nil, and `onAgentStateChange` is only
   called from that manager ("event-based mode only"). Nothing else in the app reads `agentState`. So on the
   ElevenLabs path `phase` only ever went `connecting → listening`: no `.speaking` (the island never expanded,
   Home's waves and talking pose never moved), no `.thinking`. The OpenAI path calls `apply(_:)` itself and
   was not affected. The live agent's `client_events` (read 24 Oct) are `audio, interruption, agent_response,
   user_transcript, agent_response_correction, agent_tool_response`.
2. **Island updates queued.** Each `show()` chained a task behind the previous one. A status that flips
   (speaking ↔ listening, which the SDK itself debounces by 0.5 s) reached the island one old state at a time.
   The 40 s heartbeat could also overtake a queued update and a late old state then landed.
3. **Home's moving waves ran at the display's full rate** (`TimelineView(.animation)`, 120 Hz on ProMotion)
   next to Doddy's own 120 Hz display link, and each of the nine lines had a view `.opacity` (an offscreen
   layer each).

## What changed

| Change | Where |
|---|---|
| `agentStateConfiguration = AgentStateConfiguration()` so speaking / thinking / listening arrive | `VoiceSessionController.swift` |
| `LiveActivityPacer`: newest state wins, at most one update in flight, 0.5 s apart; 10 tests | `Packages/DoddyCore/.../LiveActivityPacer.swift` |
| `VoiceLiveActivity`: one sender task using the pacer; heartbeat and the expand alert go through it; `finish`/`end` cancel it and wait for an update in flight | `VoiceLiveActivity.swift` |
| Waves: 30 fps cap, colour alpha instead of view opacity, line sets built once | `IslandExtension.swift`, `IslandWaves.swift` |
| `phase.didSet` returns when the phase did not change | `VoiceSessionController.swift` |
| Opening scene capped at 60 fps | `OpeningSceneView.swift` |

**Side effect to watch:** for the first time on ElevenLabs, `.speaking` happens, so the big-island request
(ADR-577, with its alert sound, at most every 20 s, only while Doddy is not on screen), Home's wide waves and
the talking pose now run on real conversations.

## Needs the owner (live agent, not changed here)

Add `agent_tool_request` to the agent's client events. Without it "Working on it…" during a tool call is shown
as a short Listening before Doddy answers. `vad_score` is not needed.

## Checked / not checked

- Run: `make test-core` (1,672 tests, 0 failures, 10 new), `scripts/check_island_art.sh` (pass),
  `scripts/typecheck_app_logic.sh` (26 files, pass), Swift 6.1.2 on Linux.
- **Not compiled:** the SwiftUI and ActivityKit edits (hosted Mac CI is the first compile). **Not seen on a
  device**: whether the island now says Speaking, expands, and feels smoother. Measure on a ProMotion iPhone,
  Release build (Instruments: Time Profiler, Hitches, SwiftUI).

## Suggested, not applied (from the app-wide static audit)

- Calendar / contacts / birthdays reads run on the main actor (`DeviceConnections`, called from
  `VoiceSessionController`): move to a detached task returning Sendable values. Highest value, medium risk.
- Doddy's display link asks for 120 Hz even for idle breathing (`DoddyClock.swift:47`): 60 Hz for idle, 120
  only in flight. Four cream-edge shadows per sprite (`islandCreamEdge`) only in dark mode.
- Home's full-screen `DragGesture(minimumDistance: 0)` publishes on every touch sample: throttle to 30 Hz.
- `DoddyApp.init` does Keychain, GRDB migrations and log decoding before the first frame; `LaunchWork.later()`
  starts seven jobs 1.5 s in: add signposts, start them after the opening.
- `ActivityLogStore` re-encodes and writes the whole log on every append; `MemoryStore.reload()` bumps
  `revision` every time. Full report and fix sketches were kept by the session that wrote this.
