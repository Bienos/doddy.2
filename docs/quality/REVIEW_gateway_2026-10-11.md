# Review — `gateway` (2026-10-11)

Read-only review. No code changed. Scope: `gateway/src/**`, `gateway/api/*`, `vercel.json`, README (grep), and the test list.
Status per README: written and tested, **not deployed**, and never run against the real OpenAI API.

## Tests run

| Command | Environment | Result |
|---|---|---|
| `npm ci && npm test` | Node 22.22.0, Linux container | **63 pass, 0 fail, 0 skipped** |
| `npm run typecheck` | tsc 5.7.2 | clean (exit 0) |

Not run: real OpenAI, a real Upstash/Vercel KV store, or a Vercel deployment. All provider and store responses in the tests are fakes.

## Findings (most severe first)

No critical issues found. Several areas are solid and well tested:
- Invite-bound HMAC tokens with constant-time checks.
- Fail-closed shared limits.
- Atomic budget reservation.
- Citation aliases limited by the schema.
- An allow-list for log fields.
- Strict request validation.

### Medium

1. **`src/runtime.js:39-49` + `src/config.js:96`**
   - **Problem:** In production, a missing limits store fails *open*. Unless `REQUIRE_SHARED_LIMITS=1` is set, a deploy without the Redis store runs on per-instance memory limits and budgets. Today only a log line warns about it.
   - **Failure scenario:** On Vercel, each warm instance gets its own $1/day budget and its own rate counters. The real spend cap becomes $1 × the number of instances. The README asks the owner to set the flag, but forgetting it is silent.
   - **Fix:** Treat `VERCEL_ENV === "production"` as `required` in `sharedStoreEnv`. Add a test.

2. **`src/openai.js:23-30`**
   - **Problem:** No reasoning setting is sent, and `max_output_tokens: 800` includes reasoning tokens.
   - **Failure scenario:** If `OPENAI_MODEL` is a reasoning model (gpt-5 family or o-series), reasoning can use up the 800 tokens. The response comes back `status: "incomplete"` and the user gets `providerUnavailable`, while the full estimate stays booked against the budget. This is unverified against the real API (no key exists), but `server/messaging` already guards this case for its writer (`reasoning_effort: "low"`).
   - **Fix:** For `/^(gpt-5|o\d)/` models send `reasoning: { effort: "low" }`. Map `incomplete_details.reason === "max_output_tokens"` to its own log cause.

### Low

3. **`src/http.js:252-256`**
   - **Problem:** IPv4-mapped IPv6 addresses (`::ffff:1.2.3.4`) go through `ipv6Prefix64`, and every one of them collapses to `0:0:0:0::/64`.
   - **Failure scenario:** All such clients share one registration bucket (20 per hour), so 20 sign-ups lock everyone else out.
   - **Fix:** Unwrap `::ffff:a.b.c.d` to the IPv4 address first, as `server/messaging/src/news/safeFetch.ts:27` does.

4. **`src/http.js:253-254`**
   - **Problem:** If neither forwarding header is present, every client becomes `unknown`.
   - **Failure scenario:** Behind a misconfigured proxy, the 21st registration in an hour blocks all new testers.
   - **Fix:** Keep the bucket, but log `cause: "noClientAddress"` so the problem is visible (the README already warns about proxies).

5. **`src/config.js:116-119`**
   - **Problem:** `int()` silently falls back to the default when a value is set but invalid (for example `GATEWAY_RATE_PER_DAY=2O0`), unlike `positive()`, which refuses to start.
   - **Failure scenario:** The owner thinks they lowered a limit, but the default stays in force.
   - **Fix:** Return `null` for set-but-invalid values and add the variable name to `missing`, as `positive()` does.

6. **`src/assist.js:33-38`, `src/register.js:182-189`**
   - **Problem:** The catch-all logs `code: providerUnavailable` with no cause.
   - **Failure scenario:** A gateway bug looks exactly like an OpenAI outage in the logs.
   - **Fix:** Add `cause: "unexpected"` (it already fits the allowed log format).

7. **`src/openai.js:34-47` + `src/assist.js:119`**
   - **Problem:** When a 5xx is retried, only the second call's usage is settled.
   - **Failure scenario:** If the first call was billed anyway, that cost is never counted, so the budget under-counts. OpenAI normally doesn't bill 5xx, so the impact is small.
   - **Fix:** Reserve the estimate twice when a retry is possible, or add the first attempt's usage if it was reported.

8. **`src/assist.js:104-107`**
   - **Problem:** The per-install budget is keyed by a device id the client picks.
   - **Failure scenario:** Re-registering with a new id resets that install's budget. This is bounded by the invite request cap (600 a day) and the global budget, but one invite can spend the whole day's budget.
   - **Fix:** Add a third scope `inv:${inviteTag}` with its own cap (e.g. `DAILY_BUDGET_PER_INVITE_USD`, default half the daily budget).

