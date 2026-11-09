// Provider cost ledger (migration 026) and the cached prefix of the Messages request. Nothing here calls
// Anthropic: the real responder talks to a local stand-in that records exactly what it was sent.
import assert from "node:assert/strict";
import http from "node:http";
import { after, before, beforeEach, describe, test } from "node:test";
import { AssistRequest } from "../src/assistant/request.js";
import { cacheEligible, ClaudeAssistantResponder } from "../src/assistant/responder.js";
import { addTokens, recordAssistantFailure } from "../src/assistant/usage.js";
import { DEFAULT_ASSISTANT_SETTINGS } from "../src/config.js";
import {
  accountCosts, costUsd, errorCode, recordCost, serverCosts, topAccountsByCost, usageFromAnthropic,
} from "../src/costLedger.js";
import type { Db } from "../src/db.js";
import { dbSkip, freshDb, testApp } from "./helpers.js";

const REQ = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const SESSION = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
const wire = (over: Record<string, unknown> = {}) => ({
  schemaVersion: 1, requestId: REQ, sessionId: SESSION, locale: "pl", userText: "Kiedy mam dentystę? SECRET-QUESTION",
  turns: [], memories: [{ id: "11111111-1111-4111-8111-111111111111", text: "Dentysta w piątek SECRET-NOTE", source: "explicit_voice" }], ...over,
});

describe("prices and usage parsing", () => {
  test("cost follows the official list prices, including cache reads and writes", () => {
    // Haiku 5.5: $0.10 in, $0.50 out, $0.125 5-minute write, $0.01 read per million tokens.
    const usage = { inputTokens: 1000, outputTokens: 500, cacheReadTokens: 2000, cacheWriteTokens: 1000 };
    assert.ok(Math.abs(costUsd("claude-haiku-5-5", usage)! - 0.000495) < 1e-12);
    // Sonnet 5.5: $2 in, $10 out, write 1.25x, read $0.10.
    assert.ok(Math.abs(costUsd("claude-sonnet-5-5", usage)! - (2000 + 5000 + 200 + 2500) / 1e6) < 1e-12);
    // A 1-hour write is billed at 2x input.
    assert.ok(Math.abs(costUsd("claude-sonnet-5-5", { ...usage, cacheWrite1hTokens: 1000 })! - (2000 + 5000 + 200 + 4000) / 1e6) < 1e-12);
    // Haiku over 100K prompt tokens uses the long-prompt price.
    assert.ok(Math.abs(costUsd("claude-haiku-5-5", { inputTokens: 100_001, outputTokens: 1000, cacheReadTokens: 0, cacheWriteTokens: 0 })! - (100_001 * 0.5 + 1000 * 2.5) / 1e6) < 1e-12);
    // A dated model id is the same model; an unknown model has no price (never a guessed one).
    assert.equal(costUsd("claude-haiku-5-5-20261001", usage), costUsd("claude-haiku-5-5", usage));
    assert.equal(costUsd("claude-future-9", usage), null);
  });

  test("usage keeps the cache counters; no usage object is unknown, not zero", () => {
    assert.deepEqual(usageFromAnthropic({ input_tokens: 5, output_tokens: 7, cache_read_input_tokens: 11, cache_creation_input_tokens: 13, cache_creation: { ephemeral_1h_input_tokens: 4 } }),
      { inputTokens: 5, outputTokens: 7, cacheReadTokens: 11, cacheWriteTokens: 13, cacheWrite1hTokens: 4 });
    assert.deepEqual(usageFromAnthropic({ input_tokens: 5, output_tokens: 7, cache_read_input_tokens: null }),
      { inputTokens: 5, outputTokens: 7, cacheReadTokens: 0, cacheWriteTokens: 0, cacheWrite1hTokens: 0 });
    assert.equal(usageFromAnthropic(undefined), undefined);
    assert.equal(usageFromAnthropic({}), undefined);
  });

  test("an error becomes a short code, never its message", () => {
    assert.equal(errorCode({ status: 529, message: "my secret text" }), "http_529");
    assert.equal(errorCode(Object.assign(new Error("secret"), { name: "APIConnectionTimeoutError" })), "apiconnectiontimeouterror");
  });
});

