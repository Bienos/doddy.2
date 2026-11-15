import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import { ProviderError } from "../src/errors.js";
import { AnthropicClaudeProvider, ASK_MAX_TOKENS, ClaudeNoText, ClaudeRefusal, MockClaudeProvider } from "../src/tools/claude.js";
import { type Rig, run, start } from "./toolsRig.js";

/**
 * ask_claude's answer can't be eaten by thinking (Render log, 14 Nov 2026, `doddy`: `ask_claude_failed` with
 * `malformed_provider_result` after 8.9 s). On Claude Sonnet 5.5 a request without `thinking` runs adaptive thinking
 * at the default effort, with empty thinking blocks; 900 tokens could all go on thinking, leaving no text. Now: low
 * effort, 4,000 tokens, and every stop reason handled.
 */

let rig: Rig | undefined;
afterEach(async () => {
  await rig?.close();
  rig = undefined;
});

const KEY = { apiKey: "sk-ant-test-key-1234", model: "claude-sonnet-5-5" };
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });

function fake(replies: (() => Response)[]) {
  const bodies: any[] = [];
  const impl = (async (_url: unknown, init: RequestInit) => {
    bodies.push(JSON.parse(String(init.body)));
    return (replies.shift() ?? (() => json({}, 500)))();
  }) as typeof fetch;
  return { provider: new AnthropicClaudeProvider(KEY, impl, "https://anthropic.test"), bodies };
}
const ARGS = { task: "explain" as const, request: "Explain why the sky is blue, carefully" };

test("the request leaves room for thinking and the answer: low effort, 4,000 tokens, no thinking field", async () => {
  const f = fake([() => json({ content: [{ type: "text", text: "Rayleigh scattering." }], stop_reason: "end_turn" })]);
  assert.deepEqual(await f.provider.ask(ARGS, AbortSignal.timeout(1_000)), { text: "Rayleigh scattering." });
  const [body] = f.bodies;
  assert.equal(body.max_tokens, ASK_MAX_TOKENS);
  assert.equal(ASK_MAX_TOKENS, 4_000);
  assert.deepEqual(body.output_config, { effort: "low" });
  assert.equal(body.thinking, undefined, "{type: \"disabled\"} is a 400 on Sonnet 5.5, so nothing is sent");
});

test("thinking that used up every token, with no text: a failure that names the stop reason, never an empty answer", async () => {
  const f = fake([() => json({ content: [{ type: "thinking", thinking: "", signature: "s" }], stop_reason: "max_tokens", usage: { input_tokens: 50, output_tokens: 4_000 } })]);
  await assert.rejects(f.provider.ask(ARGS, AbortSignal.timeout(1_000)), (e: ClaudeNoText) => {
    assert.ok(e instanceof ClaudeNoText);
    assert.ok(e instanceof ProviderError);
    assert.equal(e.code, "malformed_provider_result");
    assert.equal(e.stopReason, "max_tokens");
    return true;
  });
});

test("cut off at max_tokens with some text: that text is the answer", async () => {
  const f = fake([() => json({ content: [{ type: "thinking", thinking: "", signature: "s" }, { type: "text", text: "The sky is blue because" }], stop_reason: "max_tokens" })]);
  assert.deepEqual(await f.provider.ask(ARGS, AbortSignal.timeout(1_000)), { text: "The sky is blue because" });
});

test("a refusal is a refusal, not an unreadable answer", async () => {
  const f = fake([() => json({ content: [], stop_reason: "refusal" })]);
  await assert.rejects(f.provider.ask(ARGS, AbortSignal.timeout(1_000)), ClaudeRefusal);
});

test("through the server: no text is logged with its stop reason, a refusal answers `refused`", async () => {
  const empty = new MockClaudeProvider();
  empty.ask = async () => {
    throw new ClaudeNoText("max_tokens");
  };
  rig = await start({}, { claude: empty });
  const res = await run(rig, "ask_claude", ARGS);
  assert.equal(res.status, 502, res.text);
  assert.equal(res.body.error.code, "malformed_provider_result");
  assert.equal(res.body.error.message, "Claude sent no answer Doddy could use, so nothing is shown.");
  const line = rig.logs.find((l) => l.includes("ask_claude_failed"));
  assert.ok(line?.includes('"stopReason":"max_tokens"'), line);
  assert.ok(!line?.includes("sky"), "the request never reaches the log");
  await rig.close();

  const declining = new MockClaudeProvider();
  declining.ask = async () => {
    throw new ClaudeRefusal();
  };
  rig = await start({}, { claude: declining });
  const refused = await run(rig, "ask_claude", ARGS);
  assert.equal(refused.status, 422, refused.text);
  assert.equal(refused.body.error.code, "refused");
  assert.equal(refused.body.error.message, "Claude declined to answer that.");
  assert.equal(refused.body.error.receipt.status, "failed");
});
