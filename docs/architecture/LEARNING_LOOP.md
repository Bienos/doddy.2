# Learning loop — Doddy gets better for one person (design, ADR-440)
Status: **Phase A reviewed (owner, 2026-10-11: "use your proposed defaults"); Phase B (typed core, migrations, repositories) and Phase C (proposers, service, store, cards, Settings screen, voice wiring, gap tool) built on `claude/cool-archimedes-9l8l1h`. Linux-tested: core, service and SQLite. NOT RUN: every screen, the voice session wiring, the live voice agent.** Milestone status and test evidence: `docs/implementation/M6_LEARNING_LOOP_STATUS.md` (the pack file `MILESTONES.md` is byte-locked). Sections 8, 9 and 13 describe what is in the code; where it differs from the Phase A proposal, the difference is marked.

Doddy accumulates verified context about its one user, learns reusable procedures from repeated requests, records what happened and what the user corrected, and notes what it could not do. Every learned thing is **data**: proposed by a model or a rule, validated by typed code, confirmed by the user, versioned, visible, revertible. Doddy never changes its own code on the iPhone.

## 1. What exists today (inventory, read on 2026-10-11)
| Piece | State | Where | Reuse in the learning loop |
|---|---|---|---|
| Explicit notes with immutable `rawText`, corrections history, FTS5 recall, export/restore, read-back before success | Implemented, Linux tests | `DoddyCore/MemoryTypes.swift`, `MemoryHistory.swift`, `Ports.swift`; `DoddyPersistence/SQLiteMemoryRepository.swift`, migrations `v1`…`v10` in `DoddyDatabase.swift` | Pattern for every new repository: one transaction, read back, FTS over a folded `search_text` column |
| Reviewed profile (six fields, `explicit_user_review` only, revision counter) | Implemented | `DoddyCore/Profile.swift`, `DoddyApp/Infrastructure/ProfileStore.swift` | Learned facts are the *inferred-then-confirmed* sibling of the profile; they never write into profile fields |
| Personality settings (humour, length, formality, mood) | Implemented | `DoddyCore/Personality.swift` | Explicit preferences stay here; the loop never edits them |
| End-of-conversation save suggestions: rules, user's own words, nothing saved until ticked (ADR-247) | Implemented | `DoddyCore/SaveSuggestions.swift` | The first **fact proposer** is this rule set, not a model |
| Plans: `propose_plan`, up to 5 steps from an allowlist, every step checked as if asked alone, one card with tick boxes (ADR-204) | Implemented | `DoddyCore/Plan.swift` | A **procedure is a saved plan template**; execution reuses the plan card and the per-step approvals unchanged |
| Activity log: request, outcome (`done`, `notSure`, `declined`, `inProgress` → `notSure` after a crash), 30 days / 300 entries, JSON file | Implemented | `DoddyCore/ActivityLog.swift`, `DoddyApp/Infrastructure/ActivityLogStore.swift` | Source of **outcome events**; the log itself is not changed |
| Capability catalog; onboarding text derived from it | Implemented | `DoddyCore/Capabilities.swift`, `CapabilityIntroduction.swift` | Procedure steps must name a tool served by an available capability and a connection that is on |
| Tool registry: 50 voice tools in `voice-agent/tools.json`, names mirrored in `VoiceToolName`, connections in `VoiceConnection` | Implemented | `DoddyCore/VoiceTools.swift` | The only tools a procedure may reference |
| Grounding budget and citation verifier for the text assistant (5 notes, 12,000 scalars; citations must be in the sent set) | Implemented | `DoddyCore/Assistant/GroundingSelector.swift`, `CitationVerifier.swift` | The context assembler extends this with a second, smaller budget for learned items |
| Text assistant through the gateway (`GatewayAssistantClient`), voice agent (ElevenLabs / OpenAI Realtime tools) | Code exists; **live status not verified in this session** (no Xcode, no network run) | `DoddyCore/Assistant/`, `voice-agent/` | The model proposer attaches here in Phase C only if the live path is confirmed; otherwise `Unavailable*` |
| Learned facts, procedures, outcome events, capability gaps, proposal types, learning policy, "What I've learned" screen | **Missing** | — | This design |

