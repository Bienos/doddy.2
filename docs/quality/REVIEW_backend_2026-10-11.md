# Review — `backend` (Connected Apps, 2026-10-11)

Read-only review. No code changed. Scope: `backend/src/**`. I read the core paths in full: `app`, `auth`, `http`, `service`, `policy`, `tools/service`, both Composio adapters, and the write tools in `tools/catalog`. The others I only skimmed or grepped: `store`, `config`, `websearch`, and the read tools in `catalog`.

## Tests run

| Command | Environment | Result |
|---|---|---|
| `npm ci && npm test` (runs the `tsc` build first) | Node 22.22.0, Linux container | **122 pass, 0 fail, 0 skipped** |

Not run: live Composio, Google, Gmail, Drive, Notion, Todoist or Monid; the live web-search test needs keys. All provider responses in the tests are mocks.

## Findings (most severe first)

No critical issues found. Several areas are strong:
- Signed sessions, and dev identities that only work on loopback.
- No route that proxies a tool slug, URL or connection id.
- Grants re-checked on every run.
- Write approvals bound to user, tool, account and an argument digest, with one use and a 120 s expiry.
- Writes never retried.
- Content-free logs and receipts.
- Local disconnect first, then remote cleanup, with failures reported.

### Medium

1. **`src/tools/service.ts:450-469` — a write can be reported as "failed" after it happened (DOD-08)**
   - **Problem:** Only `provider_timeout` and `provider_unavailable` become `outcome_unknown`. Suppose Composio returns and the reply then fails `normalize` (`malformed_provider_result`, e.g. the draft `id` is missing or the response shape changed). The receipt then says "*wasn't reached or its answer couldn't be used. Nothing is shown*", with status `failed`.
   - **Failure scenario:** The Gmail draft or Todoist task was created. The user is told it failed, confirms again, and gets a duplicate.
   - **Fix:** For writes, use `failed` only for codes that prove nothing ran (`rate_limited`, `quota_exceeded`, `busy`, `connection_expired`, `permission_insufficient`). Everything else becomes `outcome_unknown` with the "check there before trying again" text.

