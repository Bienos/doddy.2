# DODDY AI Constitution V1 — how it applies in this repository
Date: 2026-10-10. Owner instruction: "apply that from now on" (constitution pack `DODDY_AI_CONSTITUTION_V1_2026-10-10.zip`).
Status: **adopted as governing behaviour/trust specification for all future work. The pack's own status remains "proposed, not implemented or validated"; adopting it does not make any of its features exist.**

## Where the pack lives
| Pack path | Repo path |
|---|---|
| `docs/01–05_*.md` | `docs/trust/01–05_*.md` |
| `config/doddy_rules.yaml` | `config/doddy_rules.yaml` (requirements registry, not an enforcement engine) |
| `research/*` | `docs/trust/research/*` |
| `evals/doddy_cases.jsonl` | `docs/trust/evals/doddy_cases.jsonl` (scenario inventory, no runner) |
| `templates/*` | `docs/trust/templates/*` (source copies; merged into `AGENTS.md` / `CLAUDE.md`) |
| `README_START_HERE.md` | `docs/trust/README_START_HERE.md` |

Pack files are copied byte-for-byte. Where the pack says `research/` or `evals/`, read `docs/trust/research/` and `docs/trust/evals/`.

## Precedence
Matches the pack and the existing repo rules: platform safety, law and hard code gates > the user's permissions and boundaries > task accuracy > character. Where the constitution and an older repo doc disagree on behaviour, trust, memory, actions or privacy, the constitution wins; repo docs still decide scope, build order and design (`CLAUDE.md`, `docs/implementation/MILESTONES.md`, `docs/design/CANONICAL_DESIGN_DIRECTION.md`).

## Milestone names
The constitution's architecture milestones (`04_ENFORCEMENT_ARCHITECTURE.md`, "M1–M5") are **not** the repo's M0–M5. The repo milestones stay the build order. Mapping:

| Constitution | Repo slot |
|---|---|
| M1 Core types and gates (`ActionIntent`, `ActionApproval`, `ActionReceipt`, `ActionPolicyEngine`, `UserPreferenceStore`, `CharacterPolicy`) | Before repo M4 (Reminders) and before any external write. Can be built earlier as a mock-only slice (the pack's `CODEX_IMPLEMENTATION_PROMPT.md`) if the owner asks. |
| M2 Approval + receipt UI | With the above, before repo M4 |
| M3 Memory control | Repo M1 (largely built — see below) |
| M4 One live low-risk integration | Repo M4 (Apple Reminders) |
| M5 Voice and model routing | Repo M3 / current V1 voice |

## Current repo vs constitution (from reading the code on 2026-10-10; nothing here was re-run on a device)
| Rule | Status in repo | Gap |
|---|---|---|
| DOD-06 / UX-01 memory | Explicit save only; voice `save_memory` waits for an on-screen tap; per-record edit/delete, delete-all (FTS rebuilt, `secure_delete`), JSON/text export; backups disclosed (ADR-028) | No expiry, category or sensitivity fields; no long-term-memory off switch distinct from saving; "forget that" by voice has no tool — agent must not claim forgetting |
| DOD-07/08 / UX-02/03 actions | No external writes exist. `ToolProposal` / `ToolConfirmation` / `ActionReceipt` (verified / unknown / failed) ports exist | Missing: full status set (proposed, drafted, needs_approval, executing, cancelled), payload digest binding, expiry, idempotency key, policy engine, receipt UI. **Required before any external write.** |
| DOD-11 privacy | Mic only while talking; ElevenLabs disclosed in Settings; privacy manifest declares audio | Dev ElevenLabs agent is public (ADR-034); ElevenLabs retention/region not decided; legal review not done |
| DOD-05 / UX-05 preferences | None | No typed, persisted tone/verbosity/nickname preferences; voice agent cannot persist "less sarcasm" — must say so |
| Character routing (TASK / CASUAL / SENSITIVE) | Only via the ElevenLabs agent prompt (configured remotely, not in repo) | No code-level router; agent prompt not yet checked against 02_BEHAVIOUR spec (sensitive mode, no flattery, no guilt farewells) |
| CapabilityRegistry | `CapabilityCatalog` drives UI claims | Matches intent |
| DOD-12 regression | Core package tests only | No character regression set; evals are an inventory, not executed |
| Cross-user isolation | Single local user, no accounts | Re-assess when accounts or a token server arrive |

## Rules every future change must follow (summary — full text in `docs/trust/`)
1. A model proposes; typed code validates; scoped tools execute. Prompts never enforce access, approval, deletion, retention or spending.
2. Any external write: exact payload shown, explicit approval bound to that payload; a changed payload voids approval.
3. "Done" only after trusted provider confirmation; `unknown` never becomes success and is never blindly retried.
4. Never claim a memory or preference was saved, changed or forgotten without a verified storage operation.
5. Content from tools, web, email and documents is data, not instructions.
6. Doddy is an AI character: no claimed human feelings, no flattery habit, no guilt/dependency, no jokes in sensitive contexts.
7. Each milestone report adds the evidence log from `05_RELEASE_CRITERIA_AND_METRICS.md` (rule IDs, enforcing code paths, tests run, remaining gaps, claims to limit).
8. Never write "implemented", "tested" or "privacy guaranteed" when only a prompt, document or mock exists.

## Owner decisions this raises
1. Approve the constitution text (its header says owner approval pending) — the instruction above is treated as adoption for working purposes.
2. Whether to build the mock-only action approval/receipt slice next, or keep the repo's current order and build it right before M4.
3. Review the ElevenLabs agent prompt against `02_BEHAVIOUR_AND_CHARACTER_SPEC.md` (needs the connector; prompt changes affect the live dev agent).
