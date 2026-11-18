# Use targeted local checks and avoid an unused CI install

- **Date:** 2026-11-18
- **Decided by:** owner, request for risk-based testing and faster delivery
- **Status:** proposed on feature branch

The Node job installed backend dependencies even when `scripts/ci.sh` would skip browser tests because Playwright Chromium was absent. Install them only when that same browser availability condition is met. Required checks and release builds remain in place. Local agent guidance selects checks by risk and avoids unnecessary repeats.

PRs containing only `docs/decisions/*.md` now skip the heavy Linux groups while retaining always-on checks. Swift tests do read some other documentation, including the device-data inventory and trust configuration, so those paths keep their existing classification. Main pushes continue to run all Linux groups. The AGENTS, CLAUDE and DoddyCore instructions now explicitly replace the older unconditional local full-suite instruction with risk-based targeted checks.

The Linux Swift group now compiles and runs the call, messages, price-watch, open-loops and training-log model suites in one invocation. The five focused scripts remain available separately. This removes four repetitions of preparing the shared test target without intentionally removing tests. Compare the executed suite names and counts when validating the change.

Local validation on 18 November: the combined command took 4 minutes 0 seconds including compilation and passed 65 tests. Its five suite counts (8, 23, 17, 6 and 11) matched the previous separate runs. In that earlier local log, the interval from the end of the first suite to the end of the fifth was 7 minutes 34 seconds, excluding the first compilation and including intervening steps. Those runs used different repository revisions and may have different caches and machine load, so they are observations rather than a controlled before/after benchmark or a hosted-CI saving.

## Audit and next measurements

PR jobs already use changed-file selection, cancel superseded runs, cache Swift packages and run independent groups concurrently. Documentation-only changes skip the Mac build. Main runs every Linux group; the Mac app and separate Release build run for relevant changes. TestFlight uses Xcode Cloud. GitHub API access was denied by the environment proxy, so current rulesets, run history, actual timings and approval counts could not be verified. The repository records a roughly 30-minute PR Mac run on 15 November and a 75-minute docs-only main run before existing path filtering; these are historical observations, not before/after measurements for this change.

Benchmark comparable PRs and main pushes with GitHub Actions job start/end times and cache-hit status before and after merge. Compare Node install duration, total critical-path duration, iOS build duration and Xcode Cloud archive/upload duration. Report sample size and skipped jobs. No percentage saving is claimed until runs are measured. A Mac and authorized GitHub/Xcode Cloud access are needed to validate hosted iOS and release behavior.
