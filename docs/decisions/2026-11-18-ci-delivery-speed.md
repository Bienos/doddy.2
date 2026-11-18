# Use targeted local checks and avoid an unused CI install

- **Date:** 2026-11-18
- **Decided by:** owner, request for risk-based testing and faster delivery
- **Status:** proposed on feature branch

The Node job installed backend dependencies even when `scripts/ci.sh` would skip browser tests because Playwright Chromium was absent. Install them only when that same browser availability condition is met. Existing test selection, required checks and release builds remain in place. Local agent guidance selects checks by risk and avoids unnecessary repeats.

## Audit and next measurements

PR jobs already use changed-file selection, cancel superseded runs, cache Swift packages and run independent groups concurrently. Documentation-only changes skip the Mac build. Main runs every Linux group; the Mac app and separate Release build run for relevant changes. TestFlight uses Xcode Cloud. GitHub API access was denied by the environment proxy, so current rulesets, run history, actual timings and approval counts could not be verified. The repository records a roughly 30-minute PR Mac run on 15 November and a 75-minute docs-only main run before existing path filtering; these are historical observations, not before/after measurements for this change.

Benchmark comparable PRs and main pushes with GitHub Actions job start/end times and cache-hit status before and after merge. Compare Node install duration, total critical-path duration, iOS build duration and Xcode Cloud archive/upload duration. Report sample size and skipped jobs. No percentage saving is claimed until runs are measured. A Mac and authorized GitHub/Xcode Cloud access are needed to validate hosted iOS and release behavior.
