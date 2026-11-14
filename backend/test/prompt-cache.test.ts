import assert from "node:assert/strict";
import { test } from "node:test";
import { ASSIST_SYSTEM } from "../src/assist.js";
import { CHAT_SYSTEM } from "../src/memory/chat.js";
import { AnthropicClaudeProvider, cachedSystem, estimatedTokens, minCacheableTokens, withoutCacheControl } from "../src/tools/claude.js";

/**
 * Prompt caching: only a long, fixed prefix is marked; the user's material is never in it; a prefix that
 * can't reach the model's minimum is left alone; and a provider that refuses the mark still answers.
 */

const PRIVATE_A = "PRIVATE-MATERIAL-OF-ACCOUNT-A";
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
const answer = (usage: Record<string, unknown>) => json({ content: [{ type: "text", text: JSON.stringify({ answer: "ok" }) }], stop_reason: "end_turn", usage });
const LONG = `Fixed instructions. ${"Stay accurate and brief. ".repeat(120)}`; // about 780 tokens

function rig(model: string, replies: (() => Response)[]) {
  const calls: { body: any }[] = [];
  const impl = (async (_url: unknown, init: RequestInit) => {
    calls.push({ body: JSON.parse(String(init.body)) });
    return (replies.shift() ?? (() => json({}, 500)))();
  }) as typeof fetch;
  const provider = new AnthropicClaudeProvider({ apiKey: "sk-ant-test-key-1234", model }, impl, "https://anthropic.test");
  return { provider, calls };
}
const input = (system: string, user: string) => ({ system, user, schema: { type: "object" }, maxTokens: 100 });

test("minimums come from the docs per model: 512 for Sonnet 5.5 and Haiku 5.5, 4,096 for Haiku 4.5, none for a model not listed", () => {
  assert.equal(minCacheableTokens("claude-opus-5-5"), 512);
  assert.equal(minCacheableTokens("claude-sonnet-5-5"), 512);
  assert.equal(minCacheableTokens("claude-haiku-5-5"), 512);
  assert.equal(minCacheableTokens("claude-sonnet-5"), 1024);
  assert.equal(minCacheableTokens("claude-sonnet-5-5-20261001"), 512);
  assert.equal(minCacheableTokens("claude-haiku-4-5"), 4096);
  assert.equal(minCacheableTokens("claude-unknown-1"), null);
  assert.equal(minCacheableTokens("m"), null);
});

test("a long fixed system prompt is one marked text block; a short one, or a model with no known minimum, stays plain text", () => {
  assert.deepEqual(cachedSystem("claude-sonnet-5-5", LONG), [{ type: "text", text: LONG, cache_control: { type: "ephemeral" } }]);
  assert.equal(cachedSystem("claude-sonnet-5-5", "You are brief."), "You are brief.");
  assert.equal(cachedSystem("claude-haiku-4-5", LONG), LONG, "780 tokens is under Haiku 4.5's 4,096");
  assert.equal(cachedSystem("claude-unknown-1", LONG), LONG);
  assert.ok(estimatedTokens(LONG.length) >= 512 && estimatedTokens(LONG.length) < 1024);
});

test("Doddy's real prompts: the chat's is long enough to be marked on the 512-token models, Ask Doddy's is not, and neither holds a request's text", () => {
  assert.equal(typeof cachedSystem("claude-haiku-5-5", CHAT_SYSTEM), "object", "chat instructions are marked");
  assert.equal(typeof cachedSystem("claude-sonnet-5-5", ASSIST_SYSTEM), "string", "Ask Doddy's instructions are under 512 tokens: left uncached, honestly");
  for (const marked of [cachedSystem("claude-haiku-5-5", CHAT_SYSTEM)]) assert.ok(!JSON.stringify(marked).includes("USER MESSAGE:\n\""));
});

