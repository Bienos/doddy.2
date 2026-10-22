# Doddy Web and the shared platform: audit, target and plan (22 Oct 2026)

Branch `claude/exciting-carson-08x2pk`, from main at `8aa42c5`. The owner's brief ("DODDY — Master implementation prompt", 22 Oct) asks for one personal AI platform with two interfaces, iPhone and web. This page is Phase 0 of that brief (sections A to G), plus what the first slice on this branch built. ADR-585 and ADR-586 record the two decisions. How to run, test and deploy the web app: `docs/platforms/web.md`.

Words used here: **IMPLEMENTED** = code and tests exist and pass; **PARTIAL** = part of it exists; **MOCK** = demo data only; **MISSING** = not built; **DEPRECATED** = built, but superseded or switched off; **LIVE?** = built, but never confirmed on the live service or a device.

## Summary

- **What's true today.** Doddy is a local-first iPhone app. Its memory, transcripts and profile live on the phone. Four small servers sit around it, each with its own idea of who the user is.
- **What this branch adds.** A real web app at `web/`. The existing `backend/` serves it on its own origin. The person signs in by typing a code their iPhone shows. They then see the same server account's documents (decks, Word, Excel, PDF and text Doddy made on the phone), connected accounts, receipts and signed-in browsers.
  - Built and tested: 33 backend tests, 25 web unit tests and 10 end-to-end runs in Chromium (desktop and phone width), plus 17 Swift tests compiled and run here on Linux with Swift 6.1.2.
  - Not deployed. The SwiftUI screen hasn't been compiled (no Xcode here).
- **What waits on the owner.**
  - Turning it on: one Render variable and one build-command change (`docs/platforms/web.md`).
  - Before chat, memory or tasks can come to the web, eight decisions (section F, "Owner decisions"). The biggest is whether memory leaves the phone at all. Today the product promises it doesn't.

## A. Current architecture (as found in the repository)

```
                         iPhone app (SwiftUI, DoddyApp/ + Packages/DoddyCore)
        local SQLite (GRDB): memories, lists, reminders, learned facts, errands, call cases
        local files: last 10 voice transcripts (opt-out), activity log, photos, voice memos
           |                |                     |                        |
           | voice          | tools, Claude,      | push, SMS, calls,      | typed Ask
           v                | documents           | news, errands          v
  ElevenLabs agent <-- token |                     |                 gateway/ (Vercel,
  (client tools run          v                     v                 OpenAI) NOT RUNNING
   on the phone)     backend/  "doddy"       server/messaging/
        ^            Render, Node http,       "doddy-messaging"
        |            Postgres (+PGlite        Render, Fastify,
  server/voice-token tests)                   Postgres doddy-db,
  (Vercel, Apple     Composio, Monid,         worker (SKIP LOCKED),
   sign-in, Upstash) Anthropic (Claude)       Twilio, APNs, Anthropic
                     ds1 device sessions,     anonymous device tokens
                     Supabase JWT verifier
  site/ (Vercel): static marketing site www.doddy.lol, waitlist on Vercel Blob
```

### Capability inventory

