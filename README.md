**START HERE:** [READ_ME_FIRST.md](READ_ME_FIRST.md) — consolidated design + engineering instructions, visual previews, and gated Claude prompt.

# DODDY V2 — Claude Code / Codex Build Pack
**Your mate in your pocket.** | Documentation snapshot: 8 October 2026 | **Status: proposed engineering baseline, NOT approved release specification**

## Start in 5 minutes
1. Read `docs/00_START_HERE/DECISIONS_AND_STATUS.md`, `docs/product/PRODUCT_REQUIREMENTS.md`, `docs/implementation/MILESTONES.md`, `CLAUDE.md` or `AGENTS.md` (depending on agent).
2. Review two outstanding brand-v1.3 candidates in `reference/original_archives`; choose a master before freezing visual implementation. The `assets/brand_candidate` folder is **for prototypes only**.
3. Open the existing empty private repository `Bienos/doddy.2`. Extract **this folder's contents at repository root**. Do **not** copy the existing `Bienos/AI-AGENT-DODDY` app wholesale.
4. Give Claude Code or Codex `prompts/START_BUILD.md`. Ask it to implement **M0 only**, run build/tests, report evidence and stop before expanding scope.
5. Complete M1 (local text capture → source-grounded recall → edit/export/delete) before cloud AI, real voice, Reminders, or broader integrations. Use successive prompts in `prompts/` one milestone at a time.

## Product baseline
DODDY is an iPhone-first, clearly AI-driven, character-led personal companion. Separate **character/media validation** from **app utility validation**. Proposed first utility experiment: reliable, explicit memory capture and retrieval, with follow-through later. This is a hypothesis—not proven product-market fit. Do not mistake creative content engagement for retained app users.

## Development contract
- **New V2 repository only.** Existing repo `Bienos/AI-AGENT-DODDY` is *read-only reference*. `Bienos/doddy.2` was observed empty at inventory time; verify live state before setup.
- **No fabricated completion.** Real data persistence, model usage, speech, APIs, reminders and payments may only be marked implemented after executed tests and evidence.
- **Design and data rights.** Explicit memory only; provenance and correction controls; no covert always-on mic or implied iPhone background overlay. Never claim app can assign Back Tap automatically.
- **Source ranking.** This pack's `docs/` = proposed canonical V2 requirements; `reference/` = historical source, contradictory drafts and evidence, not executable instructions. This policy applies only after owner acceptance.
- **Honest tests.** No Xcode build of this new V2 app, legal opinion or user validation is claimed by the existence of this pack. It is a documentation package, not compiled code.

## Fast navigation
| Need | File |
|---|---|
| What is verified/assumed? | `docs/00_START_HERE/DECISIONS_AND_STATUS.md` |
| Full source audit / duplicates | `docs/00_START_HERE/SOURCE_AUDIT.md` |
| Requirement and out-of-scope | `docs/product/PRODUCT_REQUIREMENTS.md` |
| SwiftUI design | `docs/architecture/IOS_ARCHITECTURE.md` |
| SQLite, memory and provenance | `docs/architecture/MEMORY_AND_DATA.md` |
| Real AI provider plan | `docs/architecture/AI_RUNTIME.md` |
| Voice / Shortcuts | `docs/architecture/VOICE_AND_APPLE_SURFACES.md` |
| Actions / Reminders | `docs/architecture/TOOLS_AND_ACTIONS.md` |
| Legal/privacy preflight | `docs/security/PRIVACY_GDPR_AI_ACT.md` |
| Brand + behavior | `docs/design/BRAND_AND_CHARACTER.md` |
| Build order and gates | `docs/implementation/MILESTONES.md` |
| Detailed agent tasks | `docs/implementation/TICKETS.csv` |
| Acceptance testing | `docs/quality/ACCEPTANCE_TESTS.md` |
| Agent prompt | `prompts/START_BUILD.md` |
| All provenance links | `reference/SOURCE_PROVENANCE.md` |

## Source materials in this package
- Original untouched archives: `reference/original_archives/` (brand versions, Character Bible, product opportunity, investment/deep research). These are included as archival ZIPs and may contain duplicate or superseded advice.
- Text extracts from project Library: `reference/compiled_research/`.
- Selected original character personality config + evaluation cases: `reference/character_evals/`.
- Candidate UI design tokens and character vectors: `assets/brand_candidate/`.
- For the old GitHub code and in-repository docs, use the linked repository directly. No source code was copied into V2.

## Definition of source labels
- **OBSERVED:** verified by a particular read/search result in the 2026-10-08 inventory.
- **HISTORICAL:** a source claimed this, but it may be obsolete or unaudited.
- **PROPOSED:** an engineering/product recommendation for V2. Founder approval and implementation pending.
- **REQUIRES TEST:** a live-device/provider/legal or user-acceptance check still needed.

Do not deploy, create cloud accounts, contact users, run destructive commands, publish, or incur billable provider usage based solely on this documentation.
