# Doddy gateway (M2)

A small server the iPhone app talks to for typed questions. It exists so that **no AI key is ever on the phone**.
It is written, tested and **not deployed**. Nothing here has been run against the real OpenAI API.

```
iPhone ──HTTPS──▶ POST /api/register   invite code + random device id  ─▶ 24 h bearer token
iPhone ──HTTPS──▶ POST /api/assist     token + question + selected notes ─▶ answer + cited note ids
                                         │
                                         └──HTTPS──▶ OpenAI POST /v1/responses  (store:false, strict JSON schema)
```

Contract and data flow: [`docs/architecture/ASSISTANT_GATEWAY.md`](../docs/architecture/ASSISTANT_GATEWAY.md).
Shared wire fixtures (read by both these tests and the Swift tests): [`schemas/fixtures/`](../schemas/fixtures).

## Develop and test

```sh
cd gateway
npm install           # dev tools only (TypeScript types); the gateway has no runtime dependencies
npm test              # 63 tests, Node >= 22, no network, no keys (the shared store is faked in-process)
npm run typecheck     # tsc over api/ and src/ (JSDoc types)
```

## Environment variables (names only; set them in the Vercel project, never in git)

The secret ones live in 1Password and reach the Vercel project `doddy-gateway` through `tools/secrets/sync.mjs` (ADR-493, `docs/security/SECRETS_1PASSWORD.md`). `GATEWAY_TOKEN_SECRET` is recorded there but never written by the tool. Run locally with them: `op run --env-file=.env.op -- vercel dev`.

| Name | Required | Meaning |
|---|---|---|
| `OPENAI_API_KEY` | yes | Provider key. Server only. |
| `OPENAI_MODEL` | yes | Exact model id from your OpenAI account. **No default on purpose**: model ids change and could not be verified when this was written. |
| `GATEWAY_TOKEN_SECRET` | yes | 32+ random characters (`openssl rand -base64 48`). Rotating it signs every device out. |
| `GATEWAY_INVITE_CODES` | yes | Comma-separated codes for private-beta testers, **each at least 16 characters** (shorter ones make the gateway refuse to start). Removing a code revokes it **and every token minted with it** at once. |
| `GATEWAY_RATE_PER_MINUTE` / `_PER_DAY` / `GATEWAY_INVITE_PER_DAY` / `GATEWAY_GLOBAL_PER_DAY` | no | Defaults 10 / 200 / 600 / 2000 (per device, per device, per invite code, everyone). Device ids are chosen by the client, so the per-invite cap is the real per-tester limit. |
| `UPSTASH_REDIS_REST_URL` + `UPSTASH_REDIS_REST_TOKEN` (or `KV_REST_API_URL` + `KV_REST_API_TOKEN`) | **yes before inviting anyone** | Shared rate-limit and budget store (Upstash Redis REST; a Vercel Marketplace Redis/KV store sets the `KV_*` names). URL must be `https://`. Setting only one of the pair is refused. |
| `REQUIRE_SHARED_LIMITS` | optional | `1` = refuse to serve (`503 notConfigured`) unless the shared store is configured. Always on when Vercel sets `VERCEL_ENV=production`; elsewhere a missing store means per-instance limits (dev/preview only, warned in the logs). |
| `DAILY_BUDGET_USD` | no | Hard cap on estimated provider spend for **everyone** per UTC day. Default `1.00`. |
| `DAILY_BUDGET_PER_INSTALL_USD` | no | Same cap for **one install** (device id) per UTC day. Default `0.25`. |
| `DAILY_BUDGET_PER_INVITE_USD` | no | Same cap for **all installs on one invite code** per UTC day (device ids are chosen by the app, so this is what stops one invite minting fresh budgets). Default: half of `DAILY_BUDGET_USD`. |
| `OPENAI_PRICE_INPUT_PER_MTOK_USD` / `OPENAI_PRICE_OUTPUT_PER_MTOK_USD` | **set them** | Your model's price in USD per 1M input / output tokens, copied from OpenAI's pricing page. Defaults `10` / `40` are **pessimistic placeholders, not a real price** (no model price could be verified when this was written); with them the cap trips early, which is the safe direction. A `placeholderPrices` warning is logged until both are set. |

If a required variable is missing, or a limit/budget/store variable is set but invalid, every endpoint answers `503 notConfigured` (fails closed) and logs only the variable *names*.

## Limits and the daily spend cap (ADR-124, ADR-125)

```
/api/assist: token ─▶ rate limits (device/min, device/day, invite/day, global/day; stop at first refusal)
                  ─▶ validate ─▶ reserve worst-case cost on [everyone today, this install today, this invite today]
                  ─▶ OpenAI ─▶ replace the reservation with usage × price ─▶ answer
```

