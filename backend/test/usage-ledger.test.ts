import assert from "node:assert/strict";
import { test } from "node:test";
import { ProviderError } from "../src/errors.js";
import { Store } from "../src/store.js";
import { AnthropicClaudeProvider, type ClaudeProvider, MockClaudeProvider } from "../src/tools/claude.js";
import { ClaudeTravelReader } from "../src/travel/claudeReader.js";
import { costNanoUsd, type LedgerEvent, PRICE_VERSION, priceFor, readUsage, UsageScope } from "../src/usageLedger.js";

/**
 * The account-linked ledger of Anthropic calls (research item 1): one content-free row per call, with
 * the provider's own counters (cache writes and reads included), an honest "unknown" for failures,
 * a cost from the price table, and strict isolation between accounts.
 */

const ACCOUNT_A = "00000000-0000-4000-8000-0000000000a1";
const ACCOUNT_B = "00000000-0000-4000-8000-0000000000b2";
const SECRET = "SECRET-PRIVATE-TEXT-must-never-reach-the-ledger";
const KEY = { apiKey: "sk-ant-test-key-1234", model: "claude-sonnet-5-5" };
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
const text = (t: string, usage?: Record<string, unknown>, stop = "end_turn") => json({ content: [{ type: "text", text: t }], stop_reason: stop, ...(usage ? { usage } : {}) });

function fake(replies: (() => Response | Promise<Response>)[]) {
  const calls: { url: string; body: any }[] = [];
  const impl = (async (url: unknown, init: RequestInit) => {
    calls.push({ url: String(url), body: init?.body ? JSON.parse(String(init.body)) : null });
    const next = replies.shift();
    return next ? next() : json({}, 500);
  }) as typeof fetch;
  return { impl, calls };
}

async function rig(replies: (() => Response | Promise<Response>)[]) {
  const store = await Store.memory();
  const events: LedgerEvent[] = [];
  const f = fake(replies);
  const provider = new AnthropicClaudeProvider(KEY, f.impl, "https://anthropic.test", {
    recorder: { record: async (e) => (events.push(e), store.recordClaudeCall(e)) },
    now: () => 1_000,
  });
  return { store, provider, events, calls: f.calls };
}

const rowsOf = (store: Store) => store.db.query<Record<string, unknown>>("SELECT * FROM claude_usage ORDER BY id", []).then((r) => r.rows);

// ------------------------------------------------------------------ prices

test("prices: cache writes cost 1.25x and reads 0.1x (0.05x on Sonnet 5.5), computed in whole nano-dollars", () => {
  const usage = { inputTokens: 1_000_000, outputTokens: 1_000_000, cacheCreationTokens: 1_000_000, cacheCreation1hTokens: 0, cacheReadTokens: 1_000_000 };
  // Sonnet 5.5 at $2 in / $10 out per MTok: 2 + 10 + 2.5 + 0.1 = $14.60.
  assert.equal(costNanoUsd("claude-sonnet-5-5", usage), 14_600_000_000);
  // Haiku 4.5 at $1 / $5: 1 + 5 + 1.25 + 0.10 = $7.35.
  assert.equal(costNanoUsd("claude-haiku-4-5", usage), 7_350_000_000);
  // A one-hour write is 2x.
  assert.equal(costNanoUsd("claude-sonnet-5-5", { ...usage, inputTokens: 0, outputTokens: 0, cacheReadTokens: 0, cacheCreation1hTokens: 1_000_000 }), 4_000_000_000);
  // A dated snapshot id prices as its family; the longer family wins over the shorter one.
  assert.equal(priceFor("claude-sonnet-5-5-20261001")?.prefix, "claude-sonnet-5-5");
  assert.equal(priceFor("claude-sonnet-5")?.prefix, "claude-sonnet-5");
  assert.equal(priceFor("claude-sonnet-5-5")?.base.input, 2);
});

