# Bring voice back and land #84, #88 and #90 (18 Oct)

You run tonight's work on `Bienos/doddy.2`. The default branch is `claude/loving-dirac-uuxoux`, head `c61f023d`. Read `STATUS.md` and `CLAUDE.md` first.

The facts below were checked read-only at about 20:40 UTC on 18 Oct. Re-check each one before you act on it. If a fact no longer holds, stop and tell me rather than improvise.

## What I (the owner) did before sending this
- **Redis store:** made an Upstash Redis database in the Upstash console. I didn't use the Vercel Marketplace, because it adds `KV_REST_API_*` names the server doesn't read.
- **Settings:** on Vercel team `doddyyyy`, project `doddy-voice-token`, Production, I added:
  - `UPSTASH_REDIS_REST_URL`;
  - `UPSTASH_REDIS_REST_TOKEN` (Sensitive);
  - `DODDY_SESSION_SIGNING_KEY` (Sensitive).

  The values are in 1Password vault `doddy-prod`, items `upstash-voice-token` and `voice-token-session-signing-key`.
- **No redeploy.** That's part of your job, below.

Never handle a secret value, and never ask me to paste one. That means:
- no `create_project_env` with a value;
- no `decrypt`;
- no `get_project_env`.

## Why voice is down (verified)
- **The voice server refuses every request.** `https://doddy-voice-token-beta.vercel.app` answers `503 server_not_configured` because the three settings were missing.
  - Production is `dpl_Cq5advWQZXRWAN8ydrzP6ZkkvqTi`, built from commit `754e5d6`.
  - Its `server/voice-token` code is identical to main's.
- **Settings only reach a new build, and most rebuilds get canceled.**
  - The `ignoreCommand` in `server/voice-token/vercel.json` cancels any build in which nothing under `server/voice-token` changed.
  - So a plain dashboard Redeploy, or an API redeploy by `deploymentId`, gets canceled. That has already happened on this team.
  - Merging #84 changes `server/voice-token`, so the production build it triggers will pick up the settings.
  - Merging #88 builds again, because it changes `voice-auth.js`. Merging #90 won't build.