Nothing in the table is a mock. `swift` is not installed in the environment this was written in, so no test or build was run for this document.

## 2. The four layers
1. **Verified facts.** Small statements about the user that a proposer noticed and the user confirmed word for word: "Marta's birthday is 12 May", "I take the 7:10 train to Warsaw on Mondays", "I prefer reminders at 9:00". Kinds: `preference`, `fact`, `routine`, `person`, `place`. They are retrieved into the assistant's context like notes are today, with their own smaller budget.
2. **Procedures.** A named plan template learned from repetition: trigger text plus ordered steps over existing tools with fixed or asked-for parameters. "Evening wrap-up: add tomorrow's first event as a reminder, then set the 6:30 alarm." Running one shows the same plan card as today, with every step checked and approved exactly as if asked alone.
3. **Outcome events.** What happened after each request, as kinds without user content: `completed`, `corrected`, `cancelled`, `redone`, `declined`, `capability_gap`. These are the evidence for proposing facts and procedures, and the source of the one metric: corrections per week.
4. **Capability gaps.** Requests Doddy could not map to any tool, as a category, stored locally only, listed on the learned screen as "things I can't do yet". They never leave the iPhone and never create code.

Off the device, nothing changes: new capabilities still arrive through reviewed pull requests, tests and a catalog update, as they do now. The loop only tells the owner which gaps the user hit most.

## 3. Lifecycle of a learned item
```
evidence (turns, outcome events)
  -> PROPOSE   (rule set on device; later a model, through AssistantClient, as typed JSON)
  -> VALIDATE  (LearningPolicy: shape, length, sensitive filter, daily cap, catalog check,
                tier preservation, not-rejected-before)
  -> SHOW      (card with the exact text, the source turns/dates, Save / Not now / Never this)
  -> CONFIRM | REJECT | EXPIRE (card dismissed, proposal dropped after 7 days)
  -> STORE     (one transaction, read back; only then "Saved")
  -> RETRIEVE  (context assembler, per request, ids only, under budget and scope)
  -> USE       (facts: grounding; procedures: a plan card)
  -> RETIRE    (user "that's wrong" / delete; expiry; procedure unused 90 days)
```
Rules the code enforces at each arrow:
- **Propose:** a proposal carries `evidenceDigest` (SHA-256 over the ordered source turn ids or outcome event ids). While any row carries that digest (proposed, confirmed, retired or rejected) the same evidence is not proposed again: the policy refuses it and the table's unique index refuses it too. An unanswered proposal is dropped after 7 days, so its evidence may come back later; "Never this" keeps a `rejected` row, so it never does.
- **Validate:** a malformed, over-long, out-of-catalog or sensitive proposal is dropped and counted in a local diagnostics counter (no content), never shown, never executed.
- **Show:** the card text is the stored text. The user confirms *that* string; the confirmation writes the string shown, byte for byte, with `confirmed_at_ms`. Editing on the card produces a new proposal, not a mutation of the old one.
- **Store:** `status = confirmed` is written only in the transaction that also reads the row back. The UI shows "Saved" only from the returned record (same rule as `MemoryRepository.save`).
- **Retrieve:** the assembler reads the repository on every request; there is no long-lived in-memory snapshot, so a deletion is visible to the very next request. The FTS table is updated in the same transaction as the row.
- **Use:** a fact is grounding text, cited by id, checked by `CitationVerifier` like a note. A procedure expands to a `PlanProposal`; the plan code decides every step's connection, permission and approval. A learned item that reads like an instruction ("always send without asking") is still just text in the grounding; nothing parses it as policy.
- **Retire:** `retired` rows are kept until the user deletes them (so "that's wrong" is visible and reversible), excluded from retrieval and FTS matches, and purged by `deleteAll`. Expired facts are not retrieved and are shown under "Expired — still true?" with a one-tap re-confirm; nothing is silently dropped.

