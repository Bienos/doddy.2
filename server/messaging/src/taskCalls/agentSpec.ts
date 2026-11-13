// What the live task-call agent must look like (ADR-503). Generated from voice-agent/task-call/ by
// hand and kept in step by `python3 -I scripts/voice_agent_spec.py check --agent task-call`, which
// fails CI when the prompt's hash or any value below differs from that folder. Render deploys only
// server/messaging, so the expected values live here.
export const TASK_AGENT_SPEC = {
  /** sha256 of voice-agent/task-call/instructions.md, trimmed, as the setup script sends it. */
  promptSha256: "8c8d5c482fccffbdf179ebbe4297e317988f8960c1d1f6213408fd30e734a83b",
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
  promptSha256: "9a9eb76821299973cde1b70087342982a1d0e2127305c3f8eb7e5eb1670de42c",
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
 * 13 Nov 2026: both prompts sound like the person's own assistant; the opening line (server-built) says "wirtualny
 * asystent". An older live prompt still answers honestly when asked, so it stays accepted until the owner's sync.
 */
export const SYNC_PENDING_PROMPTS: Readonly<Record<string, readonly string[]>> = {
  // task-call: main before 12 Nov 2026, then main from 12 to 13 Nov 2026 (before the assistant's natural voice,
  // decision docs/decisions/2026-11-13-call-agent-sounds-like-an-assistant.md)
  [TASK_AGENT_SPEC.promptSha256]: [
    "129f2aecdee4c501b32148112e64efe3f57a126e82e7358cfd2816ff27a26454",
    "0f2c05bcc3090802ae6ad0656c8f69ba6af9c6bdbfa8f63596088b8b1a25099a",
  ],
  // task-call-book: the same two
  [TASK_BOOK_AGENT_SPEC.promptSha256]: [
    "422476155c457b8d0d59a5706cbecfcd99c74386f8a65ef300a0d76b97ec2fa4",
    "e8ee34fef4e6ef97eb75bcf7c3ddf054f9fd0919f7b34abe4bf7e563cd01d03c",
  ],
};

export type TaskAgentSpec = { readonly promptSha256: string } & Omit<typeof TASK_AGENT_SPEC, "promptSha256">;
