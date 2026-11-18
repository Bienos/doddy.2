CI: avoid installing backend dependencies in the Node job when Playwright Chromium is unavailable and its browser tests will skip. Local agent guidance now calls for risk-based validation.
Decision-only PRs skip heavy Linux suites; test-backed documentation still triggers Swift checks. Required checks and main-branch coverage remain unchanged.
Validation and remaining workflow audit: `docs/decisions/2026-11-18-ci-delivery-speed.md`.
