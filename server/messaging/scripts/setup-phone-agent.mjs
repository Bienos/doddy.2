#!/usr/bin/env node
// Creates the Doddy phone agent in ElevenLabs from voice-agent/phone/ (prompt, tools, settings): a
// workspace secret, the webhook tools that call this server, and the agent itself. Run once from a
// checkout of the repo, after the server is deployed.
//
//   ELEVENLABS_API_KEY=… PUBLIC_BASE_URL=https://… ELEVENLABS_TOOL_SECRET=… \
//     node scripts/setup-phone-agent.mjs [--dry-run] [--set-workspace-webhook]
//
// --dry-run prints every request instead of sending it.
// --set-workspace-webhook also points the WORKSPACE-WIDE conversation-initiation webhook at this
//   server. That setting is shared by every agent in the workspace, so it is opt-in.
//
// Afterwards (ElevenLabs dashboard): import the Twilio number, assign it to this agent, then set
// ELEVENLABS_PHONE_AGENT_ID, ELEVENLABS_PHONE_NUMBER_ID and DODDY_PHONE_NUMBER on the server.

import { readFileSync } from "node:fs";

const dryRun = process.argv.includes("--dry-run");
const setWorkspaceWebhook = process.argv.includes("--set-workspace-webhook");
const { ELEVENLABS_API_KEY: apiKey, PUBLIC_BASE_URL: base, ELEVENLABS_TOOL_SECRET: toolSecret } = process.env;
if (!dryRun && (!apiKey || !base || !toolSecret)) {
  console.error("Set ELEVENLABS_API_KEY, PUBLIC_BASE_URL and ELEVENLABS_TOOL_SECRET (or use --dry-run).");
  process.exit(1);
}
const origin = (base ?? "https://doddy-messaging.example").replace(/\/$/, "");

async function api(method, path, body) {
  if (dryRun) {
    console.log(`\n${method} https://api.elevenlabs.io${path}\n${JSON.stringify(body, null, 2)}`);
    return { secret_id: "<secret_id>", id: `<${path.split("/").pop()}_id>`, agent_id: "<agent_id>" };
  }
  const res = await fetch(`https://api.elevenlabs.io${path}`, {
    method, headers: { "xi-api-key": apiKey, "content-type": "application/json" }, body: JSON.stringify(body),
  });
  const json = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(`${method} ${path} → HTTP ${res.status}: ${JSON.stringify(json)}`);
  return json;
}

// The agent is defined in voice-agent/phone/ (prompt, tools, settings), checked by
// scripts/voice_agent_spec.py --agent phone in CI. This script only turns it into API calls.
const specDir = new URL("../../../voice-agent/phone/", import.meta.url);
const read = (name) => readFileSync(new URL(name, specDir), "utf8");
const spec = JSON.parse(read("tools.json"));
const session = JSON.parse(read("session.json"));
const prompt = read("instructions.md").trim();
const el = session.elevenlabs;

const secretIds = {};
for (const name of Object.keys(el.workspace_secrets)) {
  const value = name === "doddy_tool_secret" ? toolSecret : undefined;
  secretIds[name] = (await api("POST", "/v1/convai/secrets", { type: "new", name, value: value ?? "<tool secret>" })).secret_id;
}

// Every tool sends the shared secret and this call's session. `secret__doddy_session` is a
// secret dynamic variable: ElevenLabs only places it in headers and never shows it to the model.
const toolConfig = (t) => {
  const http = t.x_doddy.http;
  const headers = Object.fromEntries(Object.entries(http.headers).map(([name, ref]) =>
    [name, ref.secret ? { secret_id: secretIds[ref.secret] } : { variable_name: ref.variable }]));
  const props = t.parameters.properties;
  return {
    tool_config: {
      type: "webhook", name: t.name, description: t.description, response_timeout_secs: t.x_doddy.timeout_secs,
      pre_tool_speech: t.x_doddy.speak_before, force_pre_tool_speech: t.x_doddy.speak_before === "force",
      api_schema: {
        url: `${origin}${http.path_template}`, method: http.method, request_headers: headers,
        request_body_schema: {
          type: "object",
          properties: Object.fromEntries(http.body.map((k) => [k, { type: props[k].type, description: props[k].description }])),
          required: (t.parameters.required ?? []).filter((k) => http.body.includes(k)),
        },
      },
    },
  };
};
const toolIds = [];
for (const t of spec.tools) toolIds.push((await api("POST", "/v1/convai/tools", toolConfig(t))).id);

const agent = await api("POST", "/v1/convai/agents/create", {
  name: el.agent_name,
  tags: el.tags,
  conversation_config: {
    agent: {
      first_message: session.first_message.en,
      language: session.languages[0],
      // Placeholders for tests in the dashboard; real values come from the call-start webhook.
      dynamic_variables: { dynamic_variable_placeholders: el.placeholders },
      prompt: { prompt, llm: el.llm, temperature: el.temperature, timezone: el.timezone, tool_ids: toolIds },
    },
  },
  platform_settings: {
    overrides: el.overrides,
    // Calls can contain memories read aloud: no audio recording, transcripts kept 30 days.
    privacy: { record_voice: el.privacy.record_voice, retention_days: el.privacy.retention_days },
  },
});

const webhook = {
  conversation_initiation_client_data_webhook: {
    url: `${origin}${el.call_start_webhook}`,
    request_headers: { "X-Doddy-Tool-Secret": { secret_id: secretIds.doddy_tool_secret } },
  },
};
if (setWorkspaceWebhook) {
  await api("PATCH", "/v1/convai/settings", webhook);
} else {
  console.log("\nNot changed: the workspace-wide call-start webhook. Set it in ElevenLabs → Agents → Settings, or re-run with --set-workspace-webhook:");
  console.log(JSON.stringify(webhook, null, 2));
}

console.log(`\nDone. ELEVENLABS_PHONE_AGENT_ID=${agent.agent_id}`);
console.log("Next: import the Twilio number in ElevenLabs (Phone Numbers), assign it to this agent, and set ELEVENLABS_PHONE_NUMBER_ID and DODDY_PHONE_NUMBER on the server.");
