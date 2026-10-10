# Action approval and receipts: simulation slice
Date: 2026-10-10. Owner instruction: "build the mock approval and receipt flow now".
Spec: DODDY AI Constitution V1 (`docs/trust/`), first milestone in `docs/trust/templates/CODEX_IMPLEMENTATION_PROMPT.md`.

**This is a simulation.** No message, contact, network call or other app is involved. Real actions (Reminders, messages) are still **not built**; the Settings capability list says so.

## What exists now
- **Core (`Packages/DoddyCore`, platform-agnostic):**
  - `Actions.swift`: `ActionType`, `ActionRiskTier`, `ActionStatus`, `ActionPayload` (exact content, validated, no trimming), `ActionProposal`, `ActionApproval`, `ActionRecord` (also the receipt), the `ActionAdapter` protocol, `ActionPolicyError`, and `ActionStatusCopy` for user-facing wording.
  - `ActionLedger.swift`: an actor that is the only owner of action state. It enforces every transition. It also holds `ActionProposalParser`, which turns a model tool call into a proposal and nothing more.
  - `SimulatedActionAdapter.swift`: a pretend message provider (`isSimulation = true`) with six scripted outcomes.
  - `UnavailableActionAdapter` replaces the old `UnavailableToolExecutor`. The old `ToolProposal`, `ToolConfirmation`, `ToolExecutor`, `ActionReceipt` and `ToolKind` ports were removed.
- **App:** Settings → Actions → **Try the approval flow (simulation)** opens `ActionDemoView`:
  1. Draft a sample message.
  2. Check or edit the recipient and text.
  3. Pick a simulated result, then tap Approve.
  4. Read the receipt and its history. If the result is "Couldn't confirm", use Check status.
  - A banner on every state says nothing is sent.
- **Capability:** `actionSimulation` is available in the new `CapabilityCatalog.v1Trust`, which the live app uses. `reminders` and `connectedAccounts` stay not built.

## Lifecycle as enforced
```
propose → [proposed, drafted] → requestApproval → needsApproval
needsApproval + approve(reviewedPayload == current) → approval (5 min, single use)
edit (drafted | needsApproval) → drafted, approval cleared
execute: needsApproval + valid approval → executing (stored before the provider call)
   → confirmed (only with a non-empty provider reference) | failed | unknown (timeout, thrown error, OK without reference)
unknown → reconcile (asks provider by idempotency key, never re-sends) → confirmed | failed | unknown
cancel: proposed | drafted | needsApproval → cancelled
```
Refusals:

| Situation | Error |
|---|---|
| Execute without approval | `notApproved` |
| Approve from a screen whose payload differs from the current one | `payloadChanged` |
| Approval expired | `approvalExpired` (the approval is cleared) |
| Second execute while the first is still running | `alreadyExecuting` |
| Execute after `unknown` | `reconcileFirst` |
| Execute after a final status (confirmed, failed, cancelled) | `alreadyFinished` |
| Action type no adapter supports | `unsupportedAction` (no record is created) |

