iPhone, step 4a of decision `2026-11-08-required-account`: DoddyCore `Account/DoddyAccount.swift` holds the Doddy account logic, with nothing in the app using it yet.
- `DoddyAccountClient`: Supabase Auth requests (email code send and verify, Apple identity token, Google with PKCE, refresh, sign-out), each returning a checked session or a plain error.
- Rules: `DoddyAccountConfig`, `DoddyAccountSession`, `EmailAddress`, `EmailCode`, `PKCEPair`.
- `DoddyAccountLink`: the backend's `link-device` and the messaging server's `accounts/sign-in`.
Platforms: shared package only (iPhone first; Watch and Mac paused, ADR-572).
Ran, with Swift 6.1.3 on Linux, the same version CI uses: `make test-core`, 2,726 tests, 0 failures (16 new in `DoddyAccountTests`); `scripts/ci.sh --only checks` PASS except the Studio renderers (no reportlab here). Not run: the iPhone app build (no Xcode here; nothing in the app calls this yet).
