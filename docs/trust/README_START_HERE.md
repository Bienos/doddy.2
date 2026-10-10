# DODDY AI Constitution — V1.0
Date: 2026-10-10 | Status: **proposed build specification, not yet implemented or validated**

**Purpose:** Translate AI-user objections into consistent Doddy behaviour, product controls, security requirements, and release tests. This is intended for **DODDY V2 built from scratch in a new repository**. It does not modify any existing repository.

## Use in Codex / Claude
1. Put `docs/` and `config/` under the new app repository, ideally at `docs/trust/` and `config/`.
2. Merge `templates/AGENTS.md` into the repository root's `AGENTS.md` (do not overwrite existing instructions). For Claude, place equivalent instructions in `CLAUDE.md`.
3. Start a coding session with `templates/CODEX_IMPLEMENTATION_PROMPT.md`.
4. Build one milestone at a time, starting with **explicit action status + approval guard**, a local memory-control contract, and character routing.
5. Import `research/01_RISK_REGISTER.csv` and `research/02_BEHAVIOUR_AND_AGENT_TESTS.csv` as traceability/reference cases. `evals/doddy_cases.jsonl` is an additional structured test fixture set, not an executable runner.
6. Run the P0 tests and manual adversarial review before enabling real integrations.

## Document map
- `docs/01_THE_DODDY_CONSTITUTION.md` — 12 governing principles and precise AI-language rules.
- `docs/02_BEHAVIOUR_AND_CHARACTER_SPEC.md` — modes, humour, conversation boundaries and response examples.
- `docs/03_TRUST_FEATURES_AND_UX.md` — user-facing memory wallet, action receipts, permissions, truthful answers and quiet controls.
- `docs/04_ENFORCEMENT_ARCHITECTURE.md` — hard technical constraints, state models, precedence and trust boundaries.
- `docs/05_RELEASE_CRITERIA_AND_METRICS.md` — release gates, QA and evidence requirements.
- `config/doddy_rules.yaml` — machine-readable policy metadata for implementation and testing; not a security enforcement engine.
- `evals/doddy_cases.jsonl` — structured acceptance scenarios.
- `templates/AGENTS.md` — source-code agent instructions (merge, not overwrite).
- `templates/CODEX_IMPLEMENTATION_PROMPT.md` — ready-to-paste incremental build instruction.
- `research/` — prior complaint risk register, 48 test scenarios and source notes.

## Decision: what goes where?
| Requirement | AI model prompt | Application code | Test |
|---|---|---|---|
| Be funny without being intrusive | Yes | User tone settings | Conversation evaluation |
| Admit uncertainty and correct errors | Yes | Source/verification data | Factual/tool-status cases |
| Ask before external write | Yes, explains why | **Must enforce** signed/explicit approval | Integration safety assertion |
| Never fake task completion | Yes | **Must enforce** receipt state machine | Tool failure / timeout tests |
| Let user delete memory | Explain controls | **Must implement deletion and retention** | Storage + sync verification |
| Respect privacy scopes | Describe accurately | **Must enforce least privilege** | Permission and leakage tests |

**Product promise:** Doddy can be ridiculous in stories; his help cannot be unreliable.

## Cautions
- These are product/design decisions informed by public research, not a certified security standard or legal advice.
- A system prompt cannot enforce authorisation, data erasure, access control, tool isolation, or payment safety.
- Tests marked P0 must be implemented where their supporting feature exists; mock success is not proof of external success.
- iPhone capabilities and permissions must be checked against real platform APIs and App Review rules before launch.
- The 24-person user study described in the previous research package has **not** been performed.