## 4. Proposers
### 4.1 Facts
- **Phase B/C proposer: rules on the device**, the existing `SaveSuggestions` reasons (`personalFact`, `preference`, `plan`, `dateOrNumber`, `recommendation`) extended with a `routine` detector: the same tool with the same parameters on three or more days within 30 days (from outcome events + activity log request keys, never from note text). Only the user's own transcribed sentences are used, never Doddy's lines or tool results (ADR-247 rule, kept).
- **Later proposer: the model**, only through `AssistantClient`, returning a `LearningProposal` JSON block that is parsed into the same typed struct and goes through the same `LearningPolicy`. The model never gets to mark anything confirmed, and its proposal text is validated for length and the sensitive filter exactly like a rule proposal. Not part of Phase B.

### 4.2 Procedures
A procedure is proposed when the outcome events show the **same ordered sequence of two to five allowed tools** (`PlanTool.allowed`, the ADR-204 allowlist, nothing wider) completed on three or more separate days within 30 days. The proposal names the steps, which parameters are fixed (identical every time, e.g. the alarm time) and which are **asked** (differed every time, e.g. the reminder title). The user names the trigger on the card; Doddy suggests one from the first user sentence of the most recent episode.

A procedure never contains: a look-up (look-ups run first with the ordinary tools, as plans do today), a tool that leaves the app (Maps, Shortcuts, Messages draft, as plans today), a tool whose connection is off, a free-text parameter copied from tool output or web content.

### 4.3 Outcome events
Written by the app, not by the model:
| Kind | When | Detail (no user content) |
|---|---|---|
| `completed` | `ActivityLog` outcome becomes `done`, `alreadyThere` or `lookedUp` | tool name, procedure id if any, step number |
| `corrected` | the user taps Undo on an entry; changes a step on a plan card before running it; taps "that's wrong" on a learned item | tool name or learned item id, what kind of correction |
| `cancelled` | an approval card is dismissed or times out | tool name |
| `redone` | the same tool is asked again within 10 minutes after `done` or `cancelled` with a different payload digest | tool name |
| `declined` | outcome `declined` | tool name |
| `capability_gap` | see 4.4 | gap category |

### 4.4 Capability gaps
Detecting "I can't do that" from a voice conversation needs the agent's cooperation. Proposal: a new voice tool `note_capability_gap(category)` with an **enumerated** category (e.g. `send_message`, `payment`, `music`, `smart_home`, `other_app_control`, `web_action`, `unknown`), no free text, served by no connection, writing one `capability_gap` outcome event. The agent's instructions tell it to call it when the user asks for something outside its tools. The tool makes no change, shows no card, and its only effect is a local row. On the device, a rule adds a gap when the user re-asks the same thing twice with no tool called in between.

## 5. Context assembler
`LearningContextAssembler` runs after `GroundingSelector`, per request:
- Input: the request text, the FTS candidates from `learned_facts_fts` and `procedures_fts`, the set of connections currently on, "Pause all connections" state.
- Budget: at most **3 confirmed facts** and **1 procedure** per request, at most **1,500 scalars** in total for learned items, never shortened. These are separate from and additional to the note budget (`GroundingBudget`), so a learned fact can never push out a cited note. The gateway's `validate.js` limits must be raised in step; until then the client sends none (a hard cap the gateway would reject is a bug, not a fallback).
- Scope: a fact or procedure carries a `scope` (`general` or one `VoiceConnection`). Items scoped to a connection that is off or paused are not retrieved. With "Pause all connections" on, no procedure is retrieved and no proposal is made.
- Status: only `confirmed` and not expired.
- Output: ids plus text, so the reply's citations can be verified against the sent set like note ids. A fact is presented in the reply as "you told me" with its confirmation date, never as "I think".

