# Composio integration plan — Google Calendar, read-only

Date: 2026-10-09. Scope: **one user-owned Google account, primary calendar, read-only event retrieval, a Connected
Apps screen and a minimum secure backend.** No writes, no multi-account, no calendar discovery, no history sync.

## Repository architecture (audited 2026-10-09)

| Part | Before this milestone | Added/changed |
|---|---|---|
| iOS app `DoddyApp/` (SwiftUI, iOS 17, XcodeGen) | Home/Memories/Settings tabs, capture, recall, ElevenLabs voice | `Features/ConnectedApps/` (screen, system auth browser), `Infrastructure/URLSessionTransport.swift`, `Infrastructure/KeychainSessionStore.swift`; Settings entry + dev server fields |
| `Packages/DoddyCore` (platform-agnostic, tested on Linux) | Domain ports, capability catalog, SQLite memory (GRDB/FTS5), voice tool parsing | `Sources/DoddyCore/ConnectedApps/` (Codable contracts, transport-agnostic client, callback parsing, local-day helper, `ConnectedAppsModel`), `CapabilityStatus.limited` |
| Backend | **None existed** | `backend/` — Node 22 + TypeScript, `node:http`, `node:sqlite`, zod, `@composio/core` 0.22.0 |
| Contracts | — | `contracts/connected-apps/*.json` fixtures, decoded by Swift tests and validated by TS tests |
| Auth | **None existed** (no accounts by design) | Replaceable `SessionVerifier` boundary: loopback dev identities (mock only) or owner-minted signed tokens |
| Assistant/voice | ElevenLabs agent with two client tools (search/save memory) | **Not changed.** Conversational calendar routing is not implemented; the button flow is the only entry point |

Existing capture → recall flow (unchanged): `CaptureView` → `MemoryStore.save` → `NewMemory` validation →
`SQLiteMemoryRepository.save` (transaction + read-back) → `MemoryStore.reload`. Recall: Memories search →
`RepositoryRecallService` → FTS5. The only change is that `MemoryStore.save` accepts a `source`, so a calendar event the
user explicitly saves is stored as `shared_content` with text naming Google Calendar.

## Vertical slice

```mermaid
sequenceDiagram
    autonumber
    participant U as User
    participant A as Doddy app
    participant B as Doddy backend
    participant C as Composio
    participant G as Google
    U->>A: Settings › Connected Apps › Connect Google Calendar
    A->>U: Explains: reads events only; can't create/change/delete
    A->>B: POST /connect (Bearer session)
    B->>B: user = verify(session); attempt+nonce (10 min, single use)
    B->>C: connectedAccounts.link(composioUserId, authConfigId, callbackUrl)
    C-->>B: { id: pending ca_…, redirectUrl }
    B-->>A: { attemptId, nonce, authorizationUrl, callbackScheme }
    A->>C: ASWebAuthenticationSession(authorizationUrl)
    C->>G: OAuth (performed by Composio's hosted flow)
    G-->>C: code
    alt verifier mode (recommended)
        C-->>B: GET /v1/oauth/verify?session_uri=…
        B-->>A: 302 doddy-dev://…?session_uri=…
        A->>B: POST /complete {attemptId, nonce, verifier{sessionUri}}
        B->>C: completeAuth({ userId: composioUserId, sessionUri })
    else callback mode (single-owner development)
        C-->>B: GET /v1/oauth/return?attempt=…&status=success&connected_account_id=…
        B-->>A: 302 doddy-dev://…?attempt&status&connected_account_id
        A->>B: POST /complete {attemptId, nonce, callback{…}}
    end
    B->>B: consume attempt (owner, provider, nonce, expiry) — once
    B->>C: get(id) → status, toolkit, authConfig, granted scope
    B->>C: list({userIds:[composioUserId], authConfigIds}) → ownership
    B->>B: grants ⊆ read-only allowlist? store connection; receipt
    B-->>A: { connection, receipt }
    U->>A: Tomorrow's events
    A->>B: POST /events { date: tomorrow (device calendar), timeZone: IANA }
    B->>B: owner → capability → connection → grants → schema → confirmation → limits
    B->>C: tools.execute(GOOGLECALENDAR_EVENTS_LIST, {userId, connectedAccountId, version, args})
    C->>G: events.list(primary, local-day window, singleEvents, fields=…)
    B->>B: normalize (title/times/recurrence only), bound, receipt
    B-->>A: { events, window, source, mode, retrievedAt, expiresAt, receipt }
    U->>A: Disconnect
    A->>A: drop transient events
    A->>B: POST /disconnect
    B->>B: delete local connection (reads blocked now), queue cleanup
    B->>C: revoke(id), delete(id)
    B-->>A: { connection, receipt (succeeded | outcome_unknown) }
```

