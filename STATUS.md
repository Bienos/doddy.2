# Doddy: current status (read this first)

Doddy is a voice-first memory companion for iPhone, with an Apple Watch app and a Mac menu bar prototype. This page is the short version. Update it when you merge something that changes what is below.

Last updated 2026-10-11, 21:10 UTC.

## Known-good build
- **Main branch:** `claude/loving-dirac-uuxoux`, head `ce02763` (PR #60, the learning loop).
- **Evidence:**
  - The live voice agent worked from this code on 2026-10-11 at 22:35 Warsaw time: a 139 s conversation that used `search_memories`, `save_memory` and `web_search`.
  - The variables the app sent to ElevenLabs match this branch, and not the unmerged `-all` branch.
- **To get back to a build that works,** build this branch: `make project`, open `Doddy.xcodeproj`, scheme `Doddy`.
- **Voice agent:** ElevenLabs agent `agent_0501m4et27vyeawrwqfdxxfszfa6`, live version `agtvrsn_5201m4p132brf30th15nggeqarf0`. It was unchanged between the last working call and this update. Its spec is `voice-agent/`.

## Platforms
Each platform has its own project spec, so one platform's code can't break another's build. See `docs/platforms/README.md`.

| Platform | Code | Spec → project, scheme | State | Page |
|---|---|---|---|---|
| iPhone and iPad | `DoddyApp/`, `Shared/`, `DoddyWidgets/`, `DoddyShare/` | `project.yml` → `Doddy`; `project-iphone.yml` (no Watch app) → `Doddy` | Built and used by the owner on device. The voice agent was seen working on 2026-10-11. | `docs/platforms/iphone.md` |
| Apple Watch | `DoddyWatch/`, `DoddyWatchWidgets/` | `project.yml` → `DoddyWatch` (embedded in the iPhone app) | Code exists; never compiled or run | `docs/platforms/watch.md` |
| Mac | `DoddyMac/`, `DoddyMacWidgets/` | `project-mac.yml` → `DoddyMac` | Prototype on PR #61; never compiled | `docs/platforms/mac.md` |
| Shared core | `Packages/DoddyCore/` | Swift package, used by every platform | Tests run on Linux, 934 passing | `docs/platforms/README.md` |

## Not merged yet: what each branch would change
Merge one at a time, then rebuild and talk to Doddy before the next.

| Branch / PR | What it changes | Risk to voice |
|---|---|---|
| `claude/admiring-curie-bsuwv9-all` (integrates PRs #43, #46, #48, #51, #53, #56, #57, #58) | Shorter intro, Quick start screen, first-visit Home. **The OpenAI/ElevenLabs test switch moves from Home to Settings.** "Hey Doddy" with one tap, guided first conversation, "Ask me about it". | High: changes voice start, the microphone and the wake word |
| `claude/trusting-dirac-o8ajzc` | Voice screen shows Doddy with a sound wave; the transcript is one tap away; the wave follows loudness | Medium: adds audio level meters to the live session |
| `claude/affectionate-mayer-aovol9` | Island compact view draws a pre-cut round face | Low |
| `claude/dismiss-ended-card` | Nothing: its changes were reverted | None |
| PR #44 `claude/peaceful-hopper-v3gx75` | Action status, session recovery, Stop listening, unfinished notes, "Listen until I finish" | High: changes the voice session |
| PR #61 `claude/fervent-hamilton-cv19sj` | iPad sidebar and fixes, Watch "New note" and Smart Stack, Mac menu bar app, widget and window, per-platform projects | Low for voice: no voice-agent changes |

## Known problems
- **Voice sessions sometimes start twice.** ElevenLabs logs from 2026-10-09 to 10-11 show:
  - two sessions starting in the same second;
  - a "ghost" session that connects but never sends its start data and stays silent for 30 s;
  - a session that can't hear the user.

  Not fixed yet. It needs a device log to confirm the cause.
- **GitHub Actions don't start jobs** (they fail in seconds with no logs; probably account billing). Hosted CI is effectively off.

## Waiting on the owner
- Whether notes sync between the Mac and the iPhone (today they never do).
- The kitchen timer Live Activity.
- A Pencil drawing canvas.
- The Mac minimum macOS version.
- The final icons.

## How agents should read this repo
1. This page, then **only** the page for the platform you are working on, under `docs/platforms/`.
2. That page lists the folders and the status doc for each feature. Open those, not the whole tree.
3. **Don't read `DECISIONS.md` (about 770 lines) whole.** Search it for an ADR number: `grep -n "| 452 |" DECISIONS.md`.
4. Ignore `reference/`, which is historical.
5. Run `scripts/ci.sh --core-only` on Linux. App code needs a Mac with Xcode.
