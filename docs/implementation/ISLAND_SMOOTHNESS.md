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
| Calendar, contacts and birthdays reads in tool calls run off the main actor (`readEvents`, `readContacts`, `readContactBirthdays`; fakes keep working through protocol defaults) | `DeviceConnections.swift`, `VoiceSessionController.swift` |
| Doddy's clock asks for 120 Hz only while he really moves (hop, fade, shuffle, finger down); breathing and blinks run at 60 Hz | `DoddyClock.swift`, `DoddyDirector.wantsHighRate` |
| The cream edge adds nothing in light appearance (it was four invisible shadows) | `IslandViews.swift` |
| Home's finger-following eyes take at most 30 touch samples a second | `HomeView.swift` |

**Side effect to watch:** for the first time on ElevenLabs, `.speaking` happens, so the big-island request
(ADR-577, with its alert sound, at most every 20 s, only while Doddy is not on screen), Home's wide waves and
the talking pose now run on real conversations.

## Needs the owner (live agent, not changed here)

Add `agent_tool_request` to the agent's client events. Without it "Working on it…" during a tool call is shown
as a short Listening before Doddy answers. `vad_score` is not needed.

## Checked / not checked

- Run: `make test-core` (1,672 tests, 0 failures, 10 new), `scripts/check_island_art.sh` (pass),
  `scripts/typecheck_app_logic.sh` (26 files, pass), Swift 6.1.2 on Linux.
- **Hosted CI, 24 Oct, [run 40060080233](https://github.com/Bienos/doddy.2/actions/runs/40060080233) on `3f623a8` (started by hand):** `core` and the macOS job green; `scripts/ci.sh` built the app and widget and passed the unit and UI tests. The simulator does not run a real conversation, so this proves it compiles and nothing regressed, not that the island now says Speaking. **Not seen on a
  device**: whether the island now says Speaking, expands, and feels smoother. Measure on a ProMotion iPhone,
  Release build (Instruments: Time Profiler, Hitches, SwiftUI).

## Suggested, not applied (from the app-wide static audit)

- Photos search (`PhotoLibrarySearch`) is still on the main actor; birthdays at launch (`BirthdayScheduler`), the Today card and the weekly look-back still read calendar and contacts synchronously.
- `DoddyApp.init` does Keychain, GRDB migrations and log decoding before the first frame; `LaunchWork.later()` starts seven jobs 1.5 s in: add signposts, start them after the opening.
- `ActivityLogStore` re-encodes and writes the whole log on every append; `MemoryStore.reload()` bumps `revision` every time; `RootView.body` reads live conversation state.
- Bake the cream outline into dark-mode sprites instead of four runtime shadows; downscale the 800×1200 `UploadedDoddy_Listening`.
- All of this needs measuring first (Instruments on a ProMotion iPhone, Release build). Full report: `docs/research/2026-10-24/perf_audit_app.md`.
