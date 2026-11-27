// What the live task-call agent must look like (ADR-503). Generated from voice-agent/task-call/ by
// hand and kept in step by `python3 -I scripts/voice_agent_spec.py check --agent task-call`, which
// fails CI when the prompt's hash or any value below differs from that folder. Render deploys only
// server/messaging, so the expected values live here.
export const TASK_AGENT_SPEC = {
  /** sha256 of voice-agent/task-call/instructions.md, trimmed, as the setup script sends it. */
  promptSha256: "a24e00dcd37c03e0e56bf184c7009ed017216e77a9951a95eaf1560d9ccfa7b8",
  firstMessage: "{{doddy_opening_line}}",
  language: "pl",
  systemTools: ["end_call", "voicemail_detection"] as readonly string[],
  audioFormat: "ulaw_8000",
  /** The agent's own limit must be above ours, so our server decides when the call ends. */
  minAgentMaxDurationSecs: 320,
} as const;

/**
 * The booking agent (decision docs/decisions/2026-11-12-book-agent.md), from voice-agent/task-call-book/,
 * kept in step by `python3 -I scripts/voice_agent_spec.py check --agent task-call-book`. Same rules as
 * the ask agent; only its prompt differs, so the same safety check reads it with this hash.
 */
export const TASK_BOOK_AGENT_SPEC = {
  ...TASK_AGENT_SPEC,
  /** sha256 of voice-agent/task-call-book/instructions.md, trimmed, as the setup script sends it. */
  promptSha256: "0f5097babaab961add7c0b9d81826e458157ee6b0364ddfd73df488bb1adce8c",
} as const;

/**
 * The order agent (decision docs/decisions/2026-11-12-food-by-phone.md), from voice-agent/task-call-order/,
 * kept in step by `python3 -I scripts/voice_agent_spec.py check --agent task-call-order`. Same rules as the
 * ask agent; only its prompt differs, so the same safety check reads it with this hash.
 */
export const TASK_ORDER_AGENT_SPEC = {
  ...TASK_AGENT_SPEC,
  /** sha256 of voice-agent/task-call-order/instructions.md, trimmed, as the setup script sends it. */
  promptSha256: "531308166f25efe9411d2327303fd01465948cdd82152949064ae63b6a2f94b7",
} as const;

/**
 * The message agent (decision docs/decisions/2026-11-27-voice-first-doddy.md, step 4), from voice-agent/task-call-tell/,
 * kept in step by `python3 -I scripts/voice_agent_spec.py check --agent task-call-tell`. Same rules as the ask agent;
 * only its prompt differs, so the same safety check reads it with this hash. A new agent: no older prompt to accept.
 */
export const TASK_TELL_AGENT_SPEC = {
  ...TASK_AGENT_SPEC,
  /** sha256 of voice-agent/task-call-tell/instructions.md, trimmed, as the setup script sends it. */
  promptSha256: "10c7643ce6a07aeeb1a287074697ce3399f7ae627655e914302d87524c5bb34b",
} as const;

/**
 * Prompts the drift check still accepts while the owner hasn't synced a live agent: for a spec's prompt hash, the
 * hashes of the instructions.md it replaced. Only the owner changes the live agents (CLAUDE.md), so without this a
 * deploy of a new prompt would stop every call until the sync. Keyed by the new hash, so another agent's spec never
 * inherits an entry. Each entry goes once the live agent has the new prompt.
 *
 * 12 Nov 2026 (OWNER_QUEUE 52): {{doddy_goal}} was taken out of both prompts. The server now sends `doddy_goal` as a
 * fixed sentence (payload.ts), so the old prompts get no goal text either while they are still live.
 * 13 Nov 2026: both prompts sound like the person's own assistant; the opening line (server-built) says "wirtualny
 * asystent". An older live prompt still answers honestly when asked, so it stays accepted until the owner's sync.
 * 14 Nov 2026: the order agent's prompt sounds like the person's assistant too (owner: "wybierz best options"); its
 * first prompt, live on "Doddy 7" since that day, stays accepted until the live agent has the new one.
 * 15 Nov 2026: all three prompts sound like a relaxed person on the phone, and "what is it about?" is no longer treated
 * as a wrong number (owner: "żeby były luźne i brzmiały jak człowiek"; decision docs/decisions/2026-11-15-calls-sound-natural.md).
 * Each one's prompt from before stays accepted until its live agent has the new one.
 * Later on 15 Nov 2026: the opening asks for a moment and the agent asks the question after a yes; asked whether it is a
 * robot or an AI, Doddy says yes lightly, and asked whether it is a human, no (decision 2026-11-15-call-opening-asks-for-a-moment).
 * Then: "no time" gets one quick try at the question before a polite goodbye (owner, same decision, last section).
 */
