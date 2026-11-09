import assert from "node:assert/strict";
import { test } from "node:test";
import { ASSIST_SYSTEM } from "../src/assist.js";
import { CHAT_SYSTEM } from "../src/memory/chat.js";
import { Store } from "../src/store.js";
import { AnthropicClaudeProvider, cachedSystem, estimatedTokens, minCacheableTokens, withoutCacheControl } from "../src/tools/claude.js";
import { costNanoUsd, type LedgerEvent, UsageScope } from "../src/usageLedger.js";

/**
 * Prompt caching (research item 5): only a long, fixed prefix is marked; the user's material is never in
 * it; a prefix that can't reach the model's minimum is left alone; the cache counters reach the ledger
 * and the cost; and a provider that refuses the mark still answers.
 */

const ACCOUNT_A = "00000000-0000-4000-8000-0000000000a1";
const ACCOUNT_B = "00000000-0000-4000-8000-0000000000b2";
const PRIVATE_A = "PRIVATE-MATERIAL-OF-ACCOUNT-A";
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
const answer = (usage: Record<string, unknown>) => json({ content: [{ type: "text", text: JSON.stringify({ answer: "ok" }) }], stop_reason: "end_turn", usage });
const LONG = `Fixed instructions. ${"Stay accurate and brief. ".repeat(120)}`; // about 780 tokens

function rig(model: string, replies: (() => Response)[]) {
  const calls: { body: any }[] = [];
  const events: LedgerEvent[] = [];
  const impl = (async (_url: unknown, init: RequestInit) => {
    calls.push({ body: JSON.parse(String(init.body)) });
    return (replies.shift() ?? (() => json({}, 500)))();
  }) as typeof fetch;
  const provider = new AnthropicClaudeProvider({ apiKey: "sk-ant-test-key-1234", model }, impl, "https://anthropic.test", { recorder: { record: async (e) => void events.push(e) } });
  return { provider, calls, events };
}
const input = (system: string, user: string) => ({ system, user, schema: { type: "object" }, maxTokens: 100 });

test("minimums come from the docs per model: 512 for Sonnet 5.5 and Haiku 5.5, 4,096 for Haiku 4.5, none for a model not listed", () => {
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
  await r.provider.structured(input(LONG, `NOTES: ${PRIVATE_A}`), AbortSignal.timeout(1_000), new UsageScope(ACCOUNT_A, "ask_doddy"));
  const body = r.calls[0]!.body;
  assert.deepEqual(body.system, [{ type: "text", text: LONG, cache_control: { type: "ephemeral" } }]);
  assert.equal(body.cache_control, undefined, "no top-level mark on a one-shot question");
  assert.deepEqual(body.messages, [{ role: "user", content: `NOTES: ${PRIVATE_A}` }]);
  assert.ok(!JSON.stringify(body.system).includes(PRIVATE_A), "nothing of the account is in the shared, cached part");
  assert.ok(!JSON.stringify(body.messages).includes("cache_control"));
});

