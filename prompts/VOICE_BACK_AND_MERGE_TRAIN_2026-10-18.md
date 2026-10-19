# Bring voice back and land #84, #88 and #90 (18 Oct)

You run tonight's work on `Bienos/doddy.2`. The default branch is `claude/loving-dirac-uuxoux`, head `c61f023df7cf2a0aaddf0b6c1462fe1e2c86a941`. Read `STATUS.md` and `CLAUDE.md` first.

The facts below were checked read-only between 20:00 and 20:55 UTC on 18 Oct, and again at 04:50 UTC on 19 Oct (nothing had changed: no merges, the settings still missing, no new deployments). Re-check each one before you act on it. If a fact no longer holds, stop and tell me rather than improvise.

## What I (the owner) did before sending this
- **Redis store:** made an Upstash Redis database in the Upstash console. I didn't use the Vercel Marketplace, because it adds `KV_REST_API_*` names the server doesn't read.
- **Settings:** on Vercel team `doddyyyy`, project `doddy-voice-token`, Production, I added:
  - `UPSTASH_REDIS_REST_URL`;
  - `UPSTASH_REDIS_REST_TOKEN` (Sensitive);
  - `DODDY_SESSION_SIGNING_KEY` (Sensitive).

  The values are in 1Password vault `doddy-prod`, items `upstash-voice-token` and `voice-token-session-signing-key`.
- **No redeploy,** and I won't type "added" in the voice-token settings session. The production build is your job, below.

Never handle a secret value, and never ask me to paste one. That means:
- no `create_project_env` with a value;
- no `decrypt`;
- no `get_project_env`.

## Why voice is down (verified)
- **The voice server refuses every request.** `https://doddy-voice-token-beta.vercel.app` answers `503 server_not_configured` because the three settings were missing.
  - Production is `dpl_Cq5advWQZXRWAN8ydrzP6ZkkvqTi`, built from commit `754e5d6`.
  - Its `server/voice-token` code is identical to main's.
- **Settings only reach a new build, and most rebuilds get canceled.**
  - The `ignoreCommand` in `server/voice-token/vercel.json` cancels a build when nothing under `server/voice-token` changed since the last successful production build (`754e5d6`).
  - So a plain dashboard Redeploy, or an API redeploy by `deploymentId`, gets canceled. That has already happened on this team.
  - Merging #84 changes `server/voice-token`, so the production build that merge triggers will pick up the settings.
  - Merging #88 builds again, because it changes `voice-auth.js`. Merging #90 and docs-only PRs won't build.
