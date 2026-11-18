# Spend Mac time on app changes and measure each CI phase

- **Date:** 2026-11-18
- **Decided by:** proposed in response to the owner's request to continue CI speed work after the #532 merge
- **Status:** proposed

## Why

[Main run #1750, attempt 2](https://github.com/Bienos/doddy.2/actions/runs/44378600016/attempts/2) showed Swift at 5m 19s versus 9m 21s in [run #1748](https://github.com/Bienos/doddy.2/actions/runs/43761372011). The supplied step timings were 3m 20s versus 7m 22s. The public run page also showed a passing backend job at 12m 35s and a passing `core` gate while both Mac jobs remained in progress. The checks job took 4m 40s versus 1m 06s, with about four minutes in Python setup in the supplied timings. One run per revision is insufficient to distinguish runner, cache and download variation.

## Decision

Skip Mac jobs for an explicit list of Ubuntu-only helpers and workflows. App inputs, shared CI entry points, unknown paths and missing diffs still request the Mac. Changes spanning both platforms still run both. This avoids an entire hosted Mac job on qualifying PRs and both Mac jobs on qualifying main pushes.

After generating the app project and resolving packages, use the scheme directly. The separate project listing can resolve Swift packages again and is unnecessary. If project generation, pin installation or package resolution fails, report the failure and stop before sending work to Xcode's build or test phases. Keep the existing bounded download retries, package pin checks, simulator test scopes, native Island test and unsigned Release build.

Skip Ubuntu package setup when `dpkg-query` confirms every requested package is installed. Missing dependencies still use the default signed repositories and the existing signed mirror fallback. The fast path depends on the contents of the runner image.

## Measure after merge

Compare successful main and PR runs with comparable changed paths and cache hits. Record queue time separately. For each Mac job, collect the `Elapsed:` entries under the `scripts/ci.sh --app-only` step for package resolution, build, unit tests, simulator restarts and UI tests. Also record the XcodeGen and cache steps, which are outside that script. Compare Python setup separately and note whether it reused installed dependencies. Use the median of several runs for each path and report the number of skipped Mac jobs. Verify that full UI coverage runs on app changes to main. There is no measured hosted time saving for this branch yet.
