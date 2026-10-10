# Security and permissions — Connected Apps

Date: 2026-10-09. Applies to `backend/` and `DoddyApp/Features/ConnectedApps`. This describes what the code does and
what remains open. **No GDPR, AI Act or App Store compliance has been assessed or certified.**

## Identity and ownership

- The backend derives the user from the `Authorization: Bearer` session only (`backend/src/auth.ts`). Request bodies
  are strict schemas; a `userId`, connection ID, calendar ID, URL or tool slug in a body is rejected (400).
- Internal user IDs are UUIDs. Each user gets a random Composio user ID (`doddy_<32 hex>`, `Store.composioUserId`) —
  never an email or a shared value such as `default`.
- One connection per user (`connections` primary key `(user_id, provider)`); a connection ID can belong to only one
  Doddy user (unique constraint, checked in a transaction).
- Every read, status check and disconnect looks up the connection **by the authenticated user**; there is no
  endpoint that takes a connection ID. The adapter passes both `userId` and `connectedAccountId` to Composio.
- Session mechanisms: `dev` (two fixed loopback identities; config refuses it unless mock mode + loopback host +
  non-production) and `signed` (HMAC-SHA256 tokens with expiry — default 7 days, max 30 — minted by the owner with
  `npm run session:mint`). Signed tokens cannot be revoked one by one; rotating `DODDY_SESSION_SIGNING_KEY` revokes all.
  **Production live mode is refused** until a vetted app sign-in (e.g. Sign in with Apple) replaces `signed`.

Tests: `backend/test/api-boundaries.test.ts` (unauthenticated on every route, cross-user status/read/complete/disconnect,
escape attempts, invalid arguments — each asserting zero provider calls), `config-auth.test.ts`.

## OAuth, PKCE and who does what

| Leg | Party | Notes |
|---|---|---|
| App → Doddy backend | Doddy session token | Bearer token from Keychain over TLS (http only on loopback for development) |
| Browser → Composio Connect Link → Google OAuth | **Composio's hosted flow** | Doddy never sees Google credentials or tokens. Whether Composio's hosted flow uses PKCE with Google is **not documented** in the pages checked; Doddy does not claim it and does not bolt a fake verifier onto the hosted link |
| Composio → Doddy completion redirect | Doddy backend (`/v1/oauth/return` or `/v1/oauth/verify`) → app return URL | Browser routes change no state; they forward allowlisted, well-formed parameters to the single configured return URL |
| App → Doddy `/complete` | Doddy session + attempt nonce | Server verifies everything again |

The app opens the link with `ASWebAuthenticationSession` (system browser, `prefersEphemeralWebBrowserSession = true`,
custom-scheme callback). No embedded web view or login form (RFC 8252; guard script enforces that web-auth code lives in
one file). No direct native/public-client OAuth flow is implemented, so no app-side PKCE is needed or claimed.

## Callback and state validation

1. `/connect` creates an attempt bound to the authenticated user, provider and auth config, with a 256-bit random
   nonce (only its SHA-256 is stored), 10-minute expiry, and the pending connection ID returned by `link()`. A new
   attempt supersedes any unfinished one.
2. `/complete` consumes the attempt **once** in a transaction: wrong user, provider, nonce, expired or already-consumed
   → `attempt_invalid`.
3. Callback mode: `status=success` is a hint. The returned `connected_account_id` must equal the stored pending ID.
   Verifier mode: `completeAuth({ userId: <this user's Composio ID>, sessionUri })` — Composio checks the pending
   connection's owner — and the returned ID must equal the stored pending ID.
4. Then, server-side and authoritative: `get(id)` must report `ACTIVE`, toolkit `googlecalendar` and Doddy's auth
   config; `list({ userIds: [composioUserId], authConfigIds })` must contain the ID; granted scopes must pass the
   read-only allowlist. A forged `success` therefore connects nothing.

**Residual risk in callback mode:** someone could start a link under *their* Doddy account and trick a victim into
completing Google consent, binding the victim's calendar to the attacker's Doddy account (the attacker's own
attempt/nonce would verify). Verifier mode closes this because only the browser that finished consent receives the
session URI and it is redeemed for the signed-in user. Hence: `verifier` is the default; `callback` is refused outside
`DODDY_ENV=development` (single-owner testing). Verifier availability is **Plausible**, not verified (production docs
page 404 on 2026-10-09).

Tests: `backend/test/oauth-completion.test.ts` — mismatched owner, wrong toolkit/auth config, ownership check failure,
tampered/swapped connection ID, missing/tampered/expired/replayed nonce, superseded attempt, forged success, completion
kind mismatch, verifier single use and cross-user session, redirect parameter allowlist, cancel vs denial.

## Secrets and tokens

| Secret | Where it lives | Never |
|---|---|---|
| Composio project API key | Backend environment / secret manager (`COMPOSIO_API_KEY`) | In the app, repo, logs, responses |
| Google access/refresh tokens | Composio (hosted credential owner) | Read by Doddy except the scope list; never returned, logged or stored (test plants a token in fake state and asserts it never appears) |
| Session signing key | Backend environment | In the app or repo |
| Doddy session token | iOS Keychain, `AfterFirstUnlockThisDeviceOnly` (not migrated to other devices) | UserDefaults, bundle, logs |
| Server URL | UserDefaults (not a secret) | — |

