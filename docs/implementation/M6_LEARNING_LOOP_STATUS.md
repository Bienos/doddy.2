# M6 — Learning loop: status
Status: **PLANNED, design only (Phase A done, PROPOSED).** ADR-324. `docs/implementation/MILESTONES.md` is an imported pack file (byte-locked by `scripts/verify_imported_pack.py`), so this milestone lives here, like M4a, S1 and N1.

**Place in the sequence:** after M2 (real text model), M4 (real actions) and the M5 beta decision, so learning does not confound the beta's retention measurement. Owner may instead run it inside M5 with a control group (design doc §12, decision 5).

**Goal:** Doddy gets better for one person as **data, never code**: verified facts confirmed word for word, procedures as saved plan templates over the existing ADR-204 allowlist with every step still approved on the plan card, outcome events without user text, capability gaps as local categories. Design: `docs/architecture/LEARNING_LOOP.md`.

**Phases**
- A — design review: `LEARNING_LOOP.md`, ADR-324, schema proposal (`v11_learned_facts`, `v12_procedures`, `v13_outcome_events`), policy map. Done on 2026-10-11; **waiting on the owner's six decisions** (design doc §12).
- B — typed core (`LearnedFact`, `Procedure`, `ProcedureStep`, `OutcomeEvent`, `LearningProposal`, `LearningPolicy`, `LearningContextAssembler`), three GRDB migrations and repositories with read-back, Linux tests. Not started.
- C — proposal cards, "What I've learned" screen (list, edit, delete, export, "That's wrong"), procedure runs through the plan card, gap counts, `note_capability_gap` agent tool if approved. Not started. Model proposer only if the gateway path is confirmed live; otherwise `Unavailable*`.

**Metric:** user corrections per week, computed locally from `outcome_events` of kinds `corrected`, `redone` and `cancelled`. **Baseline needed:** two weeks with learning off (owner's own use or the beta) before any "gets better" claim.

**Exit:** save → restart → read back for facts and procedures; delete reaches the FTS tables and the next request; a hand-edited procedure row cannot skip an approval card or use an off connection; a sensitive sentence is never proposed; the same evidence is never proposed twice; corrections per week on a device compared with the baseline. No cloud, sync, embeddings, telemetry or new providers.

**Evidence so far:** none. No code, no tests run, native build NOT RUN (no Xcode in the authoring environment; `swift` not installed either).
