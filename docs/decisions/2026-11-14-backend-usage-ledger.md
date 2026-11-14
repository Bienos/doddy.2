# The backend keeps a content-free ledger of its Anthropic calls, per account

- **Date:** 2026-11-14
- **Decided by:** proposal, owner approval pending (the owner asked on 14 Nov 2026 to port the cost branch's pieces one at a time and said "Go ahead" for this one; the privacy wording is theirs, owner queue 98)
- **Status:** applied in the pull request that adds `backend/src/usageLedger.ts`
- **Replaces:** nothing. It is research item 1 of the cost branch `claude/amazing-bardeen-9dkkui` (9 Nov 2026), ported onto `main`.

## Why
`doddy` calls Anthropic for Ask Doddy, the web chat, `ask_claude`, documents, decks, the trip planner and travel-email reading, and nothing recorded what any call cost or whether the prompt caching of #460 saves anything: the response's `usage` was read for two counters and thrown away. No dollar limit exists on the key (owner queue 2), so cost per account was invisible.

## Decision
- One row in the new table `claude_usage` for every HTTP call to Anthropic, a failed call included: account, provider, model, feature, request id, the call's number in its request, whether it was the first call, a continuation or a retry, outcome, a content-free error code, the stop reason when it is a plain word, the provider's own token counters (input, output, cache writes with the one-hour part, cache reads), and a cost in nano-dollars from a price table with a version string (`PRICE_VERSION`).
- **No text of any kind**: no prompt, material, answer or provider error message. A failed call whose usage the provider didn't report is a row with `usage_known = false` and no numbers: unknown is not zero, and a model with no price gets no cost, counted separately as unpriced, never guessed.
- Features recorded: `ask_doddy`, `memory_chat`, `ask_claude`, `make_document`, `make_deck` (the plan and each write, a scope per call so only a re-ask with the schema as words or a cache-mark retry is marked a retry), `travel_plan` and `travel_scan` (a scope per email). **Not recorded:** voice sessions (ElevenLabs) and everything the messaging server calls Anthropic for (a later piece). Totals from this table must never be presented as the whole cost.
- Rows go with the account (`ERASED_TABLES`, tested against the live schema) and are pruned after 400 days. Reads are per account (`claudeUsageByAccount`). No endpoint or page shows the ledger yet.
- A ledger write that fails never fails the person's request; it is logged with no content.
- The price table has Opus 5.5, Opus 5 and 4.x, Sonnet 5.5, 5 and 4.x, Haiku 5.5 (with its above-100,000-token tier) and 4.5, and Fable 5.1 and 5.2 (added 14 Nov from the claude-api skill's table, cache reads 0.025x). Fable 5 has no row.

## Consequences
- Cache hits and misses of #460 become visible per feature, once `doddy` is deployed with this.
- It is new account-linked data about use: the privacy policy draft names it (`docs/legal/PRIVACY_POLICY_DRAFT.md`, backend rows) and the published policy needs the owner's wording (owner queue 98). Nothing here is a privacy guarantee.
- Storage: about 150 bytes a row, one row per call; the table is created when `doddy` starts (no migration file; the backend makes its tables at start).
- Prices change: `PRICE_VERSION` says which table priced a row, so old rows keep their meaning.

## Evidence
`backend/test/usage-ledger.test.ts` (rows, counters, unknown usage, per-account isolation, erasure, pruning, the schema's checks, a cache-mark retry as two rows, the travel reader's scopes), `backend/test/decks.test.ts` (one row per deck call). Not run: a live Anthropic call, so no real `usage` object was read; the counters are read from the documented response fields.