- **The app on main points at a dead address.** It calls `https://doddy-voice-token.vercel.app` (the old team's project, which answers 402). #88 (ADR-521) moves it to the `-beta` address. Voice on my phone therefore needs #88 merged and a new phone build.
- **Vercel's daily deployment cap.**
  - The Hobby cap (100 deployments in a rolling 24 hours) was hit today. Vercel posted "Deployment rate limited — retry in 24 hours" between 12:05 and 12:59 UTC.
  - Every push to the default branch makes 3 deployments: site, gateway and voice-token. Canceled ones still count.
  - Preview deployments are off (go-live checklist A10), so only pushes to the default branch create deployments.
- **The red "Account is blocked." statuses are not the cap,** and they don't come from team `doddyyyy`.
  - They appear on every commit with a generic Vercel help link, probably from the old team's projects.
  - They share context names (`Vercel – doddy-voice-token` and so on) with `doddyyyy`'s real statuses, so read the description.
  - `doddyyyy` posts "Vercel is deploying your app", "Canceled by Ignored Build Step", "Deployment has completed" or, when capped, "Deployment rate limited — retry in 24 hours" (linking to `vercel.com/doddyyyy?upgradeToPro=build-rate-limit`).
  - None of these is a required check. Ignore "Account is blocked." when deciding to merge.
- **Voice on the phone also needs Sign in with Apple** (ADR-522), which only works with a paid Apple Developer Program team. Only I can confirm and set that up. Treat it as an owner item.
- **The live ElevenLabs agent is ahead of main.** Its live version is `agtvrsn_0601m57kxxh3eaprt27bk83ta8vx`, saved at 13:41 UTC from `claude/awesome-cray-2lb9ia` (commit `6672259f`).
  - That save added the `text_me` and `call_me_later` tools, which aren't on main, have no app handler and have no `x_doddy.ask`.
  - Main's docs still name `agtvrsn_2801m57etpkkfhfbjvqt95nptfha`.
  - Don't change the agent.

## Who drives what
Check-ins move, so run `list_triggers` (`enabled: true`) when you start and use what it shows. At 04:50 UTC on 19 Oct only two were left, and each was its session's last before it stops checking in.

| Branch / PR | Full head SHA | Driving session | Check-in at 04:50 UTC 19 Oct | You may |
|---|---|---|---|---|
| #84 `claude/laughing-darwin-hqxa63` | `70f064f3c685a79237ddb40c1f839470f792673e` | `session_01RCEUyeoxYnUiigB8zf6MhZ` | 06:40 UTC `trig_018znskcu45owKZ9FQDz2HMw` | merge the PR |
| #88 `claude/fervent-edison-3gnqpq` | `cdd784e69d81e5c22efa94049e205a5c27d186ec` | `session_011RwsCsm428qSsqtzycvish` | 06:23 UTC `trig_01TotzLoTkmrQBxmdZ6KiTfY` | merge the PR; push only after a takeover (step 3) |
| #90 `claude/modest-pasteur-7jnwfd` | `ebf9d3600d7d7f807c8e3cd974d61742d9619d72` | `session_014ACRWmczHwgRqrBLpE3QyF` | none (stopped) | merge the PR; push only after a takeover (step 4) |
| #89 `claude/payments-apple-pay-blik` | | Cowork `session_01F7jUa7kUbN3RRMPdCoRzW6`, on my Mac | | nothing |
| `claude/epic-wright-vz93xh` | | voice-token settings `session_01XvyTagkLivvU3GkxVe3WA7` | | nothing, and don't message it |
| `claude/awesome-cray-2lb9ia` | | phone number `session_01TWmNMWhbDNzDVVkN5AfFhs` | | open a draft PR (step 5) |
| `claude/affectionate-lovelace-4qyfwm` | | architecture `session_01EXT7JquEwaHx82KEY52Tdw` | | open a draft PR (step 5) |
| `claude/elegant-hopper-6qrj3z` | | Composio `session_01VkU5sPUikrKpXEJvVA2SCJ` | | nothing |
| `claude/motion-mv1` | | `session_016KREaFAvF9A2hS5Pa8c72B` | | nothing |
| `claude/admiring-curie-bsuwv9-hey-doddy-card` | | unknown | | nothing |
| #86 `claude/connect-in-conversation` | | Cowork `session_01ArZvvveZvmZojLVjeTYk9q`, idle | | nothing (report only) |

How to work alongside these sessions:
- **Merging:** merge only through GitHub's PR merge. Use `merge_pull_request` with `merge_method: "merge"` and `expectedHeadSha` set to the full head SHA whose CI you checked.
  - It doesn't push to the PR's own branch.
  - If GitHub refuses because the head moved, don't merge. Wait for CI on the new head.
  - If the GitHub MCP tools aren't available, use REST: `gh api -X PUT repos/Bienos/doddy.2/pulls/<n>/merge -f merge_method=merge -f sha=<full sha>`. Don't use `gh pr …`, which goes through GraphQL and has been refused in these sessions.
- **Where you push:** only to this session's own working branch, unless you have taken over #88 or #90 under the rules in step 3.
  - If the git proxy refuses a push, stop and tell me.
  - Don't work around a refused push with `push_files`, `create_or_update_file` or `update_pull_request_branch`.
- **Base merges:** the sessions that own #88 and #90 merge main into their own branches. You ask them to with `send_message`. If `send_message` isn't available or is refused, still do steps 0 to 2, then stop and give me the exact text of each message, and continue once I say I've sent them.
- **Watching CI:** don't `subscribe_pr_activity` to #84, #88 or #90, because their sessions hold those subscriptions.
  - Poll `pull_request_read` with method `get_check_runs`, waiting 10 to 15 minutes between polls with `send_later`.
  - A `Monitor` script can only use the shell (for example `gh api repos/Bienos/doddy.2/commits/<sha>/check-runs`) and stops after 30 minutes, so re-arm it.
  - Foreground `sleep` is blocked.
- **Before every merge or push,** run `git ls-remote origin` and compare against the head you expect.

## Time and order
- **Expected timeline from when you start:** #84 merged within about 15 minutes, #88 about 1.5 hours later, #90 about 1.5 hours after that, and step 6 about 30 minutes after that.
  - Each takeover or red CI run adds about 50 minutes.
  - The Vercel cap is a rolling 24 hours, not a calendar day. Date everything with the actual date.
- **While you wait for CI,** do steps 5 and 7 and the step 2 build retries. They don't depend on the merges.
- **Other sessions wake** at the check-ins `list_triggers` shows, and whenever a GitHub event on their PR arrives.
- **Hard stop 8 hours after you start** for merges and takeovers. After that, finish the step you're in, do step 6 with whatever is merged, and report. Only the step 2 voice build retries may carry on (see step 2).
- **If #88 or #90 can't be merged tonight,** still do step 6 and list the PR as open.

## Step 0: checks before anything else
1. **Branch heads.** Run `git ls-remote origin` and compare against the table above, plus the default branch at `c61f023d…`. If a head moved, find out who moved it and why before you go on.
2. **The three settings.** Run `filter_project_envs` (no decrypt) on project `prj_nUn4EnDYSoupUFVuQetQx2KzfDxf`, slug `doddyyyy`.
   - All three names must be there with target `production` and `configurationId` null (not from the Marketplace).
   - `UPSTASH_REDIS_REST_TOKEN` and `DODDY_SESSION_SIGNING_KEY` must be type `sensitive`, with an empty value.
   - If either one comes back with a non-empty value, don't copy it anywhere: not the report, a PR, STATUS.md or a message. Tell me its name so I can rotate it, because the value is now in this transcript.
   - `UPSTASH_REDIS_REST_URL` isn't secret. If its value is shown, check that it starts with `https://` and contains no `@`. Don't copy it anywhere.
   - If anything is missing or wrong, stop and tell me which name.
3. **One builder only.** Don't message the voice-token settings session (`session_01XvyTagkLivvU3GkxVe3WA7`). It has no check-in and redeploys only when I type "added" there, which I won't. A message saying the settings are in is the one thing that could set it off.
4. **Deployment cap.** You can't see it directly.
   - The last deployment is `dpl_5DxmXtJVTb4jDUmcsygqh3HrXNkS` (c61f023, 16:52 UTC, canceled by the ignore step).
   - `list_deployments` with slug `doddyyyy` and `since` `1792342357304` should come back empty. `since` includes its boundary, so use this value, not `…303`. If it returns anything, that deployment is new, so look at it.
   - The #84 merge in step 1 is the real test, and step 2 says how to read it. Go on to step 1 either way.

## Step 1: merge #84
1. **Confirm it's ready:** `core` and `ci` green on head `70f064f3c685a79237ddb40c1f839470f792673e` (run 39151481681), mergeable, and no open review threads.
2. **Translator mode:** don't change it. It keeps asking first (ASK-01), as the tests expect. The decision is mine and still open.
3. **Merge** with `expectedHeadSha` set to that SHA, and note the merge SHA.
4. **Tell #84's session** with `send_message`: "#84 is merged at <SHA> by the owner's merge session. Nothing more to do on it."

## Step 2: build voice production and check it
1. **Find the build.** Within 5 minutes of the merge, `list_deployments` with `projectId` `prj_nUn4EnDYSoupUFVuQetQx2KzfDxf`, slug `doddyyyy` and `sha` = the full merge SHA should show one production deployment. Wait up to 15 minutes for it to leave QUEUED or BUILDING.
   - **READY:**
     - `list_deployment_events` must not say the Ignored Build Step returned exit code 0.
     - `get_deployment` must list `doddy-voice-token-beta.vercel.app` among its aliases.
     - If the alias is missing, stop and tell me. Don't assign it yourself.
   - **CANCELED or ERROR:** read the build log with `list_deployment_events`, tell me what it says, don't retry, and go on with step 3.
2. **No deployment for that SHA.** Read the merge commit's statuses (`gh api repos/Bienos/doddy.2/commits/<SHA>/statuses`).
   - **"Deployment rate limited" on `Vercel – doddy-voice-token`** means the cap refused the build. Don't wait here. Go on with steps 3 and 4, and retry the build between CI polls:
     - **One call, at most once an hour:** `create_deployment` with slug `doddyyyy` and exactly `{name:'doddy-voice-token', project:'prj_nUn4EnDYSoupUFVuQetQx2KzfDxf', target:'production', gitSource:{type:'github', org:'Bienos', repo:'doddy.2', ref:'claude/loving-dirac-uuxoux', sha:'<the default branch head at that moment>'}}`.
     - Use the current head, not #84's SHA, so #88 is included once it's merged. Never deploy an older SHA after a newer one has built.
     - **Send nothing else:** no `deploymentId`, `withLatestCommit`, `forceNew` or `projectSettings`. Any `projectSettings` field is saved on the project.
     - **If the call errors, times out or returns something unclear,** don't call it again. Run `list_deployments` for that SHA. If there's still nothing, treat that attempt as refused and wait for the next hour.
     - **If a deployment for that SHA exists but ends CANCELED or ERROR,** stop retrying and tell me its ID and the last build-log lines.
     - **Before you merge #90 or the step 6 PR,** try the build first if it's still missing. Those merges create deployments that are canceled but still count, so they mustn't take the first free slots. If the cap still refuses the build, merge anyway: a refused push creates nothing.
     - **Keep trying hourly for up to 24 hours after the first refusal,** even after the hard stop, with one `send_later` per try. If it still hasn't built by then, stop and put the exact call in the report.
   - **No status at all from `doddyyyy`:** tell me, and go on with step 3.
3. **Probe without secrets,** once a deployment is READY:
   - `POST https://doddy-voice-token-beta.vercel.app/api/voice-auth` with `content-type: application/json` and body `{"action":"refresh","refreshToken":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}`.
     - **Expect `401 {"error":"session_expired"}`.** That shows the URL, the token (for reads) and the signing key are loaded, and that Upstash answers. It doesn't show the token can write: a read-only token also gets 401 here. Only a real Sign in with Apple on my phone uses the writes and the Lua scripts.
     - **`503 server_not_configured`** means a wrong or non-https URL, a wrong token, a signing key shorter than 32 bytes, or Upstash unreachable.
       - Tell me which names to check, without guessing values, and carry on with step 3.
       - A fixed value only reaches a new build, and #88's merge is the last merge in this train that builds voice-token. So before merging #88, check whether I've said it's fixed. Merge #88 when it's green either way, and repeat the probe on its build.
       - If it's still 503 after #88, don't make a commit to force a build. Put it in the report.
   - `POST https://doddy-voice-token-beta.vercel.app/api/voice-token` with no `Authorization` header. Expect 401, not 503.
4. **Tell me** the deployment ID, the SHA and both responses. This shows the server is configured. It doesn't show that a conversation works.

## Step 3: #88
1. **Ask #88's session** (`session_011RwsCsm428qSsqtzycvish`) with `send_message`:
   > From the owner's merge session: #84 is merged; the default branch head is `<SHA>`. Please merge it into `claude/fervent-edison-3gnqpq` now with a merge commit (no rebase, no force-push) and add your pending go-live checklist A1 line. Push once and reply when it's pushed. A read-only merge test found conflicts only in `DECISIONS.md` (keep your ADR 520–524 section, once, before "## BLIK transfers") and `STATUS.md` (take your text in both hunks). After that one push, don't push again until #88 is merged, including at any check-in. Put anything else in your reply instead.
2. **Check its push:**
   - `cdd784e6…` is an ancestor of the new head (so no force-push);
   - the new head has the default branch head as a parent;
   - `DECISIONS.md` has the ADR 520–524 section exactly once, before "## BLIK transfers".
3. **Take over only if:**
   - it says no or that it can't; or
   - `get_session` shows it idle, blocked or failed without having pushed; or
   - 60 minutes pass with no push.

   While it is working, keep waiting: its local checks (`scripts/ci.sh --core-only`) take a while. To take over:
   - Disable its check-in, if it still has one (find it with `list_triggers`; at 04:50 UTC on 19 Oct it was `trig_01TotzLoTkmrQBxmdZ6KiTfY`), with `update_trigger` (`enabled: false`). Never use `delete_trigger`.
   - Send it: "The owner's merge session is taking over `claude/fervent-edison-3gnqpq`. Don't push, merge or commit to it again, including the A1 change, even if a GitHub event about #88 wakes you. Reply 'ok' and do nothing else."
   - Wait until `get_session` shows it idle. Then run `git ls-remote` right before your push. If the head is no longer `cdd784e6…`, don't push; look at what it pushed instead.
   - Do the merge yourself, resolved as in the message: one merge commit, never a rebase or force-push, one push. If the push is rejected, stop and tell me.
4. **If CI goes red:**
   - Read the failed job's log (`get_job_logs`, `failed_only: true` with the run ID).
   - Ask the owning session to fix it in one more push, or fix it yourself if you have taken over.
   - Never merge on red, and never skip or loosen a test.
   - If the second run isn't green either, stop the train: leave the PR open and go to step 6.
5. **Merge** when `core` and `ci` are green on head H, H contains the current default branch, and GitHub shows no conflict. Set `expectedHeadSha` to H.
6. **Check the new voice build.** This merge builds voice-token production again. Repeat the step 2 checks on it. If the step 2 build is still waiting for the cap, the next retry now uses #88's merge SHA.

## Step 4: #90 (only after #88 is merged)
If #88 can't be merged tonight, don't start #90.

1. **Ask #90's session** (`session_014ACRWmczHwgRqrBLpE3QyF`) with `send_message`. Tell it:
   - #84 and #88 are merged, and the default branch head is `<SHA>`.
   - Merge that head into `claude/modest-pasteur-7jnwfd` with a merge commit, resolve as below, push once, and don't push again until #90 is merged, including at any check-in.
   - What the read-only merge test found, because resolving only the text conflicts turns `core` red:

   **`render.yaml`:**
   - #84 (ADR-495) removed the `doddy-messaging-secrets` group.
   - Put #90's 10 keys into the `envVars` of both `doddy-messaging` and `doddy-messaging-worker`, with no group, and keep #90's updated "Daily news (N1)" comment.
   - The keys: `TWILIO_TASK_ACCOUNT_SID`, `TWILIO_TASK_AUTH_TOKEN`, `TASK_CALL_FROM_NUMBER`, `ELEVENLABS_TASK_AGENT_ID`, `ELEVENLABS_WEBHOOK_SECRET`, `TASK_CALLS_KILL_SWITCH` = `"0"`, `CALL_RECORDING_NOTICE` = `"off"`, `PRICE_TWILIO_TRANSCRIPTION_USD_PER_MIN`, `PRICE_TWILIO_CONFERENCE_USD_PER_PARTICIPANT_MIN` and `PRICE_ELEVENLABS_USD_PER_CREDIT`.

   **`secrets/manifest.json`:**
   - It must list all 13 names that #90's `server/messaging/.env.example` adds: the 10 above plus `TASK_CALL_LIMIT_DEST_DAY`, `TASK_CALL_LIMIT_USER_HOUR` and `TASK_CALL_SAY_VOICE`.
   - Secrets (at least `TWILIO_TASK_AUTH_TOKEN` and `ELEVENLABS_WEBHOOK_SECRET`) go under `secrets`, shaped like the existing `TWILIO_AUTH_TOKEN` entry:
     - a new, unique `item` name;
     - `services` `["server/messaging"]`;
     - `targets` `["render:doddy-messaging"]` **only**;
     - `push`, `dev` and `rotate`, plus `whyNotPushed` if `push` is false.
   - Don't add `render:doddy-messaging-worker` as a target. No such Render service is listed in `hosts.render.services`, so `sync.mjs check` fails with "unknown target". Don't add the worker to `hosts`, and don't invent a service ID. The worker still gets the keys through `render.yaml`.
   - IDs, prices, limits and switches go under `notSecrets`.
   - Then run `node tools/secrets/sync.mjs templates --write`.
   - Which names count as secrets, and their 1Password item names, are my decision. List the split and the proposed item names in the PR so I can check them.

   **`STATUS.md`:** drop the modest-pasteur row from the unmerged table, and keep both owner items.

   **Before the single push, run:**
   - `node tools/secrets/sync.mjs check`
   - `node --test "tools/secrets/test/*.test.mjs"`
   - `python3 -I tools/build_strings_catalog.py --check`
   - `scripts/ci.sh --core-only`. Without Swift installed this ends `RESULT: BLOCKED` (exit 2), with the Swift steps NOT RUN. That's acceptable if every step that ran is PASS, because CI's `core` job runs the Swift steps. Don't install a Swift toolchain for this.
2. **Check its push, take over, handle red CI:** the same rules as step 3, items 2 to 4. Its check-ins had stopped by 04:50 UTC on 19 Oct; look with `list_triggers` in case it has armed a new one.
3. **Merge** when `core` and `ci` are green on head H, H contains the current default branch including #88's merge, and GitHub shows no conflict. Set `expectedHeadSha` to H.
   - #90 doesn't touch the Vercel projects, so its Vercel builds will be canceled. That is expected.
   - If the step 2 build is still missing, try it right before this merge (see step 2).

## Step 5: branches with no PR (open PRs, don't push)
Opening a PR doesn't push to the branch, so it doesn't get in its session's way. Do this while you wait for CI.
- **`claude/awesome-cray-2lb9ia`** (Doddy's own phone number, U0 to U4, 11 commits): open a **draft** PR.
  - Its session will add commits once I send it the Twilio service IDs, and Render may deploy from this branch.
  - In the PR body, list what it needs after the merges:
    - main merged in, with 14 or more conflicts expected;
    - commit `6abc1546` duplicates the guard fix already on main;
    - `text_me` and `call_me_later` need `x_doddy.ask='tap'` with `confirm_on_screen` (ASK-01). They are already on the live agent (`agtvrsn_0601m57kxxh3eaprt27bk83ta8vx`, from commit `6672259f`) without it, and main's app can't answer them yet;
    - its ADR-493, 494 and 495 collide with #84's ADR-493 (1Password), 494 (guard) and 495 (`render.yaml`). Renumber them from 531 up. 490 to 492 are free on main, and ADR-491 belongs to the duplicate guard fix in `6abc1546`.
  - Don't merge it, push to it or touch Render.
- **`claude/affectionate-lovelace-4qyfwm`** (`docs/ARCHITECTURE.md` and the case-first rules in `CLAUDE.md`): open a **draft** PR for my review.
  - In the body, note the facts that are now out of date: the guard no longer fails on main, ASK-01 is merged, and the list actions now ask first.
  - It passes `scripts/verify_imported_pack.py`.
  - Don't merge it, because it changes the agent rules.
- **`claude/epic-wright-vz93xh`:** no PR. Main plus #84 and #88 cover most of its 3 commits. What they don't carry is dropped on purpose:
  - the reply table in `server/voice-token/README.md`;
  - reading a bare HTTP 500 as "not set up";
  - its ADR-483, which collides with ASK-01.

  Mark it superseded in STATUS.md with that note, and don't delete it.
- **#86** (`claude/connect-in-conversation`): don't touch it. In the report, list what it needs after the merges:
  - main merged in;
  - its ADR-483 renumbered (it collides with ASK-01);
  - both the BLIK line and the card line kept in `voice-agent/instructions.md`.

## Step 6: update STATUS.md (after step 4, or at the hard stop)
On this session's own working branch, starting from the current default branch, open a docs-only PR. It runs changes and core (about 5 minutes); the macOS job is skipped. Merge it once `core` is green. Cover these:
- **On main:** what merged, with merge SHAs, and what is still open.
- **Voice:**
  - the server state from step 2 (deployment ID and probe results), or that the build is still pending and why;
  - the app on main now points at the `-beta` address, if #88 merged;
  - still on my side: a paid team selected in Xcode, Sign in with Apple on App ID `com.bienos.doddy2.dev`, a new phone build, and the first conversation (`MAC_VERIFICATION_CHECKLIST` rows V0a to V0f).
- **Voice agent:**
  - Re-read the live version with ElevenLabs `agents_get` (read-only) just before writing. At 20:50 UTC it was `agtvrsn_0601m57kxxh3eaprt27bk83ta8vx`.
  - Note that main's `voice-agent/README.md` still names `agtvrsn_2801…`, and that the live agent has `text_me` and `call_me_later`, which aren't on main.
  - Never write `agtvrsn_5201m…` or `agtvrsn_2801m…` as the live version.
- **Not-merged table:** one row per PR or branch that is really open, using the verdicts from steps 5 and 7. Remove the rows for ASK-01, #44, #61 and #67.
- **Waiting on the owner:**
  - the Apple membership and the Sign in with Apple capability;
  - the Composio Gmail auth config;
  - Twilio upgrade, Poland and the ID check;
  - Render paid plans (the free database is deleted on 10 Nov);
  - the legal basis for the call recording notice;
  - the 10,000 zł BLIK limit;
  - translator ask-first;
  - the #90 secrets split and item names;
  - removing `DODDY_ACCESS_CODES` once the signed-in build is on every tester's phone;
  - repository visibility: GitHub reports it as public, but ADR-497 says private. Which is right?
- **The numbering note at the top of `DECISIONS.md`:**
  - add 217 to "numbers used twice";
  - #89 uses 530, not 490;
  - #86 and epic-wright reuse 483.

## Step 7: old PRs (recommend only)
For #63, #71, #77 and #78, check each one again. Say whether it is superseded, still relevant or conflicting, and recommend close or keep.
- **#71:** commit `4abd32ff` makes same-commit Redeploys build again. Say whether to port it to `site/`, `gateway/` and `server/voice-token/vercel.json`. It would have avoided tonight's redeploy problem, but each port is a production build.
- **#78:** needs my decision on where its art came from. `CLAUDE.md` allows only my numbered asset pack.

Don't close anything.

## Never
- Handle a secret value, or ask me to paste one.
- Push to a branch another session drives, except #88 or #90 after a takeover as in step 3.
- Rebase, amend or force-push anyone's branch, delete a branch, close a PR, or delete a scheduled task.
- Redeploy by `deploymentId`, send `projectSettings`, or change settings on Vercel, Render, Twilio, ElevenLabs, Composio, Upstash or Apple.
- Merge without `expectedHeadSha`, on red CI, or with a conflict.
- Skip, disable or loosen a test.
- Say voice works on a device.

## Report at the end
Follow `CLAUDE.md` item 10. Also include:
- merge SHAs and CI run links;
- the voice-token deployment ID or IDs, and the probe responses (or the exact `create_deployment` call still to make, and why);
- the PRs you opened;
- what is still open, and why;
- the commands you ran and their results, including NOT RUN steps;
- what was not run (device, a real conversation, Stripe, Twilio);
- the decisions waiting on me.
