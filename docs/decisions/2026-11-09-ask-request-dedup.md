# Ask Doddy answers a repeated request id once, from memory, for ten minutes

- **Date:** 2026-11-09
- **Decided by:** owner, 13 Nov 2026: "Scal" on #429, which carried the proposal (research item 10, `Doddy-optimization-research-2026-11-09`) onto `main`; and, 14 Nov 2026, "Ogarnij ten render sam albo co zrobić" for the deploy
- **Status:** applied in #429 (carried onto `main` of 13 Nov from `claude/amazing-bardeen-9dkkui`, commit `70bc7034`). Deployed on `doddy` (Render, by hand) on 14 Nov 2026: deploy `dep-dbrvaidg1s2s73do2ru0` of `1ceb1d8b`, live 05:45:52 UTC. After it `/v1/health` and Doddy Web answered 200 and the logs held no error or warning. Not seen: a real repeated request on the live service.
- **Replaces:** none

## Why
`POST /v1/assist` validates and echoes `requestId` (`backend/src/assist.ts`) but never used it. A phone whose reply was lost (a timeout at 35 s while the server finishes at 30 s, a dropped connection) retries and pays Anthropic for the same generation again, and spends a second daily question.

## Decision
- The request id is an idempotency key, scoped to the account: key = account id + request id (lower-cased). Another account with the same id never meets it.
- A **fingerprint** (SHA-256 of the validated request, with the id lower-cased) is stored beside it. The same id with a different question, notes or locale is refused with `invalid_request`; it is never answered with the old answer.
- First request runs. A duplicate that arrives **while it runs waits and shares its outcome** (the answer, or the same error). A duplicate **after it finished** gets the recorded reply. Neither reserves a daily question or calls Anthropic.
- **Only a success is remembered.** A provider error, a timeout, a refusal, an unreadable answer or a quota refusal removes the entry at once, so the next try with the same id runs for real. An unknown outcome is never stored as done.
- **Retention, conservatively:** the finished reply (the user's private answer, which may quote their notes) is held in this process's memory only. It is not written to the database or to any analytics table, and is not logged. It expires after **10 minutes**, with at most **10 entries per account** and **500 in total** (oldest finished entries go first; if the memory is full of running requests, a new request simply runs unremembered). Deleting the account drops its entries immediately (`AccountEraser` `forget` hook).
- Ten minutes covers the client's retry window with a wide margin, and is short enough that the held reply is not a second copy of the user's data for any meaningful time.

## Consequences
- Fewer duplicate Anthropic charges and no double count against the daily cap on a retry. The ledger (`claude_usage`) shows one generation for such a request.
- A restart or a second server instance forgets the answers, so a retry that lands there runs again: today's behaviour, never worse. If the server is later scaled to several instances, put the key (not the reply) in the database with an in-flight marker, or route by account; the reply must stay encrypted per the existing memory cipher if it is ever stored.
- A client that deliberately re-sends the same id to get a *fresh* answer now gets the first answer for ten minutes. The app generates a new id per question; the one existing app path that reused an id was a test fixture.
- Chat (`/v1/web/chat`) has no request id and is unchanged. Voice is untouched.

## Evidence
13 Nov 2026, on `main` `89c38a5f` plus this change: `npm run typecheck` and `ask-dedup.test.ts` with `assist.test.ts` (31 tests, 0 failures); the whole backend suite result is in the pull request.

`backend/test/ask-dedup.test.ts`: replay costs no generation and no quota; cross-account isolation; mismatched content refused; in-flight duplicates share one generation and the same error; failures, refusals, malformed answers and quota refusals are not cached; TTL, per-account and total caps; account deletion drops answers. Not run: a multi-instance deployment or a real phone retry.