## Selected SDK and tool

- **SDK:** `@composio/core` **0.22.0** (npm `latest` on 2026-10-09; package modified 2026-09-29), pinned exactly,
  lockfile committed. Type-checked with TypeScript 5.9.3 against the installed declarations — no `any`, casts only in
  tests (fake client) and one narrow read of `state.val.scope`.
- **Connection flow:** `connectedAccounts.link(userId, authConfigId, { callbackUrl, allowMultiple: false })`. The
  SDK marks `initiate()` deprecated for Composio-managed OAuth (legacy endpoint retired 2026-05-08 for new orgs,
  2026-07-03 for all), so it is not used.
- **Tool:** `GOOGLECALENDAR_EVENTS_LIST` — "Lists or incrementally synchronizes events from one calendar, defaulting
  to the connected user's primary calendar." Executed with an explicit `userId`, `connectedAccountId` and pinned
  `version` (the SDK throws `ComposioToolVersionRequiredError` for unpinned direct execution).

### Input arguments Doddy sends (subset of the tool schema)

| Argument | Value | Why |
|---|---|---|
| `calendarId` | `"primary"` | Only the primary calendar in this milestone |
| `timeMin` / `timeMax` | Local start of the asked day / local start of the next day, RFC 3339 with offset | Tool doc: timeMin bounds the event **end**, timeMax bounds the **start** (both exclusive); UTC midnights would misalign local dates |
| `timeZone` | User's IANA zone | Response formatting only (per tool doc it doesn't change filtering) |
| `singleEvents` | `true` | Expand recurring series into instances |
| `orderBy` | `"startTime"` | Requires `singleEvents` |
| `showDeleted` | `false` | Cancelled instances may still appear for recurring series; they are filtered and counted |
| `maxResults` | 50 (config) | Page size; ≤ 3 pages; ≤ 100 events returned |
| `fields` | `items(status,summary,start,end,recurringEventId,eventType),nextPageToken,summary` | Partial response: descriptions, attendees, locations, conference links are never fetched |
| `pageToken` | From previous page | Bounded pagination |

### Output fields Doddy reads