describe("the cached prefix of the Messages request", () => {
  test("only a long enough prefix on a known model is marked", () => {
    assert.ok(cacheEligible("claude-haiku-5-5", "x".repeat(3000)));
    assert.ok(!cacheEligible("claude-haiku-5-5", "x".repeat(1000)), "below 512 tokens");
    assert.ok(!cacheEligible("claude-sonnet-5", "x".repeat(3000)), "Sonnet 5 needs 1,024 tokens");
    assert.ok(!cacheEligible("claude-unknown-1", "x".repeat(30_000)), "an unknown model is never marked");
  });
});

interface Seen { body: any; headers: http.IncomingHttpHeaders }
async function standIn(replies: Array<{ status: number; body: object; requestId?: string }>) {
  const seen: Seen[] = [];
  const server = http.createServer((req, res) => {
    let raw = "";
    req.on("data", (c) => { raw += c; });
    req.on("end", () => {
      seen.push({ body: JSON.parse(raw), headers: req.headers });
      const r = replies.length > 1 ? replies.shift()! : replies[0]!;
      res.writeHead(r.status, { "content-type": "application/json", ...(r.requestId ? { "request-id": r.requestId } : {}), "retry-after-ms": "10" }).end(JSON.stringify(r.body));
    });
  });
  await new Promise<void>((r) => server.listen(0, "127.0.0.1", r));
  return { seen, baseURL: `http://127.0.0.1:${(server.address() as { port: number }).port}`, close: () => server.close() };
}
const message = (usage: object, text = JSON.stringify({ answer: "W piątek.", sources: [] })) => ({
  id: "msg_1", type: "message", role: "assistant", model: "claude-haiku-5-5", stop_reason: "end_turn", stop_sequence: null,
  content: [{ type: "text", text }], usage,
});

describe("request placement (no database)", () => {
  test("the stable instructions carry the cache marker; notes, turns and the question stay after it, unmarked", async () => {
    const api = await standIn([{ status: 200, body: message({ input_tokens: 400, output_tokens: 20, cache_creation_input_tokens: 900, cache_read_input_tokens: 0 }) }]);
    try {
      const responder = new ClaudeAssistantResponder("test-key", { baseURL: api.baseURL });
      await responder.answer(AssistRequest.parse(wire()), new AbortController().signal);
      const body = api.seen[0]!.body;
      assert.equal(body.system.length, 1);
      assert.deepEqual(body.system[0].cache_control, { type: "ephemeral" });
      assert.match(body.system[0].text, /You are Doddy/);
      assert.ok(!body.system[0].text.includes("SECRET-QUESTION") && !body.system[0].text.includes("SECRET-NOTE"), "no user material inside the cached prefix");
      assert.equal(body.cache_control, undefined, "no top-level automatic marker: only the stable prefix is cached");
      const content = JSON.stringify(body.messages);
      assert.ok(content.includes("SECRET-NOTE") && content.includes("SECRET-QUESTION"));
      assert.ok(!content.includes("cache_control"), "the changing user message is never marked");
    } finally {
      api.close();
    }
  });

  test("a model without a known minimum gets no cache marker", async () => {
    const api = await standIn([{ status: 200, body: message({ input_tokens: 1, output_tokens: 1 }) }]);
    try {
      const responder = new ClaudeAssistantResponder("test-key", { baseURL: api.baseURL, model: "claude-unlisted-1" });
      await responder.answer(AssistRequest.parse(wire()), new AbortController().signal);
      assert.equal(typeof api.seen[0]!.body.system, "string");
    } finally {
      api.close();
    }
  });
});

