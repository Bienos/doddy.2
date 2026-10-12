# DODDY Brain 05: Task planning

## What exists (keep it)
`propose_plan` → `PlanProposal.parse` (`Plan.swift`): at most 5 steps from `PlanTool.allowed`. Every step is parsed exactly as
a single call would be. One card shows a tick box per step and the user approves once. Steps run in order, each re-checked at
the tap (`PlanBlock`). Each step logs its own `ActivityEntry`, and `PlanReply.summary` gives one result line per step, so
partial success is reported step by step. Learned routines (`Procedure`) expand into the same card.

Look-ups are not plan steps: the agent runs them first with the usual tools. This keeps plans bounded and inspectable.

## Gaps
- Plan execution (`runPlan`, `runPlanStep`, `runOtherPlanStep`) lives in the controller and partly duplicates itself (`VoiceSessionController.swift:1987-2149`).
- No typed `PlanRun` state outside the view state (`PlanStatus`).

## Proposal (Phase 3)
Move the step-resolution loop (ticked / blocked / unticked → reply) into `DoddyCore` as a pure function with injected
step runners, tested on Linux. Keep `PlanReply` prefixes unchanged. "Plan my Saturday" stays a sequence of read tools,
then one `propose_plan` card for the writes. No autonomous loops, no planner model call, no step without its own approval path.