`successful`, `error`, `logId` (kept as the receipt's provider reference when present), `data.items[].status|summary|
start.date|start.dateTime|end.date|end.dateTime|recurringEventId`, `data.nextPageToken`, `data.summary` (calendar name,
masked, shown as "name reported by Google", not as a verified identity). Anything else is dropped by the normalizer.

## Doddy-owned API (v1)

Product contracts designed here — **not** Composio endpoints. All routes under `/v1/connected-apps` require
`Authorization: Bearer <session>`; request bodies are strict (unknown fields → 400).

| Method + path | Body | Returns |
|---|---|---|
| `GET /v1/health` (no auth) | — | `{status, mode, api, capabilities}` — no configuration details |
| `GET /v1/connected-apps` | — | `{mode, apps:[ConnectionView], planned:[…]}` |
| `GET /v1/connected-apps/google-calendar` | — | `ConnectionView` (user-triggered status check, ≤ 1 provider lookup / 30 s) |
| `POST …/google-calendar/connect` | `{}` | `ConnectResponse` |
| `POST …/google-calendar/complete` | `{attemptId, nonce, result: callback\|verifier\|canceled\|mock}` | `ConnectionResult` |
| `POST …/google-calendar/events` | `{date: "YYYY-MM-DD", timeZone: IANA}` | `EventsResult` |
| `POST …/google-calendar/disconnect` | `{}` | `ConnectionResult` |
| `GET …/google-calendar/receipts` | — | last 20 sanitized receipts |
| `GET /v1/oauth/return`, `GET /v1/oauth/verify` (browser, no auth) | — | 302 to the configured app return URL with allowlisted parameters only; changes no state |

Errors: `{error: {code, message, correlationId, retryAfterSeconds?, receipt?}}` with codes listed in
`backend/src/contracts.ts`. Swift mirrors: `Packages/DoddyCore/Sources/DoddyCore/ConnectedApps/ConnectedAppsContracts.swift`.

## Capability registry

`backend/src/capabilities.ts` (server, enforced) and the Swift contracts (client, display only).

| ID | Version | Risk | Confirmation | Enabled | Grants | Bounds | Retry | Status |
|---|---|---|---|---|---|---|---|---|
| `calendar.listEvents` | 1 | read | none (informed connection consent) | mock, live | any of `calendar.events.readonly`, `calendar.readonly`, `calendar.events.owned.readonly`; nothing outside the read/identity allowlist | 1 local day, ≤ 7 days ahead, ≤ 3 pages × 50, ≤ 100 events, titles ≤ 200 chars, 10 s timeout | 2 retries, 250 ms → 2 s cap, honours Retry-After ≤ 2 s | implemented |
| `calendar.createEvent` | 0 | write | fresh per execution, bound to user/capability/account/argument digest/expiry/single use | **none** | — | — | never | planned (no handler) |

Execution order (server): authenticated owner → capability enabled → connection active → grants read-only →
argument schema → confirmation (if required) → usage reservation → provider call → normalization → receipt.

## Scope rationale

- **Requested:** `https://www.googleapis.com/auth/calendar.events.readonly` — "Reads events on all your calendars"
  (Google scopes page, 2026-10-09). The narrowest documented scope that covers `events.list` on the primary calendar
  for this purpose. `calendar.events.owned.readonly` is narrower (owned calendars only) and also accepted if granted,
  but whether the Composio tool works with it alone is unverified.
- **Accepted if granted:** the read scopes above plus identity scopes (`openid`, `email`, `profile`, `userinfo.*`).
- **Refused:** anything else (e.g. `calendar`, `calendar.events`). A write-capable grant puts the connection into
  `permission_insufficient / grant_not_read_only`; reads are blocked server-side. If the granted scope list is not
  exposed by Composio, the connection is `grant_unverifiable` and live reads stay blocked.
- **Configuring it:** Composio docs say scopes are set on the auth config (`credentials.scopes`, also for the managed
  app) and apply to **new connections only**; existing users must reconnect. Composio's default Google Calendar
  scopes may be broader than this feature needs — do not use the default auth config unchanged.

## Mock and live setup

### Mock (no account, no secrets)

```sh
cd backend && npm ci && npm run build
DODDY_MODE=mock npm start            # 127.0.0.1:8787, tokens dev-user-a / dev-user-b
```
App (Simulator): Settings › Connected Apps server → `http://localhost:8787`, session token `dev-user-a` → Connected
Apps. The demo connection is a tap ("Connect demo calendar"); no Google page is ever shown. Mock scenarios for manual
testing: send header `x-doddy-demo-scenario: empty|many|malformed|provider_error|rate_limited|timeout|expired|insufficient_scope|broad_scope`
(e.g. with curl; the app does not send it).

### Live (human consent required)

1. Composio project for development (separate from any production project). Create a Google Calendar auth config
   with scopes `https://www.googleapis.com/auth/calendar.events.readonly` (prefer a custom auth config with Doddy's own
   Google OAuth client; Google "Testing" mode limits who can consent and how long refresh tokens last).
2. Pick and pin the toolkit version for `googlecalendar` (YYYYMMDD_NN).
3. Expose the backend over HTTPS (e.g. a tunnel for development) and set `DODDY_PUBLIC_BASE_URL`.
4. Recommended: enable the project's OAuth callback verifier with URL `<DODDY_PUBLIC_BASE_URL>/v1/oauth/verify` and keep
   `COMPOSIO_COMPLETION_MODE=verifier`. Otherwise `callback` mode, development only.
5. `DODDY_AUTH_MODE=signed`, `DODDY_SESSION_SIGNING_KEY=$(openssl rand -base64 32)`, then
   `npm run session:mint` and paste the token into the app (stored in Keychain).
6. `DODDY_MODE=live npm start` (fails to start if anything is missing). Connect from the app; a human completes Google
   consent. Then `npm run live-check` (read-only, counts only) with `DODDY_LIVE_CHECK_USER_ID` = the minted user.

## Costs and limits

Composio pricing page, checked 2026-10-09 (new pricing for sign-ups on/after 2026-08-15; existing customers keep their
plan through 2026-12-31): Hobby $0 with 100,000 tool calls/month, of which Composio-managed OAuth may use up to 20,000;
usage pauses at the cap. Pro $29/month (includes $29 usage credit): $0.0003 per call with your own OAuth app, $0.0005
per call on managed OAuth past the 20K managed allowance; **direct execution outside a Session adds $0.0001 per call
on Pro** (Doddy's backend uses direct `tools.execute`). Meta tools are free. Connected accounts beyond the first 1K on
managed apps cost $0.10 each on paid plans. Source: [composio.dev/pricing](https://composio.dev/pricing).

What counts in Doddy's flow (estimated, not metered): one `link` per connect attempt, `get` + `list` per completion,
one `tools.execute` per page (1–3 per read, plus retries), `revoke` + `delete` per disconnect, `get` per status check.
Whether management calls (`link`, `get`, `list`) count as "tool calls" is **unknown**; only `tools.execute` is clearly a
tool call. Doddy therefore counts **every** provider call against its own ceilings.

Doddy ceilings (config, defaults): 30 reads/user/day (120 requests/user/day including refused ones); per-user provider
calls ≤ min(reads × pages × 3, ¼ of the service daily cap); 300 provider calls
service-wide/day; 3,000/month; 1 concurrent call per user, 4 service-wide; 10 s timeout. Counters are in SQLite (UTC
periods) and survive restarts; concurrency is per process (single-instance deployment). **Monetary cost: estimated
only; actual metered cost unknown** until Composio usage APIs are wired. No plan upgrade or paid fallback exists in code.

## Phases and blockers

| Phase | State |
|---|---|
| Provider-independent contracts, registry, policy, mock adapter, tests | Done (mock-tested) |
| Composio adapter against SDK 0.22.0 declarations | Done (type-checked; exercised with a fake SDK client; **never called Composio**) |
| SwiftUI Connected Apps | Written; core logic tested on Linux; **app not compiled** (no Xcode) |
| Live connection with the owner's Google account | **Blocked**: needs Composio API key, auth config with read-only scope, pinned toolkit version, HTTPS URL, verifier decision, human consent |
| Production | **Blocked** by design: needs real app sign-in, own Google OAuth client + verification, privacy review, hosting decision |

## Evidence

| # | Claim used | Source | Checked | Outcome |
|---|---|---|---|---|
| E1 | `link()`, `get()`, `list({userIds,…})`, `revoke()`, `delete()`, `completeAuth()`, `tools.execute(slug, {userId, connectedAccountId, version, arguments}, {signal})`; `initiate()` deprecated for managed OAuth; retrieve response has no user ID; `state.val.scope` exists; `state` contains tokens | `@composio/core` 0.22.0 type declarations (`node_modules/@composio/core/dist/*.d.mts`) | 2026-10-09 | Verified (declarations); compiled against |
| E2 | `GOOGLECALENDAR_EVENTS_LIST` input/output schema (fields, `timeMin`/`timeMax` semantics, `fields`, `pageToken`) | Composio tool-schema API, fetched read-only through the owner's Composio MCP connector (no execution, no connection) | 2026-10-09 | Verified (current schema; version string not reported by that API) |
| E3 | Scopes set on auth config (`credentials.scopes`, managed app allowed); new connections only | [Controlling scopes](https://docs.composio.dev/docs/authentication/controlling-scopes) | 2026-10-09 | Verified (docs); not tested |
| E4 | Callback appends `status` and `connected_account_id`; "Callback query parameters alone aren't proof of ownership" | [Manual auth management](https://docs.composio.dev/docs/authentication/manually-authenticating) | 2026-10-09 | Verified (docs). That page now documents `session.authorize()`; `link()` comes from E1 |
| E5 | Direct execution needs a toolkit version; separate projects per environment; keys server-side; `tools.execute` is sent exactly once (no SDK retry); a Connect Link alone is not an end-to-end test | [Production readiness](https://docs.composio.dev/docs/production-readiness) | 2026-10-09 | Verified (docs) |
| E6 | OAuth callback verifier: Composio redirects to the project's verifier with a single-use `session_uri`; server calls `complete_auth` with the signed-in user's ID | SDK 0.22.0 `completeAuth` declaration (E1); production page `docs.composio.dev/docs/oauth-callback-identity-verification` **404**; content seen only on a preview deployment via search | 2026-10-09 | **Plausible** — wire-up is tested with a fake; verify availability before relying on it |
| E7 | Pricing figures above | [composio.dev/pricing](https://composio.dev/pricing) | 2026-10-09 | Verified (page); billing behaviour for management calls unknown |
| E8 | Google Calendar scope names and descriptions | [Google Calendar API scopes](https://developers.google.com/workspace/calendar/api/auth) | 2026-10-09 | Verified; sensitivity classification not on that page (Unknown) |
| E9 | Monid OAuth authorises Monid account access only | [Monid OAuth quickstart](https://docs.monid.ai/guide/quickstart-oauth.html) | 2026-10-09 | Verified (docs) |
| E10 | EventKit full/write-only access, no read-only grant | Apple docs page did not render for automated fetch | 2026-10-09 | **Unverified** — re-check before stage 3 |
