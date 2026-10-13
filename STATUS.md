# Doddy: current status (read this first)

Doddy is a voice-first memory companion for iPhone, with an Apple Watch app and a Mac menu bar prototype. This page is the short version. Update it when you merge something that changes what is below.

Last updated 2026-10-13, 20:00 UTC, on the integration branch `claude/zealous-albattani-7ay32v` (see "Integration branch for device testing" below).

## Known-good build
- **Main branch:** `claude/loving-dirac-uuxoux`.
- **Last build seen working on a device:** head `ce02763` (PR #60, the learning loop).
- **Hosted CI:** since `c8aff7ae` (#69 with #70), every target compiles on Xcode 26.6 and the unit and 26 UI tests pass on the simulator. That build has not been run on a device.
- **Since then on main:** OpenAI Realtime is the default voice, with a model picker on Home (ADR-442), and the first-use screens landed (#76: ADR-324 to 327, ADR-443). On 13 October the four remaining first-use PRs merged (#53, #56, #57, #58), then #64, #65, #75, and #79 brought in #44, #61, #66, #72, #73 and #74.
- **Default branch head `e2734941` (13 Oct, 19:04 UTC):** its tree is PR #79's head `50267bb7`, which passed hosted CI (run 38426020997: every target compiles, unit and UI tests pass on the simulator). Not run on a device.
- **Evidence:**
  - The live voice agent worked from this code on 2026-10-11 at 22:35 Warsaw time: a 139 s conversation that used `search_memories`, `save_memory` and `web_search`.
  - The variables the app sent to ElevenLabs match this branch, and not the unmerged `-all` branch.
- **To get back to a build that works,** build this branch: `make project`, open `Doddy.xcodeproj`, scheme `Doddy`.
- **Voice agent:** ElevenLabs agent `agent_0501m4et27vyeawrwqfdxxfszfa6`, live version `agtvrsn_5201m4p132brf30th15nggeqarf0`. It was unchanged between the last working call and this update. Its spec is `voice-agent/`.

## Integration branch for device testing (13 October, 20:00 UTC)
`claude/zealous-albattani-7ay32v` = the default branch at `e2734941`, plus, as one merge commit each so any one can be reverted on its own:
1. `claude/friendly-bohr-gy15jv`: the app icon from the owner's pack (ADR-460) and `docs/implementation/RUN_ON_YOUR_IPHONE.md`. Clean merge.
2. `claude/affectionate-mayer-aovol9`: pre-cut round faces for the island's compact and minimal views. Doc conflict only.
3. PR #78 `claude/youthful-pasteur-25tuhv`: the "Big brain. Small body." share card in Settings and on the site. Its ADR number 444 was already the tool catalog's, so it is **ADR-462** here (row and citations renumbered; the code is PR #78's CI-passing commit).
4. `claude/trusting-dirac-o8ajzc`: the voice screen leads with Doddy and a sound wave, transcript one tap away. Its ADR numbers 442 and 443 were taken, so they are **ADR-463 and ADR-464** here. Two Swift conflicts resolved (both sides kept), and two fixes it needed to compile against today's default branch (a call signature, a line with two declarations).

Checked on this branch:
- `scripts/ci.sh --core-only` on Linux with Swift 6.1: every step PASS (DoddyCore tests, app logic type-check, island art and scenes, voice agent specs, string catalogs, platform specs, token server, backend, gateway, messaging and site tests); messaging database tests SKIPPED (no database here).
- Hosted macOS CI (`ios.yml`, workflow_dispatch) on `c8e38d3f`: run 38457949789. **Result pending when this line was written; the line below it says the outcome.**
- Nothing on this branch has been run on a device. The voice wave and the island faces were never compiled by their authors; CI is their first compile.

Build it: `make project`, open `Doddy.xcodeproj`, scheme `Doddy`, then `docs/implementation/RUN_ON_YOUR_IPHONE.md`. Merging it into the default branch is the owner's call after a conversation with Doddy on a device.

## Platforms
Each platform has its own project spec, so one platform's code can't break another's build. See `docs/platforms/README.md`.

| Platform | Code | Spec → project, scheme | State | Page |
|---|---|---|---|---|
| iPhone and iPad | `DoddyApp/`, `Shared/`, `DoddyWidgets/`, `DoddyShare/` | `project.yml` → `Doddy`; `project-iphone.yml` (no Watch app) → `Doddy` | Built and used by the owner on device. The voice agent was seen working on 2026-10-11. | `docs/platforms/iphone.md` |
| Apple Watch | `DoddyWatch/`, `DoddyWatchWidgets/` | `project.yml` → `DoddyWatch` (embedded in the iPhone app) | Compiles in hosted CI since #69; never run | `docs/platforms/watch.md` |
| Mac | `DoddyMac/`, `DoddyMacWidgets/` | `project-mac.yml` → `DoddyMac` | Prototype on PR #61; never compiled | `docs/platforms/mac.md` |
| Shared core | `Packages/DoddyCore/` | Swift package, used by every platform | Tests run on Linux, 934 passing | `docs/platforms/README.md` |

## Not merged yet: what each branch would change
Merge one at a time, then rebuild and talk to Doddy before the next.

| Branch / PR | What it changes | Risk to voice |
|---|---|---|
| `claude/admiring-curie-bsuwv9-all` (PR #67) | **Nothing for the app any more:** all eight first-use PRs are on the default branch (#43, #46, #51 through #76; #53, #56, #57, #58 on 13 Oct). `git merge-tree` against the default branch changes no app file; only `DECISIONS.md` and the Mac checklist conflict. Close it, and #48 (its base branch is merged). | None |
| `claude/trusting-dirac-o8ajzc` | Voice screen shows Doddy with a sound wave; the transcript is one tap away; the wave follows loudness | **On the integration branch** (ADR-463, 464). Medium: adds audio level meters to the live session |
| `claude/affectionate-mayer-aovol9` | Island compact view draws a pre-cut round face | **On the integration branch.** Low |
| PR #78 `claude/youthful-pasteur-25tuhv` | "Big brain. Small body." share card in Settings and on the site | **On the integration branch** (ADR-462). None |
| PR #63 `claude/zealous-lamport-hxt7lw-xcode` (draft, "NOT COMPILED") | Alarm and second-start test seams in the voice controller and its tests | Not taken: conflicts with today's `VoiceSessionController` and tests, never compiled. Medium |
| PR #71 `claude/zealous-hopper-5ctdsc`, PR #77 (Vercel analytics, draft) | Site and waitlist only; no app code | None |
| `claude/dismiss-ended-card` | Nothing: its changes were reverted | None |
| PR #44 `claude/peaceful-hopper-v3gx75` | Action status, session recovery, Stop listening, unfinished notes, "Listen until I finish" | **Merged** in #79 (13 Oct) |
| PR #61 `claude/fervent-hamilton-cv19sj` | iPad sidebar and fixes, Watch "New note" and Smart Stack, Mac menu bar app, widget and window, per-platform projects | **Merged** in #79 (13 Oct) |
| Older `claude/*` branches with no PR (`hopeful-fermat-1a63x0`: a native Mac app, the route ADR-433 did not take; `fervent-hamilton-ot5z1f`: payment decisions; `magical-newton-ip0bx2`: voice-agent wording; `blissful-davinci-3y2nfo`, `wizardly-planck-xmn06p`: superseded by #67's PRs and #65) | Not audited line by line here; each conflicts with the default branch | Unknown |

## Known problems
- **Voice sessions sometimes start twice.** ElevenLabs logs from 2026-10-09 to 10-11 show:
  - two sessions starting in the same second;
  - a "ghost" session that connects but never sends its start data and stays silent for 30 s;
  - a session that can't hear the user.

  Not fixed yet. It needs a device log to confirm the cause.
- **Vercel deployments are blocked** (account billing and the daily deployment limit), so the Vercel checks on PRs are red whatever the change. The voice pass server and the Ask Doddy gateway run on Render since 13 Oct (addresses in `docs/implementation/RUN_ON_YOUR_IPHONE.md`). GitHub Actions runs again since 2026-10-12.

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