- **The app on main points at a dead address.** It calls `https://doddy-voice-token.vercel.app` (the old team's project, which answers 402). #88 (ADR-521) moves it to the `-beta` address. Voice on my phone therefore needs #88 merged and a new phone build.
- **Vercel's daily deployment cap.**
  - The Hobby cap was hit today ("Deployment rate limited — retry in 24 hours", 12:05 to 12:59 UTC).
  - The "Account is blocked" statuses on every PR come from that. They are not required checks, so ignore them when deciding to merge.
  - Each push to the default branch uses 3 deployments: site, gateway and voice-token.
- **Voice on the phone also needs Sign in with Apple** (ADR-522), and that needs a paid Apple Developer Program team. Only I can confirm and set that up. Treat it as an owner item, not something to fix.

## Who drives what
| Branch / PR | Driving session | Check-in (UTC) | You may |
|---|---|---|---|
| #84 `claude/laughing-darwin-hqxa63` @`70f064f3` | `session_01RCEUyeoxYnUiigB8zf6MhZ` | 22:40 `trig_018znskcu45owKZ9FQDz2HMw` | merge the PR |
| #88 `claude/fervent-edison-3gnqpq` @`cdd784e6` | `session_011RwsCsm428qSsqtzycvish` | 22:19 `trig_018AtBz4kcMjvt66b627kYAQ` | merge the PR; push only after taking over (step 3) |
| #90 `claude/modest-pasteur-7jnwfd` @`ebf9d360` | `session_014ACRWmczHwgRqrBLpE3QyF` | 23:36 `trig_0166MKBUaFM1UUyV4vLhrZ4w` | merge the PR; push only after taking over (step 4) |
| #89 `claude/payments-apple-pay-blik` | Cowork `session_01F7jUa7kUbN3RRMPdCoRzW6`, on my Mac | none | nothing |
| `claude/epic-wright-vz93xh` | voice-token settings `session_01XvyTagkLivvU3GkxVe3WA7` | none | nothing (superseded) |
| `claude/awesome-cray-2lb9ia` | phone number `session_01TWmNMWhbDNzDVVkN5AfFhs` | none | open a draft PR (step 5) |
| `claude/affectionate-lovelace-4qyfwm` | architecture `session_01EXT7JquEwaHx82KEY52Tdw` | none | open a draft PR (step 5) |
| `claude/elegant-hopper-6qrj3z` | Composio `session_01VkU5sPUikrKpXEJvVA2SCJ`, working with me now | none | nothing |
| `claude/motion-mv1` | `session_016KREaFAvF9A2hS5Pa8c72B` | 21:09 | nothing |
| `claude/admiring-curie-bsuwv9-hey-doddy-card` | unknown | none | nothing |
| #86 `claude/connect-in-conversation` | Cowork `session_01ArZvvveZvmZojLVjeTYk9q`, idle | none | nothing (report only) |

How to work alongside these sessions:
- **Merging:** merge only through GitHub's PR merge (`merge_pull_request`, method `merge`). It doesn't push to the PR's own branch.
- **Where you push:** only to new branches you create.
- **Base merges:** the sessions that own #88 and #90 merge main into their own branches. Ask them with `send_message`. If `send_message` isn't available to you, stop and tell me, and I'll message them myself.
- **Watching CI:** don't `subscribe_pr_activity` to #84, #88 or #90, because their sessions hold those subscriptions. Poll `get_check_runs` instead, using `send_later` or `Monitor` to wait.

## Step 0: checks before anything else
1. **Branch heads.** Run `git ls-remote origin` and expect `70f064f3` (laughing-darwin), `cdd784e6` (fervent-edison), `ebf9d360` (modest-pasteur) and `c61f023d` (loving-dirac). If a head moved, find out who moved it and why before you go on.
2. **The three settings.** Run `filter_project_envs` (no decrypt) on project `prj_nUn4EnDYSoupUFVuQetQx2KzfDxf`, slug `doddyyyy`.
   - All three names must be there with target `production`.
   - `UPSTASH_REDIS_REST_TOKEN` and `DODDY_SESSION_SIGNING_KEY` must be type `sensitive`.
   - If any is missing or not Sensitive, stop and tell me which one, by name only.
3. **One builder only.** Tell the voice-token settings session (`session_01XvyTagkLivvU3GkxVe3WA7`) with `send_message`: the settings are in, and you'll make the production build and check it, so it shouldn't redeploy.
4. **Deployment cap.** Run `list_deployments` with slug `doddyyyy` and `since` `1792342357303` (16:52 UTC).
   - If new deployments are being created again, the cap has cleared.
   - If not, continue with the merges anyway. Step 2 covers building later.

## Step 1: merge #84
1. **Confirm it's ready:** `core` and `ci` green on head `70f064f3` (run 39151481681), mergeable, and no open review threads.
2. **Translator mode:** don't change it. It keeps asking first (ASK-01), as the tests expect. The decision is mine and still open.
3. **Merge** with a merge commit, and note the merge SHA.
4. **Tell #84's session** with `send_message`: it's merged, and there is nothing more to do on it.

## Step 2: build voice production and check it (right after step 1)
1. **Find the build.** Run `list_deployments` with project `prj_nUn4EnDYSoupUFVuQetQx2KzfDxf` and the merge SHA, and wait for READY.
   - `list_deployment_events` must not say the Ignored Build Step returned exit code 0.
   - `get_deployment` must list `doddy-voice-token-beta.vercel.app` among its aliases.
2. **If there is no deployment for that SHA**, or it was refused because of the cap:
   - Check again every 30 to 60 minutes until the cap clears. Don't retry blindly.
   - Then run `create_deployment` with slug `doddyyyy` and `{name:'doddy-voice-token', project:'prj_nUn4EnDYSoupUFVuQetQx2KzfDxf', target:'production', gitSource:{type:'github', org:'Bienos', repo:'doddy.2', ref:'claude/loving-dirac-uuxoux', sha:'<merge SHA>'}}`.
   - Never redeploy by `deploymentId`. Never override `projectSettings.commandForIgnoringBuildStep`, because that override is saved on the project.
3. **Probe without secrets:**
   - `POST https://doddy-voice-token-beta.vercel.app/api/voice-auth` with `content-type: application/json` and body `{"action":"refresh","refreshToken":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}`.
     - Expect `401 {"error":"session_expired"}`. That shows the store and the signing key work.
     - `503 server_not_configured` means a wrong URL, a read-only token or a missing key. Tell me which name to check, and don't guess at values.
   - `POST https://doddy-voice-token-beta.vercel.app/api/voice-token` with no `Authorization` header. Expect 401, not 503.
4. **Tell me** the deployment ID, the SHA and both responses. This shows the server is configured. It doesn't show that a conversation works; only my phone can show that.

## Step 3: #88
1. **Ask #88's session** (`session_011RwsCsm428qSsqtzycvish`) with `send_message`:
   - #84 is merged at `<SHA>`.
   - Merge the default branch into `claude/fervent-edison-3gnqpq` now, with a merge commit, add its pending go-live checklist A1 line, push once, and reply when CI is green.
   - Pass on what the read-only merge test found: conflicts only in `DECISIONS.md` and `STATUS.md`. In `DECISIONS.md`, keep its ADR 520–524 section, placed before "## BLIK transfers". In `STATUS.md`, take #88's text in both hunks.
2. **Watch CI** on #88. It runs changes, then core, then macOS ci, about 50 minutes in all.
3. **If that session hasn't pushed within 30 minutes, or says it can't:**
   - Tell it you're taking over the branch and that it should stop pushing.
   - Disable its check-in `trig_018AtBz4kcMjvt66b627kYAQ`.
   - Do the merge yourself as described above: a merge commit, never a rebase or force-push, and one push.
4. **Merge** when `core` and `ci` are green on a head that contains the current default branch and GitHub shows no conflict. Use a merge commit.
5. **Check the new voice build.** This merge builds voice-token production again. Repeat the step 2 checks on it.

## Step 4: #90
1. **Ask #90's session** (`session_014ACRWmczHwgRqrBLpE3QyF`, check-in `trig_0166MKBUaFM1UUyV4vLhrZ4w`) the same way. Pass on what the merge test found, because resolving only the text conflicts turns `core` red:
   - **`render.yaml`:** #84 (ADR-495) removed the `doddy-messaging-secrets` group. Put #90's 10 keys into the `envVars` of both `doddy-messaging` and `doddy-messaging-worker`, with no group, and keep #90's updated "Daily news (N1)" comment. The keys are `TWILIO_TASK_ACCOUNT_SID`, `TWILIO_TASK_AUTH_TOKEN`, `TASK_CALL_FROM_NUMBER`, `ELEVENLABS_TASK_AGENT_ID`, `ELEVENLABS_WEBHOOK_SECRET`, `TASK_CALLS_KILL_SWITCH` = `"0"`, `CALL_RECORDING_NOTICE` = `"off"`, `PRICE_TWILIO_TRANSCRIPTION_USD_PER_MIN`, `PRICE_TWILIO_CONFERENCE_USD_PER_PARTICIPANT_MIN` and `PRICE_ELEVENLABS_USD_PER_CREDIT`.
   - **`secrets/manifest.json`:** it must list all 13 names that #90's `server/messaging/.env.example` adds: the 10 above plus `TASK_CALL_LIMIT_DEST_DAY`, `TASK_CALL_LIMIT_USER_HOUR` and `TASK_CALL_SAY_VOICE`.
     - Secrets (at least `TWILIO_TASK_AUTH_TOKEN` and `ELEVENLABS_WEBHOOK_SECRET`) go under `secrets`, with targets on both Render services.
     - IDs, prices, limits and switches go under `notSecrets`.
     - Then run `node tools/secrets/sync.mjs templates --write`.
     - Which names count as secrets is my decision. List the split in the PR so I can check it.
   - **`STATUS.md`:** drop the modest-pasteur row from the unmerged table, and keep both owner items.
   - **Before the single push, run:** `node tools/secrets/sync.mjs check`, `node --test "tools/secrets/test/*.test.mjs"`, `python3 -I tools/build_strings_catalog.py --check` and `scripts/ci.sh --core-only`.
2. **Take over if needed:** same 30-minute rule as #88, with check-in `trig_0166MKBUaFM1UUyV4vLhrZ4w`.
3. **Merge** when it is green. #90 doesn't touch the Vercel projects, so its Vercel builds will be canceled. That is expected.

## Step 5: branches with no PR (open PRs, don't push)
Opening a PR doesn't push to the branch, so it doesn't get in its session's way.
- **`claude/awesome-cray-2lb9ia`** (Doddy's own phone number, U0 to U4, 11 commits): open a **draft** PR.
  - Its session will add commits once I send it the Twilio service IDs, and Render may deploy from this branch.
  - In the PR body, list what it needs after the merges:
    - main merged in, with 14 or more conflicts expected;
    - commit `6abc1546` duplicates the guard fix that is already on main;
    - `text_me` and `call_me_later` need `x_doddy.ask='tap'` with `confirm_on_screen` (ASK-01);
    - its ADR-493 collides with #84's ADR-493.
  - Don't merge it, push to it or touch Render.
- **`claude/affectionate-lovelace-4qyfwm`** (`docs/ARCHITECTURE.md` and the case-first rules in `CLAUDE.md`): open a **draft** PR for my review.
  - In the body, note the facts that are now out of date: the guard no longer fails on main, ASK-01 is merged, and the list actions now ask first.
  - Don't merge it, because it changes the agent rules.
- **`claude/epic-wright-vz93xh`:** no PR. Main plus #84 and #88 cover its 3 commits. Mark it superseded in STATUS.md, and don't delete it.
- **#86** (`claude/connect-in-conversation`): don't touch it. In the report, list what it needs after the merges:
  - main merged in;
  - its ADR-483 renumbered (it collides with ASK-01);
  - both the BLIK line and the card line kept in `voice-agent/instructions.md`.

## Step 6: update STATUS.md (after step 4)
Make a new branch from the default branch and open a docs-only PR. It runs changes and core (about 5 minutes); the macOS job is skipped. Merge it once `core` is green. Cover these:
- **On main:** #84, #88 and #90, with their merge SHAs.
- **Voice:**
  - the server state from step 2 (deployment ID and probe results);
  - the app on main now points at the `-beta` address;
  - still on my side: a paid team selected in Xcode, Sign in with Apple on App ID `com.bienos.doddy2.dev`, a new phone build, and the first conversation (`MAC_VERIFICATION_CHECKLIST` rows V0a to V0f).
- **Voice agent:** the live version is `agtvrsn_2801m57etpkkfhfbjvqt95nptfha` (see `voice-agent/README.md`), not `agtvrsn_5201m…`.
- **Not-merged table:** one row per PR or branch that is really open, using the verdicts from step 5. Remove the rows for ASK-01, #44, #61 and #67.
- **Waiting on the owner:**
  - the Apple membership and the Sign in with Apple capability;
  - the Composio Gmail auth config;
  - Twilio upgrade, Poland and the ID check;
  - Render paid plans (the free database is deleted on 10 Nov);
  - the legal basis for the call recording notice;
  - the 10,000 zł BLIK limit;
  - translator ask-first;
  - the #90 secrets split;
  - removing `DODDY_ACCESS_CODES` once the signed-in build is on every tester's phone;
  - repository visibility: GitHub reports it as public, but ADR-497 says private. Which is right?
- **The numbering note at the top of `DECISIONS.md`:**
  - add 217 to "numbers used twice";
  - #89 uses 530, not 490;
  - #86 reuses 483.

## Step 7: old PRs (recommend only)
For #63, #71, #77 and #78, check each one again. Say whether it is superseded, still relevant or conflicting, and recommend close or keep.
- **#71:** commit `4abd32ff` makes same-commit Redeploys build again. It would have avoided tonight's redeploy problem, so say whether to port it to `site/`, `gateway/` and `server/voice-token/vercel.json`.
- **#78:** needs my decision on where its art came from. `CLAUDE.md` allows only my numbered asset pack.

Don't close anything.

## Never
- Handle a secret value, or ask me to paste one.
- Push to a branch another session drives, except #88 or #90 after taking it over as in step 3.
- Rebase, amend or force-push anyone's branch, delete a branch or close a PR.
- Redeploy by `deploymentId`, or change settings on Vercel, Render, Twilio, ElevenLabs, Composio, Upstash or Apple.
- Skip, disable or loosen a test.
- Say voice works on a device.
- Put a model name in commits or PRs.

## Report at the end
Follow `CLAUDE.md` item 10. Also include:
- merge SHAs and CI run links;
- the voice-token deployment ID or IDs, and the probe responses;
- the PRs you opened;
- what is still open, and why;
- the commands you ran and their results;
- what was not run (device, a real conversation, Stripe, Twilio);
- the decisions waiting on me.
