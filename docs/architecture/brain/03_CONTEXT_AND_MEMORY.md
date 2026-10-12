# DODDY Brain 03: Context and memory

Canonical memory rules: `docs/architecture/MEMORY_AND_DATA.md`, `docs/architecture/LEARNING_LOOP.md`, ADR-247/252/310/440.
This page covers only **what may leave the device with a request**, and who decides it.

## Mapping to existing records (no new schema)
| Concept | Existing record |
|---|---|
| Working memory | `ConversationTurn` (Ask, in memory, last 6); live voice transcript (not stored unless kept) |
| Episodic | `ConversationLog` (kept voice chats, opt-in); `OutcomeEvent` (kinds only, 90 days); `MemoryRecord.capturedAt` + `MemoryCorrection` |
| Semantic | `MemoryRecord` (fact, place, item, decision, recommendation); `LearnedFact` (fact, place); `ApprovedProfile` |
| Preferences | `MemoryCategory.preference`; `LearnedFactKind.preference` (365-day expiry); profile style keys |
| Procedural | `Procedure` / `ProcedureStep` (run only through the plan card) |
| Relationship | `LearnedFactKind.person` only; Contacts and birthdays are read live, never stored |

## ContextAssembler (Phase 1, built)
`ContextAssembler.assemble(for:includeNotes:target:)` → `AssembledContext`
- **Retrieval:** the existing `RecallService` (FTS5 + matcher). The caller passes `ShareableRecallService`, so private notes never appear.
- **Relevance:** only notes that matched the request (`matchedTerms` non-empty), never "recent notes".
- **Egress contract:** `EgressTarget.assistantGateway.allowedNoteSources` equals the gateway's `SOURCES`. A test reads
  `gateway/src/validate.js`, so drift fails CI. Imported notes are **withheld and counted**, not sent, so the question still works.
- **Budget:** `GroundingBudget.standard` (5 notes, 12,000 scalars, never shortened).
- **Learned items:** `acceptsLearnedContext == false` for the gateway until its limits are raised (LEARNING_LOOP §5/§13).
- **Failure:** a search error returns `notesSearchFailed`, and the question goes without notes, as before. Cancellation is reported as cancellation.

## Gaps left for Phase 2 (decisions needed)
1. **Voice start context is not relevance-based.** `VoiceContext.savedNotes` sends the newest shareable notes up to 6,000 characters at every start. This was a product decision (V1) and is shown on the Privacy screen. Moving voice to `search_memories`-only, or to an `EgressTarget.voiceAgent` with a smaller budget, changes what Doddy "knows" when a conversation starts. **Owner decision.**
2. **Imported notes in Ask.** Either the gateway accepts `imported_file` (gateway change and redeploy), or they stay withheld. Withholding is the safe default, now built.
3. **Sensitivity on notes.** Only learned proposals have a sensitive filter (`SensitiveContentFilter`). Notes carry no sensitivity flag. Adding one is a schema change. Not proposed until a concrete leak case is shown.
4. **`{{user_profile}}` and `{{learned_context}}` outside DATA markers** (`voice-agent/instructions.md`); `ProfilePrompt.oneLine` does not strip markers. Fix in the voice target of the assembler.
5. One greedy-fill helper for `GroundingSelector` and `LearningContextAssembler`.

No embeddings or vector store: no retrieval failure has been shown that FTS5 plus `RecallMatching` (plus on-device
`MeaningSearch` for Find) cannot solve. `RECALL_BENCHMARK.md` is the place to show one first.