export const SYNC_PENDING_PROMPTS: Readonly<Record<string, readonly string[]>> = {
  // task-call: main before 12 Nov 2026, then main from 12 to 13 Nov 2026 (before the assistant's natural voice,
  // decision docs/decisions/2026-11-13-call-agent-sounds-like-an-assistant.md)
  [TASK_AGENT_SPEC.promptSha256]: [
    "129f2aecdee4c501b32148112e64efe3f57a126e82e7358cfd2816ff27a26454",
    "0f2c05bcc3090802ae6ad0656c8f69ba6af9c6bdbfa8f63596088b8b1a25099a",
    // main from 13 to 15 Nov 2026
    "8c8d5c482fccffbdf179ebbe4297e317988f8960c1d1f6213408fd30e734a83b",
    // main on 15 Nov 2026, before the opening asked for a moment
    "121edb3eb1498818ef2235e3902179b48f40dab61f1e7a7bee48f25b3d965d73",
    // live from 15 Nov 2026, about 15:00 UTC, before one quick try when they have no time
    "b37f996b3ee61a2defb041d11a5478c527a1480fd2ea6f207c1bba642cbeabdf",
  ],
  // task-call-book: the same two
  [TASK_BOOK_AGENT_SPEC.promptSha256]: [
    "422476155c457b8d0d59a5706cbecfcd99c74386f8a65ef300a0d76b97ec2fa4",
    "e8ee34fef4e6ef97eb75bcf7c3ddf054f9fd0919f7b34abe4bf7e563cd01d03c",
    // main from 13 to 15 Nov 2026
    "9a9eb76821299973cde1b70087342982a1d0e2127305c3f8eb7e5eb1670de42c",
    // main on 15 Nov 2026, before the opening asked for a moment
    "6c47339ee6c7c83cebc111d3f88fd036f8706a8eb4c6eb025bdcede6a2fc88b3",
    // live from 15 Nov 2026, about 15:00 UTC, before one quick try when they have no time
    "962bcea75c8910df201ef71e7d5bb16af9a2dea3ea566411f79b74a36a41c641",
  ],
  // task-call-order: its first prompt (13 to 14 Nov 2026, before the assistant's natural voice)
  [TASK_ORDER_AGENT_SPEC.promptSha256]: [
    "ba6d0ba8035457bea8d80ba1671c2ca9c949302e32b6f8b37b69cc1747db6210",
    // main from 14 to 15 Nov 2026
    "4d88bace9339e7d993abbdc73797699053839c06b20375132517a7e1389482f7",
    // main on 15 Nov 2026, before the opening asked for a moment
    "3b7779ed874e549feca215399c316b8d2d3b3342ced61243237ae6716726bb05",
    // live from 15 Nov 2026, about 15:00 UTC, before one quick try when they have no time
    "66090aa0353a8f61da83e3e21859bed04f071e900d80ef68d5ea815ba5bcd8d2",
  ],
};

export type TaskAgentSpec = { readonly promptSha256: string } & Omit<typeof TASK_AGENT_SPEC, "promptSha256">;
