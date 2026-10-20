# Doddy: current status (read this first)

Doddy is a voice-first memory companion for iPhone, with an Apple Watch app and a Mac menu bar prototype. This page is the short version. Update it when you merge something that changes what is below.

Last updated 2026-10-19 (the owner's merge session: #84, #88, #90 and the #97 fix). Before that, 18 Oct: stage A (ADR-520 to ADR-524) and PR #85, BLIK transfers (ADR-510).

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
- **Since then on main:** OpenAI Realtime became the default voice with a model picker on Home (ADR-442) and the first-use screens landed (#76: ADR-324 to 327, ADR-443). **On the branch `claude/friendly-volta-3recsi` (20 Oct, ADR-546 and ADR-547):** ElevenLabs is the default again and OpenAI is a choice in the picker; four unused views and four old image sets are gone, five pack poses ship smaller, and start-up jobs wait for the first screen (`docs/implementation/LAUNCH_PROFILING.md`, never measured; `docs/implementation/REPO_DIET_2026-10-20.md`). "What I can do" is back in Home's ••• menu (ADR-548) and the old design folders are deleted (the design now is the app, `design/dynamic-island-v4` and the site's folders). DoddyCore tests pass on Linux; the iOS build is NOT RUN.
- **Also on main (PR #80, 14 Oct):** the iPhone app and the landing page in ten languages, as machine-translated drafts (ADR-458 to 460). The landing page is live at https://www.doddy.lol in all ten. CI built the app and passed the unit and UI tests with these changes; the language picker and the translated screens have not been seen on a device, and no native speaker has read any of it (`l10n/REVIEW_NOTES.md`).
- **Hosted CI on 18 Oct:** jobs start again after the owner fixed the account's GitHub billing. The first Mac build since 14 Oct showed that no branch had compiled since 754e5d6 (`VoiceAccessGate.swift` used `VoiceProvider` without `import DoddyCore`), and that two app unit tests had never run: the profile intro test from 754e5d6 and the translator test that ASK-01 made stale. PR #85 fixes all three. Its run 39138962699 built the app and passed the 29 UI tests, with only those two tests failing. Actions time is paid for (12–14 Oct used about $250, almost all of it the macOS build); since #84 (on main 19 Oct) the Mac build waits for the Linux checks and skips pull requests that don't touch the app (ADR-497), and the UI tests take 26 minutes instead of 34 (ADR-499). #84's run 39143827911 passed everything (Mac job 40 minutes).
- **Also on main (PR #85, 18 Oct):** BLIK transfers by voice (ADR-510). "Send Ania 50 zł" shows a card to send in the bank app; Doddy never sends money. The `draft_blik_transfer` tool is behind an off-by-default switch and was added to the live ElevenLabs agent on 18 Oct (see "Voice agent" below for today's live version). Compiled in hosted CI; not yet seen on a device. Details: `docs/implementation/BLIK_TRANSFER_STATUS.md`.
- **Evidence:**
  - The live voice agent worked from this code on 2026-10-11 at 22:35 Warsaw time: a 139 s conversation that used `search_memories`, `save_memory` and `web_search`.
  - The variables the app sent to ElevenLabs match this branch, and not the unmerged `-all` branch.
- **To get back to a build that works,** build this branch: `make project`, open `Doddy.xcodeproj`, scheme `Doddy`.
- **Voice agent:** ElevenLabs agent `agent_0501m4et27vyeawrwqfdxxfszfa6`. Its spec is `voice-agent/`.
  - **Live version, read 19 Oct 09:21 UTC:** `agtvrsn_8901m59m3bdqe6takgkfbcmfh2yh`, 82 tools. It was saved at 08:22:55 UTC on 19 Oct over `agtvrsn_0601m57kxxh3eaprt27bk83ta8vx` (87 tools; saved 18 Oct 13:41 UTC from `claude/awesome-cray-2lb9ia`, commit `6672259f`). Which session saved it isn't recorded here.
  - **What that save removed:**
    - `text_me` (`tool_7901m57kexstfma8fsdzdxvjj9jc`) and `call_me_later` (`tool_6901m57key8nftdsvny3qd3n5kr7`). Neither is on main, and neither has an app handler or `x_doddy.ask`.
    - Three other tools: `tool_8801m4p10mbbe2avb1a9ygw4vjky`, `tool_8201m4p10nhsfdqayngyjt5g2pp7` and `tool_1401m4rmxkm5eg3v87sphf87c45p`. Their names aren't recorded in this repository.

    Nothing was changed on the agent by the merge session.
  - **`voice-agent/README.md` on main is out of date:** it still names `agtvrsn_2801m57etpkkfhfbjvqt95nptfha` (the ASK-01 restore of 18 Oct) as live.
  - Live version at the last working call (11 Oct): `agtvrsn_5201m4p132brf30th15nggeqarf0`. ASK-01 exactly: `agtvrsn_6401m57e22qwepwtr1ywwe64x2k4`.
  - Settings on 18 Oct: authentication off, 10 calls a day for the whole agent, concurrency 2, recordings kept with no time limit. **Changed 20 Oct (ADR-548): 1,000 a day, 10 at once; authentication still off; recordings still kept with no time limit (read back).**
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
Merge one at a time, then rebuild and talk to Doddy before the next. Checked 19 Oct against main at `8c25e7da`.

| Branch / PR | What it changes | State and what it needs |
|---|---|---|
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
| `claude/motion-mv1`, `claude/admiring-curie-bsuwv9-hey-doddy-card` | Not reviewed in the merge session | |
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
- **Vercel:** the `doddy` project (team `doddyyyy`) built and published the site from the default branch on 2026-10-14 (www.doddy.lol); the earlier "account blocked" failures did not recur on that build. The free plan allows 100 deployments a day, and skipped ones count: on 18 October the limit was reached by 12:22 UTC (100 deployments since 09:34, 86 of them skipped), so Vercel refused new ones and showed "Account is blocked". Since 18 October only the production branch deploys: preview deployments are off in all three projects' settings (go-live checklist A10), and each `vercel.json` says the same (ADR-498, PR #84, on main since 19 Oct). GitHub Actions stopped starting jobs on 16 October and ran again on 18 October at 15:08 UTC (run 39139146509). Since then, every commit also gets three red "Account is blocked." statuses with a generic Vercel help link, under the same names (`Vercel – doddy-voice-token` and so on) as `doddyyyy`'s real statuses. They probably come from the old team's projects. `doddyyyy` itself posts "Vercel is deploying your app", "Canceled by Ignored Build Step", "Deployment has completed" or "Deployment rate limited". None of these is a required check.

- **Render backend is newer than the app on the owner's phone.** The live `doddy` service (https://doddy-yaci.onrender.com) runs the ASK-01 server (deploy of `5904c9c` after #87; on 19 Oct `check_email` without an approval answered 403 "Doddy has to ask first"). The build installed on the owner's iPhone is older and doesn't send the approval, so its cloud reads (Gmail, Calendar) are refused until a new build from main is installed. Not a server bug; see `docs/integrations/DEPLOY_RENDER.md`.
- **Vercel `doddy-gateway` has no environment variables** (read on 19 Oct: none in any environment), while `secrets/manifest.json` targets it. Names it needs, no values:
  - secrets: `OPENAI_API_KEY`, `GATEWAY_TOKEN_SECRET`, `GATEWAY_INVITE_CODES`, and `UPSTASH_REDIS_REST_URL` with `UPSTASH_REDIS_REST_TOKEN` (or a Vercel Marketplace Redis store, which sets `KV_REST_API_URL` and `KV_REST_API_TOKEN` itself);
  - optional settings read by the code: `OPENAI_MODEL`, `GATEWAY_RATE_PER_MINUTE`, `GATEWAY_RATE_PER_DAY`, `GATEWAY_INVITE_PER_DAY`, `GATEWAY_GLOBAL_PER_DAY`, `DAILY_BUDGET_USD`, `DAILY_BUDGET_PER_INSTALL_USD`, `DAILY_BUDGET_PER_INVITE_USD`, `OPENAI_PRICE_INPUT_PER_MTOK_USD`, `OPENAI_PRICE_OUTPUT_PER_MTOK_USD`, `REQUIRE_SHARED_LIMITS`.

  Until they're set, that gateway can't serve. Decide first which gateway the phone uses (owner decision 11); nothing was changed.

## Waiting on the owner
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
- The final icons.

## How agents should read this repo
1. This page, then **only** the page for the platform you are working on, under `docs/platforms/`.
2. That page lists the folders and the status doc for each feature. Open those, not the whole tree.
3. **Don't read `DECISIONS.md` (about 770 lines) whole.** Search it for an ADR number: `grep -n "| 452 |" DECISIONS.md`.
4. Ignore `reference/`, which is historical.
5. Run `scripts/ci.sh --core-only` on Linux. App code needs a Mac with Xcode.
