# Doddy: current status (read this first)

Doddy is a voice-first memory companion for iPhone, with an Apple Watch app and a Mac menu bar prototype. This page is the short version. Update it when you merge something that changes what is below.

Last updated 2026-10-18 (read-only checks for the v1 scope proposal, ADR-500). Before that: 2026-10-14, PR #80, the ten languages.

**Right now (18 Oct), main is broken in three ways.** Fix these before anything else (`docs/implementation/GO_LIVE_CHECKLIST.md`, stage A):
1. **Voice can't connect.** The app hard-codes `https://doddy-voice-token.vercel.app` (`VoiceConfig.swift:4`), which answers 402 DEPLOYMENT_DISABLED. `754e5d6` removed the public-agent fallback. The server that runs `754e5d6` is `doddy-voice-token-beta.vercel.app`, and it doesn't yet have the sign-in settings it needs.
2. **Hosted CI is billing-blocked again** since 16 Oct, so `f40861c` and `754e5d6` have never compiled. The last green run is `44f6934`, 14 Oct.
3. **`scripts/check_forbidden_capabilities.sh` fails** on `754e5d6`. The fix is PR #84.

**The v1 scope is a proposal waiting on the owner:** `docs/product/V1_SCOPE.md`. Until it's marked up, merge fixes only.

## Known-good build
- **Main branch:** `claude/loving-dirac-uuxoux`.
- **Last build seen working on a device:** head `ce02763` (PR #60, the learning loop).
- **Hosted CI:** since `c8aff7ae` (#69 with #70), every target compiles on Xcode 26.6 and the unit and 26 UI tests pass on the simulator. That build has not been run on a device.
- **Since then on main:** OpenAI Realtime is the default voice, with a model picker on Home (ADR-442), and the first-use screens landed (#76: ADR-324 to 327, ADR-443).
- **Also on main (PR #80, 14 Oct):** the iPhone app and the landing page in ten languages, as machine-translated drafts (ADR-458 to 460). The landing page is live at https://www.doddy.lol in all ten. CI built the app and passed the unit and UI tests with these changes; the language picker and the translated screens have not been seen on a device, and no native speaker has read any of it (`l10n/REVIEW_NOTES.md`).
- **Evidence:**
  - The live voice agent worked from this code on 2026-10-11 at 22:35 Warsaw time: a 139 s conversation that used `search_memories`, `save_memory` and `web_search`.
  - The variables the app sent to ElevenLabs match this branch, and not the unmerged `-all` branch.
- **To get back to a build that works,** build this branch: `make project`, open `Doddy.xcodeproj`, scheme `Doddy`.
- **Voice agent:** ElevenLabs agent `agent_0501m4et27vyeawrwqfdxxfszfa6`. Its spec is `voice-agent/`.
  - Live version at the last working call (11 Oct): `agtvrsn_5201m4p132brf30th15nggeqarf0`.
  - Live version on 18 Oct: `agtvrsn_0201m57cm3vnfgsrv3fw49mqb9mk`.
  - Settings on 18 Oct: authentication off, 10 calls a day for the whole agent, concurrency 2, recordings kept with no time limit.
  - The ElevenLabs logs show device calls on 14–16 Oct from a build newer than `ce02763`; which commit isn't recorded.

## Platforms
Each platform has its own project spec, so one platform's code can't break another's build. See `docs/platforms/README.md`.

| Platform | Code | Spec → project, scheme | State | Page |
|---|---|---|---|---|
| iPhone and iPad | `DoddyApp/`, `Shared/`, `DoddyWidgets/`, `DoddyShare/` | `project.yml` → `Doddy`; `project-iphone.yml` (no Watch app) → `Doddy` | Built and used by the owner on device. The voice agent was seen working on 2026-10-11. | `docs/platforms/iphone.md` |
| Apple Watch | `DoddyWatch/`, `DoddyWatchWidgets/` | `project.yml` → `DoddyWatch` (embedded in the iPhone app) | Compiles in hosted CI since #69; never run | `docs/platforms/watch.md` |
| Mac | `DoddyMac/`, `DoddyMacWidgets/` | `project-mac.yml` → `DoddyMac` | Prototype, on main since PR #61 (13 Oct); never compiled, and not in CI | `docs/platforms/mac.md` |
| Shared core | `Packages/DoddyCore/` | Swift package, used by every platform | Tests run on Linux, 934 passing | `docs/platforms/README.md` |

## Not merged yet: what each branch would change
Merge one at a time, then rebuild and talk to Doddy before the next.

| Branch / PR | What it changes | Risk to voice |
|---|---|---|
| PR #84 `claude/laughing-darwin-hqxa63` | Fixes the capability guard `754e5d6` broke (ADR-494); one conversation at a time (ADR-496); voice start logging; 1Password secrets; `render.yaml` secrets | Medium: changes how a conversation starts. **Merge first**, once CI runs |
| PR #85 `claude/dreamy-cannon-gc33dj` | BLIK transfers by voice (claims ADR-483) | Hold until the v1 scope is marked up |
| PR #86 `claude/connect-in-conversation` (draft) | Connect an online account from the conversation (claims ADR-483 too) | Hold until the v1 scope is marked up |
| `claude/admiring-curie-bsuwv9-all` (PR #67, closed without merging) | 43 commits not on main. Its parts landed separately on 13 Oct: #76, then #53, #56, #57 and #58 | Check what's left before reusing it |
| `claude/trusting-dirac-o8ajzc` | Voice screen shows Doddy with a sound wave; the transcript is one tap away; the wave follows loudness | Medium: adds audio level meters to the live session |
| `claude/affectionate-mayer-aovol9` | Island compact view draws a pre-cut round face | Low |
| `claude/dismiss-ended-card` | Nothing: its changes were reverted | None |

PR #44 (action status, session recovery, Stop listening, unfinished notes) and PR #61 (iPad, Watch, Mac, per-platform projects) are **on main** since 13 Oct, through PR #79. They were compiled in CI and have never run on a device.

## Known problems
- **Voice sessions sometimes start twice.** ElevenLabs logs from 2026-10-09 to 10-11 show:
  - two sessions starting in the same second;
  - a "ghost" session that connects but never sends its start data and stays silent for 30 s;
  - a session that can't hear the user.

  Not fixed yet. Silent sessions still happened on 16 Oct (four between 04:42 and 04:47). PR #84 adds one conversation at a time and start logging. Finding the cause needs a device log.
- **Vercel:** the `doddy` project (team `doddyyyy`) built and published the site from the default branch on 2026-10-14 (www.doddy.lol); the earlier "account blocked" failures did not recur on that build. The daily deployment limit still applies, so `site/vercel.json` builds only when something under `site/` changed. The old team `bienos` is disabled: `doddy-voice-token.vercel.app` and `doddy-gateway.vercel.app` answer 402. GitHub Actions ran from 12 to 14 Oct and has been billing-blocked again since 16 Oct.

## Waiting on the owner
- Mark up `docs/product/V1_SCOPE.md`: Ship, Hide or Cut for each feature, plus the eight decisions at its end.
- Stage A of `docs/implementation/GO_LIVE_CHECKLIST.md`: GitHub billing; which host runs the voice token server and its sign-in settings; Sign in with Apple on the App ID (needs a paid team).
- A native review of the eight new app languages and of all nine landing-page translations, which are live as drafts (`l10n/REVIEW_NOTES.md`).
- "Hey Doddy" cannot work until the keyword file and a Picovoice key are in place (`docs/implementation/HEY_DODDY_STATUS.md`, "What is missing").
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
