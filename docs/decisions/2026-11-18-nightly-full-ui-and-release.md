# The full UI suite and the Release compile run nightly, not on every push to `main`

- **Date:** 2026-11-18
- **Decided by:** owner ("Remove", after the proposal to move the Release build and the full UI suite off the per-merge path)
- **Status:** accepted; proposed by an agent, in this pull request
- **Replaces:** the part of ADR-811 and decision `2026-11-15-faster-mac-ci` that has every push to `main` run the whole UI suite, the native island test and the Release compile

## Why
From the 15 Nov 2026 job logs (see `2026-11-15-faster-mac-ci`): a push to `main` that reaches the app took a Mac for about 27 to 35 minutes of full UI suite plus 13 to 18 minutes of Release compile, in two jobs. Pull requests already run the smoke classes and take about 30 minutes. The estimates below are from those logs, not measured after this change.

## Decision
1. A push to `main` runs `ios-build` with the UI smoke classes (`DODDY_UI_TESTS=smoke`), like a pull request, plus the DoddyCore package tests on Apple's Foundation as before. Every Linux group still runs on every push.
2. `ios-release` (the Release compile for devices) no longer runs on pushes to `main`. It runs in the nightly run and in runs by hand.
3. A nightly scheduled run (02:17 UTC, the default branch) and a run by hand run everything: every UI test, the native island test and the Release compile. A pull request labelled `full-ui-tests` still runs every UI test.
4. Required checks (`core`, `ios-build`, `sensitive-paths`) are unchanged; no ruleset edit is needed.

## Consequences
- Expected: about 20 to 30 Mac minutes less per merge that reaches the app, from the logs above; to be confirmed by the first runs.
- A UI regression outside the smoke classes, or a Release-only compile error, can now sit on `main` up to a day before the nightly run shows it. Xcode Cloud's archive still compiles Release for every build it makes, so a Release-only error does not reach a TestFlight build unseen. Anyone about to ship can start the full run by hand (Actions › iOS build and tests › Run workflow, `all`).
- The nightly run's result is the answer to "did the full suite pass on `main`"; a skipped or red nightly run is not a green one. Read it before a release.
- A scheduled workflow is disabled by GitHub after 60 days without repository activity; that does not apply while the repository is active.

## Evidence
`scripts/ci.sh --only checks` on Linux (see the pull request). Not run here: the hosted Mac jobs and the nightly trigger itself; the first scheduled run and the first push to `main` after the merge are the measurement.
