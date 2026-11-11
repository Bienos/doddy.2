Audited memory at `7a651eb`; four source-grounded reports and five Mermaid diagrams are in `docs/architecture/memory-rag/`.
Recall excludes lists/private notes before limits and ranks lightweight SQLite rows; voice/Siri recheck privacy. Conversation history is committed before publication, semantic caches invalidate on note changes, and voice recap generation rechecks consent and avoids duplicate work.
Validation and synthetic before/after metrics: `DODDY-MEMORY-RAG-IMPLEMENTATION.md`. iPhone simulator unit suite: 168 passed, 1 model-availability skip, 0 failures. No live voice/provider/device test or deployment.
No new runtime dependency or migration. Account-scoped local storage and source-to-summary deletion remain unresolved; this is not a completed multi-account memory rollout.
