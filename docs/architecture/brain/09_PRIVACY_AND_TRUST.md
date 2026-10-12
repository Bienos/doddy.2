# DODDY Brain 09: Privacy and trust

Binding: `docs/trust/01_THE_DODDY_CONSTITUTION.md`, `docs/trust/04_ENFORCEMENT_ARCHITECTURE.md`, `docs/trust/config/doddy_rules.yaml`.

| Principle | Where the brain enforces it |
|---|---|
| External content is data | Voice: `ToolData` markers on every reply that carries outside text (ADR-381). Typed: notes travel in `memories[]`, never in `userText` (`testANoteThatGivesOrdersIsStillOnlyData`) |
| Model output cannot authorise itself | `BrainCoordinator.route` runs before any model call; voice tools go through `VoiceToolRequest.parse` and cards |
| Minimise sensitive data | `ContextAssembler`: matched notes only, private notes excluded, per-destination source allowlist, budget, no learned items to the gateway |
| Citations only of what was sent | `CitationVerifier` (A-14), unchanged |
| Approval bound to the action | Cards (phone); digest-bound single-use approvals (server) |
| Unknown is never success | `ActivityOutcome.notSure`, `outcome_unknown`, `VoiceToolReply.addUnconfirmed` |
| Memory changes verified | Repositories read back before success (`MemoryStore`, learning repos) |
| Character never controls permissions | Personality is a prompt variable only; no code path reads it for a decision |

`BrainTrace` holds no text: route, counts and booleans only. It lives in memory in `AskController.lastTrace` and is not written to disk or sent anywhere.

Open risks are tracked in 00 §5. The ones that need new abstractions are stale sessions and the context markers (#1, #8). Neither is made harder by Phase 1.
