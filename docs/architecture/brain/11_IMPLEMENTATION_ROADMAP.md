# DODDY Brain 11: Implementation roadmap

| Phase | Scope | Status |
|---|---|---|
| 0 | Audit, inventory, target design (00–10) | Done 2026-10-12 |
| 1 | `BrainCoordinator` + `ContextAssembler` for typed questions; Ask wired through it; imported-note egress fix | **Built, Linux-tested** (ADR-442); app compile on Xcode NOT RUN |
| 2 | Voice egress target for `search_memories`; one greedy-fill helper; DATA markers for profile and learned context | Needs owner decision on voice start context (03 §Gaps 1) |
| 3 | `ToolCatalog` + spec cross-check; `ToolGate` + stale-session guard; plan loop into core | Next: see below |
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

## Next smallest verified task
**Stale-session guard + `ToolGate` (Phase 3a).** A pure `ToolGate.decide` that reproduces `VoiceSessionController.swift:1676-1697`,
plus `isCurrent(attempt:)`, with table tests on Linux. Then three call-site edits in the controller (`handle` after each `await`,
`propose`, `reply`) so a call from an ended conversation can never show a card or reply in the next one. The controller
edit needs a Mac build and the manual check "End + Start while a Gmail draft is preparing → no card in the new conversation".