9. **`src/validate.js:146-154`**
   - **Problem:** `bodyBytes` (64 KiB) is smaller than the worst case the character limits allow. With 4-byte characters, 12k memory characters plus 6×2k turns plus 2k of user text is about 104 KiB.
   - **Failure scenario:** A request that passes every per-field limit is refused as `payloadTooLarge`.
   - **Fix:** Raise `bodyBytes` to 128 KiB, or document a byte budget that the app enforces. The app side was not checked.

### Not code-enforced (claims to limit)

- **"Never say you saved, set, sent…" (`src/prompt.js:105`) is prompt-only.** The answer text isn't checked for action claims. The gateway has no tools, so nothing is actually done, but a model reply could still *say* it did something. DOD-08 compliance here rests on the prompt.

## Missing tests

- IPv4-mapped client addresses.
- Missing forwarding headers.
- Invalid integer env values.
- A reasoning model returning `incomplete`.
- A retried 5xx where the first call reports usage.
- A request at the maximum character limits with multibyte text (finding 9).

## Top 5 fixes

| # | Fix | Finding | Effort | Risk |
|---|---|---|---|---|
| 1 | Require the shared store when `VERCEL_ENV=production` | 1 | S | Low |
| 2 | Send a low reasoning effort for reasoning models; log incomplete-by-length | 2 | S | Low (unverified against the real API) |
| 3 | Refuse invalid integer env values | 5 | S | Low |
| 4 | Unwrap IPv4-mapped client addresses | 3 | S | Low |
| 5 | Per-invite daily budget scope | 8 | M | Low (new env variable) |

## Constitution evidence log

- **DOD-06:**
  - Citations are limited by the schema to this request's aliases (`prompt.js:133-142`) and checked again in code (`assist.js:140-143`), with tests (A-14).
  - Real memory ids never reach the provider (A-16 test).
- **DOD-08:**
  - Malformed or empty model output becomes an error, never a guessed answer (`assist.js:136-139`), tested.
  - Gap: action claims in answer text are prompt-only (see above).
- **DOD-11:**
  - `store: false` is sent to OpenAI.
  - Logs use an allow-list of field names and shapes (`logging.js`), tested.
  - Store keys are HMACed, so no raw ids sit in Redis (tested).
- **Claims to limit:** "Tested" means against fakes only. No real provider, store or deploy was used. The budget relies on placeholder prices until the owner sets real ones.

---

## Fix status (2026-10-11, owner approved "fix all")

| # | Status | Commit |
|---|---|---|
| 1 | fixed: `VERCEL_ENV=production` requires the shared store | `4aa95ce` |
| 2 | fixed: `reasoning.effort=low` for gpt-5/o-series; a cut-off answer logs `cause=outputLimit` and is billed at reported usage. **Not verified against the real API.** | `c95dbff` |
| 3 | fixed: `::ffff:a.b.c.d` unwrapped to IPv4; the test fails on the old code | `aeeb506` |
| 4 | fixed: `cause=noClientAddress` logged on registration | `aeeb506` |
| 5 | fixed: set-but-invalid integer settings → `503 notConfigured` naming the variable | `ecf2a99` |
| 6 | fixed: catch-all logs `cause=unexpected` | `e953922` |
| 7 | fixed: a retry first reserves one more estimate (skipped if over a cap); the failed attempt keeps its estimate booked. My first version reserved 2× up front; that was replaced because it halved the largest request the default budget allows. | `108873e`, `fd62a17` |
| 8 | fixed: `inv:<tag>` budget scope, `DAILY_BUDGET_PER_INVITE_USD` (default half the daily budget) | `408f9f8` |
| 9 | fixed: `bodyBytes` raised to 128 KiB; tested with a request at every limit using 4-byte characters | `e056c6b` |
| Prompt-only action claims | unchanged: documented as a claim limit, with no code check added | — |

Tests after the fixes: `npm test` → **73 pass, 0 fail**; `npm run typecheck` clean (Node 22.22).

**Noticed while fixing (not changed, owner decision):** with the placeholder prices (10 / 40 USD per 1M tokens) and the default per-install budget ($0.25), any prompt over about 21 KB is refused as `dailyLimitReached` on the first request. A request with several long notes is that size. Set the real `OPENAI_PRICE_*_PER_MTOK_USD` for the chosen model before testers use it.

**Deploy notes:**
- New optional variable `DAILY_BUDGET_PER_INVITE_USD`.
- A production deploy without Redis now refuses to serve.
- Invalid `GATEWAY_RATE_*` values now refuse to serve instead of using defaults.