describe("the ledger against real Postgres", { skip: dbSkip }, () => {
  let db: Db;
  before(async () => { db = await freshDb(); });
  after(async () => { await db?.end(); });
  beforeEach(async () => { await db.query("DELETE FROM provider_cost_events; DELETE FROM assistant_usage; DELETE FROM server_daily_usage"); });

  const newAccount = async (app: Awaited<ReturnType<typeof testApp>>["app"]) => {
    const r = await app.inject({ method: "POST", url: "/v1/accounts" });
    const { accountId, deviceToken } = r.json() as { accountId: string; deviceToken: string };
    return { accountId, h: { authorization: `Bearer ${deviceToken}`, "content-type": "application/json" } };
  };
  const range = { from: new Date(Date.now() - 3_600_000), to: new Date(Date.now() + 3_600_000) };

  test("a Messages call writes a row with cache counters, cost, request id and no text; the other account sees nothing", async () => {
    const api = await standIn([{ status: 200, requestId: "req_abc123", body: message({ input_tokens: 400, output_tokens: 20, cache_creation_input_tokens: 900, cache_read_input_tokens: 0 }) }]);
    try {
      const responder = new ClaudeAssistantResponder("test-key", { baseURL: api.baseURL });
      const { app } = await testApp(db, { assistant: { settings: { ...DEFAULT_ASSISTANT_SETTINGS }, responder } });
      const a = await newAccount(app);
      const b = await newAccount(app);
      const res = await app.inject({ method: "POST", url: "/v1/assistant/ask", headers: a.h, payload: JSON.stringify(wire()) });
      assert.equal(res.statusCode, 200);
      assert.deepEqual(Object.keys(res.json().usage).sort(), ["inputTokens", "outputTokens"], "the app's wire shape is unchanged");

      const { rows } = await db.query("SELECT * FROM provider_cost_events");
      assert.equal(rows.length, 1);
      const r = rows[0];
      assert.equal(r.account_id, a.accountId);
      assert.equal(r.feature, "assistant");
      assert.equal(r.model, "claude-haiku-5-5");
      assert.equal(r.provider_request_id, "req_abc123");
      assert.equal(r.outcome, "success");
      assert.equal(r.usage_known, true);
      assert.deepEqual([r.input_tokens, r.output_tokens, r.cache_read_tokens, r.cache_write_tokens], ["400", "20", "0", "900"]);
      assert.ok(Math.abs(Number(r.cost_usd) - (400 * 0.1 + 20 * 0.5 + 900 * 0.125) / 1e6) < 1e-9);
      assert.equal(r.cost_basis, "list_price");
      assert.ok(!JSON.stringify(rows).includes("SECRET"), "no prompt, note or answer text is stored");

      assert.equal((await accountCosts(db, a.accountId, range)).length, 1);
      assert.deepEqual(await accountCosts(db, b.accountId, range), [], "another account's costs are not visible");
      assert.equal((await serverCosts(db, range))[0]!.calls, 1);
    } finally {
      api.close();
    }
  });

  test("a second question reading the cache is recorded as cache reads, and costs less", async () => {
    const api = await standIn([
      { status: 200, body: message({ input_tokens: 400, output_tokens: 20, cache_creation_input_tokens: 900, cache_read_input_tokens: 0 }) },
      { status: 200, body: message({ input_tokens: 400, output_tokens: 20, cache_creation_input_tokens: 0, cache_read_input_tokens: 900 }) },
    ]);
    try {
      const responder = new ClaudeAssistantResponder("test-key", { baseURL: api.baseURL });
      const { app } = await testApp(db, { assistant: { settings: { ...DEFAULT_ASSISTANT_SETTINGS }, responder } });
      const a = await newAccount(app);
      for (let i = 0; i < 2; i++) await app.inject({ method: "POST", url: "/v1/assistant/ask", headers: a.h, payload: JSON.stringify(wire()) });
      const { rows } = await db.query("SELECT cache_read_tokens, cache_write_tokens, cost_usd FROM provider_cost_events ORDER BY id");
      assert.deepEqual(rows.map((r) => [r.cache_read_tokens, r.cache_write_tokens]), [["0", "900"], ["900", "0"]]);
      assert.ok(Number(rows[1].cost_usd) < Number(rows[0].cost_usd));
    } finally {
      api.close();
    }
  });

  test("a provider failure is a failure row with unknown usage, a code and the attempts, and the earlier attempt is a retry row", async () => {
    const api = await standIn([{ status: 500, body: { type: "error", error: { type: "api_error", message: "SECRET-ERROR-TEXT" } }, requestId: "req_fail" }]);
    try {
      const responder = new ClaudeAssistantResponder("test-key", { baseURL: api.baseURL });
      const { app } = await testApp(db, { assistant: { settings: { ...DEFAULT_ASSISTANT_SETTINGS }, responder } });
      const a = await newAccount(app);
      const res = await app.inject({ method: "POST", url: "/v1/assistant/ask", headers: a.h, payload: JSON.stringify(wire()) });
      assert.equal(res.statusCode, 503);
      assert.equal(api.seen.length, 2, "the SDK tried twice (maxRetries 1)");
      const { rows } = await db.query("SELECT * FROM provider_cost_events ORDER BY id");
      assert.deepEqual(rows.map((r) => r.outcome), ["retry", "failure"]);
      const failure = rows[1];
      assert.equal(failure.usage_known, false);
      assert.equal(failure.input_tokens, null, "unknown is NULL, never 0");
      assert.equal(failure.cost_usd, null);
      assert.equal(failure.cost_basis, "unknown_usage");
      assert.equal(failure.error_code, "http_500");
      assert.equal(failure.attempts, 2);
      assert.equal(failure.provider_request_id, "req_fail");
      assert.ok(!JSON.stringify(rows).includes("SECRET"));
      const summary = (await accountCosts(db, a.accountId, range))[0]!;
      assert.deepEqual([summary.calls, summary.failures, summary.retries, summary.unknownUsageCalls], [1, 1, 1, 2]);
    } finally {
      api.close();
    }
  });

  test("a retry that then succeeds is one retry row and one success row", async () => {
    const api = await standIn([
      { status: 529, body: { type: "error", error: { type: "overloaded_error", message: "busy" } } },
      { status: 200, body: message({ input_tokens: 10, output_tokens: 5 }) },
    ]);
    try {
      const responder = new ClaudeAssistantResponder("test-key", { baseURL: api.baseURL });
      const { app } = await testApp(db, { assistant: { settings: { ...DEFAULT_ASSISTANT_SETTINGS }, responder } });
      const a = await newAccount(app);
      const res = await app.inject({ method: "POST", url: "/v1/assistant/ask", headers: a.h, payload: JSON.stringify(wire()) });
      assert.equal(res.statusCode, 200);
      const { rows } = await db.query("SELECT outcome, attempts, usage_known FROM provider_cost_events ORDER BY id");
      assert.deepEqual(rows, [{ outcome: "retry", attempts: 1, usage_known: false }, { outcome: "success", attempts: 2, usage_known: true }]);
    } finally {
      api.close();
    }
  });

  test("an unknown model is recorded with usage but no cost, flagged unknown_model", async () => {
    const { app } = await testApp(db, {});
    const a = await newAccount(app);
    await recordCost(db, { accountId: a.accountId, model: "claude-future-9", feature: "assistant", outcome: "success", usage: { inputTokens: 5, outputTokens: 5, cacheReadTokens: 0, cacheWriteTokens: 0 } });
    const { rows } = await db.query("SELECT cost_usd, cost_basis, usage_known FROM provider_cost_events");
    assert.deepEqual(rows, [{ cost_usd: null, cost_basis: "unknown_model", usage_known: true }]);
  });

  test("free text cannot be stored through the id fields, and a ledger error never throws", async () => {
    const { app } = await testApp(db, {});
    const a = await newAccount(app);
    await recordCost(db, { accountId: a.accountId, model: "claude-haiku-5-5", feature: "assistant", outcome: "failure", providerRequestId: "my private question?", refId: "x y" });
    const { rows } = await db.query("SELECT provider_request_id, ref_id FROM provider_cost_events");
    assert.deepEqual(rows, [{ provider_request_id: null, ref_id: null }]);
    assert.equal(await recordCost(db, { accountId: a.accountId, model: "m", feature: "Bad Feature!", outcome: "success" }), false, "a bad row is refused by the schema, not thrown");
  });

  test("deleting the account removes the link but keeps the spend", async () => {
    const { app } = await testApp(db, {});
    const a = await newAccount(app);
    await recordCost(db, { accountId: a.accountId, model: "claude-haiku-5-5", feature: "assistant", outcome: "success", usage: { inputTokens: 1_000_000, outputTokens: 0, cacheReadTokens: 0, cacheWriteTokens: 0 } });
    await db.query("DELETE FROM accounts WHERE id = $1", [a.accountId]);
    const top = await topAccountsByCost(db, range);
    assert.equal(top.length, 1);
    assert.deepEqual([top[0]!.accountId, top[0]!.calls], [null, 1]);
    assert.ok(Math.abs(top[0]!.costUsd - 0.1) < 1e-9);
  });

  test("addTokens still counts when the usage has no ledger detail (a fake responder), and writes no row", async () => {
    const { app } = await testApp(db, {});
    const a = await newAccount(app);
    await db.query("INSERT INTO assistant_usage (account_id, day, requests) VALUES ($1, (now() AT TIME ZONE 'utc')::date, 1)", [a.accountId]);
    await addTokens(db, a.accountId, { inputTokens: 3, outputTokens: 4 });
    assert.equal((await db.query("SELECT input_tokens FROM assistant_usage")).rows[0].input_tokens, "3");
    assert.equal((await db.query("SELECT 1 FROM provider_cost_events")).rowCount, 0);
    await recordAssistantFailure(db, a.accountId, "claude-haiku-5-5", { status: 429 });
    assert.equal((await db.query("SELECT error_code FROM provider_cost_events")).rows[0].error_code, "http_429");
  });
});
