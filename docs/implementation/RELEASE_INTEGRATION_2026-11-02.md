# Release integration, 2 November 2026

## Scope and source

Default inspected: `6a5ca8fdb614433ffb96f6637ddeae968ba2b0b9`, Bienos/doddy.2. Owner authorizes safe tested release integration; #168 screenshot testing and #161 invoices are excluded.

#166 is reconciled with merged #164. Linux groups and caches are retained, with the original Mac --app-only path, single UI worker and test timeouts. Paths that feed shared fixtures select their consumers.

The voice branch starts from the reconciled CI tree and selects #169 commits b19161f2, 819e9407, f3fd60b7 and 4b992067. It preserves #162's cancellation/TLS/timeout taxonomy rather than replacing it. Additional fixes make caller cancellation finish promptly and invalidate SDK callbacks after a startup deadline.

## Behavior and policy evidence

DOD-02, DOD-08, DOD-09 and UX-02: a timeout reports failure, never a successful conversation or an offline-only error. Startup is bounded to ten seconds after credential/context preparation; a late provider result is ended. Pre-started credential requests are cancelled when the start exits. DOD-11: prefetch remains after consent and microphone approval. Warmup sends no token, body or user content, uses the existing HTTPS server/transport and is throttled. No action-approval rules change.

## Validation before merge

- Local checks/guards/generators/spec validation: passed with Python 3.15 and PyYAML.
- Focused Swift tests: 22 passed, zero failures (offline 3, warmup 3, deadline/cancellation 7, token 9).
- Full local Swift suite: 2,247 passed (2,048 core, 190 persistence, 9 design-token tests), zero failures.
- Real Xcode build, app unit/UI tests and current hosted CI: required before merge; consult PR #170 for the final evidence.
- No physical iPhone, live microphone/provider call, paid API, deployment or live-agent mutation has been performed.

## Deferred

Original #169 stays draft: daily service quotas, texting/country controls, database migration, remote account erasure, Outlook/backend changes and prompt trim require separate service/behavior validation and deployment planning. Default-branch service changes can deploy automatically, so those paths are excluded from this app integration. #168 and #161 remain untouched. No TestFlight upload is part of this repository-only task.