- **Shared counters.** `SharedRateLimiter` (`src/ratelimit.js`) keeps fixed windows in the shared store: one `MULTI/EXEC` of `INCR` + `EXPIRE` per check over the Upstash REST API (`src/store.js`, plain `fetch`, 2 s timeout, zero dependencies). All instances see the same counts. Store keys are HMAC-ed with `GATEWAY_TOKEN_SECRET`, so the store holds no device ids, invite tags or IP addresses. Up to 4 store round trips per question (checks run in order so a flooding device never consumes the shared counters).
- **Daily spend cap.** Before calling OpenAI the gateway reserves `(prompt bytes + 500) × input price + 800 × output price` (an upper bound per call: tokens never exceed UTF-8 bytes, and 800 is `max_output_tokens`); a retry after a 5xx first reserves the same amount again, and is skipped if that would pass a cap with atomic `INCRBY` on both scopes. If either total would pass its cap the reservation is rolled back and the request is refused: `429 dailyLimitReached` "Doddy's daily limit is reached; try again tomorrow." with `retryAfterSeconds` until the next UTC midnight. After the call the estimate is replaced by the provider-reported tokens × your prices; a 4xx rejection releases it; a timeout, 5xx or missing usage keeps the full estimate booked (it may have been billed), and so does a 5xx attempt that was retried. Each answer's cost is logged as `costMicros`.
- **Fail closed.** Store configured but unreachable (network, timeout, non-2xx, error reply) → `503 providerUnavailable`, logged with `cause: limitStore`, provider not called, never a fallback to memory. If the store fails *after* the answer is paid for, the answer is still returned and `cause: settleFailed` is logged (the estimate stays booked).
- **No store configured.** Per-instance memory adapters, so local development works unchanged; a `limitsPerInstance` warning is logged once per instance. A Vercel production deployment (`VERCEL_ENV=production`) refuses to serve without the store, so this cannot happen there.
- **What it is not.** Estimates and prices are only as good as the configured prices; cached-input discounts are ignored (over-counts). The OpenAI project's own hard limit stays the backstop.

## Owner checklist before the first real call (none of this has been done)

1. **Provider budget.** Create a dedicated OpenAI project with a hard monthly spend limit (OpenAI dashboard → project → Limits). This is the second line of defence behind `DAILY_BUDGET_USD`, and the only one that does not depend on prices you typed in.
2. **Pick the model** and set `OPENAI_MODEL`. Confirm it supports Responses-API Structured Outputs; the first real call will tell, and a wrong id fails with `503 providerUnavailable`.
3. **Create the Vercel project** from `gateway/` (root directory), add the variables above, deploy. Ask before deploying: it creates a billable cloud resource.
4. **Shared limits store (built, not yet created).** Create one Redis store: either Vercel dashboard → Storage / Marketplace → Upstash Redis, connected to the gateway project (it adds `KV_REST_API_URL` / `KV_REST_API_TOKEN`), or an Upstash Redis database whose REST URL and token you add as `UPSTASH_REDIS_REST_URL` / `UPSTASH_REDIS_REST_TOKEN`. Pick a region near the Vercel function region. Then set `REQUIRE_SHARED_LIMITS=1`, `DAILY_BUDGET_USD` (and optionally `DAILY_BUDGET_PER_INSTALL_USD`), and both `OPENAI_PRICE_*_PER_MTOK_USD` for your model. Creating the store may add a cost or plan; it needs your approval. Never commit the token.
5. **Logging and retention.** In Vercel project settings review log retention and any log drains. The code logs no text (`src/logging.js` allow-list, covered by tests), but platform request logs (IP, path, status) are Vercel's.
6. **Legal and privacy.** OpenAI data-processing terms, region/transfer, retention, and the App Store privacy label are owner/legal decisions (`docs/security/PRIVACY_GDPR_AI_ACT.md`). Nothing here is a compliance claim.
7. Put the deployed `https://…` address into the app: Settings → Ask Doddy → Gateway address, then give each tester an invite code.

## Known limitations (also in `docs/implementation/M2_STATUS.md`)

- Anonymous invite codes are a private-beta gate, not identity. Anyone holding a code can register devices (300 registrations per code per day, 20 per address per hour; shared across instances once the store is configured) and the invite code is the only credential. Use long random codes. App Attest or accounts are future work.
- Client addresses come from Vercel's `x-vercel-forwarded-for` / `x-real-ip` headers. Deployed directly on Vercel that is right; behind another proxy those headers can be spoofed or collapse everyone into one bucket. IPv6 clients are bucketed by /64.
- Without the shared store the limits and the daily budget are per instance (above). There is no per-user monthly quota. The shared adapters were tested only against an in-process fake of the Upstash REST API; **no real store has been created or called.**
- Nothing stops a model from stating a personal "fact" without citing a note; the app labels any uncited answer *"Not from your notes"* rather than pretending to catch it.
