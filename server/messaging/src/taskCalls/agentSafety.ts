// The task-call agent must stay as harmless as its spec (voice-agent/task-call/): no tools that act,
// no per-call overrides, its first message is our variable, Polish, phone audio, no recording.
// Someone with dashboard access could change any of that, and no payload check would notice, so the
// server reads the live agent and refuses to call while it differs (ADR-503). Only setting names
// are reported, never values.
import { createHash } from "node:crypto";
import { TASK_AGENT_SPEC } from "./agentSpec.js";

export type AgentProblem =
  | "unreadable" | "prompt_changed" | "first_message_changed" | "language_changed"
  | "tool_ids_present" | "tools_present" | "built_in_tool_not_allowed" | "knowledge_base_present" | "mcp_present"
  | "audio_format_changed" | "records_voice" | "overrides_enabled" | "initiation_webhook_enabled" | "max_duration_too_short"
  | "first_message_interruptible" | "auth_off";

const at = (o: unknown, ...path: string[]): unknown =>
  path.reduce<unknown>((v, k) => (v && typeof v === "object" ? (v as Record<string, unknown>)[k] : undefined), o);
const nonEmpty = (v: unknown) => (Array.isArray(v) ? v.length > 0 : v != null && typeof v === "object" ? Object.keys(v).length > 0 : !!v);

/** Any `true` anywhere inside (an override switch that is on). */
function anyTrue(v: unknown): boolean {
  if (v === true) return true;
  if (v && typeof v === "object") return Object.values(v as Record<string, unknown>).some(anyTrue);
  return false;
}

export const sha256Hex = (s: string) => createHash("sha256").update(s, "utf8").digest("hex");

export function checkAgentSafety(agent: unknown): AgentProblem[] {
  if (!agent || typeof agent !== "object") return ["unreadable"];
  const problems: AgentProblem[] = [];
  const cc = at(agent, "conversation_config");
  const a = at(cc, "agent");
  const prompt = at(a, "prompt");
  const text = at(prompt, "prompt");
  if (typeof text !== "string" || sha256Hex(text.trim()) !== TASK_AGENT_SPEC.promptSha256) problems.push("prompt_changed");
  if (at(a, "first_message") !== TASK_AGENT_SPEC.firstMessage) problems.push("first_message_changed");
  if (at(a, "language") !== TASK_AGENT_SPEC.language) problems.push("language_changed");
  if (nonEmpty(at(prompt, "tool_ids"))) problems.push("tool_ids_present");
  const tools = at(prompt, "tools");
  if (Array.isArray(tools) && tools.some((t) => at(t, "type") !== "system" || !TASK_AGENT_SPEC.systemTools.includes(String(at(t, "name"))))) {
    problems.push("tools_present");
  }
  const builtIn = at(prompt, "built_in_tools");
  if (builtIn && typeof builtIn === "object" &&
    Object.entries(builtIn as Record<string, unknown>).some(([k, v]) => v != null && !TASK_AGENT_SPEC.systemTools.includes(k))) {
    problems.push("built_in_tool_not_allowed");
  }
  if (nonEmpty(at(prompt, "knowledge_base"))) problems.push("knowledge_base_present");
  if (nonEmpty(at(prompt, "mcp_server_ids")) || nonEmpty(at(prompt, "native_mcp_server_ids"))) problems.push("mcp_present");
  if (at(cc, "tts", "agent_output_audio_format") !== TASK_AGENT_SPEC.audioFormat ||
    at(cc, "asr", "user_input_audio_format") !== TASK_AGENT_SPEC.audioFormat) problems.push("audio_format_changed");
  if (at(agent, "platform_settings", "privacy", "record_voice") !== false) problems.push("records_voice");
  // Every override switch must be off: per-call prompt, first message, voice, tools, extra LLM body...
  const overrides = at(agent, "platform_settings", "overrides");
  const { enable_conversation_initiation_client_data_from_webhook: initiation, ...rest } =
    (overrides && typeof overrides === "object" ? overrides : {}) as Record<string, unknown>;
  if (anyTrue(rest)) problems.push("overrides_enabled");
  // The workspace-wide call-start webhook (S2) must never inject its variables into these calls.
  if (initiation === true) problems.push("initiation_webhook_enabled");
  // Nobody may start a session with the bare agent id.
  if (at(agent, "platform_settings", "auth", "enable_auth") !== true) problems.push("auth_off");
  // The AI disclosure in the first message is spoken to the end, even if the callee talks over it.
  if (at(a, "disable_first_message_interruptions") !== true) problems.push("first_message_interruptible");
  const maxDuration = at(cc, "conversation", "max_duration_seconds");
  if (typeof maxDuration === "number" && maxDuration < TASK_AGENT_SPEC.minAgentMaxDurationSecs) problems.push("max_duration_too_short");
  return problems;
}