## Evidence log (constitution `05_RELEASE_CRITERIA_AND_METRICS.md`)
| Rule / scenario | Enforcing code | Executable assertion |
|---|---|---|
| DOD-07, DC-013, T25: no send before exact approval | `ActionLedger.execute` guards | `testExecuteWithoutApprovalIsRefused`, `testProposalIsOnlyADraftAndNothingRuns` |
| DOD-07, DC-014: change after approval voids it | `ActionLedger.edit`, `approve(reviewedPayload:)` | `testEditAfterApprovalVoidsItAndOnlyTheReapprovedPayloadIsSent`, `testStaleScreenCannotApproveChangedContent`, `testWhitespaceIsPartOfTheApprovedPayload`, app `testUnsavedEditsBlockApproval` |
| DOD-07: model can't self-approve | `ActionProposalParser` ignores extra fields; `ActionApproval.init` internal | `testModelCannotApproveItsOwnProposal` |
| DOD-07, DC-015: unknown/unbuilt tools refused | `ActionProposalParser`, `ActionLedger.adapter(for:)` | `testUnknownAndUnbuiltToolsAreRefused`, `testUnsupportedActionIsRefusedBeforeAnyRecordExists` |
| DOD-08, DC-018, T31: "confirmed" only with provider reference | `ActionLedger.apply` | `testConfirmedOnlyWithProviderReference`, `testSuccessWithoutReferenceIsNotConfirmed` |
| DOD-08, DC-019: failure reported as failure | `ActionLedger.apply` | `testFailureIsReportedAsFailure` |
| DOD-08/09, DC-017, DC-020, T28: unknown, no blind retry, reconcile | `execute` (`reconcileFirst`), `reconcile` | `testTimeoutIsUnknownAndIsNeverResent`, `testReconcileCanFindItWasNotDelivered`, `testReconcileWithNoAnswerStaysUnknown`, `testReconcileOnlyForUnknown` |
| Duplicate execution | `executing` stored before the await | `testConcurrentExecuteSendsOnce`, `testFinishedActionsCannotRunAgain` |
| T32: cancel | `ActionLedger.cancel` | `testCancelBeforeExecutionStopsEverything` |
| DC-027, T29: instructions inside content stay data | payload stored verbatim, never interpreted | `testInstructionsInsideContentStayData` |
| UX-02 wording: only provider-confirmed reads as done; refusals say nothing was sent | `ActionStatusCopy` | `testOnlyConfirmedReadsAsDone`, `testRefusalsNeverSuggestSomethingWasSent` |
| T42: simulation never presented as real | `isSimulation` on every record; banner and copy | `testConfirmedOnlyWithProviderReference` (copy), `testV1TrustAddsOnlyTheSimulationNotRealActions`, UI test (not run) |

**Manual only (not covered by code):** the character side of these scenarios, meaning how Doddy *phrases* drafts and uncertainty (DC-013 "Draft ready. Check the recipient…", DC-017 "I can't confirm the booking"). It also covers DC-001 to DC-012 and DC-021 to DC-030 (sycophancy, sensitive-context humour, identity), which belong to the voice agent prompt and the future character regression set (DOD-12).

## Tests executed (2026-10-10, Linux x86_64, Swift 6.3.3 official toolchain, signature not verified)
| Command | Result |
|---|---|
| `swift test --package-path Packages/DoddyCore -Xswiftc -DSQLITE_DISABLE_SNAPSHOT` | **56 tests, 0 failures**, 0 compiler warnings (25 new in `ActionLedgerTests`, 1 new in `HonestyTests`; baseline before this change was 30) |
| Mutation check: 5 deliberately broken ledgers (approval check removed, edit keeps approval, retry from `unknown`, confirm without reference, `executing` stored after the await) | each one fails at least one test |
| `DoddyTests/ActionDemoModelTests.swift` + `ActionDemoModel.swift`, compiled against DoddyCore in a scratch package on Linux | **6 tests, 0 failures**, Swift 6 strict concurrency, no warnings |
| `swiftc -parse` on every changed Swift file, including `ActionDemoView.swift` and the UI test | all parse |
| `scripts/ci.sh --core-only` | PASS for core-only scope; iOS app NOT verified |

## Not verified (needs a Mac)
- The app build with the new view; SwiftUI layout, Dynamic Type, VoiceOver order and dark mode on the approval and receipt screens.
- `ActionDemoModelTests` inside the real `Doddy` app target.
- `testSimulatedApprovalFlowSaysSimulationAndNeverClaimsUnconfirmedSuccess` (UI test, including the menu picker interaction).

## Gaps before any real action (repo M4 or earlier)
1. **Persistence:** the ledger is in memory and records vanish on quit. A real adapter needs the pending state written durably *before* the external call, plus reconciliation on relaunch.
2. **Real permission checks** (OS / OAuth scope) at proposal and at execution time; none exist for the simulation.
3. **Per-user binding:** single local user today. Approval must also bind to the account/connector once accounts exist.
4. **Receipt history screen** (all past actions); the demo only shows the current one.
5. **Voice:** the ElevenLabs agent has no action tools. Adding one must go through `ActionProposalParser` → ledger, with spoken read-back of critical fields (T37).
6. **Retry after `failed`:** deliberately not built. A retry must be a new draft and a new approval.

## Privacy and security notes
No new permission, network access, storage or telemetry. The forbidden-capability guard still passes. Sample data is fictional ("Sam (sample contact)"). Nothing in this slice reads contacts.
