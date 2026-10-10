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
npm test              # 42 tests, Node >= 22, no network, no keys
npm run typecheck     # tsc over api/ and src/ (JSDoc types)
```

## Environment variables (names only; set them in the Vercel project, never in git)

| Name | Required | Meaning |
|---|---|---|
| `OPENAI_API_KEY` | yes | Provider key. Server only. |
| `OPENAI_MODEL` | yes | Exact model id from your OpenAI account. **No default on purpose**: model ids change and could not be verified when this was written. |
| `GATEWAY_TOKEN_SECRET` | yes | 32+ random characters (`openssl rand -base64 48`). Rotating it signs every device out. |
| `GATEWAY_INVITE_CODES` | yes | Comma-separated codes for private-beta testers, **each at least 16 characters** (shorter ones make the gateway refuse to start). Removing a code revokes it **and every token minted with it** at once. |
| `GATEWAY_RATE_PER_MINUTE` / `_PER_DAY` / `GATEWAY_INVITE_PER_DAY` / `GATEWAY_GLOBAL_PER_DAY` | no | Defaults 10 / 200 / 600 / 2000 (per device, per device, per invite code, everyone). Device ids are chosen by the client, so the per-invite cap is the real per-tester limit. |

If a required variable is missing every endpoint answers `503 notConfigured` (fails closed) and logs only the variable *names*.

## Owner checklist before the first real call (none of this has been done)

1. **Provider budget.** Create a dedicated OpenAI project with a hard monthly spend limit. This, not the in-code limiter, is what actually caps cost (see below).
2. **Pick the model** and set `OPENAI_MODEL`. Confirm it supports Responses-API Structured Outputs; the first real call will tell, and a wrong id fails with `503 providerUnavailable`.
3. **Create the Vercel project** from `gateway/` (root directory), add the variables above, deploy. Ask before deploying: it creates a billable cloud resource.
4. **Shared rate-limit store.** `MemoryRateLimiter` counts per function instance, so on serverless it is a best-effort brake only. Before inviting anyone else, implement the `RateLimiter` port (`src/ratelimit.js`) on a shared store (Vercel KV / Upstash) and keep the provider budget as the backstop.
5. **Logging and retention.** In Vercel project settings review log retention and any log drains. The code logs no text (`src/logging.js` allow-list, covered by tests), but platform request logs (IP, path, status) are Vercel's.
6. **Legal and privacy.** OpenAI data-processing terms, region/transfer, retention, and the App Store privacy label are owner/legal decisions (`docs/security/PRIVACY_GDPR_AI_ACT.md`). Nothing here is a compliance claim.
7. Put the deployed `https://…` address into the app: Settings → Ask Doddy → Gateway address, then give each tester an invite code.

## Known limitations (also in `docs/implementation/M2_STATUS.md`)

- Anonymous invite codes are a private-beta gate, not identity. Anyone holding a code can register devices (limited to 300 registrations per code per day per instance) and the invite code is the only credential, so guessing is limited only by the per-instance limiter until a shared store exists. Use long random codes. App Attest or accounts are future work.
- Client addresses come from Vercel's `x-vercel-forwarded-for` / `x-real-ip` headers. Deployed directly on Vercel that is right; behind another proxy those headers can be spoofed or collapse everyone into one bucket. IPv6 clients are bucketed by /64.
- The rate limiter is per instance (above). There is no per-user monthly quota.
- Nothing stops a model from stating a personal "fact" without citing a note; the app labels any uncited answer *"Not from your notes"* rather than pretending to catch it.