test("prices: Haiku 5.5 is dearer for prompts over 100,000 tokens; an unknown model has no price rather than a guess", () => {
  const small = { inputTokens: 1_000, outputTokens: 1_000, cacheCreationTokens: 0, cacheCreation1hTokens: 0, cacheReadTokens: 0 };
  assert.equal(costNanoUsd("claude-haiku-5-5", small), 100_000 + 500_000);
  const big = { ...small, inputTokens: 100_001 };
  assert.equal(costNanoUsd("claude-haiku-5-5", big), Math.round((100_001 * 0.5 + 1_000 * 2.5) * 1000));
  assert.equal(costNanoUsd("claude-future-9", small), null);
  assert.equal(costNanoUsd("m", small), null);
});

test("readUsage: absent usage is unknown (null), a missing counter inside a usage object is 0", () => {
  assert.equal(readUsage(undefined), null);
  assert.equal(readUsage({}), null);
  assert.deepEqual(readUsage({ input_tokens: 5 }), { inputTokens: 5, outputTokens: 0, cacheCreationTokens: 0, cacheCreation1hTokens: 0, cacheReadTokens: 0 });
  assert.deepEqual(
    readUsage({ input_tokens: 1, output_tokens: 2, cache_creation_input_tokens: 30, cache_read_input_tokens: 4, cache_creation: { ephemeral_5m_input_tokens: 10, ephemeral_1h_input_tokens: 20 } }),
    { inputTokens: 1, outputTokens: 2, cacheCreationTokens: 30, cacheCreation1hTokens: 20, cacheReadTokens: 4 },
  );
  assert.equal(readUsage({ input_tokens: -3, output_tokens: 1.5 })?.inputTokens, 0, "a negative or fractional counter isn't trusted");
});

// ------------------------------------------------------------------ the provider writes events

test("a successful call writes one row with the provider's counters, the cache counters and the cost, and no text", async () => {
  const r = await rig([() => text("The answer", { input_tokens: 100, output_tokens: 40, cache_creation_input_tokens: 2_000, cache_read_input_tokens: 500 })]);
  try {
    const scope = new UsageScope(ACCOUNT_A, "ask_claude", "req-1");
    const answer = await r.provider.ask({ task: "answer", request: SECRET, material: SECRET }, AbortSignal.timeout(1_000), scope);
    assert.equal(answer.text, "The answer");
    const [row] = await rowsOf(r.store);
    assert.equal(row!.user_id, ACCOUNT_A);
    assert.equal(row!.provider, "anthropic");
    assert.equal(row!.model, "claude-sonnet-5-5");
    assert.equal(row!.feature, "ask_claude");
    assert.equal(row!.request_id, "req-1");
    assert.equal(row!.seq, 0);
    assert.equal(row!.kind, "initial");
    assert.equal(row!.outcome, "succeeded");
    assert.equal(row!.stop_reason, "end_turn");
    assert.equal(row!.usage_known, true);
    assert.deepEqual([row!.input_tokens, row!.output_tokens, row!.cache_creation_tokens, row!.cache_read_tokens], [100, 40, 2_000, 500]);
    // 100*2 + 40*10 + 2000*2.5 + 500*0.1 = 5650 micro-dollars-per-MTok-units => x1000 nano.
    assert.equal(row!.cost_nano_usd, Math.round((100 * 2 + 40 * 10 + 2_000 * 2.5 + 500 * 0.1) * 1000));
    assert.equal(row!.price_version, PRICE_VERSION);
    assert.equal(row!.created_at, 1_000);
    assert.ok(!JSON.stringify(row).includes(SECRET), "no prompt, material or answer text in the row");
    assert.ok(!JSON.stringify(row).includes("The answer"));
    assert.deepEqual(scope.total.cacheReadTokens, 500);
  } finally {
    await r.store.close();
  }
});

