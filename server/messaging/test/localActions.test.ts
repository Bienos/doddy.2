import assert from "node:assert/strict";
import http from "node:http";
import { test } from "node:test";
import { readLocalAction } from "../src/assistant/localActions.js";
import { AssistRequest } from "../src/assistant/request.js";
import { ClaudeAssistantResponder } from "../src/assistant/responder.js";
import { answerJsonSchema, buildInstructions } from "../src/assistant/prompt.js";

const clock = { version: 1, localNow: "2026-11-09T19:30", timeZone: "Europe/Warsaw" };
const request = (optIn: boolean) => AssistRequest.parse({ schemaVersion: 1, requestId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", sessionId: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb", locale: "pl", userText: "Zapisz notatkę: dokładna treść", turns: [], memories: [], ...(optIn ? { localActions: clock } : {}) });
const action = { name: "save_memory", parametersJSON: JSON.stringify({ text: "dokładna treść" }) };

test("local actions accept only bounded known arguments and a valid phone clock", () => {
  assert.deepEqual(readLocalAction(action), action);
  for (const bad of [undefined, { name: "delete_memory", parametersJSON: "{}" }, { ...action, parametersJSON: "[]" },
    { ...action, parametersJSON: JSON.stringify({ text: "x", send: true }) }, { ...action, parametersJSON: JSON.stringify({ text: ["x"] }) },
    { ...action, parametersJSON: "x".repeat(12001) }, { name: "add_to_list", parametersJSON: JSON.stringify({ list: "Shop", items: Array(201).fill("milk") }) }
  ]) assert.equal(readLocalAction(bad), undefined);
  assert.ok(request(true).localActions);
  assert.ok(!AssistRequest.safeParse({ ...request(true), localActions: { ...clock, timeZone: "bad/zone" } }).success);
  assert.ok(!AssistRequest.safeParse({ ...request(true), localActions: { ...clock, version: 2 } }).success);
  assert.match(buildInstructions("pl", true), /ONLY after the tap/);
  assert.ok(!("local_action" in (answerJsonSchema(false).properties as object)));
  assert.ok("local_action" in (answerJsonSchema(false, true).properties as object));
});

test("real responder returns proposals only to opted-in clients; never executes tools", async () => {
  const seen: any[] = [];
  const server = http.createServer((req, res) => {
    let raw = ""; req.on("data", c => { raw += c; });
    req.on("end", () => {
      seen.push(JSON.parse(raw));
      res.writeHead(200, { "content-type": "application/json" }).end(JSON.stringify({ id: "msg_test", type: "message", role: "assistant", model: "claude-haiku-5-5", stop_reason: "end_turn", stop_sequence: null,
        content: [{ type: "text", text: JSON.stringify({ answer: "Potwierdź na karcie.", local_action: action }) }], usage: { input_tokens: 1, output_tokens: 1 } }));
    });
  });
  await new Promise<void>(resolve => server.listen(0, "127.0.0.1", resolve));
  try {
    const responder = new ClaudeAssistantResponder("local-test-key", { baseURL: `http://127.0.0.1:${(server.address() as { port: number }).port}` });
    const out = await responder.answer(request(true), new AbortController().signal);
    assert.equal(out.kind, "ok");
    if (out.kind === "ok") assert.deepEqual(out.localAction, action);
    const legacy = await responder.answer(request(false), new AbortController().signal);
    if (legacy.kind === "ok") assert.equal(legacy.localAction, undefined);
    assert.ok(seen[0].output_config.format.schema.required.includes("local_action"));
    assert.ok(!seen[1].output_config.format.schema.required.includes("local_action"));
    for (const body of seen) assert.equal(body.tools, undefined);
  } finally { await new Promise<void>(resolve => server.close(() => resolve())); }
});
