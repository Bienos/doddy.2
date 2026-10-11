# Copy/paste into Claude Code at the `Bienos/doddy.2` root — Learning loop (Doddy gets better for one person)

You are the lead engineer for DODDY V2. This prompt adds a **learning loop**: Doddy accumulates verified context about its one user, learns reusable procedures from repeated requests, records outcomes and corrections, and reports capability gaps. It never modifies its own code on the device. Every learned thing is **data**: proposed by the model, validated by typed code, confirmed by the user, versioned, visible, revertible.

Read `CLAUDE.md`, `AGENTS.md`, `docs/trust/REPO_ALIGNMENT.md`, `docs/trust/04_ENFORCEMENT_ARCHITECTURE.md` (memory pipeline, action lifecycle, risk tiers), `docs/architecture/MEMORY_AND_DATA.md`, `docs/architecture/AI_RUNTIME.md`, `docs/architecture/TOOLS_AND_ACTIONS.md`, `docs/implementation/MILESTONES.md`, `DECISIONS.md` (latest ADR number). Then inventory what exists: `Packages/DoddyCore/Sources/DoddyCore/{MemoryTypes,MemoryHistory,Ports,ActivityLog,Capabilities}.swift`, `Packages/DoddyCore/Sources/DoddyPersistence/DoddyDatabase.swift` (GRDB migrator; shipped migrations are never edited), `DoddyApp/Infrastructure/{MemoryStore,ActivityLogStore,ProfileStore}.swift`. State what is implemented, mock, or missing before editing anything.

## Non-negotiables (constitution; code enforces, prompts only describe)
- No silent learning. Nothing is stored as a fact or procedure without an explicit user confirmation bound to the exact text shown (DOD-06). Rejected proposals are not retried for the same evidence.
- Learned items are **descriptive data, never instructions**. A stored procedure can never raise a permission, skip an approval card, or change a risk tier. Every external write inside a procedure still goes through the existing per-call approval with the exact payload (DOD-07).
- Never claim something was learned, saved, changed or forgotten without a read-back from the store (DOD-08). "Unknown" is never success.
- Provenance on everything: which turns/episodes produced it, when, with what confidence. Deletion reaches the live tables, the FTS index and any cached context.
- The model is a proposer. Candidate facts and procedures arrive as typed, validated structs; malformed or out-of-catalog proposals are dropped and logged, not executed.
- No new cloud infrastructure, no telemetry upload, no embeddings. Local SQLite via the existing GRDB migrator. FTS5 only, as the memory doc already decides.
- Do not fake the model. Where the real `AssistantClient` is not wired yet, implement the typed pipeline with a deterministic fake proposer in tests and label it so in docs and UI.

## Phase A — Design first, stop for review
1. Write `docs/architecture/LEARNING_LOOP.md`: the four layers (verified facts, procedures, outcome events, capability gaps), the proposal → validate → confirm → store → retrieve → retire lifecycle, the context assembler with a token budget and permission scoping, decay/expiry, a per-day proposal cap, and the "What I've learned" screen contract (list, edit, delete, export, "that's wrong").
2. Write an ADR (next number in `DECISIONS.md`): why learning is data not code, why on-device self-modification is rejected, how procedures compose only `Capability`-catalog tools, how approval tiers are preserved.
3. Propose the schema as three GRDB migrations appended to `DoddyDatabase.migrator`, never editing shipped ones:
   - `learned_facts(id, kind, value, confidence, provenance_json, source_episode_ids_json, status, created_at_ms, updated_at_ms, expires_at_ms, confirmed_at_ms, schema_version)`; status ∈ proposed | confirmed | retired | rejected.
   - `procedures(id, trigger_text, steps_json, version, status, source_episode_ids_json, created_at_ms, updated_at_ms, last_used_at_ms, use_count)`; each step references a `Capability` and a tool name that exists in the tool registry, with parameters and the approval tier it keeps.
   - `outcome_events(id, request_id, kind, detail_json, created_at_ms)`; kinds: completed, corrected, cancelled, redone, declined, capability_gap.
   Add CHECK constraints for status/kind enums and an FTS5 table over `learned_facts.value` and `procedures.trigger_text`.
4. Add a milestone entry to `docs/implementation/MILESTONES.md` placed after the real model (M2) and real actions (M4); list the metric: user corrections per week, with the baseline it needs.
5. List the policy IDs from `docs/trust/config/doddy_rules.yaml` each part enforces. **Stop and report.** Do not write code until the design is reviewed.

## Phase B — Typed core and storage (after review)
In `DoddyCore` add `LearnedFact`, `Procedure`, `ProcedureStep`, `OutcomeEvent`, `LearningProposal` (model output parsed into typed structs with validation errors), `LearningPolicy` (proposal cap, sensitive-category filter, catalog check, tier preservation), and ports `LearnedFactRepository`, `ProcedureRepository`, `OutcomeEventRepository`. In `DoddyPersistence` implement them over GRDB with read-back before success, matching the style of `SQLiteMemoryRepository`. Add a `LearningContextAssembler` that selects confirmed facts and procedures by FTS relevance and permission scope under a token budget and returns record ids only, so citations can be verified like memory ids.

Tests (same pattern as `DoddyPersistenceTests`): migration up on an existing v-latest database; save → restart → read back; expiry and retirement; delete reaches FTS; a procedure referencing an unknown tool is rejected; a procedure cannot lower an approval tier; proposals over the daily cap are dropped; conflicting facts are both returned with provenance; deterministic fixture corpus including Polish diacritics. Run `swift test` from `Packages/DoddyCore` and paste real output.

## Phase C — App integration (after Phase B is green)
- Proposal cards: "I noticed X. Save it?" with exact text, source turns, and Not now. Confirmation writes through the repository and shows success only after read-back.
- "What I've learned" screen under Settings: facts and procedures with provenance, edit, delete, export JSON, and "that's wrong" which retires the item and logs a `corrected` outcome.
- Procedure execution: expands into the existing tool calls; each L3 step still shows its approval card with the exact payload; outcomes go to `ActivityLog` as today plus an `outcome_event`.
- Capability gaps: when a request maps to no catalog capability, log `capability_gap` locally (no upload) and show it on the learned screen as "things I can't do yet".
- Hook the proposer to the real `AssistantClient` only if M2 is wired on this line; otherwise leave it `Unavailable*` and say so.

## Report and stop
Files changed; shipped behaviour vs mock vs blocked; exact test commands and output; native build status (NOT RUN if no Xcode); constitution evidence log (rule IDs, enforcing code, tests, gaps, claims to limit); privacy implications of storing learned facts; decisions required (proposal cap default, expiry defaults, which categories are never learned). Do not add off-device self-coding, cloud sync, embeddings, or new providers. Stop after the phase you were asked to run.