test("failures write a row each, marked unknown rather than zero: a 429, a 500, a timeout and an unreadable answer", async () => {
  const r = await rig([() => json({ error: { type: "rate_limit_error", message: SECRET } }, 429), () => json({}, 500), () => json({ content: "nope" }), () => json({ content: [{ type: "text", text: "x" }] })]);
  try {
    const scope = new UsageScope(ACCOUNT_A, "ask_claude");
    for (const expected of ["rate_limited", "provider_unavailable", "malformed_provider_result"]) {
      await assert.rejects(r.provider.ask({ task: "answer", request: "x" }, AbortSignal.timeout(1_000), scope), (e: ProviderError) => e.code === expected);
    }
    // A reply with content but no usage object still worked, but its usage is unknown.
    await r.provider.ask({ task: "answer", request: "x" }, AbortSignal.timeout(1_000), scope);
    const rows = await rowsOf(r.store);
    assert.deepEqual(rows.map((x) => [x.outcome, x.error_code, x.usage_known, x.input_tokens, x.cost_nano_usd, x.kind, x.seq]), [
      ["failed", "rate_limited", false, null, null, "initial", 0],
      ["failed", "provider_unavailable", false, null, null, "retry", 1],
      ["failed", "malformed_provider_result", false, null, null, "retry", 2],
      ["succeeded", null, false, null, null, "retry", 3],
    ]);
    assert.ok(!JSON.stringify(rows).includes(SECRET), "the provider's error text isn't kept");
    // The summary says how many calls its sums leave out.
    const [sum] = await r.store.claudeUsageByAccount(ACCOUNT_A, 0);
    assert.equal(sum!.calls, 4);
    assert.equal(sum!.failedCalls, 3);
    assert.equal(sum!.retryCalls, 3);
    assert.equal(sum!.unknownUsageCalls, 4);
    assert.equal(sum!.costNanoUsd, 0);
  } finally {
    await r.store.close();
  }
});

test("a timeout is a failed row with unknown usage (it may have been billed; nothing is invented)", async () => {
  const store = await Store.memory();
  try {
    const events: LedgerEvent[] = [];
    const impl = (async () => {
      throw Object.assign(new Error("timeout"), { name: "TimeoutError" });
    }) as unknown as typeof fetch;
    const provider = new AnthropicClaudeProvider(KEY, impl, "https://anthropic.test", { recorder: { record: async (e) => (events.push(e), store.recordClaudeCall(e)) } });
    await assert.rejects(provider.ask({ task: "answer", request: "x" }, AbortSignal.timeout(1_000), new UsageScope(ACCOUNT_A, "ask_claude")));
    assert.equal(events.length, 1);
    assert.equal(events[0]!.outcome, "failed");
    assert.equal(events[0]!.usage, null);
    assert.equal(events[0]!.costNanoUsd, null);
  } finally {
    await store.close();
  }
});

test("a refusal and a cut-off answer cost money, so their calls are recorded as succeeded calls with the stop reason", async () => {
  const r = await rig([
    () => text("", { input_tokens: 10, output_tokens: 1 }, "refusal"),
    () => json({ content: [{ type: "text", text: '{"answer": "cut' }], stop_reason: "max_tokens", usage: { input_tokens: 10, output_tokens: 1500 } }),
  ]);
  try {
    const scope = new UsageScope(ACCOUNT_A, "ask_doddy", "r-2");
    const input = { system: "S", user: SECRET, schema: { type: "object" }, maxTokens: 1500 };
    await assert.rejects(r.provider.structured(input, AbortSignal.timeout(1_000), scope));
    await assert.rejects(r.provider.structured(input, AbortSignal.timeout(1_000), scope));
    const rows = await rowsOf(r.store);
    assert.deepEqual(rows.map((x) => [x.outcome, x.stop_reason, x.usage_known]), [["succeeded", "refusal", true], ["succeeded", "max_tokens", true]]);
    assert.ok(Number(rows[1]!.cost_nano_usd) > 0);
  } finally {
    await r.store.close();
  }
});

