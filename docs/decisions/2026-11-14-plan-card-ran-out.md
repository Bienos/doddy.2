# A plan card that has run out never runs; it is shown again, and only a new tap on it runs the plan

- **Date:** 2026-11-14
- **Decided by:** the owner approved this work and its edits to the voice controller and `VoiceView.swift` (agent brief, 14 Nov 2026). The points marked "Owner decision" below are proposals until the owner says otherwise.
- **Status:** applied in the pull request from `claude/stale-plan-approval-new-tap`
- **Replaces:** in part ADR-209 (the sentence "a card that waited more than 90 seconds asks the server for a fresh approval of the same arguments, and the server checks them again"). Everything else in ADR-204, ADR-205 and ADR-209 stays.

## Why
Read in the code on 14 Nov 2026:
- The plan card (`propose_plan`, ADR-204) is one card for up to five steps. A Gmail draft or Todoist step gets a preview and a single-use approval from Doddy's server when the card is put up (`prepareCloud`); the server's approval works for two minutes.
- The card itself had no end. It did not go through `AskLedger` (the plan is run straight from `confirmPendingAction`), so a tap ten minutes later ran it as readily as one after ten seconds.
- The 90 s sat in `runPlanCloud`: when a step's approval was older than 90 s, the app asked the server for a new approval for the same arguments and ran the step at once. The preview the server made the second time was not compared with the one on the card and was not shown. The person's tap had approved the first preview.
- A spoken yes reached the same path (`spokenAnswer`, decision `2026-11-14-spoken-yes-and-fewer-cards`, step 2a) for up to 120 s after the card appeared.
- The constitution says the approval is bound to the exact payload shown (DOD-07) and that nothing is reported done without confirmation (DOD-08).

## Decision
The decision logic is one small pure type in DoddyCore, `PlanApprovalGate` (`PlanApproval.swift`), with the clock passed in at each call like `AskLedger`; the voice controller asks it and does what it says.

1. **A card is fresh for 90 s** from when its steps were prepared: the oldest server approval it holds, or the moment it is shown when no step goes through the server. That keeps 30 s inside the server's two minutes, so every step's approval is alive when its turn comes. A tap at exactly 90 s still counts.
2. **A tap while the card is fresh, for the payload it showed, runs the plan once.** A second tap does nothing.
3. **A tap after the window runs nothing.** The app checks every step again as it did for the first card (switches, permissions, earlier tries, the server's prepare), then shows the card again with what is true now and a new 90 s. A step whose server preview changed comes back unticked; a step that cannot run any more is blocked with its reason; the person's other ticks and their Changes stay. The first card's approvals are dropped, never used. The same happens if the payload at the tap is not the one the card was shown with.
4. **Only a new tap on the shown-again card runs the plan.** A press within one second of the card coming back is taken as the press that asked for it and does nothing. The card says why it came back (`This card ran out, so here it is again with what's true now. Nothing was done. Check it, then tap once more.`, Polish in `l10n/pl.json`).
5. **A spoken yes** (owner's table, `ConfirmationTiers`: plans are on the spoken-yes tier, and tap only once outside text has reached the conversation): a first card still takes the person's yes while it is fresh, as before. A yes never runs a card that ran out or one that was shown again, and it does not refresh one; the card's header says "Doddy needs your tap" for those.
6. **A step never gets an approval made after the card was shown.** The branch in `runPlanCloud` that made one when the card was old is gone. A step with no approval says `failed: … Nothing was done.`; an approval that ran out between two steps is refused by the server and that step's line says what the server said.
7. **The agent.** Its call stays open while the card is shown again; it hears what the new tap does (the usual per-step lines), or the decline, or nothing if the conversation ends first (then the steps are logged as not done, as before). A declined, replaced or ended card runs nothing.

### Owner decisions
- **Plans stay on the spoken-yes tier.** The brief for this change said a spoken yes never runs a plan; the table in `ConfirmationTier.swift` and the decision above (step 2a, "…plans…") put `propose_plan` on the spoken-yes tier, and `ConfirmationTierTests` pins it. This change keeps the table: only a card that ran out, or was shown again, is tap-only. Making every plan tap-only is a different decision: `ConfirmationTiers.tapOnly`, `x_doddy.ask` for `propose_plan` in `voice-agent/tools.json` (`yes_or_tap` to `tap`, which waits for the live-agent sync) and `scripts/voice_agent_spec.py`.
- **The window applies to every plan card**, also one with no step on Doddy's server. For those the shown-again card is the same plan, checked again, with one more tap.
- **90 s is a number I chose** from the existing one and the server's two minutes. It is one constant (`PlanApprovalGate.window`).

## Consequences
- A person who reads a plan card for longer than 90 s taps twice. Nothing is run on a preview they did not see.
- The agent waits up to 120 s for `propose_plan` (`timeout_secs` in `voice-agent/tools.json`). After that its call is closed. A tap on a shown-again card after that still runs the steps the person is looking at, but the result can no longer be sent to the agent (as before this change: `reply` is dropped for a closed call), so the agent may not know. Not changed here.
- The header can still say "Say yes, or tap" for a card that ran out until the screen next redraws; a yes then does nothing and the tap works.
- Not covered: the person's own Changes to a local step are not part of the bound payload (they are theirs, on the card, and each local step is checked again when it runs).

## Evidence
- DoddyCore on Linux (Swift 6.1.3): `PlanApprovalTests`, written first and seen red, then green; five deliberate breaks of the gate each fail them. Results in the pull request.
- `scripts/check_forbidden_capabilities.sh` gained one DOD-07 check for the controller (the gate is asked, the card is registered twice, the old age check is gone); shown failing on two planted regressions.
- Not compiled: `VoiceSessionController.swift` and `VoiceView.swift` (no Xcode here; the new functions were type-checked against DoddyCore in a stand-in harness and both files were parsed, which is not a build). Not seen on a device.