test("structured: the mark is on the fixed system block only; the account's material is in messages after it", async () => {
  const r = rig("claude-sonnet-5-5", [() => answer({ input_tokens: 30, output_tokens: 5, cache_creation_input_tokens: 800, cache_read_input_tokens: 0 })]);
  await r.provider.structured(input(LONG, `NOTES: ${PRIVATE_A}`), AbortSignal.timeout(1_000));
  const body = r.calls[0]!.body;
  assert.deepEqual(body.system, [{ type: "text", text: LONG, cache_control: { type: "ephemeral" } }]);
  assert.equal(body.cache_control, undefined, "no top-level mark on a one-shot question");
  assert.deepEqual(body.messages, [{ role: "user", content: `NOTES: ${PRIVATE_A}` }]);
  assert.ok(!JSON.stringify(body.system).includes(PRIVATE_A), "nothing of the account is in the shared, cached part");
  assert.ok(!JSON.stringify(body.messages).includes("cache_control"));
});

test("two accounts' requests carry the identical marked prefix and differ only after it", async () => {
  const r = rig("claude-sonnet-5-5", [() => answer({ input_tokens: 1, output_tokens: 1 }), () => answer({ input_tokens: 1, output_tokens: 1 })]);
  await r.provider.structured(input(LONG, `A: ${PRIVATE_A}`), AbortSignal.timeout(1_000));
  await r.provider.structured(input(LONG, "B: something else"), AbortSignal.timeout(1_000));
  assert.deepEqual(r.calls[0]!.body.system, r.calls[1]!.body.system);
  assert.notDeepEqual(r.calls[0]!.body.messages, r.calls[1]!.body.messages);
});

test("a schema Anthropic refuses is not mistaken for a refused mark: one marked request, then the schema as words, itself marked", async () => {
  const refusal = () => json({ error: { type: "invalid_request_error", message: "Schema is too complex" } }, 400);
  const r = rig("claude-sonnet-5-5", [refusal, () => answer({ input_tokens: 1, output_tokens: 1 })]);
  const result = await r.provider.structured({ ...input(LONG, "u"), promptFallback: true }, AbortSignal.timeout(1_000));
  assert.deepEqual(result.value, { answer: "ok" });
  assert.equal(r.calls.length, 2, "no extra request without the mark in between");
  assert.equal(r.calls[0]!.body.output_config.format.type, "json_schema");
  const last = r.calls[1]!.body;
  assert.equal(last.output_config.format, undefined, "the second request carries the schema as words, not as a format");
  assert.ok(Array.isArray(last.system) && last.system[0].text.startsWith(LONG) && last.system[0].cache_control !== undefined, "the longer prompt is still one marked block");
});

test("a short one-off prompt is sent exactly as before: no mark anywhere", async () => {
  const r = rig("claude-sonnet-5-5", [() => answer({ input_tokens: 5, output_tokens: 5 })]);
  await r.provider.structured(input("S", "U"), AbortSignal.timeout(1_000));
  assert.equal(r.calls[0]!.body.system, "S");
  assert.ok(!JSON.stringify(r.calls[0]!.body).includes("cache_control"));
  const ask = rig("claude-sonnet-5-5", [() => json({ content: [{ type: "text", text: "a" }], stop_reason: "end_turn" })]);
  await ask.provider.ask({ task: "answer", request: "x" }, AbortSignal.timeout(1_000));
  assert.ok(!JSON.stringify(ask.calls[0]!.body).includes("cache_control"));
});

