// What the live task-call agent must look like (ADR-503). Generated from voice-agent/task-call/ by
// hand and kept in step by `python3 -I scripts/voice_agent_spec.py check --agent task-call`, which
// fails CI when the prompt's hash or any value below differs from that folder. Render deploys only
// server/messaging, so the expected values live here.
export const TASK_AGENT_SPEC = {
  /** sha256 of voice-agent/task-call/instructions.md, trimmed, as the setup script sends it. */
  promptSha256: "03365dd4c3006a854f639a5bb274b32b3fc5363689e5c647cae60a0f678a68cb",
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
  promptSha256: "9d0a1ebe54e06d1029baa4a3c20a74bc0874deb3de450f6a437914f77a3a6ad1",
} as const;

export type TaskAgentSpec = { readonly promptSha256: string } & Omit<typeof TASK_AGENT_SPEC, "promptSha256">;
