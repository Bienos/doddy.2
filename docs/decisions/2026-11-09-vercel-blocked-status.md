# Pull requests stop showing the old Vercel account's "Account is blocked."

- **Date:** 2026-11-09
- **Decided by:** owner ("ok" to the proposal in the session that opened #270, after "and not this constant Vercel is blocked")
- **Status:** accepted
- **Replaces:** none (works alongside ADR-498)

## Why
Every pull request shows three red statuses, `Vercel – doddy`, `Vercel – doddy-gateway` and `Vercel – doddy-voice-token`, each saying "Account is blocked." (read 9 Nov 2026).
- **Not the live team.** The live team, `doddyyyy` (account patcich55@gmail.com, Hobby plan, active, `softBlock` null), has no deployment in state BLOCKED.
- **On `main` the red is overwritten.** The commit statuses of `2efae64` on `main` show, oldest first: "Vercel is deploying your app", then "Account is blocked.", then the live team's "Canceled by Ignored Build Step" (success). All three come from `vercel[bot]` with the same context, so the last one wins and `main` shows green.
- **On `claude/…` branches the red stays.** The live team builds none of them (ADR-498, to stay under the free plan's 100 deployments a day), so nothing replaces it.

The blocked account still has the repository connected, but it is outside what this repository's agents can reach. Turning `claude/…` builds back on would hide the red, but at three deployments a push it would bring back the October rate limit that stopped the site.

## Decision
- **The workflow.** `.github/workflows/vercel-blocked-status.yml` runs on each commit status. When `scripts/vercel_blocked_status.sh` says to, it posts a success status for the same context: "Skipped: Vercel doesn't build pull request branches (ADR-498)".
- **When it replaces a status.** Only when all of these hold:
  - the context is one of the three live projects;
  - the state is failure and the description is exactly "Account is blocked.";
  - every branch whose head is the commit is a `claude/…` branch.
- **What it never touches.** Anything on `main`, any other Vercel message (a build error, a rate limit) and any other check.

## Consequences
- **Pull requests.** The three Vercel rows show as skipped instead of red, which is true for the live team.
- **Only on merged code.** `status` workflows run from `main`, so it starts working once this is merged.
- **What it could hide.** It could hide a red status from the old account. The live team builds nothing on these branches, so there is nothing real behind that red.
- **The real fix** is still the owner's: disconnect the repository from the old account's projects (`docs/OWNER_QUEUE.md`, 14). After that this workflow has nothing to match and can be deleted.

## Evidence
`scripts/test_vercel_blocked_status.sh`: 19 cases pass. With the `main` rule broken on purpose, 2 of them fail. The workflow parses as YAML. It has not run on GitHub yet: it can only run from `main`.
