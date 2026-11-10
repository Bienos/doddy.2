# Focus, the wind-down and the stopwatch start by voice; Home's "Focus, timers and stopwatch" menu goes

- **Date:** 2026-11-10
- **Decided by:** owner, 10 Nov 2026, in Polish: "Skupienie, minutniki i stoper … lepiej to schować i po prostu wywoływać to na komendę do Doddy'ego … Tak, proszę, zrób to."
- **Status:** accepted; applied in the pull request from branch `claude/voice-timers`
- **Replaces:** the "Home › ••• › Focus and stopwatch" row of ADR-652 and the "Home → Timer" and "Home → Wind down" entries of ADR-780

## Why
Home's ••• menu had a submenu, "Focus, timers and stopwatch", with four rows (Focus, Stopwatch, Timer, Wind down). The owner wants them out of sight and started by asking Doddy. Before this change only the stopwatch (`start_stopwatch`, `stop_stopwatch`, `check_stopwatch`, ADR-652) and the AlarmKit timer (`set_timer`, ADR-650) had voice tools; the focus timer (ADR-241) and the wind-down (ADR-780) had none, so removing the menu alone would have made them unreachable (pull request #315 kept the menu for that reason).

## Decision
1. **Five new voice tools**, Doddy's own timers on this iPhone, classified like the stopwatch:

   | Tool | Parameters | Effect | Ask (ASK-01) |
   |---|---|---|---|
   | `start_focus` | `minutes` (1 to 180, default 25), `label` (optional) | local change | card with the exact length and line, a tap |
   | `stop_focus` | none | local change | card, a tap |
   | `check_focus` | none | look-up | a spoken yes or a tap |
   | `start_wind_down` | `minutes` (1 to 60, default 10) | local change | card with the exact length, a tap |
   | `stop_wind_down` | none | local change | card, a tap |

   A length out of range, or not a number, is refused with a reason the agent reads ("minutes must be a number from 1 to 180"), never shifted. They run the existing `FocusController` and `CountdownController` (`.windDown`). One of each at a time: a start while one runs or is paused replaces nothing and says how much is left. Every reply is built from the session the app reads back after the change (`TimerVoice.swift` in DoddyCore): "added" only for a running session, with its end time; "changed" only when the read-back says stopped; a notification is promised only when iOS listed it as pending. They sit outside Pause all and the Connections switches (no other app or account), are refused while driving except the reading, and are core tools, so the beta's release scope keeps them.
2. **A plain timer by voice stays `set_timer`** (AlarmKit, rings through Silent mode, ADR-650). No second "set a timer" tool: the agent never chooses between two paths. This settles ADR-780's open question ("two timers by two paths") for voice. Home's kitchen-timer countdown (`CountdownController`, `.timer`) loses its only way to start; its code, island and screen stay, so one started earlier still shows and can be stopped.
3. **Home's menu loses the submenu** (`home.timers`, `home.focus`, `home.stopwatch`, `home.timer`, `home.windDown`). While a focus, kitchen timer, wind-down or stopwatch runs or is paused, Home shows one small row for it above the other cards (`RunningTimersView`, `home.running.<kind>`), with its time ticking by itself; a tap opens its existing screen with Pause and Stop. Nothing shows when none runs. The island and Lock Screen keep their own Pause and Stop.
4. **What I can do:** the "Reminders and calendar" row becomes "Reminders, calendar and timers" and says focus, the stopwatch and a wind-down start the same way, in a conversation. No new row (pull request #315 is reshaping that screen).
5. **The live agent** gets the five tools only on the owner's yes (`docs/OWNER_QUEUE.md` item 35). The prompt (`instructions.md`) is unchanged: each description says when to use it and how it differs from `set_timer` and the others.

## Consequences
- Until the five tools are on the live agent, a build with this change can't start focus or a wind-down at all. Sync them before, or right after, the merge reaches TestFlight.
- A kitchen countdown can no longer be started; if the owner wants it back, the choice is a menu row or routing `set_timer` to it (losing AlarmKit's ring).
- Privacy: nothing leaves the iPhone beyond what the voice already sends (the tool call and its reply: a length, the user's line, the end time). The line shows on the Lock Screen, as before.
- Each new tool adds a little to every conversation's tool list (five short descriptions).

## Evidence
- Linux, Swift 6.1.2: DoddyCore tests, `TimerVoiceTests` (new) and the updated `ActivityTextTests` and `AskFirstPolishTests`; `scripts/ci.sh --only swift,checks`; `python3 -I scripts/voice_agent_spec.py check`; the string catalogs' `--check`.
- `swiftc -parse` on every app file changed. **Not compiled with Xcode** (no Mac here): `VoiceSessionController`'s five cases, Home's row, the screen fixture and the UI tests. Not tried on a device, and no real conversation with the new tools (they aren't on the live agent).