`.gitignore` covers `.env*` (except `.env.example`), keys, SQLite files, logs, `node_modules`, `dist`. The guard script
scans app, package, scripts, backend sources/tests, fixtures and `.env.example` for key-shaped strings.

## Authorization and confirmations

- Connection consent (Google/Composio), operation authorization (server pipeline), revocation (disconnect) and
  memory-save consent (explicit tap per event) are separate.
- Reads after informed connection consent need no repeated confirmation. Connect and disconnect are deliberate actions
  with a confirmation dialog in the app.
- Future consequential capabilities: `ConfirmationPolicy` binds an approval to user, capability, account, SHA-256 of
  canonical validated arguments, a 2-minute expiry and one execution (atomic consume). Changed arguments → different
  digest → rejected. Tested with a synthetic non-executing write capability. No real write handler exists;
  `calendar.createEvent` is disabled in every mode; the registry refuses write definitions without confirmation or with
  automatic retries.

## Untrusted content

Event titles are untrusted. They are length-bounded, stripped of control characters, displayed as plain text, and
never passed to an LLM by this milestone (the voice agent has no calendar tool). Event text cannot select tools, widen
scopes or change policy: there is no code path from provider output to the registry or to Composio.

## Data boundaries

| Data | Where | Retention |
|---|---|---|
| Saved memories | iPhone only (SQLite, Data Protection `completeUntilFirstUserAuthentication`, included in device backups) | Until the user deletes them; disconnecting Google does not delete them |
| Calendar results | App memory only (`ConnectedAppsModel.events`) | Dropped after `expiresAt` (15 min), on disconnect, on any non-connected state, or when a read fails |
| Sent to backend | Session token, the asked date, IANA time zone, connect/complete/disconnect requests | — |
| Backend store | User ↔ Composio ID map, attempts (nonce hash), connection metadata (ID, status, granted scopes, masked calendar label), receipts, usage counters | Indefinite in this milestone — **retention policy is an open decision** |
| Backend never stores | Event titles/times, descriptions, attendees, locations, memories, chat, contacts | — |
| Composio / Google | Composio holds OAuth tokens and its own execution logs; Google holds the calendar | Per their policies — **not reviewed** |

## Logs and receipts

- Access log per request: correlation ID, route template, status, duration, error code. No bodies, query strings
  (session URIs), tokens, user IDs or provider payloads. Unexpected errors log the error class name only.
- Receipts: operation ID, operation, capability, provider, masked label, time, mode, status (`succeeded`, `failed`,
  `canceled`, `blocked`, `outcome_unknown`), bounded summary (counts, date, zone — no titles), safe error code,
  provider reference only when Composio returned a `logId`. Mock receipts say `mode: mock` and never carry a reference.
- Test: `disconnect-privacy.test.ts` asserts logs, receipts, connection and attempt rows contain no event text,
  planted tokens, nonce, session URI or session token, and that no content tables exist.

## Disconnect and deletion

Disconnect deletes the local connection row and queues remote cleanup in one transaction, so reads are blocked
immediately. Then `revoke` (best effort; may be unsupported) and `delete`. If remote cleanup fails, the receipt is
`outcome_unknown`, the view shows `remoteCleanup: failed`, and disconnecting again retries. The user can also remove
access in their Google Account. Deleting a Doddy account / backend data export is **not built** (no accounts exist yet).

## Rate and cost enforcement

Every events request is counted per user per day (4 × the read limit) before anything — including a blocked receipt —
is written. Before every provider call the backend reserves usage atomically in SQLite: per-user reads/day, per-user
provider calls/day (never more than a quarter of the service's daily calls), service calls/day and /month; each page and
each retry reserves again. Disconnect and its remote cleanup are never blocked by quota. Per-user and service-wide
concurrency limits (per process). Safe reads retry at most twice with capped backoff; a `Retry-After` longer than 2 s is
returned to the client instead of waiting. No cache. Tests cover ceilings, retries, timeouts and rate limits.

## Outstanding privacy and production gates

1. Real app sign-in replacing owner-minted tokens; account deletion and data export for backend records.
2. Backend retention policy for receipts/attempts; log retention at the host.
3. Own Google OAuth client (custom auth config), Google verification as required, privacy policy URL.
4. Review of Composio's data processing terms, sub-processors, regions and retention; DPA if required.
5. Confirm verifier availability; otherwise keep live connections single-owner development only.
6. App Store privacy labels for data sent to the Doddy server (`PrivacyInfo.xcprivacy` currently declares audio and
   other user content for voice; calendar handling needs owner review).
7. TLS termination and hosting choice (none deployed; no paid resources created).
8. Independent human security review of `backend/` before any other person uses it (an automated reviewer pass on
   2026-10-09 found and we fixed one unauthenticated crash; see IMPLEMENTATION_STATUS.md).
9. Release builds should return via a universal link (https) instead of the `doddy-dev://` custom scheme.
10. Usage counter rows are kept per day/month and never pruned (small, but unbounded over years).