test("a document that pauses and continues is one request id with numbered calls, the later ones marked continuations", async () => {
  const usage = { input_tokens: 50, output_tokens: 10, cache_read_input_tokens: 0 };
  const r = await rig([
    () => json({ content: [{ type: "text", text: "Working" }], stop_reason: "pause_turn", container: { id: "cntr_1" }, usage }),
    () => json({ content: [{ type: "text", text: "Done" }], stop_reason: "end_turn", container: { id: "cntr_1" }, usage }),
  ]);
  try {
    // A text document is one call; use the deck path with files stubbed out by failing the fetch after.
    const scope = new UsageScope(ACCOUNT_A, "make_document", "doc-1");
    await assert.rejects(r.provider.makeDocument({ kind: "deck", title: "T", request: "R" }, AbortSignal.timeout(1_000), undefined, scope), (e: ProviderError) => e.code === "malformed_provider_result");
    const rows = await rowsOf(r.store);
    assert.deepEqual(rows.map((x) => [x.request_id, x.seq, x.kind]), [["doc-1", 0, "initial"], ["doc-1", 1, "continuation"]]);
  } finally {
    await r.store.close();
  }
});

test("a ledger write that fails never fails the user's request, and logs no content", async () => {
  const logs: string[] = [];
  const impl = fake([() => text("fine", { input_tokens: 1, output_tokens: 1 })]).impl;
  const provider = new AnthropicClaudeProvider(KEY, impl, "https://anthropic.test", {
    recorder: { record: async () => Promise.reject(new Error(`db down ${SECRET}`)) },
    log: (line) => logs.push(JSON.stringify(line)),
  });
  const answer = await provider.ask({ task: "answer", request: "x" }, AbortSignal.timeout(1_000), new UsageScope(ACCOUNT_A, "ask_claude"));
  assert.equal(answer.text, "fine");
  assert.equal(logs.length, 1);
  assert.ok(logs[0]!.includes("claude_usage_not_recorded"));
  assert.ok(!logs[0]!.includes(SECRET));
});

test("without a scope or a recorder (mock mode, old callers) nothing is written and nothing breaks", async () => {
  const r = await rig([() => text("a", { input_tokens: 1, output_tokens: 1 })]);
  try {
    await r.provider.ask({ task: "answer", request: "x" }, AbortSignal.timeout(1_000));
    assert.equal((await rowsOf(r.store)).length, 0);
    const mock = new MockClaudeProvider();
    assert.equal((await mock.ask({ task: "answer", request: "x" })).text.startsWith("DEMO"), true);
  } finally {
    await r.store.close();
  }
});

// ------------------------------------------------------------------ the store

test("per-account totals only read that account's rows; erasing an account removes its rows; old rows are pruned", async () => {
  const store = await Store.memory();
  try {
    const base = { provider: "anthropic", model: "claude-sonnet-5-5", requestId: "r", seq: 0, kind: "initial", outcome: "succeeded", errorCode: null, stopReason: "end_turn", priceVersion: PRICE_VERSION } as const;
    const usage = { inputTokens: 10, outputTokens: 5, cacheCreationTokens: 0, cacheCreation1hTokens: 0, cacheReadTokens: 100 };
    const put = (userId: string, feature: string, at: number) =>
      store.recordClaudeCall({ ...base, userId, feature, usage, costNanoUsd: costNanoUsd(base.model, usage), at });
    await put(ACCOUNT_A, "ask_doddy", 1_000);
    await put(ACCOUNT_A, "ask_doddy", 2_000);
    await put(ACCOUNT_A, "make_document", 3_000);
    await put(ACCOUNT_B, "ask_doddy", 2_000);

    const a = await store.claudeUsageByAccount(ACCOUNT_A, 0);
    assert.deepEqual(a.map((x) => [x.feature, x.calls, x.cacheReadTokens]), [["ask_doddy", 2, 200], ["make_document", 1, 100]]);
    assert.equal((await store.claudeUsageByAccount(ACCOUNT_B, 0)).length, 1, "B sees only B's row");
    assert.equal((await store.claudeUsageByAccount(ACCOUNT_A, 2_500)).length, 1, "the window applies");
    assert.deepEqual(await store.claudeUsageByAccount("nobody", 0), []);

    assert.equal(await store.pruneClaudeUsage(1_500), 1);
    const erased = await store.eraseUser(ACCOUNT_A, 5_000);
    assert.equal(erased.deleted.claude_usage, 2);
    assert.deepEqual(await store.claudeUsageByAccount(ACCOUNT_A, 0), []);
    assert.equal((await store.claudeUsageByAccount(ACCOUNT_B, 0)).length, 1, "B's rows survive A's erasure");
  } finally {
    await store.close();
  }
});

