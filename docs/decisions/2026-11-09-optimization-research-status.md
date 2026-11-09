# Status of the 16 optimization recommendations (9 Nov 2026 research)

- **Date:** 2026-11-09
- **Decided by:** owner asked for the research's justified improvements to be applied ("Apply the improvements described in this file", 9 Nov 2026); voice sessions explicitly out of scope.
- **Status:** applied on branch `claude/amazing-bardeen-9dkkui` for review; nothing deployed.

## Why
`Doddy-optimization-research-2026-11-09.md` listed five verified findings and 16 opportunities. This page records what each became. Measured numbers come from local, synthetic runs (pglite or a disposable Postgres 16), never production.

## Status by recommendation

| # | Recommendation | Status | Where |
|---|---|---|---|
| 1 | Account-linked cost ledger | **Implemented** for the backend (`claude_usage`) and the messaging server (`provider_cost_events`, migration 026): account, model, feature, request id, cache read/write, retries, failures (usage unknown, never zero), no content. Not voice metering. No owner/admin route yet. | `changes/backend-usage-ledger.md`, `changes/messaging-cost-ledger-polling.md` |
| 2 | Reserve dollars and SMS segments before work | **Implemented** for Studio (pre-call ceiling) and SMS (segment counters, migration 023). **Deferred:** a dollar reservation for backend Ask/chat (their per-account request quotas stay; the ledger now provides the data to set one). | `changes/studio-precall-budget.md`, `changes/sms-segment-budget.md` |
| 3 | Bound Studio's next call by the remaining budget | **Implemented.** Reproduced first ($0.204 spent against a $0.05 limit); now never dispatches a call whose worst case exceeds the budget. | `server/messaging/src/studio/budget.ts` |
| 4 | Segment-budgeted SMS | **Implemented.** Estimator (GSM-7 / UCS-2), 3-segment reply budget, Polish letters never stripped. 600-char Polish reply: 9 → 3 segments. | `server/messaging/src/smsSegments.ts` |
| 5 | Cache eligible Claude prefixes | **Implemented, narrow.** Only fixed instructions above the model's minimum are marked; user material never. Hit rate **not measured** (no live calls). | both changes notes |
| 6 | Route models by task difficulty | **Deferred, prepared.** `server/messaging/scripts/model-benchmark.mjs` (dry-run tested; live mode needs a key and is never run in CI). No model was changed. | `changes/messaging-cost-ledger-polling.md` |
| 7 | Adaptive idle polling | **Implemented.** 2 s → 30 s back-off with `LISTEN/NOTIFY` wake; scheduled and task calls unchanged. Fake clock: 1,801 → 124 idle passes per hour per loop. | `idlePoll.ts`, `wake.ts`, migration 027 |
| 8 | SQL pagination for notes | **Implemented.** 100-note page of 5,000: 5,000 → 100 rows, ~94 ms → ~7 ms (pglite, local). Search untouched. | `changes/notes-sql-pagination.md` |
| 9 | Versioned incremental sync | **Deferred (design only).** Cross-device overwrite reproduced in tests; design proposed. Build before `IPHONE_SYNCS_MEMORY` is turned on for multi-device accounts. | `2026-11-09-incremental-sync-design.md` |
| 10 | Deduplicate Ask requests | **Implemented.** Same account + request id within 10 min returns the first answer; in memory only, per process. | `2026-11-09-ask-request-dedup.md` |
| 11 | Reuse public news summaries | **Deferred.** Needs overlap data; the writer call now has its own ledger tag and a public-story fingerprint to measure it. | `changes/messaging-cost-ledger-polling.md` |
| 12 | Batch work that can wait | **Deferred.** Needs an asynchronous result path and a retention/eligibility check first. | — |
| 13 | Public web delivery | **Implemented at the origin** (ETag/304, brotli/gzip, in-memory copy). Edge behaviour unverified. | `changes/web-static-delivery.md` |
| 14 | Persistent provider-file cleanup | **Implemented.** Pending deletion recorded before the first attempt, cleared only after a 404 read-back, backoff, stuck reporting. | `backend/src/providerFiles.ts` |
| 15 | Right-size hosting | **Deferred: owner decision.** Needs invoices and the real Render/Supabase account state. Nothing created or changed. | research file, "Hosting options" |
| 16 | Versioned releases, staging, outcome metrics | **Partly:** the ledger gives cost per feature and per account. **Deferred:** staging and version reporting are deployment decisions. | — |

Already resolved before this work (not repeated): the account token refresh before server linking (#268); account linking, `accounts.auth_subject` and sign-in on both servers.

## Decisions and steps that stay with the owner
- **Studio default limit:** the conservative ceiling makes the highest tier ("Fable max") stop with `cost_limit` before research at the $2 default (its research allowance alone is about $3). Raise `STUDIO_JOB_LIMIT_USD` for that tier, or accept it.
- **SMS:** confirm the daily caps (120 segments per account, 1,200 per server) and the 3-segment reply budget; decide whether full SMS answers should ever be stored for the app.
- **Deploy:** migrations 023, 026 and 027 apply on the messaging server's next migrate; the backend creates `claude_usage` and `provider_file_deletions` at start (`CREATE TABLE IF NOT EXISTS`). `LISTEN` needs a direct Postgres connection (not a transaction-mode pooler). None of this was applied.
- Whether to add an owner/admin usage route over the ledgers.

## Evidence
Run: messaging `npm test` against a disposable Postgres 16; backend suite on pglite. Not run: any live Anthropic, Twilio, Render, Supabase or voice call; `scripts/ci.sh --only checks` ran except the Studio skills renderers (python reportlab/matplotlib missing); the iOS app and Mac job. Voice sessions were not touched.
