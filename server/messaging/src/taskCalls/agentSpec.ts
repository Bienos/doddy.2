// What the live task-call agent must look like (ADR-503). Generated from voice-agent/task-call/ by
// hand and kept in step by `python3 -I scripts/voice_agent_spec.py check --agent task-call`, which
// fails CI when the prompt's hash or any value below differs from that folder. Render deploys only
// server/messaging, so the expected values live here.
export const TASK_AGENT_SPEC = {
  /** sha256 of voice-agent/task-call/instructions.md, trimmed, as the setup script sends it. */
  promptSha256: "6985e55ea98fdacf20c6977be047bfadc859c444d583eb3fa4577a0ea40feef8",
  firstMessage: "{{doddy_opening_line}}",
  language: "pl",
  systemTools: ["end_call", "voicemail_detection"] as readonly string[],
  audioFormat: "ulaw_8000",
  /** The agent's own limit must be above ours, so our server decides when the call ends. */
  minAgentMaxDurationSecs: 320,
} as const;