| Capability | Status | Evidence |
|---|---|---|
| iPhone app (SwiftUI, iOS 17) | IMPLEMENTED; last seen working on a device at `ce02763` | `STATUS.md` "Known-good build"; hosted Mac CI green on `e9fc9ae` |
| Local memory: SQLite, FTS5, provenance (`rawText`, `source`, `capturedAt`), corrections, export, encrypted backup | IMPLEMENTED | `Packages/DoddyCore/Sources/DoddyPersistence/DoddyDatabase.swift`, `MemoryTypes.swift`, `EncryptedBackup.swift`; DoddyCore 1,371 tests |
| Deleting a memory | IMPLEMENTED as a hard purge, **no tombstones** (blocks sync, section E) | `SQLiteMemoryRepository.delete` |
| Conversation transcripts | PARTIAL: last 10, on the phone only, can be switched off | `DoddyApp/Infrastructure/ConversationLogStore.swift` |
| Voice (ElevenLabs agent, phone-side client tools) | IMPLEMENTED; LIVE? ("voice works on no device yet" since Apple sign-in) | `voice-agent/`, `STATUS.md` "Voice, 19 Oct" |
| Voice credentials (Apple sign-in, HS256 sessions, Upstash) | IMPLEMENTED, deployed on Vercel | `server/voice-token/src/voice-auth.js`, `handler.js` |
| backend/ tools: Composio accounts, Monid search, ASK-01 approvals, receipts, caps | IMPLEMENTED; LIVE? | `backend/src/tools/service.ts`, `askFirst.ts`; 274 tests before this branch |
| Claude on the server: `ask_claude`, `make_document` | IMPLEMENTED; LIVE? (no real Anthropic call made from tests) | `backend/src/tools/claude.ts`, ADR-564 |
| Documents | PARTIAL: Postgres rows kept 7 days. Signed 7-day links. Made by an in-memory job that is lost on restart | `backend/src/documents.ts`, `store.ts` (`documents`), `tools/service.ts` `makeDocumentInBackground` |
| Background tasks ("errands") | IMPLEMENTED, off by default (`ERRANDS_ENABLED=0`). Durable worker. The server copy is deleted once the phone saves the result | `server/messaging/src/errands/`, migration `009_errands` |
| Phone calls, call cases, news digests, push, SMS | IMPLEMENTED; LIVE? (calls never tried live) | `server/messaging/src/`, `docs/implementation/CALL_CASES_STATUS.md` |
| Typed "Ask Doddy" | The OpenAI gateway was never configured on any host, so it did not work. **Moved to `backend/` (Claude) on 22 Oct, ADR-587:** `POST /v1/assist`, open to every iPhone through a guest session; not run against the real Anthropic API | `backend/src/assist.ts`, `gateway/` (unused) |
| Marketing site, waitlist, admin | IMPLEMENTED, live | `site/`, `site/api/` |
| Authenticated web UI | MISSING before this branch (the only web login was the single-password waitlist admin) | `site/admin/` |
| Shared identity | PARTIAL: four separate identities (below) | — |
| Supabase sign-in (Apple/Google) | PARTIAL: verifier built on the server; the app side was never built. **Deferred by the owner on 22 Oct** ("leave google sign in for now"), so the web keeps its code from the phone (ADR-585) | `backend/src/auth.ts`, ADR-526 |
| Projects | MISSING | — |
| Conversation sync, memory sync | MISSING. Only an opt-in, whole-snapshot memory copy that phone calls read | `server/messaging` `PUT /v1/memory-copy/snapshot` |
| Usage metering | PARTIAL: per-user and per-service daily counters for tools and Claude. Errand tokens counted, not priced | `backend/src/store.ts` `usage`; `server/messaging` errands |
| Billing and entitlements | MISSING (#89's Apple Pay/BLIK purchase is an unmerged draft) | `STATUS.md` "Not merged yet" |
| Versioned migrations | PARTIAL: messaging has numbered SQL migrations; backend has an idempotent `CREATE … IF NOT EXISTS` schema | `server/messaging/migrations/`, `backend/src/store.ts` `SCHEMA_SQL` |
| Observability | PARTIAL: content-free JSON logs with correlation IDs; no metrics or traces | `backend/src/http.ts`, `server/messaging/src/log.ts` |
| macOS and watchOS paused (ADR-572) | Verified: not in `project.yml`; `make` refuses them without `ENABLE_*`; the Mac CI job skips Watch/Mac-only changes | `scripts/check_platform_specs.py`, `scripts/ci_needs_mac.sh` |

### Duplication audit

| Area | What overlaps | Recommendation |
|---|---|---|
| **Identity** (highest risk) | `server/voice-token`: Apple sign-in, HS256 tokens, Redis sessions. `backend/`: Supabase JWTs and `ds1` device sessions. `server/messaging`: anonymous device tokens. `gateway/`: invite tokens. One phone has up to four unrelated user IDs. | Converge on one account (ADR-526's Supabase user) with `backend/` as the place that checks it. Then voice-token and messaging accept that session. Phased, section F. Don't merge the stores first: link identities, then move data. |
| AI gateways | `gateway/` (OpenAI), `backend/` (Claude), `server/messaging` (Anthropic for news, calls and errands) | Typed Ask now goes through `backend/` (ADR-587); `gateway/` is unused and can be deleted when the owner decides (decision 11). Web chat will go through `backend/` too. |
| Background jobs | messaging's durable worker (leases, SKIP LOCKED, timeouts) vs backend's in-memory document jobs | Move document making onto a durable job when documents become durable (Phase 4). Don't build a third job system. |
| Databases | backend's Postgres (schema `doddy_backend`, `DATABASE_URL`) and messaging's `doddy-db` | One Postgres with a schema per module is the stated plan (`render.yaml` header). Do it when identity is shared, not before. |
| Rate limits and budgets | gateway `budget.js`, backend `usage` table, messaging per-route limits | Keep backend's `usage` table as the one meter (it is transactional and survives restarts); messaging can call into it once they share a database. |
| Tool registries | `backend/src/tools/catalog.ts` (server tools), `voice-agent/tools.json` (voice agent), DoddyCore `CloudToolName` | These already check each other (`scripts/voice_agent_spec.py`, fixtures). Leave them. |

Nothing here was refactored on this branch: the audit's rule is consolidation only where it removes real risk, in its own step.

## B. Target architecture

```
         iPhone app                          Doddy Web (web/, Vite + React)
   (voice-first, local SQLite)           served by backend on the same origin
              \                                      /
               \  Authorization: Bearer            /  HttpOnly SameSite=Strict cookie
                \                                 /   (+ Origin check, x-doddy-web)
                 v                               v
            backend/  = the Doddy server (one deployable, modules inside)
            identity & sessions | tools & approvals (ASK-01) | documents
            Claude (one model router) | usage & caps | receipts/audit
            later: conversations, memory sync, projects, tasks API
                 |                                \
            Postgres (one database,                server/messaging = worker + telephony
            schema per module)                     (errands, calls, push), same account
```

- **One server for both clients.** `backend/` already holds tools, approvals, Claude, documents, caps and receipts, and checks Apple/Google sessions. It is the shared API.
  - Its modules stay folders (`src/tools`, `src/web`, later `src/conversations`, `src/memory`), not services.
  - `server/messaging` stays the worker and telephony service until the shared account lands.
- **Web is served by `backend/` (ADR-586),** so the browser session is a first-party HttpOnly cookie. There is no new host, no CORS, and no token in browser storage.
- **One agent, two interfaces, eventually.** Today the "agent" is the ElevenLabs voice agent, and its memory tools run on the phone. A web chat that is the *same* Doddy needs the same tools on the server. So web chat waits on two decisions: memory sync (E) and a server-side text runtime. Building a separate web chatbot with its own prompt and no memory would break the brief's "do not create a second agent".

## C. Reuse vs build vs refactor

| Capability | Exists | Reuse | Modify | Build | Risk | Priority |
|---|---|---|---|---|---|---|
| Web app | none | design tokens and brand files (generated), contracts | — | `web/` (done, slice 1) | low | P1 ✔ |
| Web sign-in | backend sessions, device sign-in | `SessionVerifier`, `usage` table | — | link codes, cookie sessions, CSRF (done) | medium: phishing of codes (mitigated, section on risks) | P1 ✔ |
| Account (Apple/Google) | Supabase verifier (server) | verifier | app sign-in; account linking | Supabase project config (owner) | high: identity migration | P2 |
| Documents list and download | `documents` table | rows, ownership | list + owned download (done) | durable storage, versions, editing | medium: BYTEA size | P1 ✔ / P4 |
| Document jobs | in-memory promise | Claude provider | — | durable job (messaging worker pattern) | medium | P4 |
| Connected apps view | `GET /v1/tools` | as is (cookie read allowed) | — | connect from the web (needs a web return URL) | low | P1 ✔ / P7 |
| Activity | tool receipts | as is | — | localised summaries (server text is English) | low | P1 ✔ |
| Conversations | phone-local transcripts | `ConversationLog` shape | — | server conversation store, text runtime, SSE | high: privacy, cost | P2 (decisions) |
| Memory | phone SQLite with provenance | IDs, provenance, corrections | add tombstones | consented sync, conflict rules, web Memory UI | **highest**: product promise | P3 (decisions) |
| Tasks / research | errands worker | states, approvals, digests | keep results (today deleted after ack) | task API on the shared account, web dashboard | medium | P5 |
| Projects | none | — | — | project tables, links, scoped retrieval | low | P6 |
| Usage and cost | daily counters | `usage` table | add priced records | per-task cost, entitlements | low | P8 |

## D. Repository structure

Nothing that works was moved.

```
backend/            the Doddy server (Render "doddy")
  src/web/          ADR-585: contracts.ts, sessions.ts (codes, cookies, CSRF), routes.ts, static.ts
  test/web.test.ts, test/webRig.ts, test/fixtures.web.generate.ts
web/                Doddy Web: Vite 7 + React 19 + TypeScript 5.9 + zod 3 (ADR-586)
  src/api           typed client, schemas mirrored from the server
  src/auth          session state (asks the server; holds no token)
  src/i18n          Polish (default) and English messages
  src/pages         sign-in, Home, Documents, Connected apps, Activity, Settings
  src/styles        tokens.css (generated), app.css
  test/             Vitest + Testing Library, against contracts/ fixtures
  e2e/              Playwright: real backend + Chromium
contracts/web/      fixtures written by the server (npm run fixtures:web), read by web and Swift tests
tools/gen_web_assets.py   tokens and brand files from the app; --check in CI
Packages/DoddyCore  WebLinkClient + WebSignInModel (tested on Linux)
DoddyApp/Features/Web/WebSignInView.swift   Settings › Doddy on the web
```

Later modules go under `backend/src/<module>/`. A separate package for shared TypeScript contracts is not worth it yet: the fixtures already pin both clients to the server's real output.

## E. Data and identity migration

**Identities today, on one phone:**
- `backend/`: a device user. The server derives it with HMAC from a Keychain device ID; it is the first-device owner (ADR-563).
- `server/messaging`: an anonymous account with its own device token.
- Voice: an Apple-sign-in user on `server/voice-token`.

**What this branch does:** the browser joins the **existing `backend/` device user**. The phone vouches for it with a code. No account is created, merged or migrated, and nothing moves off the phone.

**Account linking (Phase 2, needs the owner's Supabase setup):**
1. The phone signs in with Apple or Google through Supabase (ADR-526).
2. While still holding its device session, it calls a link endpoint. In one transaction, the server re-keys every row the device user owns to the Supabase user: `users` (keeping the Composio user, so connections survive), `connections`, `tool_switches`, receipts, `documents` and `web_sessions`. It runs only when the caller holds both sessions.
3. If the Supabase user already owns rows (a second phone, say), nothing is merged automatically. The phone shows both and asks.
4. Messaging and voice-token then accept the Supabase session. Their anonymous and Apple users are linked the same way, one service at a time.
5. Device sign-in (development only) is retired after every tester has linked.

**Memory (Phase 3, needs decisions 1 to 3):**
- **Default stays local.** Sync is a switch with a consent screen that says what goes, to which server, encrypted how, and how to delete it.
- **IDs:** the existing memory UUIDs, lowercased on the wire, as the messaging copy already does.
- **Provenance travels unchanged:** `rawText`, `source`, `category`, `capturedAt`, corrections.
- **Deletion:** the phone needs a deletion log (tombstones). Today delete is a hard purge, so a sync couldn't tell "deleted here" from "not synced yet".
- **Conflicts:** edits to the same memory on two devices keep both wordings in the correction history and ask; they are never last-writer-wins for text. Lists merge per item.
- **Encryption:** at minimum the messaging server's pattern (AES-256-GCM, AAD bound to account and row, server-held key, `server/messaging/src/crypto.ts`). End-to-end encryption, with the key in iCloud Keychain, means the server can't search memories for the web. That trade is the owner's call.
- **Interrupted migration:** an upload cursor, plus idempotent upserts by ID, so a retry repeats nothing.
- Export and delete-everything already exist on the phone. The server side needs its own "delete my synced copy" with a receipt (messaging has `server_data_deletions` to copy).

**Conversations:** transcripts stay on the phone (last 10, switchable). Cross-device conversations need a server conversation store and a server text runtime (decisions 4 and 5). Voice transcripts would sync only if the person turns it on.

## F. Roadmap (dependency order)

| Phase | Deliverables | Main files | Tests | Done when | Size | Risks / owner decisions |
|---|---|---|---|---|---|---|
| **1 Web foundation** (this branch) | Web app, iPhone-vouched sign-in, cookie sessions, workspace (documents, apps, activity, browsers), PL/EN, brand tokens | `backend/src/web/`, `web/`, `DoddyApp/Features/Web/`, DoddyCore `WebLinkClient` | backend 33, web 25 + 10 e2e, Swift 17 | Signed in on a real browser against the live server with a real phone code | M | Hosted Mac compile of the SwiftUI screen; Render build change; `DODDY_WEB_ORIGIN` |
| 2 Shared account + conversations | Supabase sign-in in the app, account linking, conversation store, server text runtime (SSE), web chat | `backend/src/conversations/`, `src/identity/`, `web/src/pages/Chat*` | linking transaction, isolation, SSE | Start on phone, continue on web | L | Decisions 1, 4, 5, 6 |
| 3 Shared memory | Tombstones on the phone, consented sync, server memory API, web Memory page with provenance | DoddyPersistence migration, `backend/src/memory/` | conflict cases, crypto AAD, cross-user | A saved memory managed on both, no cross-user leak | L | Decisions 1, 2, 3 |
| 4 Documents | Durable storage and jobs, versions, text editing, conversational revision bound to a version | `backend/src/documents/`, worker job | restart mid-job, version conflicts | Made on phone, edited on web, opened on phone | M | Decision 7 (storage) |
| 5 Research and tasks | Errands on the shared account, kept results, web dashboard, cancel, unknown states | `server/messaging` errands → shared account | lifecycle, duplicate prevention | Start on phone, see result later on web | M | Errand spend cap (open since ADR-570) |
| 6 Projects | Projects and links, scoped retrieval | `backend/src/projects/` | scope, retrieval | Project context in answers | S–M | — |
| 7 Integrations | Connect from the web (web return URL), unified approvals, daily summary | `backend/src/tools/`, `web/` | approval parity phone/web | One approval system | M | Composio web return URL |
| 8 Commercial hardening | Security review, priced metering, entitlements, monitoring, runbooks | all | load, accessibility audit | — | M | Prices and plans |

**Owner decisions** (none is needed to merge this branch):
1. **Memory off the phone:** keep "your notes stay on this iPhone", or offer opt-in sync? This decides Phases 2 and 3.
2. **If sync:** server-held key (searchable from the web) or end-to-end (not searchable)?
3. **Where synced memory lives:** backend's Postgres (shared account) or messaging's.
4. **Web chat's model and voice:** the same ElevenLabs agent in the browser (microphone, its cost), or text-only Claude through `backend/` first?
5. **Retention of web conversations,** and whether voice transcripts sync.
6. **Supabase project configuration** (Apple and Google providers) and a paid Apple team (already open: checklist A5).
7. **Document storage:** keep files in Postgres (simple, fine at beta scale) or object storage (cheaper per GB, another vendor).
8. **The web address:** keep the Render URL or point `app.doddy.lol` at it (a DNS change).

## G. Cost

**Architectures compared, simplest first:**

| Option | Fixed monthly | Notes |
|---|---|---|
| **A. Web served by the existing `backend/` on Render (chosen, ADR-586)** | $0 extra on the current free plan; Render Starter is about $7 a month for an instance that doesn't sleep (assumption, verify on render.com) | One deploy, one origin, first-party cookie, no CORS. The free plan sleeps when idle, so the first request after a sleep waits for the server to start; the page says so. |
| B. Next.js on Vercel as a BFF in front of `backend/` | Vercel Pro per seat; the Hobby plan is for non-commercial use (assumption, verify) | A second deployable and a second session store. Server functions far from the Frankfurt backend add latency. The team already hit the free plan's 100 deploys a day (`STATUS.md`). |
| C. Static SPA on Vercel calling `backend/` with Bearer tokens | $0 | Tokens in browser storage (readable by any XSS) and CORS on every route. Rejected on security. |

**Per-use estimates** use Claude prices from the API reference cached 6 Oct 2026 (input/output per million tokens: Opus 5.5 $4/$20, Sonnet 5.5 $2/$10, cache reads $0.20; Haiku 5.5 $0.10/$0.50 up to 100K-token prompts). Token counts are assumptions, not measurements:

| Use | Assumption | Estimate |
|---|---|---|
| Web workspace (this branch) | Database reads only, no AI call | ≈ $0 per visit |
| A chat turn, Sonnet 5.5 | 3,000 tokens in, 500 out | ≈ $0.011 |
| A chat turn, Haiku 5.5 (simple requests) | same | ≈ $0.0006 |
| A research task (errand), Opus 5.5, effort high | 150,000 in (pages read), 15,000 out | ≈ $0.90 plus web search fees (price not in the reference; verify) |
| A document (`make_document`), Sonnet 5.5 with Skills | 30,000 in, 8,000 out | ≈ $0.14 plus code-execution time (verify) |
| Document storage | 50 KB to 2 MB each, kept 7 days, in Postgres | negligible at beta scale |
| Voice | ElevenLabs per its plan; not estimated here | see `PRICE_ELEVENLABS_USD_PER_CREDIT` |

**Model routing that pays for itself:** Haiku 5.5 for classification and short answers, Sonnet 5.5 for writing and documents, Opus 5.5 only for errands. Keep caching the fixed system prompt. The daily caps already in `backend/` (`DODDY_LIMIT_USER_DAILY_CLAUDE` 40, service 100) bound the worst case.

**New recurring cost from this branch:** none.

## Security and privacy of the first slice

| Risk | Protection | Test |
|---|---|---|
| Stolen or guessed code | 8 characters from 30 (≈ 39 bits). 5-minute life, one use, only the newest. Every sign-in try is reserved atomically before the code is read: per client 10 per quarter hour (`DODDY_WEB_SIGNIN_TRIES_PER_CLIENT`; an IPv6 client counts by its /64), per server 2,000 per hour. | `web.test.ts` "sign-in tries are limited…", "parallel tries can't get past the limit", "IPv6 clients count by their /64", "a code works once…" |
| Code phishing (someone talks a person into reading their code out) | The phone shows the exact web address. Both screens say Doddy never asks for the code. The phone lists every browser and signs any out at once. | e2e "the iPhone signs the browser out" |
| Session theft via script | HttpOnly cookie, `__Host-` prefix, Secure, SameSite=Strict. Strict CSP: scripts from the origin only, no inline. The token is stored only as a hash. | "HttpOnly, SameSite=Strict, __Host- cookie"; e2e reads `document.cookie` |
| Cross-site requests | Unsafe cookie requests need the exact Origin plus `x-doddy-web: 1`. No CORS is ever answered. Signing in itself is checked, against login CSRF. | "signing in must come from the web app itself", "signing out … needs the web app's origin" |
| Web session doing too much | Allow-list: the cookie works only on `/v1/web/*` reads, sign-out, and `GET /v1/tools` and `/v1/tools/receipts`. It can't run tools, switch them, connect accounts or make codes. | "a browser session reads the workspace lists and nothing that runs tools" |
| Cross-account access (IDOR) | Every query is keyed by the session's user. Another user's document or session ID answers 404. | "one user's browser never sees or touches another user's documents or sessions" |
| A file running as a page on the app's origin | Downloads only: `attachment`, `nosniff`, `CSP: sandbox`. The page saves a blob; it never opens the file. The phone's older signed links (`/v1/documents/:id`, ADR-564) still serve files inline for Safari's Quick Look, so the web app should run on its own name (`app.doddy.lol`, a custom domain on the same Render service) while signed links keep `DODDY_PUBLIC_BASE_URL`; then the two are different origins. | documents test checks the headers |
| Logs | Route templates, statuses and timings only. No codes, tokens, cookies, User-Agent or document names. | "logs name routes and statuses only" |
| Lost session state | 30 days at most, 14 idle, ten browsers per user (oldest signed out). Pruned a day after ending. | expiry, ten-browser and prune tests |

**Limits that remain** (an independent security review of `backend/src/web/` on 22 Oct found nothing blocking; its two rate-limit findings are fixed: tries are reserved atomically, the server cap is 2,000 an hour and IPv6 counts by /64):
- The per-client limit trusts the last `X-Forwarded-For` entry behind Render. That is LIVE?: whether Render appends exactly one hop wasn't checked. If the last hop were a shared edge address, many people would share one allowance.
- Someone with many addresses can still use up the server-wide 2,000 tries and block sign-ins for the rest of the hour.
- If `DODDY_WEB_ORIGIN` and `DODDY_PUBLIC_BASE_URL` are the same host, a signed document link is served inline on the web app's origin. The type is fixed by the server, so no way to run script was found, but separate hosts remove the question.
- Receipt summaries and connected-app descriptions come from the server in English.
