# Reuse local memory and repair lifecycle boundaries before expanding retrieval

- **Date:** 2026-11-10
- **Decided by:** engineering recommendation within the user's memory audit/implementation request; broader rollout is proposed for owner review
- **Status:** focused repairs implemented locally; architecture rollout proposed
- **Replaces:** none

## Why

The repository already wires GRDB/SQLite, FTS5, approved profiles, confirmed learning, recent conversations and opt-in recaps. The audit found scope/limit, persistence, cache and consent races. Adding a vector service would leave those defects and account isolation unresolved.

## Decision

Keep the existing database and source-grounded lexical retrieval for the MVP. Apply scoped filtering before limits, load selected records after ranking, verify history writes, invalidate derived vectors and recheck voice recap consent. Add no runtime dependency or schema migration in this slice. Expanded automatic/semantic retrieval waits for account isolation, source-linked deletion and measured EN/PL benefit.

## Consequences

Fewer redundant decoded rows and more reliable recall under privacy restrictions. No additional embedding/extraction/router API calls from these changes. Local account ownership, remote cleanup, queryable episodes and general paraphrase recall are not solved by this patch.

## Evidence

Four reports, exact commands, test results, before/after measurements and limitations: [memory implementation evidence](../architecture/memory-rag/DODDY-MEMORY-RAG-IMPLEMENTATION.md). No merge, deployment or live prompt change.
