# A pull request's Mac job runs the unit tests and a two-test launch check; the UI smoke classes run on `main`

- **Date:** 2026-11-25
- **Decided by:** owner ("remove unnecessary checks … reduce the time for pushing code to minimum", then "think very hard if they can be done or removed, fixed … you can do it"); which checks, proposed by an agent in this pull request
- **Status:** proposed; applied by the pull request that adds this file, **not yet run on a hosted Mac**
- **Replaces:** the part of ADR-811 and decision `2026-11-18-nightly-full-ui-and-release` that has every pull request run the UI smoke classes

## Why
Measured from the job logs of pull request run 44473265852 (19 Nov 2026), a change that reaches the app:

| Part of `ios-build` | Time |
|---|---|
| build-for-testing | 5.8 min |
| unit tests (195 tests take 33 s; the simulator's first boot takes 3.5 min, tear-down 1.4 min) | 5.7 min |
| simulator restart | 0.5 min |
| UI smoke pass (29 tests take 10.7 min; 66 s waiting for `xcodebuild` after the restart, a second set-up and tear-down) | 13.4 min |
| whole job | 26 min |

Every Linux group finished within 7 minutes of the same run, so the Mac job is the time a pull request waits.

What the UI tests caught, read from the failed jobs of the 150 runs before 25 Nov 2026 (14 to 25 Nov):

- UI tests: 10 failed runs. Two were a pull request changing the UI tests' own wait helper (#524, runs #1722 and #1728). Eight were on pushes to `main` after the pull request had passed, on commits that could not have caused them (a docs merge, a one-line workflow bump, server prompts) or that passed again with nothing fixed. None was traced to a fault in the app.
- Unit tests and the build step: no failed run in the sample (failures inside runs that a newer push cancelled were not read). One push to `main` (#1707) ran into the job's 100-minute limit; #530's commit message puts that day's hang down to a race in `MessagingTokenRenewalTests`. That log was not read.
- The four failures that were real faults in a pull request were all in the Linux `swift` job.

## Decision
1. `DODDY_UI_TESTS=launch` (new, `scripts/ci.sh`): the unit tests and two UI tests, `LaunchSmokeTests/testFirstLaunchGoesStraightHomeAndNeverStartsVoice` and `WelcomeUITests/testSkipGoesToTheLastChapter`, in one `xcodebuild test-without-building` pass. No simulator restart, no second test session. A UI test that fails only because the app would not start is run once more on a restarted simulator, as before (decision `2026-11-13-ui-launch-retry`).
2. Pull requests run `launch`. A pull request that changes `DoddyUITests/` runs `smoke` (`ui_smoke` from `scripts/ci_needs_mac.sh`); one labelled `full-ui-tests` runs every UI test, as before.
3. Pushes to `main` still run `smoke`; the nightly run and runs by hand still run everything. Required checks (`core`, `ios-build`, `sensitive-paths`) keep their names.

## Consequences
- Expected Mac time for a pull request: about 13 minutes instead of 26 (build 5.8, first boot 3.5, tests about 1, set-up and tear-down about 2.5). An estimate from the log above, not a measurement.
- A pull request that breaks a flow only the smoke classes cover (Settings pages, the Back Tap card, Polish, legal acceptance) is now found by the push to `main`, about half an hour after the merge, not before it. Xcode Cloud builds `main` for TestFlight, so such a build can reach a tester before the red run is read.
- ADR-561's risk comes back for the two launch tests: the first UI launch right after the unit tests was slow once (20 Oct 2026). The launch retry covers the "app would not start" case; an assertion that times out fails the job.
- To go back: set `DODDY_UI_TESTS` for pull requests to `smoke` in `.github/workflows/ios.yml` (one expression).

## Evidence
Run on Linux: `scripts/test_ci_mac_phases.sh` (stand-ins for `xcodebuild` and `xcrun`: one pass, the three `-only-testing` arguments, no restart, the SKIPPED lines), `scripts/test_ci_needs_mac.sh` (`ui_smoke`), `scripts/ci.sh --only checks`. **Not run:** anything on a Mac. No hosted job has started since 20 Nov 2026 (`docs/OWNER_QUEUE.md` 123), so the first pull request after Actions works again is the measurement.
