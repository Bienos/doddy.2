# Security review: messaging server (before first deploy)

Date: 2026-10-10. Scope: `server/messaging/` and the iOS pieces that talk to it
(`DoddyApp/Infrastructure/Server/`, `ServerClient`, `CallsClient`, `NewsClient`). A read-only
review by a separate agent, then fixes in this branch (ADR-175). A review is not a penetration
test; nothing here has run against a deployed server.

## Findings and what was done

| # | Severity | Finding | Status |
|---|---|---|---|
| 1 | High | Rate limits keyed on the raw `Authorization` header, and `trustProxy: true` took the left-most (client-supplied) `X-Forwarded-For`. Unlimited anonymous accounts, each with its own Verify quota: SMS pumping, texting any number repeatedly, more code-guessing room | **Fixed.** Fixed proxy hop count (`TRUST_PROXY_HOPS`, default 1) reads the IP from the right; `/v1/accounts` limited per IP only; signed-in routes per token hash; Verify capped per destination number (3/hour, 6/day, across all accounts, number stored as a hash) and per server per UTC day (`VERIFY_DAILY_CAP`, default 200). Tests: made-up headers still hit 429 on the 11th account; 4th code to one number → 429 |
| 2 | Medium-high | Feed fetch timeout was socket-idle only: a feed dripping a byte every few seconds held the single worker loop (and every queued message) indefinitely | **Fixed.** One overall deadline per fetch, redirects included. Test: a drip server is cut off at the deadline (without the fix the test hangs) |
| 3 | Medium | PIN lockout reset the counter: 5 guesses every 15 min forever; 4-digit PINs allowed; caller ID spoofable | **Fixed.** Lockouts escalate 15 min, 1 h, 4 h, 16 h, then 24 h, reset only by a correct or new PIN; the owner gets a push on each lock (no caller number in it); PINs 6–8 digits (server and app). Test covers escalation and the alert |
| 4 | Low-medium | `news_cache` keyed by the raw feed URL (may carry a private token), never pruned, not removed with the account | **Fixed.** Key is a SHA-256 of the URL; rows not refreshed for 24 h are pruned hourly by the worker; migration clears old rows. Test: cache keys are 64-hex only |
| 5 | Low | SSRF block list missed IPv4-compatible `::/96`, NAT64 `64:ff9b:1::/48`, 6to4 `2002::/16`, Teredo `2001::/32` | **Fixed.** Added; test covers each and a public IPv6 address |
| 6 | Low | Registering another device's APNs token moves it to your account | **Not fixed.** Needs the victim's 64-hex device token, which isn't exposed anywhere; documented here |
| 7 | Low | Escalating lockouts let a caller who can spoof the owner's number lock their PIN entry | **Accepted** as the cost of #3; the owner is notified on every lock and can set a new PIN, which clears it |

Hardening also done: tool secret must be ≥32 characters (server refuses to start); memory
snapshot uploads limited to 60/hour and duplicate ids refused with 400 (was a 500); one memory
that fails to decrypt is skipped instead of failing the whole call search; the server-address
field in Settings and its stored override work in debug builds only, so a shipped build sends its
token only to the built-in address.

Not done (noted for later): key rotation for the memory copy (`key_version` is stored but not
yet used to pick a key); call sessions live 2 h rather than ending with the call; the rate-limit
store is per instance (fine while there is one instance); no HSTS/`nosniff` headers on the JSON
API (Render serves HTTPS only); AI-written news lines are length-checked but come from feed text,
so a hostile feed can shape its own subscriber's message.

Verified as already right: every `/v1/*` query is scoped to the caller's account (no IDOR found);
bearer and session tokens are 256-bit and stored hashed; the tool secret uses a constant-time
compare; Twilio webhooks fail closed and build the signed URL from `PUBLIC_BASE_URL`; schemas are
explicit (no mass assignment); SQL is parameterized; the outbox never blind-retries `unknown` and
erases bodies; the iOS transport refuses redirects, pins the host and caps responses.

## Tests (Linux, Node 22, PostgreSQL 16)
`npm test` in `server/messaging`: **39 tests, 0 failures** (was 35). Two checks were run with
the fix reverted: the rate-limit test failed and the drip-feed test hung, as expected.
