# Doddy: current status (read this first)

Doddy is a voice-first companion for iPhone and iPad. The Apple Watch app and the Mac menu bar prototype are **paused** (ADR-572). This page says what is true now, in one page. **Replace facts when they change; don't add dated log paragraphs.** What a pull request changed goes in `changes/` (see `changes/README.md`); the full log up to 7 Nov 2026 is in `docs/archive/STATUS-log-2026-10-08-to-2026-11-07.md`.

Last checked: **7 Nov 2026, 19:30 UTC** (GitHub, and Render read-only through its API). Repository facts re-checked against the code the same evening (docs review, decision `docs/decisions/2026-11-07-plain-readme.md`); live services not re-read.

## Code
- **Default branch:** `main` (renamed from `claude/loving-dirac-uuxoux` on 7 Nov 2026). It is the only permanent branch; every change arrives by pull request (`AGENTS.md`, last section).
- **CI:** `.github/workflows/ios.yml`. Pushes to `main` run every job (ADR-765, ADR-811); pull requests run path-selected jobs and the UI smoke classes.
- **Open pull requests:** [GitHub list](https://github.com/Bienos/doddy.2/pulls). Long-running drafts that are off by default and for review only: #196 (Doddy's own phone number), #193 (Studio research jobs), #192 (USDC pay-for-pages).
- **Decisions:** ADR-001 to ADR-812 in `DECISIONS.md` (look them up by number, never read the file whole); new ones in `docs/decisions/`.

## On a phone
- **Last build recorded as working on a device:** `ce02763` (PR #60, 11 Oct). Newer builds have been run since, but none is recorded by commit. Nothing merged since 20 Oct has a recorded device check.
- **TestFlight:** Xcode Cloud is the one path (ADR-697), into the App Store Connect record for `com.bienos.doddy2.dev`, which is **Doddy Beta** (ADR-812). It hasn't produced a build yet: its first runs failed on package resolution and on a quoted project value. The fix for both, #200, was merged on 7 Nov; the next Xcode Cloud run will show whether it works.

## Live services
| Service | Runs | Notes |
|---|---|---|
| `doddy` (Render, https://doddy-yaci.onrender.com): phone backend and Doddy Web | `360c99f` (4 Nov), deployed 5 Nov 05:49 UTC | Branch `main`, auto-deploy off. Since then `main` changed only Logbook's tool list (#195: `backend/src/web/logbook.ts` and two `web/` files, adding `follow_news` and `control_home`); it matters once the iPhone sends Logbook days. Free plan: sleeps after about 15 minutes. |
| `doddy`'s database (Supabase) | Free plan | Pauses after 7 days without use (engineering audit, 7 Nov). Its password is to be rotated (owner queue 6). |
| `doddy-messaging` (Render): Messages, errands, leaflets, texts and calls, push | `174ba21` (#198), deployed 7 Nov 13:58 UTC (owner queue 19) | Branch `main`, auto-deploy off. Free plan, with the worker inside the web process. |
| `doddy-messaging-db` (Render Postgres) | Free plan | **Expires 10 Nov 2026, 10:11 UTC**, read 7 Nov 19:30 UTC. Not upgraded. Everything the messaging server keeps is in it (owner queue 1). |
| Vercel `doddy-voice-token`, `doddy` (www.doddy.lol), `doddy-gateway` | Production builds of the default branch | After the rename, the Production Branch setting must say `main` (owner queue 20). Pull requests' Vercel statuses say "Account is blocked." The gateway is unused by the app (ADR-586, ADR-587) and has no variables, so it answers 503. |
| ElevenLabs agent (main) | One agent for Debug, TestFlight and future App Store builds | Authentication off (owner queue 4). 103 tools when last read (1 Nov): the 102 in `voice-agent/tools.json` plus `draft_invoice` from unmerged work. `tools.json` still lacks the live ids of `hand_over_errand` and `check_errands`. The phone and task-call agents aren't created yet. |
| Old Render copies `doddy-gateway`, `doddy-voice-token` | Old branch, free plan | Not used. Delete them. |

## Platforms
| Platform | Code | Project | State | Page |
|---|---|---|---|---|
| iPhone and iPad | `DoddyApp/`, `Shared/`, `DoddyWidgets/`, `DoddyShare/` | `project.yml`; `project-iphone.yml` (free team, no entitlements) | Built and tested by the hosted Mac job on every push to `main` (all UI tests) and on pull requests that can reach the app (smoke UI tests) | `docs/platforms/iphone.md` |
| Web | `web/`, `backend/src/web/` | Vite, served by `doddy` | Live | `docs/platforms/web.md` |
| Shared core | `Packages/DoddyCore/` | Swift package | Tests on Linux and macOS in CI | `docs/platforms/README.md` |
| Apple Watch | `DoddyWatch/`, `DoddyWatchWidgets/` | `project-watch.yml` | **Paused** (ADR-572) | `docs/platforms/watch.md` |
| Mac | `DoddyMac/`, `DoddyMacWidgets/` | `project-mac.yml` | **Paused**, never compiled | `docs/platforms/mac.md` |

## Known problems
- **The messaging database is deleted on 10 Nov at 10:11 UTC unless it is upgraded** (owner queue 1).
- **No dollar spend limits** on Anthropic, OpenAI or Monid. The main ElevenLabs agent has authentication off, and its ID is public (owner queue 2, 4, 12, 13).
- **No staging environment:** Debug, TestFlight and production builds all use the production servers and voice agent. The plan is Doddy Beta on staging (ADR-812).
- **The hosted Mac's simulator sometimes freezes** during the native island UI test. That test runs alone and last, under a watchdog (ADR-764).
- **Silent voice sessions** were seen in October (`docs/implementation/VOICE_SESSION_STARTS.md`). Confirming the cause still needs a device log.
- **Engineering audit, 7 Nov 2026:** CI gaps, branch backlog, migration safety, privacy manifest, confirmed app bugs. The plan and checklist are in `docs/engineering/AUDIT_2026-11-07.md`; tick items there as pull requests land.

## Waiting on the owner
`docs/OWNER_QUEUE.md`: one list, soonest deadline first.

## How to update this page
Change the facts above, keeping them to what's true now, with the date at the top. Fold the notes in `changes/` into it and delete them in the same pull request. Never paste a log entry here.
