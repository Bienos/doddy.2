# DODDY Brain 10: Testing and evaluations

All brain tests use fake recall and a fake `AssistantClient` (`AssistantTestSupport.swift`). They prove the boundary's
rules, **not** live gateway, model or voice behaviour.

## Matrix (Phase 1 covers the typed path)
| Case | Test (`BrainCoordinatorTests`) | Status |
|---|---|---|
| Direct answer, no unnecessary tool | `testASimpleQuestionWithNoMatchingNoteIsAnsweredDirectlyAndMarkedGeneral` (`toolCalls == 0`) | Passing |
| Memory retrieved and cited | `testARelevantNoteIsSentAsDataAndItsCitationIsVerified` | Passing |
| Memory privacy (private, unmatched, fixture, imported) | `testPrivateUnmatchedAndFixtureNotesNeverLeave`, `testNotesTheGatewayRejectsAreWithheld…` | Passing |
| Egress contract matches gateway | `testEverySentSourceIsOneTheGatewayAccepts` (reads `gateway/src/validate.js`) | Passing |
| No memory, no fabrication | `testAReplyCitingANoteThatWasNotSentIsDiscarded` | Passing |
| Consent: nothing searched or sent | `testARefusedRequestSearchesNothingAndNeverReachesTheProvider` | Passing |
| Learned items not sent to gateway | `testLearnedFactsNeverGoToTheGatewayYet` | Passing |
| Context budget | `testTheNoteBudgetBoundsWhatLeavesTheDevice` | Passing |
| Prompt injection in a note | `testANoteThatGivesOrdersIsStillOnlyData` | Passing |
| Provider failure / search failure / cancellation | three tests | Passing |
| `AssistantService.ask` compatibility | `testAssistantServiceAskTakesTheSamePath` + the 16 existing `AssistantServiceTests` | Passing |
| Tool selection, unknown tool, approval, payload integrity, multi-step, partial failure, timeout, duplication | existing `VoiceToolsTests`, `PlanTests`, `ActivityLogTests`, `OnlineAccountsTests`, backend tests | Existing; not re-run as brain tests |
| Voice interruption / stale session | `ToolCallOwnershipTests` (5); controller wiring: Mac checklist 5c | Core passing; app NOT RUN |
| Tool gate (translator, plan, Pause all, switches) | `ToolGateTests` (8, equivalence with the old controller code) | Passing; controller NOT RUN |
| Capability honesty / approval drift | `HonestyTests`, `RealtimeVoiceTests`, `ToolCatalogTests` (9: spec, server and approval rules for all 59 tools) | Passing |
| Learning only under user control | `LearningTests`, `LearningServiceTests` | Existing |

## Evaluation metrics (Phase 6)
`BrainTrace` gives, per request and without content: notes considered, sent and withheld, search failures, whether the provider was called, and tool calls.
Those counts cover context disclosure, unnecessary calls and recall reach. Correct-answer rates need a labelled set
(`docs/quality/evals`, `docs/trust/evals/doddy_cases.jsonl`) and live runs. Not done.