2. **`src/service.ts:224-245, 267-272` and `src/tools/service.ts:243-260, 280-284` — a failed completion can leave a live grant Doddy doesn't track**
   - **Problem:** After the remote connection becomes active, several failure paths throw without recording the connection or queueing its removal: `verification_failed`, `attempt_mismatch` in verifier mode, and a provider error during `getConnection`/`isOwnedBy`.
   - **Failure scenario:** The user's Google, Gmail or Drive grant stays active at Composio, possibly with broad scopes. Disconnect can't remove it because it doesn't know about it, and the attempt has already been used up.
   - **Fix:** On those paths, queue cleanup for ids known to belong to this user (`attempt.pending_connection_id`, and the id returned by `completeVerifiedAuth`, which is scoped to this user's Composio id). Try `removeConnection` and report it in `remoteCleanup`. Never queue the unverified callback-mode `connectedAccountId` hint.

### Low

3. **`src/tools/service.ts:403-429`**
   - **Problem:** The approval is consumed *before* the quota and concurrency checks.
   - **Failure scenario:** A `quota_exceeded` or `busy` refusal still uses up the user's confirmation, so they have to confirm again.
   - **Fix:** Reserve the tool run first, then consume the approval (an unapproved request is still refused before the provider is called).

4. **`src/providers/composio.ts` vs `src/tools/composio.ts` — duplicated adapter code that has already drifted**
   - **Problem:** `mapStatus`, `guard` and `removeConnection` are duplicated. The calendar version stops when revoke times out; the tools version goes on to call `delete` with the already-aborted signal.
   - **Failure scenario:** The two adapters treat the same Composio error differently, and later fixes land in only one of them.
   - **Fix:** Move the shared helpers into one module used by both adapters.

5. **`src/store.ts` — nothing is ever pruned**
   - **Problem:** `attempts`, `approvals`, `usage` counters, `receipts` and `tool_receipts` grow forever, and no route erases a user's data.
   - **Failure scenario:** Disk use grows without bound, and there is no retention story for DOD-11.
   - **Fix:**
     - (S) Prune expired attempts and approvals, usage periods older than two months, and receipts beyond the newest 200 per user or older than 90 days.
     - (Decision) An account-erase route; sessions are owner-minted today.

6. **`src/providers/composio.ts:218`**
   - **Problem:** Any 404 or 410 becomes `connection_expired`. For `tools.execute` a 404 can also mean an unknown tool slug or version (a server configuration problem).
   - **Failure scenario:** The user is told to reconnect, and every tool in that toolkit is switched off, for a problem on Doddy's side. Not verified against the Composio API.
   - **Fix:** Map 404 to `connection_expired` only for connected-account calls (`ComposioConnectedAccountNotFoundError` is already handled separately). For `execute`, use `provider_unavailable`.

## Missing tests

- A write whose reply is malformed after the provider ran it (finding 1).
- A completion that fails verification after the connection is active (finding 2).
- The approval survives a `busy` or `quota_exceeded` refusal (finding 3).
- Revoke times out in the tools adapter (finding 4).
- Pruning (finding 5).

## Top 5 fixes

| # | Fix | Finding | Effort | Risk |
|---|---|---|---|---|
| 1 | A write with an unreadable reply → `outcome_unknown`, not `failed` | 1 | S | Low |
| 2 | Queue remote cleanup when a completion fails after the grant is active | 2 | M | Low–Medium (touches the connect flow) |
| 3 | Reserve the tool run before consuming the approval | 3 | S | Low |
| 4 | Prune expired attempts and approvals, old usage and receipts | 5 | S | Low |
| 5 | One shared Composio helper module | 4 | S | Low |

## Constitution evidence log

- **DOD-07:**
  - Write approvals are bound to user, tool, connection and an argument digest, single-use, and expire after 120 s (`tools/service.ts:379-419`, `store.consumeApproval`).
  - The preview shows the exact fields.
  - The provider gets only `toArguments(args)`.
  - Tested (`tools.test.ts`).
- **DOD-08:**
  - Writes never retry (`maxRetries: 0`).
  - A timeout or provider error on a write gives `outcome_unknown`.
  - Gap: finding 1.
  - Disconnect reports `outcome_unknown` when remote cleanup fails.
- **DOD-11:**
  - Logs hold the route template, status and timing only.
  - Receipts hold counts, not content.
  - Web-search queries are not stored.
  - Store keys use a separate Composio user id.
  - Gaps: findings 2 and 5.
- **Claims to limit:** Everything was tested against mocks. No live Composio or OAuth flow was run.

---

## Fix status (2026-10-11, owner approved "fix all")

| # | Status | Commit |
|---|---|---|
| 1 | fixed: writes are `failed` only for codes that prove nothing ran; otherwise `outcome_unknown` | `0fef8b3` |
| 2 | fixed: a completion that doesn't end recorded removes the remote connections known to be this user's (the pending id, or the redeemed id); a failed removal stays queued, shows `remoteCleanup: failed` and is retried before the next connect. The callback hint is never removed. The tests fail on the old code. | `ad7db03` |
| 3 | fixed: approval checked first and consumed right before the provider call, inside the concurrency slot | `c4ee2bc` |
| 4 | fixed: `providers/composioShared.ts` used by both adapters; a revoke timeout stops before delete in both | `1d14bca` |
| 5 | fixed (pruning): `Store.prune` at start and hourly. **Erase-account route: not built, owner decision.** | `36a7376` |
| 6 | fixed: a 404 on `tools.execute` → `provider_unavailable`; `ComposioConnectedAccountNotFoundError` still → `connection_expired`. Not verified against the real Composio API. | `1d14bca` |

Tests after the fixes: `npm test` (includes the `tsc` build) → **132 pass, 0 fail** (Node 22.22).

**Behaviour changes to note:**
- A canceled or denied connect now also deletes its pending Composio connection.
- Completing a connect can take a little longer when cleanup runs.
- Receipts older than 90 days, or beyond the newest 200 per user, are deleted.

## Follow-up (2026-10-12, DODDY Brain audit §5 #4, ADR-445)

Finding 2's fix covered completions that fail **after** the attempt is consumed. Three ways a sign-in could still leave a live grant that Doddy didn't track:
1. **Superseded:** a second Connect ended the first attempt (`createAttempt`) but left its pending connection at Composio, where the user could still finish it.
2. **Late completion:** `complete` on an expired attempt threw `attempt_invalid` and removed nothing.
3. **Abandoned:** the user finished consent in the browser but never returned to Doddy. A day after expiry, `prune` deleted the attempt row and with it the only copy of the connection id.

Fixed: ending an attempt without redeeming it (supersede, expiry, or a link that arrives after a supersede) queues its pending connection for removal **in the same transaction**, unless the connection is recorded as a Doddy connection. Connect and a late `complete` remove it at once. An hourly sweep (`sweepAbandoned`, run before `prune`) ends expired attempts and retries failed removals: rows older than 5 minutes, 20 per sweep, 24 tries per row. A row past that stays visible as `remoteCleanup: failed` and is still retried before the next Connect. `test/abandoned-attempts.test.ts` (7 tests) and the updated supersede test; the two HTTP-level ones fail on the old code. `npm test`: 195 pass. Not run against the real Composio API.

**Behaviour changes to note:** a second Connect deletes the first link's pending connection, so the first link no longer works (it never could be completed). `remoteCleanup` can briefly read `pending` or `failed` after a Connect if that removal is slow or fails.
