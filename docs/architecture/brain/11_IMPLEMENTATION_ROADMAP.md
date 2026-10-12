# DODDY Brain 11: Implementation roadmap

| Phase | Scope | Status |
|---|---|---|
| 0 | Audit, inventory, target design (00–10) | Done 2026-10-12 |
| 1 | `BrainCoordinator` + `ContextAssembler` for typed questions; Ask wired through it; imported-note egress fix | **Built, Linux-tested** (ADR-442); app compile on Xcode NOT RUN |
| 2 | Voice egress target for `search_memories`; one greedy-fill helper; DATA markers for profile and learned context | Needs owner decision on voice start context (03 §Gaps 1) |
| 3a | Stale-session guard (`ToolCallOwnership`, controller call sites) | **Built** (ADR-443); core Linux-tested, controller not compiled |
| 3b | `ToolGate.decide` (the gate chain of `handle`) | **Built** (ADR-444); equivalence-tested on Linux, controller not compiled |
| 3c | `ToolCatalog` + spec cross-check; plan loop into core | Next |
| 4 | Typed tools through the same gate (needs a gateway tool contract) | Needs owner approval |
| 5 | Proactive jobs (08) | Design only; any scheduler is a separate approved task |
| 6 | Evaluation from `BrainTrace` + labelled sets | Not started |

## Phase 1 changes (files)
- `Packages/DoddyCore/Sources/DoddyCore/Brain/ContextAssembler.swift` (new)
- `Packages/DoddyCore/Sources/DoddyCore/Brain/BrainCoordinator.swift` (new)
- `Packages/DoddyCore/Sources/DoddyCore/Assistant/AssistantService.swift` (context via `ContextAssembler`; `ask` runs through the coordinator; new `answer`; `AssistantAnswer.notesWithheld`)
- `DoddyApp/Features/Ask/AskController.swift` (calls `BrainCoordinator`; keeps `lastTrace`)
- `Packages/DoddyCore/Tests/DoddyCoreTests/BrainCoordinatorTests.swift` (new, 16 tests)

Behaviour change: notes whose source the gateway rejects (`imported_file`) are no longer sent. Before, the whole question
failed with a misleading "Shorten it" message. Everything else is unchanged; the 16 existing `AssistantServiceTests` pass unmodified.
`AskView` does not show `notesWithheld` yet (a SwiftUI change; Mac needed to check it).

## Phase 3a changes (ADR-443)
- `Packages/DoddyCore/Sources/DoddyCore/Brain/ToolCallOwnership.swift` (new) + `ToolCallOwnershipTests` (5 tests)
- `DoddyApp/Features/Voice/VoiceSessionController.swift`: each call recorded with its start attempt; `propose`, list writes,
  plan and ingredients cards, parking and list receipts and the connection prompt need `isCurrent`; `reply` logs late
  results but sends only to the conversation that asked. Not compiled here: Mac checklist 5c.

## Phase 3b changes (ADR-444)
- `Packages/DoddyCore/Sources/DoddyCore/Brain/ToolGate.swift` (new) + `ToolGateTests` (8 tests, >10,000 equivalence cases)
- `VoiceSessionController.handle` calls `ToolGate.decide` instead of its four inline checks.

## Next smallest verified task
**`ToolCatalog` cross-check (Phase 3c, design in 04).** Per-tool effect and approval, derived from the existing constants,
with a test that `voice-agent/tools.json`'s `confirm_on_screen` agrees for every tool. Core-only, no app change.
