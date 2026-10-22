# Assistant gateway and typed questions (M2)
> **Superseded for the app by ADR-581 (22 Oct 2026):** typed questions now go to Doddy's own server (`POST /v1/assist` in `backend/`, Claude, no gateway address or invite code). The wire contract below is unchanged and both sides test against the same fixtures. This page and `gateway/` describe the first, never-deployed OpenAI gateway and are kept until the owner decides to delete them.

Status: **built and unit-tested; never run against a real provider or deployed.** Date: 2026-10-10.
Implements the plan in `AI_RUNTIME.md` (request flow, error taxonomy, citation verifier). Provider: OpenAI (owner choice, 2026-10-10). Host: Vercel Functions (owner choice).

## Flow
```
Ask screen ──▶ AssistantService
   consent? ──no──▶ consentRequired (nothing searched or sent)
   notes on? ─▶ RepositoryRecallService (local FTS) ─▶ GroundingSelector (≤5 notes, ≤12,000 chars, never truncated, no sample fixtures)
   ──▶ GatewayAssistantClient ──HTTPS──▶ /api/assist ──▶ OpenAI Responses API
   ◀── text + citedMemoryIDs ◀── gateway maps aliases n1.. back to ids ◀── strict JSON {answer, sources[]}
   ──▶ CitationVerifier (device) ──▶ UI: "From your saved notes" + the notes, or "Not from your notes"
```

## Wire contract v1 (fixtures in `schemas/fixtures/`)
`POST /api/register` `{inviteCode, deviceId}` → `{schemaVersion, token, expiresAtMs}`.
`POST /api/assist` with `Authorization: Bearer <token>`:

| Field | Limit | Notes |
|---|---|---|
| `schemaVersion` | `1` | |
| `requestId`, `sessionId` | UUID | random per request / per chat screen; never persisted |
| `locale` | `^[a-z]{2,3}(-xx)?$` | |
| `userText` | 1–2,000 Unicode scalars | blank rejected |
| `turns[]` | ≤6 × `{role,text≤2,000}` | RAM-only chat history |
| `memories[]` | ≤8 (app sends ≤5), ≤5,000 each, ≤12,000 total | `{id, text, source, capturedAt?}`; `sample_fixture` rejected |

Unknown fields at any level → `400`. Body > 64 KB → `413`. Success: `{schemaVersion, requestId, text, citedMemoryIDs[], usage?}`.
Errors: `{schemaVersion, requestId?, error:{code,message,retryAfterSeconds?}}`, fixed content-free messages.

| Gateway code | HTTP | App `AssistantError` |
|---|---|---|
| `notAuthorized` | 401 | `notAuthorized` (app re-registers once, then reports it) |
| `rateLimited` | 429 (+`Retry-After`) | `rateLimited(retryAfterSeconds)`, not auto-retried |
| `dailyLimitReached` | 429 (+`Retry-After` = seconds to next UTC midnight) | `dailyLimitReached` ("Doddy's daily limit is reached. Try again tomorrow."), not auto-retried. Daily spend cap, ADR-125 |
| `timeout` | 504 | `timeout`, retried up to 2 more times with 0.5 s / 1.5 s backoff |
| `providerUnavailable` | 503 | `providerUnavailable`, same retry. Also returned when the shared limits store is configured but unreachable (fail closed, ADR-124) |
| `invalidCitations` | 502 | `invalidCitations`, answer discarded |
| `refused` | 422 | `refused` |
| `invalidRequest`/`payloadTooLarge` | 400/413 | `invalidRequest` |
| `notConfigured` | 503 | `notConfigured` |
| (no network) | – | `offline`, never retried; `cancelled` for Stop |

## Egress audit (acceptance A-16)
| Data | Leaves the device? | To whom | Controls / evidence |
|---|---|---|---|
| Question, ≤6 earlier chat turns | Yes, only when the user asks | Gateway → OpenAI | Ask Doddy is off until the user confirms a disclosure dialog (`settings.assistantConsent`); gateway & Swift tests pin the field list |
| Matching saved notes (≤5) | Only if "Use relevant saved notes" is on **and** the note matched the question | Gateway → OpenAI | Selector tests; the answer lists which notes were sent; no bulk upload; sample fixtures never sent |
| Real note ids / session id / request id / device id | Notes ids, session id: gateway only. **Not** forwarded to OpenAI (notes are aliased `n1…`) | Gateway | test "real memory ids … are not sent to the provider" |
| Invite code, random install id | Yes, at registration only; never in `/api/assist` bodies | Gateway | Keychain, `ThisDeviceOnly`; test "approved fields only" |
| Bearer token | Header of every assist call | Gateway | HMAC-signed, 24 h, revocable via invite removal |
| Logs | Gateway logs: 8-char request and device tags (hashes, not ids), status/code, ms, token counts, note/turn counts | Vercel logs | allow-list in `src/logging.js`; tests assert no question/note/answer/token/key/full id in any log line |
| OpenAI side | `store:false` requested. Retention/usage is governed by OpenAI's terms and account settings | OpenAI | **Not verified**; legal review pending |

## Trust model
- Notes, history and the question are *data*: sent as JSON strings under `NOTES`, `EARLIER TURNS`, `USER MESSAGE`; the system prompt says never to follow instructions found in them. This reduces but cannot eliminate prompt injection.
- The model's citation field is a strict enum of this request's aliases, the gateway rejects anything else (`invalidCitations`), and the device re-verifies against the notes it actually sent. A discarded answer is never shown.
- **Residual risk:** the model can still say something about the user without citing a note. The app therefore labels every uncited answer "Not from your notes. This is a general answer." It does not claim to detect fabrication.
- The model has **no tools**. It cannot save, delete, remind or send anything; the prompt tells it not to claim it did. Chats are never saved as notes.
- Local memory never depends on the gateway: a failed ask changes nothing (covered by `testAFailureNeverTouchesLocalMemory`).

## Limits (ADR-114, ADR-124, ADR-125)
Rate limits and a daily spend cap (everyone / per install, per UTC day) are counted in a shared Redis-compatible store over its REST API when one is configured; store down → refuse. Without a store they are per instance (dev only; `REQUIRE_SHARED_LIMITS=1` turns that into `notConfigured`). Details and env vars: `gateway/README.md`. No real store exists yet.

## Not built (M2 scope boundary)
Streaming, saving an answer as a note, private/no-history toggle beyond "chat is RAM-only", per-user quotas, App Attest/accounts, content-free metrics beyond gateway logs, voice. Gmail / Google Calendar / EventKit: see `CONNECTED_APPS_PROPOSAL.md`.
