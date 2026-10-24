# Doddy server (S1)

TypeScript / Node 22 + Postgres, deployed on Render (EU, `render.yaml` at repo root).
It holds provider keys so the iPhone app never does, and sends updates by **push** and **SMS**.
**Memories are not stored here.** They stay in the app's local SQLite database.

## What it does
| Area | Endpoints |
|---|---|
| Anonymous account (no email/name) | `POST /v1/accounts` → `{accountId, deviceToken}` · `DELETE /v1/account` erases everything |
| Push token | `PUT/DELETE /v1/device/push-token` `{token, environment: sandbox\|production}` |
| Phone (Twilio Verify) | `POST /v1/phone/verification` `{phone}` · `POST /v1/phone/verification/check` `{phone, code}` · `GET/DELETE /v1/phone` |
| SMS opt-in | `PUT /v1/phone/sms-consent` `{consent, textVersion}`: the app records which wording the user agreed to |
| Updates | `POST /v1/updates` `{text ≤640, channels:[push,sms], sendAt?, idempotencyKey}` · `GET/DELETE /v1/updates/:id` |
| Twilio webhooks | `POST /webhooks/twilio/sms` (STOP/START) · `POST /webhooks/twilio/status` (delivery receipts), signature-checked |
| Calls (S2, app) | `GET/PUT /v1/calls/settings` (inbound on/off, outbound consent `calls-v1`) · `PUT/DELETE /v1/calls/pin` · `POST /v1/calls/outbound` ("call me now") · `GET /v1/calls` |
| Memory on calls (opt-in) | `PUT /v1/memory-copy` `{enabled}` (off deletes every copy) · `PUT /v1/memory-copy/snapshot` (replaces the copy) |
| Notes from calls | `GET /v1/call-notes` · `DELETE /v1/call-notes/:id` (after the user confirms or discards) |
| ElevenLabs (S2) | `POST /webhooks/elevenlabs/call-start` · `POST /webhooks/elevenlabs/tools/{verify-pin,search-memories,save-note}`; all need `X-Doddy-Tool-Secret`, tools also `X-Doddy-Session` |
| Errands (ADR-570) | `POST /v1/errands` · `POST /v1/errands/:id/{approve,cancel,ack}` · `GET /v1/errands` · `GET/DELETE /v1/errands/:id` (below) |
| News digests | `GET /v1/news/catalog` · `GET/PUT /v1/news/settings` (topics, own keywords, own feeds, time, zone, channels, language) · `POST /v1/news/feeds/check` · `POST /v1/news/send-now` · `GET /v1/news/digests` |
| Health | `GET /healthz` |

All `/v1` routes except account creation need `Authorization: Bearer <deviceToken>`.

## Rules built in
- SMS goes out only to a **verified** number with **explicit in-app consent** and no STOP since. Consent is re-checked when the message is actually sent.
- STOP cancels queued texts. Only an inbound START re-opens SMS, as carrier rules require.
- Outbox states: `queued → sending → sent | failed | unknown | cancelled`.
  - A timeout or dropped connection becomes `unknown` and is **never resent automatically**, so nobody gets a text twice.
  - A 429 or 5xx refusal is retried with backoff, at most 5 attempts.
- Message text is erased from the database as soon as a message reaches a final state. While queued it is encrypted with `MEMORY_ENCRYPTION_KEY` when that key is set (plain text otherwise).
- Logs carry ids and counts only. No message text, no phone numbers, no tokens.
- A missing provider configuration returns `503 not_configured`. It never fakes success.

## Phone calls (S2)
- **Who:** Doddy answers only verified numbers whose owner turned calls on. Unknown numbers get a polite "add this number in the app".
- **PIN:** every call needs the user's PIN before memories are searched or notes saved, because caller ID can be faked.
  - The PIN is stored as an scrypt hash.
  - 5 wrong tries lock it for 15 minutes.
- **Session:** each call gets a random session key, passed as an ElevenLabs `secret__` variable. That kind of variable is only put in request headers and never shown to the language model.
- **Encryption:** memory copies and call notes are encrypted with AES-256-GCM, bound to account and row, using `MEMORY_ENCRYPTION_KEY`. This is encryption at rest, **not end-to-end**: the server decrypts to answer.
- **Notes:** notes taken on a call wait in the app until the user confirms them. The push notification never contains the note.
- **Outbound:** goes only to the verified number, after consent (`calls-v1`). Limits are 3 per hour and 10 per day. A network timeout is recorded as `unknown` and never redialled.
- **Agent setup:**
  1. Run `node scripts/setup-phone-agent.mjs --dry-run` to see the requests, then run it for real after deploy.
  2. In ElevenLabs, import the Twilio number and assign it to the new agent.
  3. Set the call-start webhook (or use `--set-workspace-webhook`).