test("the table refuses a row that claims known usage without counters, or a cost without known usage", async () => {
  const store = await Store.memory();
  try {
    const insert = (known: boolean, input: number | null, cost: number | null) =>
      store.db.query(
        `INSERT INTO claude_usage (created_at, user_id, provider, model, feature, request_id, seq, kind, outcome, usage_known, input_tokens, output_tokens, cache_creation_tokens, cache_creation_1h_tokens, cache_read_tokens, cost_nano_usd)
         VALUES (1, 'u', 'anthropic', 'm', 'f', 'r', 0, 'initial', 'succeeded', $1, $2, $2, $2, $2, $2, $3)`,
        [known, input, cost],
      );
    await assert.rejects(insert(true, null, null));
    await assert.rejects(insert(false, null, 5));
    await insert(false, null, null);
    await insert(true, 0, 0);
  } finally {
    await store.close();
  }
});

test("a request refused because of its cache mark is two rows: the refused one unknown, then the retry recorded as a retry", async () => {
  const LONG = `Fixed instructions. ${"Stay accurate and brief. ".repeat(120)}`;
  const r = await rig([
    () => json({ error: { type: "invalid_request_error", message: "cache_control not supported" } }, 400),
    () => text(JSON.stringify({ answer: "ok" }), { input_tokens: 9, output_tokens: 2 }),
  ]);
  try {
    await r.provider.structured({ system: LONG, user: "u", schema: { type: "object" }, maxTokens: 100 }, AbortSignal.timeout(1_000), new UsageScope(ACCOUNT_A, "ask_doddy", "req-x"));
    assert.deepEqual(r.events.map((e) => [e.seq, e.kind, e.outcome, e.usage === null]), [[0, "initial", "failed", true], [1, "retry", "succeeded", false]]);
    assert.equal((await rowsOf(r.store)).length, 2);
  } finally {
    await r.store.close();
  }
});

test("Fable 5.1 and 5.2 have prices (reads at 0.025x), Fable 5 and a made-up model have none", () => {
  const usage = { inputTokens: 1_000_000, outputTokens: 1_000_000, cacheCreationTokens: 0, cacheCreation1hTokens: 0, cacheReadTokens: 1_000_000 };
  assert.equal(costNanoUsd("claude-fable-5-2", usage), (8 + 40 + 0.2) * 1_000_000_000);
  assert.equal(costNanoUsd("claude-fable-5-1", usage), (10 + 50 + 0.25) * 1_000_000_000);
  assert.equal(costNanoUsd("claude-fable-5", usage), null);
  assert.equal(costNanoUsd("claude-made-up-1", usage), null);
});

test("the travel reader gives each email its own scope under one request id, and none without an account", async () => {
  const scopes: (UsageScope | undefined)[] = [];
  const claude = {
    mode: "mock", isConfigured: () => true, ask: async () => ({ text: "" }), deleteFile: async () => "removed",
    makeDocument: async () => { throw new Error("not used"); },
    structured: async (_input: unknown, _signal: AbortSignal, scope?: UsageScope) => { scopes.push(scope); return { value: {}, usage: { inputTokens: 1, outputTokens: 1 } }; },
  } as unknown as ClaudeProvider;
  const email = { system: "s", text: "t", subject: "x", sender: "y" };
  const reader = new ClaudeTravelReader(claude, 1_000, ACCOUNT_A);
  await reader.read(email);
  await reader.read(email);
  assert.notEqual(scopes[0], scopes[1], "a scope for each email, so the second isn't recorded as a retry of the first");
  assert.deepEqual([scopes[0]!.userId, scopes[0]!.feature, scopes[0]!.begin(false).kind], [ACCOUNT_A, "travel_scan", "initial"]);
  assert.equal(scopes[0]!.requestId, scopes[1]!.requestId);
  scopes.length = 0;
  await new ClaudeTravelReader(claude, 1_000).read(email);
  assert.equal(scopes[0], undefined, "without an account nothing is recorded");
});