## 6. Decay, caps and privacy
- **Expiry defaults** (decision required): `preference` 365 days, `routine` 180 days, `plan`-like facts 30 days, `fact`/`person`/`place` no expiry but a "still true?" review after 365 days. Procedures: retired after 90 days unused, shown as "retired", one tap to revive.
- **Proposal cap** (decision required): at most 3 proposals shown per day, at most 1 per conversation end, none in the sensitive mode of the character router, none while "Pause all connections" is on.
- **Never learned** (decision required, enforced by the sensitive filter): passwords, codes, card and account numbers (already blocked by ADR-247); plus health conditions and medication, sexual orientation, religion, political views, immigration status, precise location history, anything about a third person's health or finances. Such sentences are not proposed; the user can still save them as a plain note by hand.
- **What leaves the iPhone:** confirmed facts, only inside an assistant request as grounding, under the egress rules of `AI_RUNTIME.md` and the "What leaves this iPhone" screen (which gains a line for learned facts). Procedures never leave the device: they expand locally into tool calls that are approved locally. Outcome events and capability gaps never leave the device. No telemetry, no sync, no embeddings.
- **Deletion:** delete one item → row, FTS row and `rejected`/`retired` siblings for the same evidence are removed in one transaction; the next request reads the repository fresh. "Delete all notes" also deletes all learned items and outcome events. Export (Memory Wallet) includes facts and procedures as JSON with provenance; outcome events are exportable separately.

