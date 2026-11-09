# Agents merge their own pull requests once the required checks are green

- **Date:** 2026-11-08
- **Decided by:** owner, 8 Nov 2026: "to zmień zasady" ("then change the rules"), asked why a finished change wasn't on `main`, then chose "Agent merguje wszystko": an agent merges its own pull request and adds `owner-approved` itself when sensitive paths change
- **Status:** applied in the pull request from `claude/beautiful-tesla-s79cm7`, once merged
- **Replaces:** the line in `AGENTS.md` "Current working rules" (decision `2026-11-07-agent-rules-and-records`): "**Never** push to `main`, force-push a branch you didn't create, merge, approve, or add the `owner-approved` or `full-ui-tests` labels. The owner merges (squash)."

## Why
Finished, tested changes waited on `main` for the owner to merge them by hand. The owner wants agents to land their own work.

## Decision
- An agent squash-merges its own pull request once the checks the `main` ruleset requires (`core`, `ios-build`, `sensitive-paths`, `.github/rulesets/main.json`) are green and every review thread is resolved.
- When `sensitive-paths` names its files, the agent adds `owner-approved` itself, after the description says why each named file changes.
- The `main` ruleset is unchanged: pull requests only, squash only, required checks, linear history, no force-push. Agents still never push straight to `main`, never merge another person's or agent's pull request unless the owner asks, and never add `full-ui-tests`.
- The section "Merging (owner, 8 Nov 2026)" at the end of `AGENTS.md` states the rule; `CLAUDE.md` imports it.

## Consequences
- **A merge ships.** Vercel builds production from `main` (the site, www.doddy.lol, and the voice token server, per `STATUS.md`), and Xcode Cloud builds `main` on its way to TestFlight. A merge by an agent can therefore change the live site and the voice token server without the owner looking. Render has `autoDeploy: false`, so the messaging and backend servers still deploy only by hand.
- `owner-approved` no longer means the owner looked. Entitlements, Info.plist, migrations, `voice-agent/`, CI and these rules can reach `main` with no human review. To get the gate back, revert this decision, or make `sensitive-paths` also require the label's author to be the owner (`.github/workflows/pr-guard.yml`).
- With several agents merging, `main` moves faster, so branches more often need updating from `main` before merging.

## Evidence
Rule text only. `python3 -I scripts/verify_imported_pack.py` and `scripts/ci.sh --only checks` were run on this branch (results in the pull request). No workflow, ruleset or GitHub setting was changed.
