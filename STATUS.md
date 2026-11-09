# Doddy: current status (read this first)

Doddy is a voice-first companion for iPhone and iPad. The Apple Watch app and the Mac menu bar prototype are **paused** (ADR-572). This page says what is true now, in one page. **Replace facts when they change; don't add dated log paragraphs.** What a pull request changed goes in `changes/` (see `changes/README.md`); the full log up to 7 Nov 2026 is in `docs/archive/STATUS-log-2026-10-08-to-2026-11-07.md`.

Last checked: **7 Nov 2026, 20:30 UTC** (the ElevenLabs row: 9 Nov 2026, 10:30 UTC) (GitHub; Render last read 19:30 UTC through its API). Repository facts re-checked against the code (docs review, decision `docs/decisions/2026-11-07-plain-readme.md`, re-checked on 8 Nov after the merge of `main`); live services not re-read.

## Code
- **Default branch:** `main` (renamed from `claude/loving-dirac-uuxoux` on 7 Nov 2026). It is the only permanent branch; every change arrives by pull request (`AGENTS.md`, last section).
- **CI:** `.github/workflows/ios.yml`. Pushes to `main` run every job (ADR-765, ADR-811); pull requests run path-selected jobs and the UI smoke classes.
- **Open pull requests:** [GitHub list](https://github.com/Bienos/doddy.2/pulls). On 7 Nov every open pull request but one was merged into `main` (owner: "make sure all branches are merged"; `changes/merge-all-open-prs-2026-11-07.md`). Still open: #172 (the Mac UI tests split over four jobs), held because it conflicts with the CI design #209 and #211 chose the same day. Merged but **off until the owner turns them on:** #196 (Doddy's own phone number), #193 (Studio research jobs), #192 (USDC pay-for-pages).
- **Decisions:** ADR-001 to ADR-828 in `DECISIONS.md` (look them up by number, never read the file whole); new ones in `docs/decisions/`.

## On a phone
- **Last build recorded as working on a device:** `ce02763` (PR #60, 11 Oct). Newer builds have been run since, but none is recorded by commit. Nothing merged since 20 Oct has a recorded device check. To try everything merged on 7 Nov, build `main` (`make project`, scheme `Doddy`) and record the commit here.
- **TestFlight:** Xcode Cloud is the one path (ADR-697), into the App Store Connect record for `com.bienos.doddy2.dev`, which is **Doddy Beta** (ADR-812). It hasn't produced a build yet: its first runs failed on package resolution and on a quoted project value. The fix for both, #200, was merged on 7 Nov; the next Xcode Cloud run will show whether it works.

## Live services
| Service | Runs | Notes |
|---|---|---|
| `doddy` (Render, https://doddy-yaci.onrender.com): phone backend and Doddy Web | `360c99f` (4 Nov), deployed 5 Nov 05:49 UTC | Branch `main`, auto-deploy off. **Behind `main`:** #186 (Google and Apple sign-in on the web), #184 (generic app tools) and #192 (payments, off) changed `backend/` and `web/` on 7 Nov; not deployed. Free plan: sleeps after about 15 minutes. |
| `doddy`'s database (Supabase) | Free plan | Pauses after 7 days without use (engineering audit, 7 Nov). Its password is to be rotated (owner queue 6). |
| `doddy-messaging` (Render): Messages, errands, leaflets, texts and calls, push | `174ba21` (#198), deployed 7 Nov 13:58 UTC (owner queue 19) | Branch `main`, auto-deploy off. **Behind `main`:** Studio (#193), the phone number (#196, off), phone-agent conversation deletion and the other #169 parts changed `server/messaging/` on 7 Nov; not deployed. The next deploy applies migrations 017 to 020 (two files start 017; they run in name order). Free plan, with the worker inside the web process. |
| `doddy-messaging-db` (Render Postgres) | Free plan | **Expires 10 Nov 2026, 10:11 UTC**, read 7 Nov 19:30 UTC. Not upgraded. Everything the messaging server keeps is in it (owner queue 1). |
| Vercel `doddy-voice-token`, `doddy` (www.doddy.lol), `doddy-gateway` | Production builds of the default branch | After the rename, the Production Branch setting must say `main` (owner queue 20). Pull requests' Vercel statuses say "Account is blocked." The gateway is unused by the app (ADR-587). |
| ElevenLabs agent (main) | One agent for Debug, TestFlight and future App Store builds | **Working: nine conversations connected on 9 Nov 2026** (log read 9 Nov; before that every start failed at 0 seconds from 2 Nov to 7 Nov 22:28 UTC). Authentication **on**, 1,000 a day (owner queue 4). `draft_invoice` (#161) and `lost_wallet` (#176) are live on it and now on `main` too. The tools of #193, #196 and #192 (`make_something`, `text_me`, `call_me_later`, `pay_for_page`) are in `voice-agent/` but not on the live agent; the agent is changed only on the owner's instruction. |
| Old Render copies `doddy-gateway`, `doddy-voice-token` | Old branch, free plan | Not used. Delete them. |

## Platforms
| Platform | Code | Project | State | Page |
|---|---|---|---|---|
| iPhone and iPad | `DoddyApp/`, `Shared/`, `DoddyWidgets/`, `DoddyShare/`, `DoddyNotificationContent/` | `project.yml`; `project-iphone.yml` (free team, no entitlements) | Built and tested by the hosted Mac job on every push to `main` (all UI tests) and on pull requests that can reach the app (smoke UI tests) | `docs/platforms/iphone.md` |
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
