# Doddy: current status (read this first)

Doddy is a voice-first memory companion for iPhone, with an Apple Watch app and a Mac menu bar prototype. This page is the short version. Update it when you merge something that changes what is below.

Last updated 2026-10-20, 23:35 UTC (the Xcode warning fixes, below the 20 Oct table). Before that, 21:45 UTC (the day's merges: #106, #113, #108, #111, #110, #112 and #114; his eyes on the new Home). Before that, 2026-10-19 (the owner's merge session: #84, #88, #90 and the #97 fix). Before that, 18 Oct: stage A (ADR-520 to ADR-524) and PR #85, BLIK transfers (ADR-510).

**Merged to main on 20 Oct** (UTC, all as merge commits). Five of them (#108, #111, #110, #112, #114) merged while their Mac build was still running (or not yet started), so **main at `5633b8f4` has not had a full Mac build and UI-test pass as one commit.** Run states below were read at 22:06 UTC. The Mac jobs of #108, #111, #110 and #112 finished green, so main's tree at `01d3329c` (everything before #114) is built and passed its unit and UI tests. #114's Mac job built the app, but its first 12 UI tests failed at launch (see its row). **Main's tree at `f919216e` (all of the day's merges, the iPhone project commits and the ADR-561 CI fix) passed everything** in run 39508561204, started by hand on `claude/wizardly-ritchie-53ncqv` at `a7babeae`, the same tree: build, 48 app unit tests, the simulator restart, and 52 UI tests (1 skipped, 0 failures) (read 23:51 UTC). The Xcode warning fixes merged after it (`2610656`, below) were not in that run. Before building main for a phone, read the runs below again. Three direct commits to main at 20:56 UTC (`8ece39ba`, `fb7b6d67`, `b9f5ad86`: the iPhone project drops its entitlements so a Personal Apple team can sign it, turns off generated string symbols, and a comment names #108's Debug voice switch) come after #112 and before #114; no hosted run was started for them on their own.

| When | PR | Merge commit | CI on the head |
|---|---|---|---|
| 06:05 | #106: the calm "I'm here" Home (ADR-545) | `f3bd10d6` | [run 39435586291](https://github.com/Bienos/doddy.2/actions/runs/39435586291) on this commit: green |
| 19:49 | #113: calls by Doddy may run until 23:00 Warsaw time (ADR-553) | `4d410c67` | [run 39485067152](https://github.com/Bienos/doddy.2/actions/runs/39485067152): `core` green; Mac job green at 20:34, after the merge |
| 20:36 | #108: ElevenLabs default again, smaller app and repo, faster start-up, "What I can do" back, Hey Doddy and the Picovoice package removed, Debug voice without Apple sign-in (ADR-546 to 551) | `a74e6e17` | [run 39490022263](https://github.com/Bienos/doddy.2/actions/runs/39490022263): `core` green; **Mac job green at 21:08 UTC, and the whole run succeeded** (finished 21:09). That head, `11620dca`, has #113 but not #111, #110 or #112 |
| 20:37 | #111: motion v2, one persistent Doddy that hops, rides and behaves, on the calm Home (ADR-552, 554, 555) | `05482c90` | [run 39463830375](https://github.com/Bienos/doddy.2/actions/runs/39463830375) on its head `30f9f04`: `core` and Mac job green (50 UI tests; 10 had failed on the first run and were fixed). It merged after another session brought #108 in (`c8b5562a`); that head's [run 39493532952](https://github.com/Bienos/doddy.2/actions/runs/39493532952): `core` green at 20:45; **Mac job green at 21:38 UTC, and the whole run succeeded** |
| 20:39 | #110: Brand Guidelines V2.2, the wave-frame app icon, orange `#FF6A00`, how Doddy speaks (ADR-556, 557) | `40af3dba` | [run 39493858270](https://github.com/Bienos/doddy.2/actions/runs/39493858270): `core` green at 20:47; **Mac job green at 21:39 UTC**: `xcodebuild test` passed (51 UI tests, 1 skipped, 0 failures) and `scripts/ci.sh` ended with RESULT: PASS. A trial merge of its head onto the main of the time (`05482c90`, #111) has the same tree as main at `40af3dba` (checked with git). The Swift in it was edited without a compiler; this run is the compile |
| 20:51 | #112: ways to open Doddy, a one-screen Back Tap, the "Open Doddy faster" card returning once after "Later", a weekly reminder (ADR-558, 559) | `01d3329c` | [run 39495477296](https://github.com/Bienos/doddy.2/actions/runs/39495477296): merged within seconds of the run starting, before `core` or the Mac job had finished. Merged on top of #108, #110 and #111. `core` green at 20:59; **Mac job green at 21:49 UTC, and the whole run succeeded.** Its head `c8bbd76e` has the same tree as main at `01d3329c` (checked with git) |
| 21:14 | #114: his eyes on the persistent Doddy (gaze, blink, squint), and a finger anywhere on Home moves them (ADR-560) | `5633b8f4` | head `c5feebbd`: [run 39496321722](https://github.com/Bienos/doddy.2/actions/runs/39496321722): `core` green at 21:05; Mac job **failed** at 21:55 UTC. The app built; 12 of 52 UI tests failed and 39 passed (1 skipped). The 12 are the run's first UI tests (21:24 to 21:26, all of `DoddyArtTests` and the first seven of `LaunchSmokeTests`), and each failed while XCTest launched the app, with "Failed to get background assertion for target app … Timed out while acquiring background assertion". Every later test passed, including launches onto Home and all the motion tests, and the same 12 passed in #112's run. This reads as the simulator failing at the start, not #114's code; a re-run (on main) would confirm it. Merged while the Mac job ran. A trial merge of `b9f5ad86` and `c5feebbd` has the same tree as main at `5633b8f4` (checked with git); the run's own merge ref is gone since the merge, so I could not confirm it built that tree |
| 22:32 | The CI fix: the Mac job runs the UI tests on a freshly restarted simulator (ADR-561), merged at the owner's request ("Merge now and ok") before its run finished | `f919216e` | [run 39508561204](https://github.com/Bienos/doddy.2/actions/runs/39508561204) on `a7babeae` (same tree): `core` green; **Mac job green at 23:41 UTC**: build-for-testing, 48 unit tests, the restart (34 s), 52 UI tests (1 skipped, 0 failures). The first UI launch still took 15 s; none timed out |

None of these has been seen on a device. The live ElevenLabs agent was updated for #110 before it merged (ADR-556, `voice-agent/README.md`).

**Also merged on 20 Oct, 23:35 UTC: the Xcode warning fixes** (`claude/fix-xcode-warnings`, merged straight into main at the owner's request, no PR). The iPhone build's 7 warnings are fixed: an unused result in `IntroductionView`, `isReading` read from `PhotosPicker`'s label in `PhotoViews` (2), the non-Sendable CoreSpotlight captures in `SpotlightSync` (3), and Xcode's "Update to recommended settings" (`project.yml` sets `options.xcodeVersion: "26.6"`; XcodeGen's default had marked the project as Xcode 16). Don't accept that offer if a newer Xcode shows it again: it changes only the generated project and can turn on the string symbols `project-iphone.yml` turns off. The owner built `DoddyiPhone.xcodeproj` from the branch on their Mac with 0 warnings. No hosted run: the workflow starts only for pull requests or by hand.

**The fixes #108, #111, #110 and #112 needed together** (found on the test build `claude/wizardly-cannon-k0u1mv`, notes in its `docs/implementation/TEST_BUILD_2026-10-20.md`), each a commit on the PR that merged second:
- **#111:** motion v2's listening pose no longer reads `WakeWordListener`, which #108 deleted; the "What I can do" sheet hides the persistent Doddy like Home's other sheets.
- **#110:** its greeting changes moved into `WakeGreeting.swift` (no "bud"; "Hi, I'm Doddy. What's on your mind?" the first time, then "I'm here. What's up?"). The microphone prompt is #108's text after #110's first sentence, in all ten languages; Settings' privacy text is #108's with "Doddy" casing.
- **#112:** `PreferenceKey.connectedConversations` and the voice controller's counter stay. #108 had removed them with the Hey Doddy card, but #112's card return and reminder read them, so main would not have compiled.
- **ADR numbers:** #108 keeps 546 to 551. #111's 550 and 551 became 554 and 555; #110's 546 and 547 became 556 and 557; #112's 546 and 547 became 558 and 559.

**Linux checks:** `scripts/ci.sh --core-only` (Swift 6.1.2) passed on main's tree after each of those merges: DoddyCore 1,149 tests after #108, 1,219 after #111 and #110, 1,244 after #112, 0 failures; the messaging server's database tests SKIPPED (no `TEST_DATABASE_URL`).

**Deploys** (Vercel team `doddyyyy`, read about 21:10 UTC): production builds READY for `doddy-voice-token` from `a74e6e17` (#108, `dpl_GKtjwZVy8mMdv2dSKZb1QC8jL5kU`) and the site `doddy` from `a74e6e17` and then `40af3dba` (#110, `dpl_536XKjNR3AZ4kY9xvRun8gHd2WBM`). The other builds from these merges show CANCELED; why wasn't checked (the Ignored Build Step cancels a build whose folder didn't change). Render (the messaging server, #113's hours) was not checked.

**Merged to main on 19 Oct** (UTC, all as merge commits). The merge session merged #84, #88, #97 and #90 only with `core` and `ci` green on the head it merged.

| When | PR | Merge commit | CI on the head |
|---|---|---|---|
| 05:46 | #84: 1Password secrets, Linux checks, one voice conversation at a time, cheaper CI, Vercel deploys production only (ADR-493 to 499) | `fc8a5027` | [run 39151481681](https://github.com/Bienos/doddy.2/actions/runs/39151481681) |
| 06:37 | #88: stage A, the app points at `doddy-voice-token-beta.vercel.app`, v1 scope proposal, go-live checklist, notification limit, Apple revocation (ADR-520 to 524) | `01e7b345` | [run 39206594852](https://github.com/Bienos/doddy.2/actions/runs/39206594852) |
| 07:05 | #95: Connected Apps server on Postgres (ADR-525), merged by the owner | `29facd0c` | `core` was red: `DATABASE_CA_CERT` missing from `secrets/manifest.json` |
| 07:46 | #98: the server accepts Doddy accounts from Supabase Auth (ADR-526), merged by the owner | `72f7d152` | added `SUPABASE_URL` without a manifest entry |
| 08:02 | #99: only Apple and Google sign-ins make a Doddy account, merged by the owner | `37471af6` | |
| 08:13 | #97: lists `DATABASE_CA_CERT` and `SUPABASE_URL` under `notSecrets`, so `core` is green on main again | `71481f4f` | [run 39220013043](https://github.com/Bienos/doddy.2/actions/runs/39220013043) |
| 09:20 | #90: Doddy calls on your behalf, call cases in Polish (ADR-500 to 507) | `8c25e7da` | [run 39222532484](https://github.com/Bienos/doddy.2/actions/runs/39222532484) |

#90's first macOS run on `adedc1f0` hit the job's 75-minute limit: the island test "System Unmute must reach the app handler" failed once, and the next UI test hung relaunching the simulator. Neither touches #90's code. The run on `1d9c74b9` passed everything.

**Voice, 19 Oct:**
- **Server:** the owner added `UPSTASH_REDIS_REST_URL`, `UPSTASH_REDIS_REST_TOKEN` and `DODDY_SESSION_SIGNING_KEY` to Vercel project `doddy-voice-token` (team `doddyyyy`, Production, Sensitive). Production builds:
  - `dpl_9RPq2DvxtBbXELPGGuUYnLbhShUn` from `fc8a5027` (#84);
  - then `dpl_GUs1RGcFhT2nTmiXcvLuc4WVexoe` from `01e7b345` (#88), the current one.

  Both are READY with the alias `doddy-voice-token-beta.vercel.app`, and the Ignored Build Step let both build.
- **Probes without secrets,** on both builds:
  - `POST /api/voice-auth` with a made-up refresh token gives `401 {"error":"session_expired"}`;
  - `POST /api/voice-token` with no `Authorization` gives 401;
  - neither gives 503 `server_not_configured`.

  This shows the URL, the token (for reads) and the signing key are loaded and Upstash answers. It doesn't show the token can write, and it doesn't show a conversation works.
- **The app on main** points at `https://doddy-voice-token-beta.vercel.app/api/voice-token` (ADR-521, #88).
- **Still on the owner's side:**
  - a paid Apple Developer team selected in Xcode;
  - Sign in with Apple on App ID `com.bienos.doddy2.dev`;
  - a new phone build;
  - the first conversation (`MAC_VERIFICATION_CHECKLIST` rows V0a to V0f).
- **Voice works on no device yet.**
- **Debug builds can talk without Apple sign-in (ADR-551):** run from Xcode with a free Apple ID, voice connects straight to the agent (Settings › Voice › Developer switch, on by default in Debug only). Release builds still need a voice account.
- **Default voice (ADR-546) and agent limits (ADR-548):** ElevenLabs is the default for everyone. On 20 Oct the owner chose to raise the live agent's limits (read back from ElevenLabs after saving): **1,000 calls a day and 10 at once** (were 10 and 2), bursting still off. **Authentication on the agent is still off** (read 20 Oct), so anyone with the agent id can start calls on the owner's bill; it was not changed (the owner was told and chose the raise-the-cap option).

**The v1 scope is a proposal waiting on the owner:** `docs/product/V1_SCOPE.md`. Until it's marked up, merge fixes only.

## Known-good build
- **Main branch:** `claude/loving-dirac-uuxoux`.
- **Last build seen working on a device:** head `ce02763` (PR #60, the learning loop).
- **Hosted CI:** since `c8aff7ae` (#69 with #70), every target compiles on Xcode 26.6 and the unit and 26 UI tests pass on the simulator. That build has not been run on a device.
- **Since then on main:** OpenAI Realtime became the default voice with a model picker on Home (ADR-442) and the first-use screens landed (#76: ADR-324 to 327, ADR-443). **On main since 20 Oct (#108, ADR-546 to ADR-551):** ElevenLabs is the default again and OpenAI is a choice in the picker; four unused views and four old image sets are gone, five pack poses ship smaller, and start-up jobs wait for the first screen (`docs/implementation/LAUNCH_PROFILING.md`, never measured; `docs/implementation/REPO_DIET_2026-10-20.md`). "What I can do" is back in Home's ••• menu (ADR-548) and the old design folders are deleted (the design now is the app, `design/dynamic-island-v4` and the site's folders). #108's Mac job was still running when it merged and finished green at 21:08 UTC (table above). **Also on main since 20 Oct (#110, ADR-556 and ADR-557):** Brand Guidelines V2.2 (`design/brand-v2.2/`) is the brand reference, the orange is `#FF6A00`, the app icon is the pack's wave frame, and Doddy's opening lines and voice follow the guide (`docs/design/BRAND_V2_2_REVIEW.md`). The Mac runs for #111 and #110 finished green at 21:38 and 21:39 UTC; those for #112 and #114 had not finished when this was written.
- **Also on main (PR #80, 14 Oct):** the iPhone app and the landing page in ten languages, as machine-translated drafts (ADR-458 to 460). The landing page is live at https://www.doddy.lol in all ten. CI built the app and passed the unit and UI tests with these changes; the language picker and the translated screens have not been seen on a device, and no native speaker has read any of it (`l10n/REVIEW_NOTES.md`).
- **Hosted CI on 18 Oct:** jobs start again after the owner fixed the account's GitHub billing. The first Mac build since 14 Oct showed that no branch had compiled since 754e5d6 (`VoiceAccessGate.swift` used `VoiceProvider` without `import DoddyCore`), and that two app unit tests had never run: the profile intro test from 754e5d6 and the translator test that ASK-01 made stale. PR #85 fixes all three. Its run 39138962699 built the app and passed the 29 UI tests, with only those two tests failing. Actions time is paid for (12–14 Oct used about $250, almost all of it the macOS build); since #84 (on main 19 Oct) the Mac build waits for the Linux checks and skips pull requests that don't touch the app (ADR-497), and the UI tests take 26 minutes instead of 34 (ADR-499). #84's run 39143827911 passed everything (Mac job 40 minutes).
- **Also on main (PR #85, 18 Oct):** BLIK transfers by voice (ADR-510). "Send Ania 50 zł" shows a card to send in the bank app; Doddy never sends money. The `draft_blik_transfer` tool is behind an off-by-default switch and was added to the live ElevenLabs agent on 18 Oct (see "Voice agent" below for today's live version). Compiled in hosted CI; not yet seen on a device. Details: `docs/implementation/BLIK_TRANSFER_STATUS.md`.
- **Evidence:**
  - The live voice agent worked from this code on 2026-10-11 at 22:35 Warsaw time: a 139 s conversation that used `search_memories`, `save_memory` and `web_search`.
  - The variables the app sent to ElevenLabs match this branch, and not the unmerged `-all` branch.
- **To get back to a build that works,** build this branch: `make project`, open `Doddy.xcodeproj`, scheme `Doddy`.
- **On a free (Personal) Apple team,** use `make project-iphone` and open `DoddyiPhone.xcodeproj` instead. It has no entitlements (since 20 Oct), so widgets and "Save to Doddy" say they aren't set up, and a Debug build talks to Doddy without Apple sign-in (ADR-551).
- **Voice agent:** ElevenLabs agent `agent_0501m4et27vyeawrwqfdxxfszfa6`. Its spec is `voice-agent/`.
  - **Live version since 20 Oct 14:08 UTC (ADR-556):** `agtvrsn_8701m5ct8dxsf8htebwpdykppqbv`, saved over `agtvrsn_9601m5cg7h2jf0ctpbggw15zzq4n` (read just before saving; not the 19 Oct version below, and who saved it isn't recorded). Eleven prompt lines and the `opening_line` placeholder changed; the 82 tools did not.
  - **Earlier, read 19 Oct 09:21 UTC:** `agtvrsn_8901m59m3bdqe6takgkfbcmfh2yh`, 82 tools. It was saved at 08:22:55 UTC on 19 Oct over `agtvrsn_0601m57kxxh3eaprt27bk83ta8vx` (87 tools; saved 18 Oct 13:41 UTC from `claude/awesome-cray-2lb9ia`, commit `6672259f`). Which session saved it isn't recorded here.
  - **What that save removed:**
    - `text_me` (`tool_7901m57kexstfma8fsdzdxvjj9jc`) and `call_me_later` (`tool_6901m57key8nftdsvny3qd3n5kr7`). Neither is on main, and neither has an app handler or `x_doddy.ask`.
    - Three other tools: `tool_8801m4p10mbbe2avb1a9ygw4vjky`, `tool_8201m4p10nhsfdqayngyjt5g2pp7` and `tool_1401m4rmxkm5eg3v87sphf87c45p`. Their names aren't recorded in this repository.

    Nothing was changed on the agent by the merge session.
  - **`voice-agent/README.md`** names `agtvrsn_8701m5ct8dxsf8htebwpdykppqbv` as live since #110 (20 Oct). That the live agent runs Eleven Realtime Max is recorded only on the unmerged `claude/ecstatic-allen-ptjm3u`.
  - Live version at the last working call (11 Oct): `agtvrsn_5201m4p132brf30th15nggeqarf0`. ASK-01 exactly: `agtvrsn_6401m57e22qwepwtr1ywwe64x2k4`.
  - Settings on 18 Oct: authentication off, 10 calls a day for the whole agent, concurrency 2, recordings kept with no time limit. **Changed 20 Oct (ADR-548): 1,000 a day, 10 at once; authentication still off; recordings still kept with no time limit (read back).**
  - The ElevenLabs logs show device calls on 14–16 Oct from a build newer than `ce02763`; which commit isn't recorded.

## Platforms
Each platform has its own project spec, so one platform's code can't break another's build. See `docs/platforms/README.md`.

| Platform | Code | Spec → project, scheme | State | Page |
|---|---|---|---|---|
| iPhone and iPad | `DoddyApp/`, `Shared/`, `DoddyWidgets/`, `DoddyShare/` | `project.yml` → `Doddy`; `project-iphone.yml` (no Watch app, and since 20 Oct no entitlements, for a free Apple team) → `Doddy` | Built and used by the owner on device. The voice agent was seen working on 2026-10-11. | `docs/platforms/iphone.md` |
| Apple Watch | `DoddyWatch/`, `DoddyWatchWidgets/` | `project.yml` → `DoddyWatch` (embedded in the iPhone app) | Compiles in hosted CI since #69; never run | `docs/platforms/watch.md` |
| Mac | `DoddyMac/`, `DoddyMacWidgets/` | `project-mac.yml` → `DoddyMac` | Prototype, on main since PR #61 (13 Oct); never compiled, and not in CI | `docs/platforms/mac.md` |
| Shared core | `Packages/DoddyCore/` | Swift package, used by every platform | Swift package tests run in the hosted `core` job (green in the runs of #108, #111, #110, #112 and #114); the last count read is 1,244 passing, in the local core-only run for #112 on 20 Oct (the 934 from 13 Oct is out of date) | `docs/platforms/README.md` |

## Not merged yet: what each branch would change
Merge one at a time, then rebuild and talk to Doddy before the next. Rows other than the first two were last checked 19 Oct against main at `8c25e7da`; the 20 Oct merges (table above) may have changed what they conflict with. The rows for #104, `claude/ecstatic-allen-ptjm3u`, `claude/busy-volta-qgwgz3`, `claude/sweet-newton-2z7asj`, the test branch and `claude/admiring-curie-bsuwv9-hey-doddy-card` were checked on 20 Oct against main at `5633b8f4`.

| Branch / PR | What it changes | State and what it needs |
|---|---|---|
| `claude/doddy-sidekick-character-ofgjf5` (21 Oct, no PR) | Doddy as a sidekick with Talk and Task modes (ADR-562), and errands: tasks Doddy researches in the background with one yes per task, uncapped (ADR-563, `docs/implementation/ERRANDS.md`) | <ul><li>**Live already:** the Talk/Task prompt on the ElevenLabs agent since `agtvrsn_6201m5ewm90bezjvesacr57ma1gv` (rollback `agtvrsn_5201m5dtmpvne48vt1hxc6h53hh0`), still asking before each search.</li><li>Server: 153 tests pass with Postgres; errands **off by default** (`ERRANDS_ENABLED=0`). DoddyCore: 1,312 tests pass on Linux.</li><li>**The Tasks screens and the voice controller changes were never compiled** (no Xcode): needs a Mac build. A PR runs it (it touches the app and `instructions.md`, ADR-497).</li><li>To turn on: the build, `ERRANDS_ENABLED=1` on the messaging server, a paid Render instance, then the two tools on the live agent.</li></ul> |
| PR #109 `claude/calm-home-eyes` | Eyes on the calm-Home picture (`HomeEyes`) and Type opening as a bottom sheet | <ul><li>Superseded for the eyes: the picture it draws them on is now the persistent Doddy, so the eyes are on him (ADR-560, merged in #114). Close it, or cut it down to the bottom-sheet change.</li><li>The sheet change would meet motion's Ask hooks (he rides Ask's composer in a cover): check before merging.</li><li>Renumber its ADR-546, which #108 holds.</li></ul> |
| PR #107 `claude/motion-mv6` | The same motion stack as #111 | Superseded: #111 merged it onto the calm Home on 20 Oct. Close it. The branches `claude/motion-mv1` to `mv7`, `claude/motion-probe` and `claude/motion-probe-mv7` (a throwaway; never merge) and `claude/motion-v2-plan` can be deleted. |
| PR #92 `claude/awesome-cray-2lb9ia` (draft) | Doddy's own phone number, U0 to U4 (`text_me`, `call_me_later`, texts and calls) | <ul><li>Its session (`session_01TWmNMWhbDNzDVVkN5AfFhs`) still drives it, and Render may deploy from it.</li><li>Needs main merged in: 16 files conflicted against `fc8a5027`.</li><li>Drop `6abc1546`, which duplicates the guard fix on main.</li><li>Give `text_me` and `call_me_later` `x_doddy.ask='tap'` with `confirm_on_screen` (ASK-01).</li><li>Renumber its ADR-493 to 495 from 531 up.</li></ul> |
| PR #93 `claude/affectionate-lovelace-4qyfwm` (draft) | `docs/ARCHITECTURE.md` and case-first rules in `CLAUDE.md` | <ul><li>Owner review: it changes the agent rules.</li><li>Merges cleanly and passes `verify_imported_pack.py`.</li><li>Its notes on the guard, ASK-01 and list actions are out of date.</li></ul> |
| PR #86 `claude/connect-in-conversation` (draft) | Connect an online account from the conversation | <ul><li>Hold until the v1 scope is marked up.</li><li>Needs main merged in (conflicts in `DECISIONS.md` and `voice-agent/instructions.md`).</li><li>Renumber its ADR-483, which collides with ASK-01.</li><li>Keep both the BLIK line and the card line in `voice-agent/instructions.md`.</li></ul> |
| PR #89 `claude/payments-apple-pay-blik` (draft) | Buy card with Apple Pay or BLIK, test mode (ADR-530) | Cowork session on the owner's Mac |
| PR #94 `claude/happy-volta-9a11kw` | Keep private notes out of Memory on calls (ADR-310), plus session prompts | Not reviewed in the merge session |
| PR #96 `claude/bold-noether-gtd1l5` | Phase 1: the sprawa direction, written down (ADR-540) | Not reviewed in the merge session |
| PR #78 `claude/youthful-pasteur-25tuhv` | "Big brain. Small body." share card (ADR-444) | <ul><li>Owner decision: its pose is cut from an image pasted into a session, not from the numbered asset pack `CLAUDE.md` requires.</li><li>Conflicts with main.</li><li>Renumber ADR-444, which main already uses.</li><li>Change its doddy-nine URLs to doddy.lol.</li></ul> |
| PR #71 `claude/zealous-hopper-5ctdsc` | Waitlist redeploys; site moves to doddy-nine | <ul><li>Superseded and conflicting. Recommend closing it.</li><li>Its `4abd32ff` (a same-commit redeploy builds again) is still useful as a new small PR for `site/`, `gateway/` and `server/voice-token/vercel.json`. That would cost three production builds.</li></ul> |
| PR #77 `vercel/vercel-web-analytics-to-projec-6x9y6k` (draft) | Adds an unused `@vercel/analytics` package | Redundant: the site already loads Vercel Web Analytics. Recommend closing it. |
| PR #63 `claude/zealous-lamport-hxt7lw-xcode` (draft) | Voice controller alarm and second-start test seams, never compiled | Mostly superseded by ADR-496 and conflicting. Recommend closing it; redo the alarm seam on main if wanted. |
| `claude/epic-wright-vz93xh` | Voice token server settings work | <ul><li>Superseded: main plus #84 and #88 carry most of its 3 commits.</li><li>Dropped on purpose: the reply table in `server/voice-token/README.md`, reading a bare HTTP 500 as "not set up", and its ADR-483 (collides with ASK-01).</li><li>Kept, not deleted.</li></ul> |
| `claude/trusting-dirac-o8ajzc` | Voice screen shows Doddy with a sound wave; the transcript is one tap away | Medium risk to voice: adds audio level meters to the live session |
| `claude/affectionate-mayer-aovol9` | Island compact view draws a pre-cut round face | Low |
| PR #104 `claude/bold-hawking-38iysy` (draft) | "Hey Doddy" with Apple's on-device speech recognition instead of Picovoice (ADR-472) | Hey Doddy was removed on main (#108, ADR-549). Owner decision: close it, or rework it on top of main. |
| `claude/ecstatic-allen-ptjm3u` | Docs only: the live agent runs Eleven Realtime Max (read back 20 Oct) | Merges cleanly into main. |
| `claude/busy-volta-qgwgz3` | Its two `project-iphone.yml` commits are on main since 20 Oct | Its three voice commits do what #108's Debug switch (ADR-551) does. Nothing left to merge. |
| `claude/sweet-newton-2z7asj` | Breathing removal; no PR, never compiled | Duplicates #108 (ADR-550). Nothing left to merge. |
| `claude/wizardly-cannon-k0u1mv` | The 20 Oct test build: #108, #111, #110, #112 and #113 merged together for the owner's iPhone | Not for main. Main has all of it except `claude/ecstatic-allen-ptjm3u`'s docs (and adds #114); build main instead. |
| `claude/admiring-curie-bsuwv9-hey-doddy-card` | Already in main (nothing ahead, 20 Oct). Hey Doddy itself was removed on 20 Oct (ADR-549) | None |
| `claude/dismiss-ended-card` | Nothing: its changes were reverted | None |

## Known problems
- **Voice sessions sometimes start twice.** ElevenLabs logs from 2026-10-09 to 10-11 show:
  - two sessions starting in the same second;
  - a "ghost" session that connects but never sends its start data and stays silent for 30 s;
  - a session that can't hear the user.

  Investigated 18 Oct (`docs/implementation/VOICE_SESSION_STARTS.md`, ElevenLabs list only, no transcripts):
  - Two starts at once mostly predate the 11 Oct "review H1" fix.
  - Silent 30-second sessions with zero messages still happen: six since that build, four of them within five minutes on 16 Oct at night.
  - Leading suspect: a "Hey Doddy" start from the background that stalls before its start data and stops when iOS's roughly 30-second background allowance runs out. **That start path was removed with the wake word (ADR-549), so this cause is gone; check the next device log for silent sessions.**
  - PR #84 (on main since 19 Oct) adds one conversation at a time (ADR-496) and the log lines a phone log needs. Not fixed yet: it still needs a device log to confirm the cause.
- **Vercel:** the `doddy` project (team `doddyyyy`) built and published the site from the default branch on 2026-10-14 (www.doddy.lol); the earlier "account blocked" failures did not recur on that build. The free plan allows 100 deployments a day, and skipped ones count: on 18 October the limit was reached by 12:22 UTC (100 deployments since 09:34, 86 of them skipped), so Vercel refused new ones and showed "Account is blocked". Since 18 October only the production branch deploys: preview deployments are off in all three projects' settings (go-live checklist A10), and each `vercel.json` says the same (ADR-498, PR #84, on main since 19 Oct). GitHub Actions stopped starting jobs on 16 October and ran again on 18 October at 15:08 UTC (run 39139146509). Since then, every commit also gets three red "Account is blocked." statuses with a generic Vercel help link, under the same names (`Vercel – doddy-voice-token` and so on) as `doddyyyy`'s real statuses. They probably come from the old team's projects. `doddyyyy` itself posts "Vercel is deploying your app", "Canceled by Ignored Build Step", "Deployment has completed" or "Deployment rate limited". None of these is a required check. On 20 Oct #110's merge deployed the site normally (www.doddy.lol served `#FF6A00` at 20:40 UTC) while the three red statuses showed.

- **Render backend is newer than the app on the owner's phone.** The live `doddy` service (https://doddy-yaci.onrender.com) runs the ASK-01 server (deploy of `5904c9c` after #87; on 19 Oct `check_email` without an approval answered 403 "Doddy has to ask first"). The build installed on the owner's iPhone is older and doesn't send the approval, so its cloud reads (Gmail, Calendar) are refused until a new build from main is installed. Not a server bug; see `docs/integrations/DEPLOY_RENDER.md`.
- **Vercel `doddy-gateway` has no environment variables** (read on 19 Oct: none in any environment), while `secrets/manifest.json` targets it. Names it needs, no values:
  - secrets: `OPENAI_API_KEY`, `GATEWAY_TOKEN_SECRET`, `GATEWAY_INVITE_CODES`, and `UPSTASH_REDIS_REST_URL` with `UPSTASH_REDIS_REST_TOKEN` (or a Vercel Marketplace Redis store, which sets `KV_REST_API_URL` and `KV_REST_API_TOKEN` itself);
  - optional settings read by the code: `OPENAI_MODEL`, `GATEWAY_RATE_PER_MINUTE`, `GATEWAY_RATE_PER_DAY`, `GATEWAY_INVITE_PER_DAY`, `GATEWAY_GLOBAL_PER_DAY`, `DAILY_BUDGET_USD`, `DAILY_BUDGET_PER_INSTALL_USD`, `DAILY_BUDGET_PER_INVITE_USD`, `OPENAI_PRICE_INPUT_PER_MTOK_USD`, `OPENAI_PRICE_OUTPUT_PER_MTOK_USD`, `REQUIRE_SHARED_LIMITS`.

  Until they're set, that gateway can't serve. Decide first which gateway the phone uses (owner decision 11); nothing was changed.

## Waiting on the owner
**Added on 20 Oct (after #108, #110 and #111):**
- **Build main and look at it on a phone** (on a free Apple team: `make project-iphone`): the new app icon on the Home Screen and the watch; "Hi, I'm Doddy. What's on your mind?" on a first conversation and "I'm here. What's up?" after that; "Working on it…"; the motion v2 Doddy; the new options screen for opening Doddy (#112). Then one conversation with the updated live agent (it has run no conversation yet). If it feels off, roll the live agent back to `agtvrsn_9601m5cg7h2jf0ctpbggw15zzq4n`.
- **Open PRs the merges affect:** #104 (Hey Doddy, which is removed) and #109 (see "Not merged yet"): close or rework them.
- **Docs:** merge `claude/ecstatic-allen-ptjm3u` (Eleven Realtime Max), if it's still true.
- **Brand review leftovers** (`docs/design/BRAND_V2_2_REVIEW.md`): step 3b, the dark canvas `#171F29` against the guide's night `#16171C`, after the new orange has been seen on a device; item 7, the homepage copy (the owner said "later"); a Polish speaker for the two spoken lines "Cześć, tu Doddy. Co ci chodzi po głowie?" and "Jestem. Co słychać?", and for the nine machine-drafted "Working on it…" lines (`l10n/REVIEW_NOTES.md`).
- **Motion v2 (#111) and his eyes (#114), never run on a device:** 80 to 120 Hz riding, the keyboard, haptics, hand-off alignment, the system's Reduce Motion and VoiceOver; how small the eyes read (2 to 4 pt) and the seam where his own eye was covered (D20 to D23). Checklist: `docs/design/MOTION_V2_DEVICE_CHECKLIST.md`. The owner confirmed on 20 Oct ("Confirm and ok for home") the plan's answers for Q2, Q3, Q4, Q8, Q10, Q13, Q14, Q15 and Q16; Home stays 1.4x (the agent's reading). Still open: Q6 (blink and eye art) and Q11 (larger exports). Art the pack lacks: `docs/design/MOTION_V2_ART_REQUESTS.md`.

**Added or confirmed on 19 Oct by the merge session:**
- **Apple:** a paid Apple Developer Program membership, selected in Xcode, and the Sign in with Apple capability on App ID `com.bienos.doddy2.dev`. Voice can't sign in on a phone without both (ADR-522).
- **Composio:** the Gmail auth config.
- **Twilio:** the account upgrade, Poland, and the ID check.
- **Render:** paid plans. The free database is deleted on 10 Nov.
- **Calls (#90):** the legal basis for the call recording notice. `CALL_RECORDING_NOTICE` stays `off` until then. After that: a Poland-only Twilio subaccount, the task-call agent with a Polish voice, then live tests #1 to #3 (`docs/implementation/CALL_CASES_STATUS.md`).
- **#90's secrets split:** confirm which call names are secrets and their 1Password item names. Proposed: `TWILIO_TASK_AUTH_TOKEN` (item `twilio-task-auth-token`) and `ELEVENLABS_WEBHOOK_SECRET` (item `elevenlabs-webhook-secret`), with the other 11 under `notSecrets`. The sync tool can't reach `doddy-messaging-worker`, so its two secrets go there by hand.
- ~~**BLIK:** the 10,000 zł limit~~: decided 19 Oct, 1,000 zł per transfer (ADR-541, #101).
- ~~**Translator:** ask first or not~~: decided 19 Oct, it asks first like every other tool (ADR-542). This answers #84's open question.
- **`DODDY_ACCESS_CODES`:** remove it once the signed-in build is on every tester's phone.
- ~~**Repository visibility**~~: decided 19 Oct, it stays public (ADR-543); ADR-497's text is corrected.
- ~~**The live voice agent** lost five tools on 19 Oct~~: intended. The owner had `upcoming_renewals`, `add_to_diary`, `pay_for_page`, `text_me` and `call_me_later` detached (ADR-544, `voice-agent/README.md`). Still open: trimming the prompt's "Texts and calls from Doddy's number" paragraph waits on the owner's yes.
- **Old PRs:** close #63, #71 and #77 if you agree (recommendations in the table above). Decide on #78's art.

**From before:**
- Mark up `docs/product/V1_SCOPE.md`: Ship, Hide or Cut for each feature, plus the eight decisions at its end.
- Stage A of `docs/implementation/GO_LIVE_CHECKLIST.md`:
  - ~~the voice token server's sign-in settings on Vercel~~: done 19 Oct, see "Voice, 19 Oct";
  - Sign in with Apple on the App ID (needs a paid team);
  - then build on a Mac and talk to Doddy on the phone.
- GitHub Actions cost: 12–14 October used about $250, almost all of it the macOS build. ADR-497 (PR #84) makes that build wait for the Linux checks and skip pull requests that don't touch the app.
- 1Password for project secrets (ADR-493, `docs/security/SECRETS_1PASSWORD.md`).
  - Create the four vaults and items, then run the sync tool one host at a time.
  - Built and tested on Linux against fakes only; it hasn't touched the real 1Password, Vercel or Render.
- Delete the two old Supabase functions and their secrets (code saved in `docs/archive/supabase-functions-2026-10-18/`).
  - Decide whether to keep the Render copies of `doddy-voice-token` and `doddy-gateway` (research report, decision 11).
- A native review of the eight new app languages and of all nine landing-page translations, which are live as drafts (`l10n/REVIEW_NOTES.md`).
- "Hey Doddy" and Picovoice were removed on 20 Oct (ADR-549): the wake word had never run on a device. The Vercel project `doddy-voice-token` may still hold a `PICOVOICE_ACCESS_KEY` value; remove it (`tools/secrets/sync.mjs --prune`).
- Whether notes sync between the Mac and the iPhone (today they never do).
- The kitchen timer Live Activity.
- A Pencil drawing canvas.
- The Mac minimum macOS version.
- The final icons: the app icon is the pack's wave frame since 20 Oct (ADR-557, `tools/whole_doddy/make_app_icon.py`); it is a 2.5x upscale of a small frame, so an artist's larger or vector wave would replace it.

## How agents should read this repo
1. This page, then **only** the page for the platform you are working on, under `docs/platforms/`.
2. That page lists the folders and the status doc for each feature. Open those, not the whole tree.
3. **Don't read `DECISIONS.md` (about 770 lines) whole.** Search it for an ADR number: `grep -n "| 452 |" DECISIONS.md`.
4. Ignore `reference/`, which is historical.
5. Run `scripts/ci.sh --core-only` on Linux. App code needs a Mac with Xcode.
