# A direct instruction can authorize its exact research job or single inquiry call

- **Date:** 2026-11-18
- **Decided by:** owner, supplied “DODDY — MASTER AGENT INTELLIGENCE, AUTONOMY & EXECUTION AUDIT”: “This request itself authorizes the specific call. DODDY should not ask for redundant confirmation when the recipient and objective are clear.” The task also requests autonomous read-only research, bounded scope, tests and reviewable changes.
- **Status:** accepted for this implementation branch; production rollout pending validation
- **Replaces:** the unconditional extra start question for these two narrowly recognized scopes. It does not replace exact-payload approval for bookings, orders, payments, deletion or other consequential writes.

## Why

Ordinary reads already run immediately. Background handoff still requested an extra yes; `call_places` conflated inquiry, booking and order approval. A prompt-only bypass would violate the constitution. The existing typed task/digest APIs and persistent workers support a smaller, enforceable change.

## Decision

`RequestedWorkSession` accepts only recent user-side final transcript text. Its private, single-use grant binds the turn and exact typed request, expires after two minutes, and is reset with the conversation. Research words/brief must match the instruction. A direct inquiry needs one exact distinctive live listing or spoken number, the verbatim question and no booking/order/SMS. The compiled server preview must preserve scope, principal, destination, language and recording/disclosure state. The current conversation and pause state are rechecked before the existing digest-bound approval call.

Keep conservative card fallbacks and all server gates. Store evidence-backed call reports in existing results and content-free progress on existing errand rows. Use the current PostgreSQL worker; introduce no dependency or generic workflow engine. Live agent changes remain a separately reviewed operation after compatible native validation.

## Consequences

Clear supported instructions avoid a redundant question. Contextual/rewritten/ambiguous instructions still use the existing card. English recognition is tested in Core, but the currently Polish call payload cannot be silently authorized as English. Default result SMS becomes false. Native controller/UI wiring is not compiled on Linux. New report fields require a compatible app to retain/read them; old clients may discard them during local adoption. Apply migration 042 before the worker/API. The report writer's output ceiling increases from 2,000 to 4,000 tokens, with one existing writer request; real cost/latency is unmeasured.

## Evidence

See [actual tests](../../DODDY_AGENT_TEST_RESULTS.md), [implementation and rollout](../../DODDY_IMPLEMENTATION_SUMMARY.md) and [authorization design](../../DODDY_AUTONOMY_DESIGN.md). No production change, real third-party call, historical transcript analysis or native device validation occurred.
