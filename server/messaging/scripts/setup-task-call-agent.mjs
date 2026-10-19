#!/usr/bin/env node
// Creates the "Doddy (calls for you)" agent in ElevenLabs from voice-agent/task-call/ (ADR-500,
// docs/decisions/calls.md). This agent only talks: no webhook or client tools, only the end_call and
// voicemail_detection system tools, Polish, phone audio (μ-law 8000 for register-call), no audio
// recording, no per-call overrides. The server refuses to call while the live agent differs from this
// spec (src/taskCalls/agentSafety.ts), so change the agent here, never in the dashboard.
//
//   ELEVENLABS_API_KEY=… TASK_CALL_VOICE_ID=<a Polish voice id> node scripts/setup-task-call-agent.mjs [--dry-run]
//
// --dry-run prints the request instead of sending it.
// Afterwards: set ELEVENLABS_TASK_AGENT_ID on the server, and point the workspace's post-call webhook
// at <PUBLIC_BASE_URL>/webhooks/elevenlabs/post-call (transcripts on, audio off) with its HMAC secret in
// ELEVENLABS_WEBHOOK_SECRET. See server/messaging/README.md, "Calls Doddy makes for you".

import { readFileSync } from "node:fs";

const dryRun = process.argv.includes("--dry-run");
const { ELEVENLABS_API_KEY: apiKey, TASK_CALL_VOICE_ID: voiceId } = process.env;
if (!dryRun && (!apiKey || !voiceId)) {
  console.error("Set ELEVENLABS_API_KEY and TASK_CALL_VOICE_ID (a Polish voice from your ElevenLabs library), or use --dry-run.");
  process.exit(1);
}

const specDir = new URL("../../../voice-agent/task-call/", import.meta.url);
const read = (name) => readFileSync(new URL(name, specDir), "utf8");
const tools = JSON.parse(read("tools.json"));
const session = JSON.parse(read("session.json"));
const prompt = read("instructions.md").trim();
const el = session.elevenlabs;

if (tools.tools.length) throw new Error("voice-agent/task-call/tools.json must have no function tools");

// System tools in the shape the API returns them (read from a live agent on 2026-10-18).
const builtInTools = Object.fromEntries(tools.system_tools.map((t) => [t.name, {
  type: "system",
  name: t.name,
  description: t.description,
  params: t.name === "voicemail_detection"
    ? { system_tool_type: "voicemail_detection", voicemail_message: t.voicemail_message ?? "" }
    : { system_tool_type: t.name },
}]));

const body = {
  name: el.agent_name,
  tags: el.tags,
  conversation_config: {
    asr: { user_input_audio_format: el.audio_format },
    tts: { model_id: el.tts_model, voice_id: voiceId ?? el.tts_voice_id, agent_output_audio_format: el.audio_format },
    turn: { silence_end_call_timeout: el.silence_end_call_timeout },
    conversation: { max_duration_seconds: el.max_duration_seconds },
    agent: {
      first_message: session.first_message.pl,
      language: session.languages[0],
      disable_first_message_interruptions: el.disable_first_message_interruptions,
      // Only for tests in the dashboard; real values come from the approved brief at every call.
      dynamic_variables: { dynamic_variable_placeholders: el.placeholders },
      prompt: {
        prompt, llm: el.llm, temperature: el.temperature, timezone: el.timezone,
        tool_ids: [], built_in_tools: builtInTools, knowledge_base: [],
      },
    },
  },
  platform_settings: {
    // Every override switch stays off: nothing per call can change the prompt, first message or tools.
    overrides: { enable_conversation_initiation_client_data_from_webhook: el.overrides.enable_conversation_initiation_client_data_from_webhook },
    privacy: { record_voice: el.privacy.record_voice, retention_days: el.privacy.retention_days },
    auth: { enable_auth: el.auth.enable_auth },
  },
};

if (dryRun) {
  console.log("POST https://api.elevenlabs.io/v1/convai/agents/create");
  console.log(JSON.stringify(body, null, 2));
  process.exit(0);
}

const res = await fetch("https://api.elevenlabs.io/v1/convai/agents/create", {
  method: "POST", headers: { "xi-api-key": apiKey, "content-type": "application/json" }, body: JSON.stringify(body),
});
const json = await res.json().catch(() => ({}));
if (!res.ok) {
  console.error(`HTTP ${res.status}: ${JSON.stringify(json)}`);
  process.exit(1);
}
console.log(`Done. ELEVENLABS_TASK_AGENT_ID=${json.agent_id}`);
console.log("Next: set ELEVENLABS_TASK_AGENT_ID on the server, then GET /v1/call-cases/availability lists any setting the server still finds unsafe (agentProblems).");
