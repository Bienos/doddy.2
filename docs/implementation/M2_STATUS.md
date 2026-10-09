# M2 status — real text AI through a server-side gateway
Date: 2026-10-09. Owner instruction: build with an OpenAI model, the cheap one.

## Built (services/assistant-gateway)
| Item | Status |
|---|---|
| Request contract (sessionId/requestId UUID v4, taskType enum, locale, turns, memory snippets) | Built, strict validation, tests |
| Server-side key, bearer-token gate (fail closed) | Built, tests |
| OpenAI chat call with timeout and error mapping (429, 5xx, abort) | Built, tests against a stub |
| Citation verifier (cited ids must be ids sent; malformed reply rejected) | Built, tests |
| No-match answer without a model call | Built, tests |
| Per-session rate limit (in memory) | Built, tests |
| Content-free request logs | Built, test asserts no note, question or key in logs |

## Executed
- `npm test` in `services/assistant-gateway` (Node 22.22.0): **13 tests, 13 pass, 0 fail**. The provider is stubbed. These tests do not show the real OpenAI API responds.
- **Live provider run (2026-10-09):** one `memory_answer` request through the gateway with a test key passed as an environment variable for that process only (not stored). Result: HTTP 200 in 2.3 s; answer "Your locker code is 412." citing the sent note id; model `gpt-4o-mini` accepted by the key. One request only; cost and the current model price were not measured or checked.
- Start-up smoke test: `/health` 200; wrong token → 401 `notAuthorized`.
- `scripts/check_forbidden_capabilities.sh`: PASS. `scripts/verify_imported_pack.py`: PASS.

## Not run / blocked
| Item | Blocker |
|---|---|
| Deployment (TLS, spend cap, host) | Billable infrastructure. Needs owner approval. |
| Provider terms (DPA, retention, region, moderation) | Owner and legal decision (`AI_RUNTIME.md` production gate). |
| Device/user auth and quotas | Open security design decision. Until then the gateway must not be exposed publicly. |
| iOS client (`AssistantClient` over HTTP) | Needs Swift and a Mac to compile. Not built in this pass. |
| Guard update for app networking | Needed once the client exists: the current guard forbids app networking by design. |
| Model choice | `gpt-4o-mini` is a placeholder default. Verify current model ids and prices before the live run. |

## Exit criteria (from MILESTONES.md) still open
- Real provider response confirmed, not mocked — **open** (needs key).
- Offline, cancellation and rate-limit paths in the app — **open** (client not built).
- Citation verifier blocks unknown memory ids — **done in the gateway, tested with a stub**.
- Measured request cost and logs scrubbed of personal text — logs **done**; cost measurement **open** (needs live calls).

## Decisions for the owner
1. Provide an OpenAI key for the gateway host (secret store, not chat or git).
2. Choose a host for the gateway and approve its spend cap.
3. Revoke the key pasted into chat on 2026-10-09 and issue a new one with a spend cap.
4. Approve the device/user auth approach before any user outside the owner's devices.
5. Confirm the cheap model (`OPENAI_MODEL`) after checking current pricing.
