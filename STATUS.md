# Doddy: current status (read this first)

Doddy is a voice-first memory companion for iPhone, with an Apple Watch app and a Mac menu bar prototype. This page is the short version. Update it when you merge something that changes what is below.

Last updated 2026-10-18 (stage A, ADR-520 to ADR-524). Before that: 2026-10-14, PR #80, the ten languages.

**On 18 Oct, main was broken in three ways** (`docs/implementation/GO_LIVE_CHECKLIST.md`, stage A). Branch `claude/fervent-edison-3gnqpq` carries the code fixes for two of them; the rest needs the owner:
1. **Voice couldn't connect.** The app hard-coded `https://doddy-voice-token.vercel.app`, which answers 402 DEPLOYMENT_DISABLED, and `754e5d6` removed the public-agent fallback. The fix points the app at `doddy-voice-token-beta.vercel.app` (ADR-521). That server still needs its sign-in settings before anyone can talk (checklist A4).
2. **Hosted CI was billing-blocked** from 16 Oct, so `f40861c` and `754e5d6` never compiled in CI. It ran again on 18 Oct at 15:08 UTC (run 39139146509, this branch): the app build failed on a missing `import DoddyCore` in `754e5d6`'s `VoiceAccessGate.swift`, and one DoddyCore test failed only on macOS. PR #84's `c819c24b` fixes both and is merged here. The last green macOS run is still `44f6934`, 14 Oct.
3. **`scripts/check_forbidden_capabilities.sh` failed** on `754e5d6`. The fix is PR #84, which this branch merges.

The same branch also fixes two go-live risks: note reminders and birthdays now share iOS's limit of 64 pending notifications instead of being dropped quietly (ADR-523, checklist B6), and deleting the voice account revokes Sign in with Apple once the owner adds a Sign in with Apple key to the server (ADR-524, checklist C8). Both are tested on Linux only.

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
  - Live version after the ASK-01 sync (18 Oct, `43a94083`): `agtvrsn_6401m57e22qwepwtr1ywwe64x2k4`, 85 tools.
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
| PR #84 `claude/laughing-darwin-hqxa63` | Fixes the capability guard `754e5d6` broke (ADR-494); one conversation at a time (ADR-496); voice start logging; 1Password secrets; `render.yaml` secrets. Also merged into `claude/fervent-edison-3gnqpq` with the voice address fix (ADR-521) | Medium: changes how a conversation starts. **Merge first**, once CI runs |
| PR #85 `claude/dreamy-cannon-gc33dj` | BLIK transfers by voice (renumbered to ADR-510 on 18 Oct) | Hold until the v1 scope is marked up |
| PR #86 `claude/connect-in-conversation` (draft) | Connect an online account from the conversation (claims ADR-483 too: renumber) | Hold until the v1 scope is marked up |
| `claude/admiring-curie-bsuwv9-all` (PR #67, closed without merging) | 43 commits not on main. Its parts landed separately on 13 Oct: #76, then #53, #56, #57 and #58 | Check what's left before reusing it |
| `claude/trusting-dirac-o8ajzc` | Voice screen shows Doddy with a sound wave; the transcript is one tap away; the wave follows loudness | Medium: adds audio level meters to the live session |
| `claude/affectionate-mayer-aovol9` | Island compact view draws a pre-cut round face | Low |
| `claude/dismiss-ended-card` | Nothing: its changes were reverted | None |

PR #44 (action status, session recovery, Stop listening, unfinished notes) and PR #61 (iPad, Watch, Mac, per-platform projects) are **on main** since 13 Oct, through PR #79. They were compiled in CI and have never run on a device.

PR #87 (`claude/trusting-sagan-7lky84`) is **on main** since 18 Oct, merged at the owner's request: ASK-01, every tool asks first (server gate, app ask cards, agent spec), and Gmail, Google Calendar, Outlook, Todoist, Notion, Drive and Monid tools behind cards (ADR-483 to 489). Hosted CI couldn't run, so its app code has never been built; the live agent sync is recorded in `43a94083`. Runbook: `docs/integrations/LIVE_GMAIL_TEST_RUNBOOK.md`. Risk to voice: high, because every tool call now waits for an answer.

## Known problems
- **Voice sessions sometimes start twice.** ElevenLabs logs from 2026-10-09 to 10-11 show:
  - two sessions starting in the same second;
  - a "ghost" session that connects but never sends its start data and stays silent for 30 s;
  - a session that can't hear the user.

  Investigated 18 Oct (`docs/implementation/VOICE_SESSION_STARTS.md`, ElevenLabs list only, no transcripts):
  - Two starts at once mostly predate the 11 Oct "review H1" fix.
  - Silent 30-second sessions with zero messages still happen: six since that build, four of them within five minutes on 16 Oct at night.
  - Leading suspect: a "Hey Doddy" start from the background that stalls before its start data and stops when iOS's roughly 30-second background allowance runs out.
  - PR #84 adds one conversation at a time (ADR-496) and the log lines a phone log needs. Not fixed yet: it still needs a device log to confirm the cause.
- **Vercel:** the `doddy` project (team `doddyyyy`) built and published the site from the default branch on 2026-10-14 (www.doddy.lol); the earlier "account blocked" failures did not recur on that build. The free plan allows 100 deployments a day, and skipped ones count: on 18 October the limit was reached by 12:22 UTC (100 deployments since 09:34, 86 of them skipped), so Vercel refused new ones and showed "Account is blocked". Since 18 October only the production branch deploys: preview deployments are off in all three projects' settings (go-live checklist A10), and each `vercel.json` says the same (ADR-498, PR #84, carried by `claude/fervent-edison-3gnqpq`). GitHub Actions stopped starting jobs on 16 October and ran again on 18 October at 15:08 UTC (run 39139146509).

## Waiting on the owner
- Mark up `docs/product/V1_SCOPE.md`: Ship, Hide or Cut for each feature, plus the eight decisions at its end.
- Stage A of `docs/implementation/GO_LIVE_CHECKLIST.md`:
  - the voice token server's sign-in settings on Vercel (Upstash Redis, signing key, `APPLE_BUNDLE_ID`), then a redeploy;
  - Sign in with Apple on the App ID (needs a paid team);
  - then build on a Mac and talk to Doddy on the phone.
- GitHub Actions cost: 12–14 October used about $250, almost all of it the macOS build. ADR-497 (PR #84) makes that build wait for the Linux checks and skip pull requests that don't touch the app.
- 1Password for project secrets (ADR-493, `docs/security/SECRETS_1PASSWORD.md`).
  - Create the four vaults and items, then run the sync tool one host at a time.
  - Built and tested on Linux against fakes only; it hasn't touched the real 1Password, Vercel or Render.
- Delete the two old Supabase functions and their secrets (code saved in `docs/archive/supabase-functions-2026-10-18/`).
  - Decide whether to keep the Render copies of `doddy-voice-token` and `doddy-gateway` (research report, decision 11).
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
