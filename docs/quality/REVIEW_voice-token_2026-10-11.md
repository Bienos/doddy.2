# Review — `server/voice-token` (2026-10-11)

Read-only review. No code changed. Scope: all of it (`src/handler.js`, `api/voice-token.js`, README, tests; 127 lines of code).
Status per README: **not deployed**.

## Tests run

| Command | Environment | Result |
|---|---|---|
| `npm test` (no dependencies) | Node 22.22.0, Linux container | **6 pass, 0 fail** |

Not run: a real ElevenLabs token request or a Vercel deploy.

## Findings (most severe first)

No critical or medium issues found. The service is small and does one job:
- Constant-time code comparison.
- Codes shorter than 16 characters ignored.
- The API key stays on the server.
- Token responses use `no-store`.
- Logs carry no codes or tokens.
- Upstream bodies are never forwarded.
- Fails closed when not configured.

### Low

1. **`src/handler.js:53-88` — no per-tester limit**
   - **Problem:** One access code can mint tokens without limit. The README says the ElevenLabs agent's concurrency and daily limits are the spending cap, but that cap is shared by everyone.
   - **Failure scenario:** One tester, or a leaked code in a script, uses up the agent's daily calls and every other tester gets `voice_busy`. Brute-forcing a code is not realistic (at least 16 characters; the README's generator gives about 192 bits).
   - **Fix:** A per-tester and per-IP fixed-window limit (e.g. 30 tokens per hour per tester), returning 429 `rate_limited`.
     - In memory per instance as a best-effort brake, with a note that a shared store is needed for a hard cap (as in `gateway`).
     - Or document the risk and leave it to the ElevenLabs limits. Owner decision.

2. **`src/handler.js:91-104` — short codes are dropped silently**
   - **Problem:** A configured code under 16 characters is dropped with no log line. If at least one other code is valid, the server starts normally.
   - **Failure scenario:** A tester with a short code always gets `invalid_access_code`, and the logs never say why.
   - **Fix:** Log once per instance `{event: "voice_token_config", ignoredShortCodes: <labels>}`. Labels only, never codes.

3. **`src/handler.js:44-46`**
   - **Problem:** A 405 has no `Allow: POST` header.
   - **Failure scenario:** HTTP clients and tools can't tell from the response which method is accepted. Cosmetic.
   - **Fix:** Add the header.

4. **`package.json:4`**
   - **Problem:** `engines: node >=20`, but the README and Vercel defaults have moved on. `AbortSignal.timeout` and global `crypto.subtle` need Node 18+ / 19+, so this is not a bug.
   - **Failure scenario:** None today.
   - **Fix:** None needed; noted for consistency with the other services (Node 22).

## Missing tests

- Upstream timeout → 504 `upstream_timeout`, if not already covered by the "upstream failures" test (it covers status mapping; a hung fetch was not checked).
- Duplicate code across two labels (the first label wins).
- A code containing `:` (only the first `:` splits label from code).

## Top fixes

| # | Fix | Finding | Effort | Risk |
|---|---|---|---|---|
| 1 | Per-tester / per-IP token rate limit, or an explicit decision to rely on ElevenLabs limits | 1 | S | Low |
| 2 | Log ignored short codes by label | 2 | S | Low |
| 3 | `Allow: POST` on 405 | 3 | S | Low |

## Constitution evidence log

- **DOD-11:**
  - Logs hold the outcome, tester label, upstream status and ms only; tested ("never logs secrets").
  - The token is in the response body only, with `no-store`.
  - The ElevenLabs key never leaves the server.
- **DOD-08:** Not applicable (no external writes).
- **Claims to limit:** Tested with a stubbed `fetch` only. ElevenLabs agent authentication and limits are owner configuration and are not verified here.

---

## Fix status (2026-10-11, owner approved "fix all")

| # | Status | Commit |
|---|---|---|
| 1 | fixed: `DODDY_TOKENS_PER_HOUR` (default 30) per tester per clock hour, per instance (a brake, not a hard cap; ElevenLabs agent limits stay the spending cap). 429 `rate_limited` with Retry-After; ElevenLabs not called. Invalid value → 500 `server_not_configured`. | `103fd06` |
| 2 | fixed: one `voice_token_config` log line per instance names the testers whose codes are too short (labels only) | `103fd06` |
| 3 | fixed: 405 carries `Allow: POST` | `103fd06` |
| 4 | aligned: `engines` set to Node ≥22 like the other services; README updated | `103fd06` |

Tests after the fixes: `npm test` → **9 pass, 0 fail** (Node 22.22). The README documents the new variable and the 429 response.
