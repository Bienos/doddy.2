# DODDY Brain 07: Voice and text integration

## Today
- **Typed (Ask):** `AskController` → `BrainCoordinator` (since ADR-442) → `AssistantService.answer` → gateway. No tools.
- **Voice:** `VoiceSessionController` owns transport (ElevenLabs SDK or `OpenAIRealtimeSession`), audio session,
  context variables, tool dispatch, cards, plans, translator, Live Activity and logging.

Shared today: `RecallService`, the private-notes filter, record types, `ActivityLog`, reply builders.

## Path (one workflow at a time; prove equivalence first)
1. **Done:** typed questions through `BrainCoordinator` (read-only, Linux-verified).
2. **Next:** `ToolGate` (06) plus the stale-session guard. These are pure functions with table tests; the controller calls them. Mac verification is needed for the controller edit.
3. `search_memories` through `ContextAssembler` with an `EgressTarget.voiceAgent`, so both channels share one recall-and-egress contract. The reply text stays `VoiceToolReply.search`, which the agent rules depend on.
4. Plan step loop into core (05).
5. Only then consider typed tools: Ask proposing a card would reuse the same `ToolGate` and executors. This needs a gateway tool-call contract and owner approval.

## Stays provider-specific
Audio session and interruptions, barge-in, partial transcripts, ElevenLabs/LiveKit config, OpenAI Realtime events,
the wake word and Live Activity. Polish/English handling stays in prompts and parsers (`ReminderDueRules`, `RecallMatching`)
and is already shared.
