// What the live task-call agent must look like (ADR-503). Generated from voice-agent/task-call/ by
// hand and kept in step by `python3 -I scripts/voice_agent_spec.py check --agent task-call`, which
// fails CI when the prompt's hash or any value below differs from that folder. Render deploys only
// server/messaging, so the expected values live here.
export const TASK_AGENT_SPEC = {
  /** sha256 of voice-agent/task-call/instructions.md, trimmed, as the setup script sends it. */
  promptSha256: "61390ba26f61f1887ac24b39c4ab8d225ddf09004018e818ee33c6b7350cde0b",
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
  promptSha256: "3db95f6fef49cf8095c7cfd58ae7cf183a774b8ed52ee3f0b5000caa3f0532d8",
} as const;

/**
 * The order agent (decision docs/decisions/2026-11-12-food-by-phone.md), from voice-agent/task-call-order/,
 * kept in step by `python3 -I scripts/voice_agent_spec.py check --agent task-call-order`. Same rules as the
 * ask agent; only its prompt differs, so the same safety check reads it with this hash.
 */
export const TASK_ORDER_AGENT_SPEC = {
  ...TASK_AGENT_SPEC,
  /** sha256 of voice-agent/task-call-order/instructions.md, trimmed, as the setup script sends it. */
  promptSha256: "ba6d0ba8035457bea8d80ba1671c2ca9c949302e32b6f8b37b69cc1747db6210",
} as const;

/**
 * Prompts the drift check still accepts while the owner hasn't synced a live agent: for a spec's prompt hash, the
 * hashes of the instructions.md it replaced. Only the owner changes the live agents (CLAUDE.md), so without this a
 * deploy of a new prompt would stop every call until the sync. Keyed by the new hash, so another agent's spec never
 * inherits an entry. Each entry goes once the live agent has the new prompt.
 *
 * 12 Nov 2026 (OWNER_QUEUE 52): {{doddy_goal}} was taken out of both prompts. The server now sends `doddy_goal` as a
 * fixed sentence (payload.ts), so the old prompts get no goal text either while they are still live.
 * 13 Nov 2026 (decision 2026-11-13-calls-sound-like-your-assistant, OWNER_QUEUE 66): both prompts rewritten to sound like
 * the person's own assistant. Accepted until the sync: the prompts live before 12 Nov and the 12 Nov ones (in case the
 * owner synced those first). Their texts are kept in test/fixtures/task-call-prompts/ so the hashes stay checkable.
 */
export const SYNC_PENDING_PROMPTS: Readonly<Record<string, readonly string[]>> = {
  // task-call: main before 12 Nov 2026, then main on 12 Nov 2026
  [TASK_AGENT_SPEC.promptSha256]: [
    "129f2aecdee4c501b32148112e64efe3f57a126e82e7358cfd2816ff27a26454",
    "0f2c05bcc3090802ae6ad0656c8f69ba6af9c6bdbfa8f63596088b8b1a25099a",
  ],
  // task-call-book: main before 12 Nov 2026, then main on 12 Nov 2026
  [TASK_BOOK_AGENT_SPEC.promptSha256]: [
    "422476155c457b8d0d59a5706cbecfcd99c74386f8a65ef300a0d76b97ec2fa4",
    "e8ee34fef4e6ef97eb75bcf7c3ddf054f9fd0919f7b34abe4bf7e563cd01d03c",
  ],
};

export type TaskAgentSpec = { readonly promptSha256: string } & Omit<typeof TASK_AGENT_SPEC, "promptSha256">;