test("two accounts' requests carry the identical marked prefix and differ only after it", async () => {
  const r = rig("claude-sonnet-5-5", [() => answer({ input_tokens: 1, output_tokens: 1 }), () => answer({ input_tokens: 1, output_tokens: 1 })]);
  await r.provider.structured(input(LONG, `A: ${PRIVATE_A}`), AbortSignal.timeout(1_000), new UsageScope(ACCOUNT_A, "ask_doddy"));
  await r.provider.structured(input(LONG, "B: something else"), AbortSignal.timeout(1_000), new UsageScope(ACCOUNT_B, "ask_doddy"));
  assert.deepEqual(r.calls[0]!.body.system, r.calls[1]!.body.system);
  assert.notDeepEqual(r.calls[0]!.body.messages, r.calls[1]!.body.messages);
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

test("cache write and read counters reach the ledger event and the cost; the reply's own usage keeps them too", async () => {
  const r = rig("claude-sonnet-5-5", [
    () => answer({ input_tokens: 30, output_tokens: 5, cache_creation_input_tokens: 800, cache_read_input_tokens: 0 }),
    () => answer({ input_tokens: 30, output_tokens: 5, cache_creation_input_tokens: 0, cache_read_input_tokens: 800 }),
  ]);
  const first = await r.provider.structured(input(LONG, "u"), AbortSignal.timeout(1_000), new UsageScope(ACCOUNT_A, "ask_doddy"));
  const second = await r.provider.structured(input(LONG, "u"), AbortSignal.timeout(1_000), new UsageScope(ACCOUNT_A, "ask_doddy"));
  assert.deepEqual(first.usage, { inputTokens: 30, outputTokens: 5, cacheCreationInputTokens: 800, cacheReadInputTokens: 0 });
  assert.deepEqual(second.usage, { inputTokens: 30, outputTokens: 5, cacheCreationInputTokens: 0, cacheReadInputTokens: 800 });
  const [w, h] = r.events;
  assert.equal(w!.usage!.cacheCreationTokens, 800);
  assert.equal(h!.usage!.cacheReadTokens, 800);
  // Sonnet 5.5: a write is 1.25x the $2 input price, a read 0.05x.
  assert.equal(w!.costNanoUsd, Math.round((30 * 2 + 5 * 10 + 800 * 2.5) * 1000));
  assert.equal(h!.costNanoUsd, Math.round((30 * 2 + 5 * 10 + 800 * 0.1) * 1000));
  assert.ok(h!.costNanoUsd! < w!.costNanoUsd!, "the hit is cheaper than the write");
  assert.equal(costNanoUsd("claude-haiku-5-5", { inputTokens: 0, outputTokens: 0, cacheCreationTokens: 0, cacheCreation1hTokens: 0, cacheReadTokens: 100_000 }), 1_000_000, "Haiku 5.5 reads at $0.01 per MTok (100,000 tokens is the edge of the cheaper tier)");
});

test("a document's continuation call is marked once the conversation is long enough; its first call and short conversations are not", async () => {
  const big = "x".repeat(3_000);
  const paused = (text: string) => json({ content: [{ type: "text", text }], stop_reason: "pause_turn", container: { id: "cntr_1" }, usage: { input_tokens: 1, output_tokens: 1 } });
  const r = rig("claude-sonnet-5-5", [() => paused(big), () => paused("short"), () => json({ content: [{ type: "text", text: "done" }], stop_reason: "end_turn", usage: { input_tokens: 1, output_tokens: 1 } })]);
  // No file ids come back, so the document itself fails; only the requests matter here.
  await assert.rejects(r.provider.makeDocument({ kind: "deck", title: "T", request: PRIVATE_A }, AbortSignal.timeout(1_000), new UsageScope(ACCOUNT_A, "make_document")));
  const [first, second, third] = r.calls.map((c) => c.body);
  assert.equal(first.cache_control, undefined, "the first call may never continue, so it isn't marked");
  assert.deepEqual(second.cache_control, { type: "ephemeral" }, "3,000+ characters re-sent: marked");
  assert.deepEqual(third.cache_control, { type: "ephemeral" });
  const small = rig("claude-sonnet-5-5", [() => paused("a"), () => json({ content: [{ type: "text", text: "done" }], stop_reason: "end_turn" })]);
  await assert.rejects(small.provider.makeDocument({ kind: "deck", title: "T", request: "R" }, AbortSignal.timeout(1_000)));
  assert.equal(small.calls[1]!.body.cache_control, undefined, "a short conversation is under the minimum");
});

test("if the provider refuses a request because of the mark, it is sent once more without it, and both calls are in the ledger", async () => {
  const r = rig("claude-sonnet-5-5", [() => json({ error: { type: "invalid_request_error", message: "cache_control not supported" } }, 400), () => answer({ input_tokens: 9, output_tokens: 2 })]);
  const scope = new UsageScope(ACCOUNT_A, "ask_doddy", "req-x");
  const result = await r.provider.structured(input(LONG, "u"), AbortSignal.timeout(1_000), scope);
  assert.deepEqual(result.value, { answer: "ok" });
  assert.equal(r.calls.length, 2);
  assert.ok(JSON.stringify(r.calls[0]!.body).includes("cache_control"));
  assert.ok(!JSON.stringify(r.calls[1]!.body).includes("cache_control"));
  assert.equal(r.calls[1]!.body.system, LONG);
  assert.deepEqual(r.events.map((e) => [e.seq, e.kind, e.outcome, e.usage === null]), [[0, "initial", "failed", true], [1, "retry", "succeeded", false]]);
});

test("a 400 on a request with no cache mark is not retried", async () => {
  const r = rig("claude-sonnet-5-5", [() => json({ error: { type: "invalid_request_error", message: "bad" } }, 400), () => answer({ input_tokens: 1, output_tokens: 1 })]);
  await assert.rejects(r.provider.structured(input("short", "u"), AbortSignal.timeout(1_000)));
  assert.equal(r.calls.length, 1);
});

test("withoutCacheControl strips the top-level mark and flattens a marked system block", () => {
  const body = { model: "m", cache_control: { type: "ephemeral" }, system: [{ type: "text", text: "S", cache_control: { type: "ephemeral" } }], messages: [] };
  assert.deepEqual(withoutCacheControl(body), { model: "m", system: "S", messages: [] });
});

test("the ledger keeps cache counters per account in the store's totals", async () => {
  const store = await Store.memory();
  try {
    const p = new AnthropicClaudeProvider(
      { apiKey: "sk-ant-test-key-1234", model: "claude-haiku-5-5" },
      (async () => answer({ input_tokens: 5, output_tokens: 5, cache_read_input_tokens: 700 })) as unknown as typeof fetch,
      "https://anthropic.test",
      { recorder: { record: (e) => store.recordClaudeCall(e) } },
    );
    await p.structured(input(LONG, "u"), AbortSignal.timeout(1_000), new UsageScope(ACCOUNT_A, "memory_chat"));
    const [sum] = await store.claudeUsageByAccount(ACCOUNT_A, 0);
    assert.equal(sum!.cacheReadTokens, 700);
    assert.equal(sum!.cacheCreationTokens, 0);
    assert.deepEqual(await store.claudeUsageByAccount(ACCOUNT_B, 0), []);
  } finally {
    await store.close();
  }
});
