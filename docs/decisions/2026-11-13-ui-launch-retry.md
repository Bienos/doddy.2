# A UI test that failed only because the app would not start is run once more

- **Date:** 2026-11-13
- **Decided by:** owner, 13 Nov 2026: "Ok", answering the proposal "a separate small pull request: run the failed tests again after a failed start" (after the review of main's red UI runs)
- **Status:** applied in the pull request that adds this file
- **Replaces:** nothing; narrows what ADR-561 (restart the simulator before the UI tests) leaves open

## Why
After #412 fixed the one real failure (`MotionEvidenceTests.testHiddenPicturesLeaveNoGap`), the full UI suite on `main` was still red, now only for the simulator:
- Run 43412113691 (head 58278785, 13 Nov 2026): `DoddyArtTests.testAFailedSaveNeverPops` failed after 76 s with "Failed to launch … via Xcode: Timed out while launching application via Xcode", and `testEmptyActivityShowsDoddyWaiting` hung for 602 s with "Failed to get launch progress … No failure details provided". Both are the first tests of the run. The other 75 tests ran with 0 failures; the built, unit, island and Release steps passed.
- Run 43412040308 (#414): the same first test failed with "Failed to launch" after 67 s. In run 43412031979 (#418) the same test passed in 41 s.
- No test code ran in these failures: XCTest could not take hold of the app. ADR-561 recorded the same class on 20 Oct (run 39496321722, 12 tests) and restarts the simulator before the UI tests, which has not stopped it.

Each such failure turns a push to `main` red for a reason that says nothing about the app, and one of them held the job for ten minutes.

## Decision
1. `scripts/ci.sh` runs the UI pass through `with_launch_retry`. When the pass fails, `scripts/ci_launch_failures.sh` reads its log. If **every** failed test has only launch errors ("Failed to launch", "Failed to get launch progress", "Timed out while launching") and there are at most 25 of them, the simulator is restarted and **just those tests** run once more. The retry's result is the step's result.
2. Nothing else is retried: an assertion failure, a crash, a failed test with no error line, a mix of launch and other failures, or more than 25 failed tests fails the step as before.
3. The first failure is never hidden: the whole first log stays in the job, a `RETRY:` block names the tests, and the summary adds a `NOTE` line, "UI tests run again because the app would not start", with their names.
4. One retry, not a loop. The native island test (ADR-764) has its own pass and is not changed.

## Consequences
- A real flaky test is not hidden: it fails with an assertion, which this never retries. A test that passes only on its second try after a launch failure is, as far as this log can show, a launch problem, not a test one; the `NOTE` line makes the count visible. If the notes become frequent, the cause is the hosted simulator, and ADR-561's restart needs another look.
- Costs one more launch of a few tests, only when a launch failed. The hang of 602 s in run 43412113691 would still be spent once before the retry; a shorter limit for the first launch is not part of this decision.
- The retry runs the retried tests alone on a fresh boot, so it does not prove that the rest of the suite is unaffected: they already ran and passed in the first pass.

## Evidence
- `scripts/test_ci_launch_failures.sh` (12 cases, run in the `checks` group): the two failures of run 43412113691 are named once each; the runner's timestamps are read; an assertion, a mix, a crash with no error line, 26 failures and a missing log are not retried; 25 are.
- A dry run of `with_launch_retry` with a fake `xcodebuild`: pass (1 call), assertion failure (no retry, exit 65), launch failure then pass (retry names only that test on a restarted simulator, exit 0), launch failure then an assertion failure (exit 65).
- Not run: the function under macOS's bash 3.2 and a real `xcodebuild` (no Mac here); the first real retry will be a hosted run that hits a launch failure. Until then, "the UI suite is green again on `main`" is not shown.
