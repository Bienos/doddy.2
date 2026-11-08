# Doddy keeps the BLIK phone-transfer draft: what ADR-810 removed is restored

- **Date:** 2026-11-07
- **Decided by:** owner, 7 Nov 2026: "close 207 and keep blik", then "yes i want" the revert. This reverses the owner's 5 Nov 2026 choice ("1" = remove it now, answering ADR-760's open question).
- **Status:** applied in the pull request that adds this file, once merged
- **Replaces:** ADR-810 (its row in `DECISIONS.md` is marked superseded, not deleted). ADR-510 and ADR-541 are in force again.

## Why
- On 5 Nov the owner chose to remove the draft because BLIK payments were meant to go through Stripe later. On 7 Nov the owner reversed that: removing it leaves Doddy with no BLIK at all and nothing replaces it. Stripe's agent checkout has no BLIK, and BLIK through Stripe would make Doddy the merchant, which was not chosen.
- Pull request #207 (the removal) was closed by the owner, but its commits reached `main` anyway as `e7c9d001` (7 Nov 19:57 UTC; original commit `00826cdc`). `10d376b4` then mixed the BLIK part with #194's work.
- The live ElevenLabs agent was never changed: it still has the `draft_blik_transfer` tool (`tool_5701m57c1717fmebcs14kbrjqmdq`) and its prompt section. After this change the app and the live agent match again.

## Decision
1. The BLIK phone-transfer draft is back exactly as ADR-510 and ADR-541 describe it: the `draft_blik_transfer` voice tool, `BlikTransfer.swift` with its typed checks (grosze, never rounded, 1,000 zł ceiling) and tests, the transfer card and "Send it in your bank app" receipt with their Copy buttons, Settings › Connections › Money › BLIK transfers (on by default since ADR-813, no iOS permission), `VoiceConnection.blik`, `IslandAction.transfer` with its island words and screenshot sample, the "What Doddy did" rows, the 12 Polish strings, the tool in `voice-agent/tools.json` and its lines in `instructions.md`, and its entry in the Logbook tool list. `voice_agent_spec.py check` passes with `draft_blik_transfer` among the tools (108 on the base this was merged with).
2. From `10d376b4`, only the BLIK part is undone: `.blik` is in `VoiceConnection.startsOn` again (so ADR-813's "BLIK transfers start on" is true again) and the test expects it. Everything else that commit did stays: `.home` in `startsOn` (off), and #194's decisions numbered 813 and 814.
3. Doddy still never sends or pays money. The user sends the transfer in their own bank app.
4. Stripe stays the payment direction for later. Nothing for Stripe is built or decided here, and each payment feature needs its own milestone approval (CLAUDE.md rule 6).

## Consequences
- Existing installs that never touched the switch get it on again (a stored value under `voiceConnection.blik` is read again).
- The live voice agent needs no change.
- The activity-log decode test that #207 added (a stored `blik` row still loads) is kept only if it applies; see the pull request.

## Evidence
See the pull request: the guards and generators run on Linux, and the hosted CI run. Swift is not compiled or run on the machine that wrote this.