## Calls Doddy makes for you (task calls, ADR-500)
Doddy calls a business in Polish for the user, says it's an AI calling on their behalf, asks one question and brings the answer back as a card. Design, docs checked and open legal questions: `docs/decisions/calls.md`. Status and live-test steps: `docs/implementation/CALL_CASES_STATUS.md`. **Not tried on a real call yet.**

| Area | Endpoints |
|---|---|
| App | `GET /v1/call-cases/availability` · `POST /v1/call-cases` (brief → preview built from the exact payload) · `GET /v1/call-cases` · `GET /v1/call-cases/:id` · `POST …/:id/approve {digest, at?}` · `GET …/:id/live?after=` · `POST …/:id/end` · `POST …/:id/takeover` · `POST …/:id/cancel` · `POST …/:id/ack {attemptId, resultDigest}` · `PUT/DELETE …/:id/live-activity` |
| Twilio (signed with the task account's token) | `/webhooks/twilio/task-call/{answer,fallback,connect-ended,status,transcription,takeover-answer,takeover-digits,takeover-status,conference}` |
| ElevenLabs (HMAC on the raw body) | `POST /webhooks/elevenlabs/post-call`: other agents' calls are dropped unread |

- **Our server places the call; ElevenLabs is only the voice** (register-call). The approved payload is encrypted and bound to its digest by a foreign key; what Twilio and ElevenLabs receive is exactly that payload.
- **Hard limits** (code ceilings; env can only lower them): Polish mobile, landline and 800 numbers only; the whole call inside 8:00–23:00 Warsaw time; per user 3/hour and 10/day; per number 2/day per user, 3/day in all, 15 min apart; 50/day in all; one live call per account; longest call 300 s; `TASK_CALLS_KILL_SWITCH=1` stops everything, live calls included. Dial and answer are refused while the live ElevenLabs agent differs from `voice-agent/task-call/`.
- **Audio is never recorded.** A text transcript is: live from Twilio Real-Time Transcription, final from ElevenLabs. Both are encrypted here only until the app has saved the answer card; then they are deleted, with a receipt per deletion. The ElevenLabs conversation is deleted after processing and checked gone.
- **Cost:** every dialled attempt gets cost items (Twilio price, transcription, ElevenLabs credits, model tokens) in the transaction that claims the dial. Unset prices make an item `unknown`, never zero.
- **Env:** `TWILIO_TASK_ACCOUNT_SID`, `TWILIO_TASK_AUTH_TOKEN` (fall back to the main Twilio pair; use a Poland-only subaccount), `TASK_CALL_FROM_NUMBER`, `ELEVENLABS_API_KEY`, `ELEVENLABS_TASK_AGENT_ID`, `ELEVENLABS_WEBHOOK_SECRET`, `TASK_CALLS_KILL_SWITCH`, `CALL_RECORDING_NOTICE` (`off` by default), `TASK_CALL_LIMIT_*`, `TASK_CALL_MAX_SECS`, `PRICE_TWILIO_TRANSCRIPTION_USD_PER_MIN`, `PRICE_TWILIO_CONFERENCE_USD_PER_PARTICIPANT_MIN`, `PRICE_ELEVENLABS_USD_PER_CREDIT`, `TASK_CALL_SAY_VOICE`. `ANTHROPIC_API_KEY`, if set, lets Claude Haiku point at the answer and write the summary; the card works without it. `.env.example` explains each.
- **Setup:** `node scripts/setup-task-call-agent.mjs --dry-run`, then for real; point the ElevenLabs post-call webhook (transcript on, audio off) at `/webhooks/elevenlabs/post-call` with its HMAC secret.
- **Try it without the app:** `node scripts/task-call.mjs init|status|brief|approve|live|takeover|end|card|ack` (usage at the top of the script).

## Errands: Doddy works on a task in the background (ADR-570)
The user hands Doddy a task ("sprawdź loty i hotele do Rzymu…"), says yes once, and Doddy researches it on the web while the app is closed. Contract: `docs/implementation/ERRANDS.md`. **Not run against the real Anthropic API, APNs or a device yet**; the tests use a fake researcher and a local stand-in for the API.

| Route | Body | Reply |
|---|---|---|
| `POST /v1/errands` | `{words ≤1000, brief ≤1000, title ≤80, language}` | `201 {id, digest, title, words, brief, language, expiresAt}`: a draft, nothing runs |
| `POST /v1/errands/:id/approve` | `{digest}` | `202 {id, state: "queued"}` · `409 digest_mismatch` · `409 not_approvable {state}` (not a draft, or `expired`) · `409 too_many_open_errands` · `503 errands_disabled` |
| `GET /v1/errands` | | `{errands: [{id, title, state, createdAt, finishedAt, failure}]}`, newest first, no drafts; `title` is null once the server's copy is deleted |
| `GET /v1/errands/:id` | | id, state, times, `searches`, `fetches`, `cancelRequested`; `title`, `words`, `brief`, `digest` while the server holds them; `result` + `resultDigest` when done; `failure` when failed |
| `POST /v1/errands/:id/cancel` | | `204` (a draft is deleted, a queued errand never starts, a running one stops at its next step) · `409 not_cancellable {state}` when done or failed |
| `POST /v1/errands/:id/ack` | `{resultDigest}` | `200 {deletions: [{what, reason, deletedAt}]}`: words, brief, title and result are deleted, id, state and times stay · `409 result_mismatch` · `409 no_result {state}` |
| `DELETE /v1/errands/:id` | | `204`: the row goes (receipts stay) |

- **One yes, exactly these words.** The draft's words, brief and title are stored encrypted (`MEMORY_ENCRYPTION_KEY`, AAD bound to account and errand) with their SHA-256 over the canonical JSON of `{brief, language, title, words}` (keys sorted, no spaces, strings as `JSON.stringify` writes them, UTF-8). Plain SHA-256, as the contract says, so the app can recompute it; the call-case digest is an HMAC instead. Approve needs that digest, a draft under 10 minutes old, and fewer than `ERRANDS_MAX_OPEN` queued or running errands (counted under an advisory lock). The worker checks the digest again before it runs anything.
- **The runner** (`src/errands/researcher.ts`): `claude-opus-5-5` (`ERRANDS_MODEL`), adaptive thinking, effort `high` (`ERRANDS_EFFORT`), streamed, `max_tokens` 64000, server-side refusal fallbacks (`fallbacks: "default"`), prompt caching, and only two tools: `web_search_20260209` and `web_fetch_20260209`, **with no `max_uses`** (owner: no cap on look-ups). `pause_turn` is resumed by sending the paused content back, until the model ends its turn. A second call writes the card in a fixed schema (`output_config.format`, effort `medium`, no tools). Web pages are data: the prompts say so, and there is no tool that could book, buy, send or start anything.
- **Rules in code, not only the prompt** (`src/errands/card.ts`): a `url` in an item or in `sources` is kept only if a search result or fetched page in this run had exactly that url; an item without a kept url loses its `price` and its detail says the price wasn't confirmed; lengths and counts are clamped (6 sections, 8 items, 3 next, 20 sources, answer 600); `checkedAt` is the server's clock. A card that still doesn't fit is `unreadable_result`.
- **What stops a run:** the model finishing; Cancel (checked between requests and every 15 s during one); the time limit (`ERRAND_TIME_LIMIT_MINUTES`, default 30; the card call gets 4 more minutes) → `failed: time_limit`; a refusal → `refused`; an API or network error → `provider_error`. A running errand older than the time limit + 5 minutes lost its worker → `failed: interrupted`, never re-run by itself; on a clean shutdown running errands are stored as `interrupted` at once.
- **Worker:** its own loop (`errandLoop` in `src/workerLoop.ts`), up to 3 runs at once per process, claims with `FOR UPDATE SKIP LOCKED` committed before any model call. The result (or failure code), the counts and the push go in one transaction. The push carries no words from the errand: "Gotowe. Wynik sprawy czeka w aplikacji." / "Done. Your task's result is waiting in the app." (failure: "Nie udało się dokończyć sprawy." / "Doddy couldn't finish a task."), Polish when the errand's language is `pl`.
- **Kept on the server:** encrypted words, brief, title and result until `ack` or `DELETE`; an unapproved draft is deleted after 10 minutes; the content of any finished errand not acknowledged or deleted is deleted 30 days after it finished. Each deletion writes a receipt (`errand_deletions`, no content). Deleting the account deletes its errands and receipts.
- **Sent to Anthropic:** the words, the brief, the language and today's date (not the title), then whatever the run searches and reads; the card call gets the notes and the list of sources. Nothing from notes, lists, the profile or earlier conversations.
- **Cost visibility:** per errand, input, cache-write, cache-read and output tokens across both calls, searches and fetches, and the model, stored on the row and logged with ids only. Not priced in code.
- **Env:** `ERRANDS_ENABLED` (default `0`, off: set `1` to turn errands on; runs only when `ANTHROPIC_API_KEY` and `MEMORY_ENCRYPTION_KEY` are also set, otherwise `503 errands_disabled`), `ERRANDS_MODEL`, `ERRANDS_EFFORT` (`low|medium|high|xhigh|max`), `ERRAND_TIME_LIMIT_MINUTES` (1–120), `ERRANDS_MAX_OPEN` (1–20). Migration `009_errands.sql` (new tables only) is applied at startup.
- **Caveat:** a free Render web service sleeps after about 15 minutes without requests, which stops the worker; for dependable errands use a paid instance or the separate `doddy-messaging-worker` (`render.yaml`).

## Price watches (shopping stage 2)
Contract: `docs/implementation/SHOPPING_WATCH.md` and `schemas/fixtures/watch_create_v1.json`. After one yes the worker reads one shop page about four times a day for 30 days and queues one push when the confirmed price is at or below the user's number. It only notifies: it never buys, signs in or fills in anything, and no model is involved. Code: `src/watches/` (`schema.ts` request and digest, `rules.ts` the pure decisions, `service.ts` create/approve/read/stop/delete, `worker.ts` the checks), `src/routes/watches.ts`, migration `013_price_watches.sql` (a new table only).
- **Routes** (device token; strict bodies; every route `503 watches_disabled` unless `WATCHES_ENABLED=1`, `MEMORY_ENCRYPTION_KEY` is set and a fetcher is wired): `POST /v1/watches` (reads the page once through the shared `PoliteFetcher`; `422 price_not_readable {reason: blocked|not_allowed|no_price|failed}`, `422 currency_mismatch`, `422 already_below {currentMinor}`), `POST /v1/watches/:id/approve {digest}`, `GET /v1/watches`, `GET /v1/watches/:id`, `POST /v1/watches/:id/stop`, `DELETE /v1/watches/:id`. Create and approve 30 an hour per device, reads 1200, stop 120, delete 240.
- **One yes, bound to the digest:** SHA-256 over the canonical JSON of `{checksPerDay, currency, days, language, shop, thresholdMinor, title, url}` (the fixture holds the exact text). Approve needs a draft under 10 minutes old, its own digest and fewer than `WATCHES_MAX_OPEN` active watches (counted under an advisory lock). Nothing is read before the approval; the first check is one interval later.
- **Only a confirmed price counts:** a check triggers only on a read in the user's currency, not out of stock, at or below the number (`rules.ts`). A failed read, a page with no structured price, another currency or an out-of-stock page never becomes a price; a failed read counts toward the 8 in a row that end the watch as `failed`, a readable page (another currency, out of stock) resets that run and records no price.
- **Worker:** its own loop (`watchLoop` in `src/workerLoop.ts`, also in the web process with `RUN_WORKER_IN_WEB=1`). A tick claims up to 10 due watches with `FOR UPDATE SKIP LOCKED`, moving each one's due time 15 minutes ahead (a claim), then checks them one at a time with at least 2 seconds between two requests to one host (per process). Each result, and its one push, is written in one transaction that applies only if the watch is still active and still held by that claim, so a Stop, a DELETE or a later claim wins over a late result. A claim that is never recorded (the worker died) is due again when it lapses; on shutdown the check in flight is given back unrecorded, never counted as a failure. The last check is made at the end of the 30 days, then the watch expires.
- **Pushes:** only "Cena, której pilnujesz, spadła." / "A price you're watching dropped." and, after 8 failed checks, "Nie mogę już odczytać ceny, której pilnujesz." / "Doddy can no longer read a price you're watching." No product word, shop, address or price. Expiry and Stop send nothing.
- **Kept on the server:** the title, shop and page address encrypted (AAD `{account}:watch:{id}`) for the watch's life; plain, only the user's number and currency, the last confirmed price, times and counts. A finished watch is deleted, content and all, 30 days after it ended; a draft after 10 minutes; DELETE at once; deleting the account removes all (`ON DELETE CASCADE`). Logs carry ids, outcomes and counts, never words or addresses.
- **Env:** `WATCHES_ENABLED` (default `0`), `WATCHES_MAX_OPEN` (1–20, default 5), `WATCHES_CHECK_HOURS` (1–24, default 6; the card promises four checks a day, so a shorter time checks more often than it says).

## Messages (ADR-585, ADR-586)
`POST /v1/assistant/ask` answers the app's typed conversation with Claude. The wire is the Ask gateway's (`gateway/src/validate.js`, `AssistantWire.swift`): `{ schemaVersion, requestId, sessionId, locale, userText, turns[≤6], memories[≤8] }` in, `{ schemaVersion, requestId, text, citedMemoryIDs, usage }` out, or `{ schemaVersion, requestId?, error: { code, message } }` with the gateway's status codes (400 `invalidRequest`, 422 `refused`, 429 `dailyLimitReached`, 503 `providerUnavailable` / `notConfigured`, 504 `timeout`). Needs a device bearer token.
- **Text only, no tools:** nothing it reads can search, send, book or change anything (ASK-01). The prompt (`src/assistant/prompt.ts`) says it is an AI, that notes and earlier turns are data, and that it cannot state current prices or dates.
- **Notes:** sent under aliases `n1…`; the real ids never reach the model, and an alias that was not sent maps to nothing. Citations are read back as ids; the app checks them again.
- **Stored and logged:** the database keeps counts per account and UTC day (`assistant_usage`, migration `010`: requests, input and output tokens). The question, the answer and the notes are not stored; the log holds the model, counts and codes.
- **Caps:** `ASSISTANT_DAILY_PER_ACCOUNT` (default 100, exact) and `ASSISTANT_DAILY_PER_SERVER` (default 1000, may overshoot by the requests in flight). A request is counted before the model runs, so a flood cannot spend more than the cap. Also 60 requests per hour per device, and a 45 s time limit that aborts the call; if the person stops the question the call is aborted too.
- **Env:** `ASSISTANT_ENABLED` (default `0`; runs only when `ANTHROPIC_API_KEY` is also set, otherwise `503 notConfigured`), `ASSISTANT_MODEL` (default `claude-haiku-5-5`), `ASSISTANT_EFFORT` (`low|medium|high`, default `medium`), `ASSISTANT_DAILY_PER_ACCOUNT`, `ASSISTANT_DAILY_PER_SERVER`.
- **Sent to Anthropic:** the question, up to six earlier turns, and the notes the app chose to send (none for a private note, ADR-310). Not cost-priced in code; the token counts are in `assistant_usage`.

## News digests## News digests
Once a day at the user's local time, the worker builds a short news message:
1. **Gather:** curated RSS feeds per topic, the user's own feeds, and GNews keyword search for their own topics. Fetches are cached 30–60 minutes and shared across users.
2. **Shortlist:** deterministic. Stories from the last 36 hours, not sent in the past 14 days, deduplicated by URL (tracking parameters ignored) and title, scored by topic fit and freshness, at most 3 per source.
3. **Write:** Claude Haiku (`claude-haiku-5-5`, structured output) picks up to 5 stories and writes one line each, using only the headline and feed summary.
   - Links and sources always come from the shortlist; lines pointing at unknown stories are dropped.
   - If Claude is unavailable, refuses, or returns nothing usable, the digest falls back to plain headlines.
4. **Send:** push (short list; links are in the app) and/or SMS (up to 3 stories with links, ≤640 characters), through the outbox. One scheduled digest per local day, guaranteed by a unique index.
- **Custom feed URLs** are fetched with protections against reaching the server's own network: private and reserved addresses are blocked, the address is checked at connect time (so a DNS change can't swap one in), redirects are re-checked, and size and time are capped.
- **Sent to Anthropic or OpenAI (whichever key is set, ADR-197):** topic labels plus public headlines and summaries. Never memories, phone numbers or account IDs.

