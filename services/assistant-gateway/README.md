# Assistant gateway (M2)

Server-side gateway that sits between the app and the model provider. The provider key lives only in this process's environment. The app never sees it, and nothing here is committed.

Design source: `docs/architecture/AI_RUNTIME.md` (request contract, citation verifier, error taxonomy).

## Run

```sh
cd services/assistant-gateway
export GATEWAY_TOKEN="$(openssl rand -hex 32)"   # 32+ chars; required
export OPENAI_API_KEY="..."                      # set in your host's secret store, never in git
export OPENAI_MODEL="gpt-4o-mini"                # default; check current pricing and model list first
npm start                                        # listens on PORT (default 8080)
npm test                                         # 13 tests, provider stubbed
```

Requires Node 20+. No dependencies.

## Endpoints

- `GET /health` → `{"ok":true}`
- `POST /v1/assist` with `Authorization: Bearer <GATEWAY_TOKEN>` and a body matching `src/contract.mjs`.

Response: `{"requestId", "answer", "citedIds", "noMatch"}`, or `{"requestId", "error"}` with one of `badRequest`, `notAuthorized`, `rateLimited`, `providerUnavailable`, `timeout`, `invalidCitations`, `invalidResponse`.

## What it guarantees

- **Fails closed:** refuses to start without a 32+ character `GATEWAY_TOKEN`; every `/v1` call needs it (constant-time compare).
- **Key stays server-side:** the key is only sent to `api.openai.com`; it is never echoed or logged.
- **Strict contract:** unknown task types, oversized fields, duplicate memory ids and bad UUIDs are rejected, not coerced. Body capped at 64 KB.
- **Notes are data:** note text goes to the model as JSON, and the system prompt says it is not instructions.
- **Citations are checked:** any cited id that was not sent in the request fails the whole reply (`invalidCitations`). Malformed model output fails as `invalidResponse`. Neither reaches the client.
- **No invented answers:** a memory question with nothing matched returns `noMatch` without calling the model.
- **Content-free logs:** one line per request with request id, status, error code and latency. No prompt, note text or key.
- **Per-session limit:** 20 requests per minute by default.

## Not done (required before any real user)

- **No device or user authentication.** The gateway token is a single shared secret. Anonymous per-device auth and quotas are an open M2 security decision (`AI_RUNTIME.md`, Gateway).
- **Rate limit is in memory.** It resets on restart and does not coordinate across instances.
- **No deployment.** Hosting, TLS, spend limits and provider data terms (DPA, retention, region) are not set up. The production gate in `AI_RUNTIME.md` applies.
- **Live provider call not run.** The tests stub OpenAI. A real run needs a key and a recorded response before M2 can be called done.
- **Model choice unverified.** `gpt-4o-mini` is a default placeholder. Check current model ids and pricing at the time of the live run.
- **App client not built.** The Swift client, the app's HTTP calls and the matching change to `scripts/check_forbidden_capabilities.sh` (which currently forbids app networking) are still to do. They need a Mac to compile.
