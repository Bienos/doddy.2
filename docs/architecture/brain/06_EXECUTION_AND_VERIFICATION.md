# DODDY Brain 06: Execution and verification

## Lifecycle: the brief's states mapped to what exists (no new statuses)
| Brief | Existing |
|---|---|
| PROPOSED | model tool call (`ClientToolCallEvent`) |
| VALIDATED / NEEDS_CLARIFICATION | `VoiceToolRequest.parse` → typed case / `.needsClarification` / `.invalid` / `.unsupported` |
| AWAITING_APPROVAL | `PendingAction` card (one at a time); cloud: server `prepare` → `approvalId` (120 s, single use, digest-bound) |
| EXECUTING | `ActivityEntry` with outcome `inProgress`, written **before** the side effect |
| VERIFYING | read-back in `DeviceConnections` (`AddOutcome.verified/unconfirmed`), server receipts |
| SUCCEEDED / FAILED / UNKNOWN / CANCELLED | `ActivityOutcome.done / notDone / notSure / declined`; server `succeeded / failed / outcome_unknown / canceled / blocked` |

Unknown is never success. A crash mid-write turns `inProgress` into `notSure` (`ActivityLog.recoverInterrupted`).
A timeout after a cloud write was submitted becomes `outcome_unknown` (`service.ts:490-507`). The agent hears
`unknown: … ask the user to check before trying again`, so it is never told to retry blindly.

## Gaps (priority order)
1. **Stale session (OPEN, safety).** A call from conversation A can show its card, or reply, in conversation B (00 §5 #1). Fix: carry the start attempt with every call and drop results whose attempt is no longer current. Apply this at `propose`, at `reply`, and after every `await` in `handle`/`handleCloud`.
2. **Phone-tool approval binds to the card, not a digest.** A changed payload means a new card today, because "Change" re-renders it. A digest test would make that explicit.
3. **Gate chain untestable on Linux** (`handle`, `:1674-1697`).

## Proposal (Phase 3)
`ToolGate.decide(request, toolName, environment) -> ToolGateDecision` in `DoddyCore`:
`refuse(reply) | clarify(reply) | lookup | proposeCard | plan`, with environment `{translatorOn, paused, connectionsOn, access, sessionAttempt}`.
It reproduces lines 1676-1697 exactly, proven by table tests before the controller calls it. The stale-session fix is
written as `ToolGate.isCurrent(attempt:)` plus three call sites. Execution, iOS permission prompts and UIKit stay in the app.