## Run locally
```sh
cp .env.example .env            # fill what you have; empty blocks stay off
npm ci && npm run build
DATABASE_URL=... npm start      # applies migrations, then serves on $PORT
DATABASE_URL=... npm run worker # sends due updates every 2 s
TEST_DATABASE_URL=postgres://…/doddy_test npm test   # WARNING: drops that DB's public schema
```
With 1Password (ADR-493): `npm run start:op` takes the secrets from the `doddy-dev` vault through `.env.op` (references only) and the rest from `.env`. See `docs/security/SECRETS_1PASSWORD.md`.

## Before the first deploy (owner)
1. Apply `render.yaml` in Render. This creates **paid** resources: 2 × starter + basic-256mb Postgres.
2. Render asks for each secret when the Blueprint is created, once for the web service and once for the worker (ADR-495). Take the values from 1Password, and set `PUBLIC_BASE_URL` to the service's URL. Later changes go through `tools/secrets/sync.mjs` (`docs/security/SECRETS_1PASSWORD.md`).
3. Twilio:
   - Buy a number and create a Messaging Service with **Advanced Opt-Out** on.
   - Point the inbound webhook at `/webhooks/twilio/sms`.
   - Create a Verify service.
   - US numbers also need A2P 10DLC registration.
4. APNs: create a .p8 key and enable the Push capability on the app id.
5. ElevenLabs: turn on **authentication** for the Doddy agent, so tokens are required.