## 7. "What I've learned" screen (Settings)
Contract, same UX family as the Memory Wallet (UX-01):
- **Facts** list: text, kind, scope, "from a conversation on <date>" (the source turns' dates; never the import time), confirmed date, expiry. Actions: edit (creates a new confirmed revision, history kept like note corrections), delete, **That's wrong** (retires + `corrected` event).
- **Procedures** list: trigger, steps in the plan card's own words, version, times used, last used. Actions: run (shows the plan card), edit steps (new version), delete, That's wrong.
- **Pending**: proposals not yet answered, with Save / Not now / Never this.
- **Things I can't do yet**: gap categories with counts, with the sentence "This stays on your iPhone".
- **Export** JSON; the counters "corrections this week" and "learned items used this week", computed locally.
- Copy never says "I learned" before a read-back; while a save is in flight the card says "Saving…".

## 8. Schema as built (migrations `v11_learned_facts`, `v12_procedures`, `v13_outcome_events`, appended after `v10_list_shares` in `DoddyDatabase.swift`)
Same conventions as `v9`/`v10`: milliseconds, CHECK on enums inlined from Swift `CaseIterable` raw values via `sqlList`, FTS5 over a folded `search_text` column kept by GRDB's `synchronize(withTable:)` triggers in the same transaction (the `memories` pattern). Differences from the Phase A proposal: the two FTS-indexed tables are ordinary rowid tables (FTS5 content sync needs a rowid, so no `WITHOUT ROWID`); `procedures` also carries `provenance_json` like facts; `learned_fact_revisions` keeps every confirmed wording (the `memory_corrections` pattern); the evidence digest is a UNIQUE column.

```sql
-- v11_learned_facts
CREATE TABLE learned_facts (
    id TEXT PRIMARY KEY NOT NULL,
    kind TEXT NOT NULL CHECK (kind IN ('preference','fact','routine','person','place')),
    value TEXT NOT NULL CHECK (length(trim(value)) BETWEEN 1 AND 400),
    search_text TEXT NOT NULL,                    -- SearchFolding.fold(value)
    scope TEXT NOT NULL DEFAULT 'general',        -- 'general' or a VoiceConnection raw value
    confidence INTEGER NOT NULL CHECK (confidence BETWEEN 0 AND 100),
    provenance_json TEXT NOT NULL,                -- {proposer, reason, episodeDates}; never user text
    source_episode_ids_json TEXT NOT NULL,        -- ordered ids; the digest is over these
    evidence_digest TEXT NOT NULL UNIQUE,
    status TEXT NOT NULL CHECK (status IN ('proposed','confirmed','retired','rejected')),
    created_at_ms INTEGER NOT NULL,
    updated_at_ms INTEGER NOT NULL,
    expires_at_ms INTEGER,
    confirmed_at_ms INTEGER,
    schema_version INTEGER NOT NULL DEFAULT 1,
    CHECK ((status = 'confirmed') = (confirmed_at_ms IS NOT NULL))
);
CREATE INDEX learned_facts_status ON learned_facts(status, expires_at_ms);
CREATE TABLE learned_fact_revisions (
    fact_id TEXT NOT NULL REFERENCES learned_facts(id) ON DELETE CASCADE,
    number INTEGER NOT NULL CHECK (number >= 1),
    value TEXT NOT NULL CHECK (length(trim(value)) > 0),
    confirmed_at_ms INTEGER NOT NULL,
    PRIMARY KEY (fact_id, number)
) WITHOUT ROWID;
CREATE VIRTUAL TABLE learned_facts_fts USING fts5(search_text, content='learned_facts', tokenize='unicode61');  -- plus GRDB sync triggers

-- v12_procedures
CREATE TABLE procedures (
    id TEXT PRIMARY KEY NOT NULL,
    trigger_text TEXT NOT NULL CHECK (length(trim(trigger_text)) BETWEEN 1 AND 120),
    search_text TEXT NOT NULL,
    steps_json TEXT NOT NULL,                     -- [ProcedureStep], 1..5, validated on every read
    version INTEGER NOT NULL CHECK (version >= 1),
    scope TEXT NOT NULL DEFAULT 'general',
    status TEXT NOT NULL CHECK (status IN ('proposed','confirmed','retired','rejected')),
    provenance_json TEXT NOT NULL,
    source_episode_ids_json TEXT NOT NULL,
    evidence_digest TEXT NOT NULL UNIQUE,
    created_at_ms INTEGER NOT NULL,
    updated_at_ms INTEGER NOT NULL,
    confirmed_at_ms INTEGER,
    last_used_at_ms INTEGER,
    use_count INTEGER NOT NULL DEFAULT 0 CHECK (use_count >= 0),
    schema_version INTEGER NOT NULL DEFAULT 1,
    CHECK ((status = 'confirmed') = (confirmed_at_ms IS NOT NULL))
);
CREATE INDEX procedures_status ON procedures(status, last_used_at_ms);
CREATE VIRTUAL TABLE procedures_fts USING fts5(search_text, content='procedures', tokenize='unicode61');

-- v13_outcome_events
CREATE TABLE outcome_events (
    id TEXT PRIMARY KEY NOT NULL,
    request_id TEXT NOT NULL,
    kind TEXT NOT NULL CHECK (kind IN ('completed','corrected','cancelled','redone','declined','capability_gap')),
    detail_json TEXT NOT NULL,                    -- OutcomeDetail: tool name, procedure id, step, gap category, correction kind; no text field exists
    created_at_ms INTEGER NOT NULL
);
CREATE INDEX outcome_events_created ON outcome_events(created_at_ms);
CREATE INDEX outcome_events_request ON outcome_events(request_id);
```
`ProcedureStep` (JSON inside `steps_json`): `{"number":1,"tool":"create_reminder","fixed":{"list":"Home"},"asked":["title","due"]}`. The approval tier is **not stored**: `ProcedureStep.approval` is derived from the tool name (`ProcedureApproval.required(for:)`, always the card, since every allowed tool is a change). A row edited by hand to add `"approval":"none"` decodes with those keys ignored and still shows the card; a row naming a tool outside `PlanTool.allowed` does not decode at all and is reported as corrupt (tested). Outcome events keep 90 days (`prune(olderThan:)`).

## 9. Phase B code (built, Linux-tested)
`DoddyCore/Learning/`: `LearningTypes.swift` (`LearnedFactKind`, `LearningScope`, `LearningStatus`, `LearningProposer`, `LearningProvenance`, `LearningValidationError`, `EvidenceDigest`, `LearnedFact`, `LearnedFactRevision`, `ProcedureApproval`, `ProcedureStep`, `Procedure`, `OutcomeKind`, `CapabilityGapCategory`, `CorrectionKind`, `OutcomeDetail`, `OutcomeEvent`, `LearningJSON`), `LearningProposal.swift` (`FactProposal`, `ProcedureProposal`, `LearningProposal.parse`, `LearningProposalError`), `LearningPolicy.swift` (`LearningLimits` with the owner's defaults, `LearningEnvironment`, `ProposalCounts`, `ValidatedProposal` which only the policy can make, `LearningPolicy.validate`, `SensitiveContentFilter`), `LearningPorts.swift` (`LearnedFactRepository`, `ProcedureRepository`, `OutcomeEventRepository`, `LearningStoreError`, `OutcomeMetrics`), `LearningContextAssembler.swift` (`LearningBudget`, `LearningContext`, `LearningContextAssembler`).
`DoddyPersistence/`: `SQLiteLearnedFactRepository`, `SQLiteProcedureRepository`, `SQLiteOutcomeEventRepository`; migrations in `DoddyDatabase.swift`.
Tests: `DoddyCoreTests/LearningTests.swift` (19) and `DoddyPersistenceTests/SQLiteLearningRepositoryTests.swift` (12), real SQLite, no mocks. Evidence in `docs/implementation/M6_LEARNING_LOOP_STATUS.md`.

Not in Phase B (Phase C): the proposers themselves (the `SaveSuggestions` extension and the repeated-sequence detector), the cards, the "What I've learned" screen, running a procedure through the plan card, the `note_capability_gap` agent tool, wiring to `ActivityLog` and `AssistantRequest`, the gateway limit change for learned facts, the "What leaves this iPhone" line, `deleteAll` of learned items from "Delete all notes".

## 10. Policy map (`docs/trust/config/doddy_rules.yaml`)
| Rule | Enforced by (Phase B code; UI parts are Phase C) | Test (Linux, 2026-10-11) |
|---|---|---|
| DOD-06 user-controlled relevant memory; `explicit_long_term_memory_opt_in_default`, `auto_save_sensitive_data: false`, `require_user_visible_provenance` | `LearningPolicy` (sensitive filter, cap), confirm-only writes in the repositories, provenance columns, learned screen | proposal without confirmation is never `confirmed`; sensitive sentence never proposed; provenance present on every row |
| DOD-07 scoped action approval; `bind_approval_to_payload_and_identity`, `enforce_current_scope` | procedures expand through `PlanProposal`; tier derived from the registry; connection check at run time | hand-edited step cannot skip a card; step for an off connection is refused |
| DOD-08 verified status; `deletion_claim_requires_storage_confirmation` | read-back in every repository write; "Saved" only from the returned record; delete reaches FTS | save → restart → read back; delete → FTS miss |
| DOD-09 correction and recovery | "That's wrong", Undo and card changes write `corrected`; retired rows are visible and revivable | corrected event written; retired item not retrieved |
| DOD-11 observable privacy; `raw_secrets_in_model_prompt_or_logs: forbidden`, `privacy_preserving_telemetry` | outcome events carry no user text; gaps are categories; nothing uploaded; "What leaves this iPhone" line | detail_json schema test; no network code in learning modules (existing guard script) |
| DOD-02 honesty, UX-04 reality check | facts cited as "you told me on <date>", never "I think"; `CitationVerifier` covers fact ids | reply citing an unsent fact id is rejected |
| UX-01 Memory Wallet, UX-05 Your Doddy | learned screen: list, edit, delete, export; personality untouched | UI test on the screen (NOT RUN without Xcode) |
| `release_gates.blocking`: `unauthorized_memory_access`, `prompt_injection_permission_bypass` | scope filter in the assembler; learned text is data in grounding only | fact text "ignore approvals" changes nothing in `LearningPolicy`/plan decisions |

## 11. Rejected alternatives
- **On-device self-modification or generated code:** no way to test, review or roll back on the phone; breaks rule 1 of `REPO_ALIGNMENT.md`. Gaps go to the owner instead.
- **Implicit learning from every turn:** forbidden by DOD-06; also the main cause of "creepy and wrong" in comparable products.
- **Model-decided risk tiers or approval skipping for trusted procedures:** the model is a proposer; a stored row is data; tiers come from the registry only.
- **Embeddings or a cloud store:** `MEMORY_AND_DATA.md` already decides FTS5 first; nothing here needs more.
- **Writing learned facts into the profile or personality settings:** those are explicit-review-only stores with different guarantees; mixing them would blur provenance.

## 12. Decisions (owner, 2026-10-11: "use your proposed defaults" — all six accepted as proposed)
1. Daily proposal cap default (proposed 3/day, 1 per conversation end).
2. Expiry defaults per kind (section 6) and the 90-day retirement for unused procedures.
3. The never-learned categories (section 6) beyond the ADR-247 secrets list.
4. Capability gaps via a `note_capability_gap` agent tool with enumerated categories (yes/no); if no, gaps are rule-detected only and will undercount.
5. Where the milestone sits (`docs/implementation/M6_LEARNING_LOOP_STATUS.md`): proposed as M6 after the M5 beta decision, so learning does not confound the beta's retention measurement. Alternative: run it inside M5 with a control group.
6. Metric baseline: corrections per week measured for two weeks with learning off (owner's own use or the beta) before any claim that Doddy "gets better".

## 13. Phase C as built (ADR-441)
**Code.** `DoddyCore/Learning/`: `LearningService` (everything that is not a screen: recording, proposing, answering a card, "That's wrong", voice text, housekeeping, delete), `OutcomeRecorder` (activity log entry → outcome events), `LearningProposers` (`FactProposer`, `ProcedureDetector`, `ProcedureStepTemplates`), `LearningPrompt` (the `{{learned_context}}` text), `UnavailableLearning*Repository`. App: `LearningStore` (view state), `LearnedView` (Settings), `LearningCardsView` (voice screen), hooks in `ActivityLogStore`, `VoiceSessionController`, `SettingsView`, `DataFlowView`, `AppEnvironment`, `DoddyApp`.

**What now happens, in order.**
1. Every entry that "What Doddy did" adds or replaces is passed to the recorder. It writes `completed`, `declined`, `cancelled` (a card nobody answered), `corrected` (Undo) and `redone` events, with tool name, conversation id and request id only. This runs whether or not learning is on, so the baseline for the metric exists.
2. When a conversation ends and learning is on, the service looks for one thing to propose: a tool sequence repeated on 3 separate days (first), else a preference or personal fact from sentences the "Worth keeping?" card did not already offer. The policy checks it (sensitive words, caps, paused, known evidence, tools on) and only then is it stored as `proposed` and shown.
3. Save confirms the exact stored text, shows "Saved" only after the read-back, and the item appears in Settings. Not now leaves it under "Waiting for your answer" for 7 days. Never this keeps a refused row.
4. With "Use what Doddy learned in voice conversations" on, the next conversation starts with the confirmed facts and routines in `{{learned_context}}` (not in translator mode, not while paused for routines). The agent asks for a routine's details and calls `propose_plan`; the plan card and per-step approvals run it; a plan whose tools equal a routine's marks it used.
5. "That's wrong" retires the item and writes a `corrected` event only after the retirement read back. Delete removes it and its index entry. Delete all memories also empties all three tables, read back.
6. `housekeeping` runs at launch and when the screen opens: proposals older than 7 days go, routines unused 90 days are retired, events older than 90 days go.

**Differences from the Phase A proposal.**
- Running a routine is by voice only. The plan card lives in the voice session, so Settings has no Run button.
- The routine's name is suggested in the iPhone's language and renamed in Settings; it is not edited on the card.
- Fact evidence is the sentence, not the conversation, so "Never this" holds across conversations. A routine sequence with any row is never proposed again on new evidence.
- Gaps are written only when the agent calls `note_capability_gap`; no rule detects them, so they undercount (decision 4, as warned). The live agent has no such tool until the owner syncs it.
- `sensitiveMode` is always false: the app has no character router yet. Only the content filter applies.
- Typed Ask does not use learned facts; the gateway limits would have to be raised in step first.

**Known limits.** Learned facts reach the voice service as plain text at conversation start (listed on the Privacy screen when on); ElevenLabs' retention applies to them as to notes. The never-learned list is word rules in English and Polish, not a classifier, so it will miss some phrasings and wrongly block some harmless ones. Outcome counts use the activity entry's outcome, so a change whose result was "not sure" is not counted as completed.
