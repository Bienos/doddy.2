# The least checking between a push and a merge: pull requests build the app and run the Linux groups; every test runs nightly

- **Date:** 2026-11-25
- **Decided by:** owner: "remove as much checks as possible … remove the process of pushing the code, checking the code to minimum"
- **Status:** applied by the pull request that adds this file; **not yet run on a hosted runner**
- **Replaces:** in ADR-811 and decisions `2026-11-15-faster-mac-ci` and `2026-11-18-nightly-full-ui-and-release`, the parts that run tests on the Mac for every pull request and run CI on every push to `main`; in decision `2026-11-08-agents-merge-their-own-pull-requests`, the `owner-approved` label; in `docs/decisions/2026-11-07-agent-rules-and-records.md`, the change note per pull request

## Why
Pull request run 44473265852 (19 Nov 2026), a change that reached the app: the Mac job took 26 minutes, of which the build was 5.8 and the tests and simulator about 20; every Linux group finished within 7. In the 150 runs from 14 to 25 Nov, no unit or UI test failure was traced to a fault in the app: ten UI-test failures were a pull request changing the tests' own wait helper (2) or failures that passed again with nothing fixed (8, all on pushes to `main`). The four real faults caught were all in the Linux `swift` job.

## Decision
1. **Pull requests:** the `changes` job picks the Linux groups the change can reach (`checks` always). `ios-build` compiles the app, its extensions and both test targets and runs no test (`DODDY_MAC_TESTS=none`), unless the pull request has the `full-ui-tests` label. Docs and design files no longer start the `swift` group, except the five a Swift test reads (`scripts/ci_groups.sh`).
2. **Pushes to `main` run nothing.** The nightly run (02:17 UTC) and runs by hand run every group, every unit and UI test, the native island test and the Release compile.
3. **`sensitive-paths` never fails** and needs no label. It still lists the sensitive files. It keeps its name because the `main` ruleset requires it, so no setting changes.
4. **Agents** (`AGENTS.md`, "Minimum process from push to merge"): merge on green; run only the test nearest to the change before pushing; no change note, decision file or `STATUS.md` edit unless the owner asks; a two-part pull request description.
5. Kept from the same pull request: backend tests in three shares side by side, apt from the HTTPS mirror first, the SwiftPM cache saved only off pull requests, the `.xcresult` kept only for failed and nightly runs, and a flaky web test fixed.

Required checks (`core`, `ios-build`, `sensitive-paths`) keep their names.

## Consequences
- Expected: a pull request that reaches the app waits for about 8 minutes of Mac (checkout, build, artifact upload) instead of 26; one that reaches only servers or docs waits for its slowest Linux group (about 3 to 6 minutes). Estimates from the 19 Nov logs, to be confirmed by the first runs.
- An app change that compiles but breaks a unit or UI test merges and is found by the next nightly run, up to a day later. Xcode Cloud builds `main` for TestFlight, so such a build can reach testers before anyone reads the red nightly run. Read the nightly result before shipping a TestFlight build to anyone else.
- Two pull requests that each pass but conflict in behaviour are no longer tested together before the nightly run.
- Sensitive files (signing, deploy configs, migrations, CI, agent rules) merge with no owner step.
- To go back: in `.github/workflows/ios.yml`, `DODDY_MAC_TESTS` for pull requests to `all` and `DODDY_UI_TESTS` to `smoke`; add `push: branches: [main]` back; `git revert` the pull request for the rest.

## Evidence
Run on Linux: `scripts/ci.sh --only checks` (the stand-in tests of the build-only mode, the group choice and the sensitive-path list included), the backend's three shares (1101 tests, 0 failures), the web test. **Not run:** anything on a hosted runner (Actions started no job from 20 Nov until the repository was made public on 25 Nov) or on a Mac.