test("a document's continuation call is marked once the conversation is long enough; its first call and short conversations are not", async () => {
  const big = "x".repeat(3_000);
  const paused = (text: string) => json({ content: [{ type: "text", text }], stop_reason: "pause_turn", container: { id: "cntr_1" }, usage: { input_tokens: 1, output_tokens: 1 } });
  const r = rig("claude-sonnet-5-5", [() => paused(big), () => paused("short"), () => json({ content: [{ type: "text", text: "done" }], stop_reason: "end_turn", usage: { input_tokens: 1, output_tokens: 1 } })]);
  // No file ids come back, so the document itself fails; only the requests matter here.
  await assert.rejects(r.provider.makeDocument({ kind: "deck", title: "T", request: PRIVATE_A }, AbortSignal.timeout(1_000)));
  const [first, second, third] = r.calls.map((c) => c.body);
  assert.equal(first.cache_control, undefined, "the first call may never continue, so it isn't marked");
  assert.deepEqual(second.cache_control, { type: "ephemeral" }, "3,000+ characters re-sent: marked");
  assert.deepEqual(third.cache_control, { type: "ephemeral" });
  const small = rig("claude-sonnet-5-5", [() => paused("a"), () => json({ content: [{ type: "text", text: "done" }], stop_reason: "end_turn" })]);
  await assert.rejects(small.provider.makeDocument({ kind: "deck", title: "T", request: "R" }, AbortSignal.timeout(1_000)));
  assert.equal(small.calls[1]!.body.cache_control, undefined, "a short conversation is under the minimum");
});

test("if the provider refuses a request because of the mark (a 400 that names cache_control), it is sent once more without it", async () => {
  const r = rig("claude-sonnet-5-5", [() => json({ error: { type: "invalid_request_error", message: "cache_control not supported" } }, 400), () => answer({ input_tokens: 9, output_tokens: 2 })]);
  const result = await r.provider.structured(input(LONG, "u"), AbortSignal.timeout(1_000));
  assert.deepEqual(result.value, { answer: "ok" });
  assert.equal(r.calls.length, 2);
  assert.ok(JSON.stringify(r.calls[0]!.body).includes("cache_control"));
  assert.ok(!JSON.stringify(r.calls[1]!.body).includes("cache_control"));
  assert.equal(r.calls[1]!.body.system, LONG);
});

test("a 400 on a request with no cache mark is not retried, even one that names cache_control", async () => {
  const r = rig("claude-sonnet-5-5", [() => json({ error: { type: "invalid_request_error", message: "cache_control: not allowed here" } }, 400), () => answer({ input_tokens: 1, output_tokens: 1 })]);
  await assert.rejects(r.provider.structured(input("short", "u"), AbortSignal.timeout(1_000)));
  assert.equal(r.calls.length, 1);
});

test("a 400 on a marked request that isn't about the mark (the key, the balance, a schema) is not retried without it", async () => {
  for (const message of ["invalid x-api-key", "Your credit balance is too low", "model: claude-nope", "Schema is too complex"]) {
    const r = rig("claude-sonnet-5-5", [() => json({ error: { type: "invalid_request_error", message } }, 400), () => answer({ input_tokens: 1, output_tokens: 1 })]);
    await assert.rejects(r.provider.structured(input(LONG, "u"), AbortSignal.timeout(1_000)), message);
    assert.equal(r.calls.length, 1, message);
  }
});

test("a mark refused with a message that also names the model is still recognised as the mark", async () => {
  const r = rig("claude-sonnet-5-5", [() => json({ error: { type: "invalid_request_error", message: "system.0.cache_control: not supported for this model" } }, 400), () => answer({ input_tokens: 1, output_tokens: 1 })]);
  const result = await r.provider.structured(input(LONG, "u"), AbortSignal.timeout(1_000));
  assert.deepEqual(result.value, { answer: "ok" });
  assert.equal(r.calls.length, 2);
});

test("a 400 that persists without the mark is reported once, not retried again", async () => {
  const refuse = () => json({ error: { type: "invalid_request_error", message: "cache_control: nope" } }, 400);
  const r = rig("claude-sonnet-5-5", [refuse, refuse, () => answer({ input_tokens: 1, output_tokens: 1 })]);
  await assert.rejects(r.provider.structured(input(LONG, "u"), AbortSignal.timeout(1_000)));
  assert.equal(r.calls.length, 2, "one marked request and one unmarked retry, then the error");
});

test("withoutCacheControl strips the top-level mark and flattens a marked system block", () => {
  const body = { model: "m", cache_control: { type: "ephemeral" }, system: [{ type: "text", text: "S", cache_control: { type: "ephemeral" } }], messages: [] };
  assert.deepEqual(withoutCacheControl(body), { model: "m", system: "S", messages: [] });
});
