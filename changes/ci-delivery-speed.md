CI: avoid installing backend dependencies in the Node job when Playwright Chromium is unavailable and its browser tests will skip. Local agent guidance now calls for risk-based validation.
Decision-only PRs skip heavy Linux suites; test-backed documentation still triggers Swift checks. Required checks and main-branch coverage remain unchanged.
The Linux Swift group compiles the five screen-model test suites together instead of rebuilding their shared test target five times.
Validation and remaining workflow audit: `docs/decisions/2026-11-18-ci-delivery-speed.md`.
