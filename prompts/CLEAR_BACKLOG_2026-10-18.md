# Clear the 18 Oct backlog: merge the green PRs, give orphan branches a PR, refresh STATUS

Repo `Bienos/doddy.2`. Default branch `claude/loving-dirac-uuxoux`, at `c61f023` (PR #85, BLIK, merged). Read `STATUS.md` and `CLAUDE.md` first. This snapshot is from 18 Oct, 19:50 UTC. Re-check each item before you act on it.

## Who is driving what
Several sessions are still watching their PRs and have check-ins scheduled tonight. Two agents pushing to the same branch will break each other's work.

| PR / branch | State at 19:50 UTC | Driving session | What you may do |
|---|---|---|---|
| #84 `claude/laughing-darwin-hqxa63`: 1Password, Linux checks, one voice session at a time, cheaper CI, Vercel production only (ADR-493 to 499) | `core` and `ci` green, no conflict | `session_01RCEUyeoxYnUiigB8zf6MhZ` | Merge train (part 1) |
| #88 `claude/fervent-edison-3gnqpq`: Stage A, voice address, v1 scope, go-live checklist, notification limit, Apple revocation (ADR-520 to 524) | green, no conflict. Has every commit of #84 except its last 3 | `session_011RwsCsm428qSsqtzycvish` | Merge train (part 1) |
| #90 `claude/modest-pasteur-7jnwfd`: Doddy calls on your behalf, in Polish (ADR-500 to 507) | green, no conflict | `session_014ACRWmczHwgRqrBLpE3QyF` | Merge train (part 1) |
| #89 `claude/payments-apple-pay-blik` (draft, payments) | CI running | Cowork session `session_01F7jUa7kUbN3RRMPdCoRzW6`, on the owner's Mac, still working | Read only. Never push. |
| `claude/elegant-hopper-6qrj3z` (Composio Gmail) | waiting on the owner's `ac_…` | `session_01VkU5sPUikrKpXEJvVA2SCJ` | Don't touch |

Before your first push to a branch that another session drove, send that session a short `send_message`: you are taking over this branch, and it should stop pushing to it. Don't do this for #89 or the Composio branch.

## 1. Merge train: #84, then #88, then #90
I approve merging these three in this order. Merge each one only when `core` and `ci` are green on a head that already contains the current default branch, and GitHub shows no conflict.

For each PR in turn:
1. Fetch. If the default branch moved since the PR's last CI run, merge it into the PR head with a merge commit. No rebase, no amend, no force-push.
2. Resolve conflicts:
   - Expect them in `DECISIONS.md`, `STATUS.md`, `l10n/` Polish strings and the generated string catalog.
   - Keep both sides.
   - Regenerate generated files with the repo's own scripts (`scripts/build_strings_catalog.py`), never by hand.
   - The ADR numbers don't collide today (#84: 493 to 499, BLIK: 510, #90: 500 to 507, #88: 520 to 524). Check again after each merge.
3. Run the Linux checks before you push:
   - `scripts/ci.sh --core-only`
   - `scripts/check_forbidden_capabilities.sh`
   - `voice_agent_spec.py check`
   - `build_strings_catalog.py --check`
   - `check_platform_specs.py`
   - the Node tests for any of `backend/`, `gateway/` or `server/` the merge touched.
4. Push and wait for `core` and `ci`. The macOS `ci` job takes about 45 minutes. Vercel's "Account is blocked" statuses come from the account's daily deployment limit, not from the code, and don't block a merge.
5. Merge with a merge commit. Then go to the next PR.

On #88, put its one leftover into the push that merges main: mark the go-live checklist's "CI blocked" row as fixed.

If a check fails, find the cause and fix it. Never skip, disable or loosen a test to get green. If a fix needs a product decision, stop and ask me.

Translator mode: don't change whether it asks first. That decision is mine and is still open.

## 2. Branches that have work but no PR
- **`claude/awesome-cray-2lb9ia`: Doddy's own phone number, U0 to U4.**
  - 11 commits, none on main. Its session (`session_01TWmNMWhbDNzDVVkN5AfFhs`) is waiting on me for Twilio and Render. Message it before you push.
  - Merge main in, then run the Linux checks and the messaging server tests.
  - Open a **draft** PR and get CI green. Don't merge it.
  - Don't change anything on Render or Twilio.
- **`claude/affectionate-lovelace-4qyfwm`: `docs/ARCHITECTURE.md` and the case-first rules in `CLAUDE.md`.**
  - One commit.
  - Merge main in. A CI check guards the first 28 lines of `CLAUDE.md`, so leave them byte for byte.
  - Open a PR for my review. Don't merge it, because it changes the agent rules.
- **PR #86 (draft): connect an online account from the conversation.**
  - Based on `754e5d6`, so it has never compiled. Its CI never started because of the old billing block.
  - Its Cowork session (`session_01ArZvvveZvmZojLVjeTYk9q`) is idle. Message it, then merge main in.
  - Fix what the compile breaks, get CI green, and keep the PR a draft.
- **`claude/epic-wright-vz93xh`: 3 commits** (voice server address, guard fix, a STATUS line).
  - For each commit, check whether main plus #84 and #88 already cover it.
  - Tell me the result. Don't open a PR for duplicates, and don't delete the branch.

## 3. Bring STATUS.md up to date
After the merge train, update `STATUS.md` through a small docs-only PR. Under ADR-497 it skips the macOS build. Merge it once `core` is green. Fix these facts:
- **"Not merged yet" table:** ASK-01 (#87), PR #44 and PR #61 are merged, and PR #67 was closed. Replace the table with the PRs and branches that are really open.
- **Voice agent line:**
  - The live version is `agtvrsn_2801m57etpkkfhfbjvqt95nptfha` (`voice-agent/README.md`, ASK-01 restored), not `agtvrsn_5201m…`.
  - Confirm it from the README and git history. Don't call ElevenLabs.
- **Voice is down for everyone** until the `doddy-voice-token` Vercel project has `DODDY_SESSION_SIGNING_KEY`, `UPSTASH_REDIS_REST_URL` and `UPSTASH_REDIS_REST_TOKEN` and production is redeployed. Put this at the top of "Waiting on the owner".
- **Add to "Waiting on the owner":**
  - finish the Composio Gmail auth config;
  - Twilio upgrade and Polish identity bundle;
  - Render paid plans (the free database is deleted on 10 Nov);
  - the legal basis for the call recording notice;
  - the 10,000 zł BLIK limit;
  - the translator ask-first decision;
  - the paid Apple developer account for Sign in with Apple.

## 4. Old PRs: report only
#63, #71, #77 and #78 haven't moved since 12 and 13 Oct. For each one, say whether it is still relevant, superseded or conflicting, and recommend close or keep. Don't close any of them.

## Never
- Touch settings or secrets on Vercel, Render, Twilio, ElevenLabs, Composio, Upstash or Apple.
- Push straight to the default branch.
- Put a model name in commits or PRs.
- Say anything works on a device. Nothing here was run on one.

## Report at the end
Follow `CLAUDE.md` item 10. Include:
- what merged, with merge commits and CI run links;
- the PRs you opened;
- what is still open and why;
- the commands you ran and their results;
- what was not run (device, Stripe, Twilio);
- the decisions waiting on me.
