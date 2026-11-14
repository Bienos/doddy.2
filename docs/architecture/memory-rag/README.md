# DODDY memory audit and foundation — final report

10 November 2026. Initial audit/measurement baseline: `7a651eb`. Final implementation base: `b000ee19` after rebasing onto current `main`. Local branch: `feat/intelligent-memory-foundation`. Nothing was pushed, merged, deployed or uploaded.

**Recommendation:** keep the existing structured memory and SQLite/FTS5 foundation. Repair scope and lifecycle boundaries before adding semantic voice retrieval or another database. The focused repairs are implemented and verified; the entire Phase 1 is not complete.

## Answers to the twelve requested questions

1. **How does DODDY remember now?** Notes, lists, reviewed profile fields, learned facts/procedures and Messages live in one GRDB/SQLite database. The last ten voice conversations live in a separate protected JSON file. Optional recaps become notes; two separately consented server memory copies serve web/phone use.
2. **What works and what is missing?** Explicit saves, correction history, lexical recall, bounded voice startup context and typed Messages grounding are wired. Missing or incomplete: account separation in local stores, general local episode search, source-to-summary deletion, universal model abstention and broad paraphrase retrieval. The patch fixes private/list crowding, stale cache work, premature history publication and voice recap consent races.
3. **Does it need RAG now?** It already uses retrieved notes in generation. It needs more reliable retrieval and provenance; it does not currently need a new vector service.
4. **Simplest effective architecture?** Existing reviewed profile/confirmed facts + scoped local FTS5 + selected source-labelled context + live APIs for fresh state. Keep extraction outside the voice critical path.
5. **What can be reused?** `DoddyDatabase`, `SQLiteMemoryRepository`, `RepositoryRecallService`, `ProfileRepository`, `LearningService`, `VoiceStartupSnapshot`, `AssistantService`, `CitationVerifier`, `RecapKeeper`, native approval gates and existing settings. Keep the current semantic Find experiment isolated until evaluated.
6. **What needs adding?** Next: owner partition/legacy quarantine and source links/deletion coordination. Later: bounded queryable episodes, a deterministic retrieval plan and, only if justified, a versioned hybrid ranker. None requires a cloud vector database by default.
7. **How should memories be written/updated/retrieved?** Explicit Save or confirmed candidates, sensitivity/scope checks, duplicate/source tracking and committed read-back. Correct a known record with revision history. Supersede a canonical fact only after an explicit supported update; retrieve conflicting sources rather than choosing truth from recency. Apply owner/privacy/type/status/expiry before limits.
8. **Voice speed?** The patch adds no classifier/extraction/embedding call to each turn. At 5,000 synthetic notes on Mac Debug, medians changed from 93–102 ms to 61–87 ms; first-audio latency on an iPhone remains unmeasured. These are local storage results, not voice-speed claims.
9. **API/infrastructure cost?** Zero additional model/embedding calls or hosting dependencies from these repairs. Existing prompt token cost can change as better selection includes relevant notes. Real per-interaction dollar cost was not measured.
10. **Privacy protection?** Existing consent/local protection plus earlier private filtering, post-await rechecks, read-back verification, cache invalidation and voice recap revocation checks. Account isolation and complete derived/remote erasure remain release blockers for broader memory claims.
11. **What was implemented and verified?** Scoped SQL recall and selected-row materialization; privacy rechecks in voice/Siri/fallback; confirmed history writes/corruption recovery; semantic invalidation across suspended work; voice recap consent epochs and concurrent deduplication. On the rebased branch: 2,876 package tests passed, two opt-in diagnostics skipped; 168 iPhone simulator unit tests passed, one availability skip; final app compile passed. CI reported 26 passing steps and one existing GNU-sed/macOS portability failure in the Studio negative-renderer fixture.
12. **What remains?** Owner-scoped migration, source-linked erasure and pending jobs, queryable episodes, natural-language correctness/false-memory evaluation, EN/PL semantic calibration, and real supported-iPhone voice/resource tests. Thirteen diagnostic retrieval cases gave Recall@5 7/9; both deliberate paraphrases were missed. No production readiness or full Phase 1 completion is claimed.

| Priority | Improvement | User benefit | Complexity | Status |
|---|---|---|---|---|
| P0 | Local account isolation | Personal data stays with its owner | High | Proposed; not implemented |
| P0 | Source/derived/remote deletion | Accurate forgetting | High | Proposed; not implemented |
| P1 | Scoped, lighter lexical retrieval | Finds eligible notes with less local work | Medium | Implemented and measured locally |
| P1 | History/cache/voice recap reliability | Fewer stale or revoked memories | Medium | Implemented; unit tests/compile passed |
| P2 | Episodic and hybrid retrieval | Better continuity and paraphrases | Medium/high | Designed; rollout gated |

## Documents and evidence

- [Repository audit](DODDY-MEMORY-RAG-AUDIT.md): actual paths, defects, current architecture and immutable source anchors.
- [Research](DODDY-MEMORY-RAG-RESEARCH.md): official sources, recent papers, candidate comparisons and three implementation options.
- [Architecture](DODDY-MEMORY-RAG-ARCHITECTURE.md): memory categories, schema/lifecycle/retrieval design, five diagrams across audit/design, agent scenarios and privacy.
- [Implementation and verification](DODDY-MEMORY-RAG-IMPLEMENTATION.md): phased plan, actual repairs, exact commands, test outcomes, benchmarks, constitution evidence and rollback.
- [Timing observations](retrieval-benchmark.json), [quality diagnostic](retrieval-evaluation.json), [verification counters](verification.json).

The source patch has no database migration or new runtime dependency. The unchanged Studio portability check failure must be addressed or run with its expected GNU environment before claiming the whole checks group is green. No test was skipped or weakened to conceal it.
