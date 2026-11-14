import assert from "node:assert/strict";
import { test } from "node:test";
import { AccountEraser } from "../src/account.js";
import { AssistService } from "../src/assist.js";
import { testLimits } from "../src/config.js";
import { AppError, ProviderError } from "../src/errors.js";
import { RequestOnce } from "../src/idempotency.js";
import { Store } from "../src/store.js";
import { type ClaudeProvider, ClaudeRefusal, type StructuredInput, type StructuredResult } from "../src/tools/claude.js";

/**
 * Ask Doddy's request id is an idempotency key (research item 10): the same account asking the same
 * id again gets the first result, or waits for it, without paying for another generation. Other
 * accounts, other questions and failures never share a result.
 */

const A = "00000000-0000-4000-8000-0000000000a1";
const B = "00000000-0000-4000-8000-0000000000b2";
const REQUEST_ID = "0f8fad5b-d9cb-469f-a165-70867728950e";
const SESSION_ID = "7c9e6679-7425-40de-944b-e07fc1f90ae7";

const body = (over: Record<string, unknown> = {}) => ({ schemaVersion: 1, requestId: REQUEST_ID, sessionId: SESSION_ID, locale: "en", userText: "What is two plus two?", turns: [], memories: [], ...over });

class CountingClaude implements ClaudeProvider {
  readonly mode = "live" as const;
  calls = 0;
  gate: Promise<void> | null = null;
  constructor(private readonly outcome: () => StructuredResult | Promise<StructuredResult> = () => ({ value: { answer: "Four." }, usage: { inputTokens: 10, outputTokens: 3 } })) {}
  isConfigured() {
    return true;
  }
  async ask(): Promise<never> {
    throw new Error("unused");
  }
  async makeDocument(): Promise<never> {
    throw new Error("unused");
  }
  async deleteFile(): Promise<"removed" | "failed"> {
    return "removed";
  }
  async structured(_input: StructuredInput): Promise<StructuredResult> {
    this.calls++;
    if (this.gate) await this.gate;
    return this.outcome();
  }
}

async function rig(claude: ClaudeProvider, over: { once?: RequestOnce<any>; userDailyAsk?: number } = {}) {
  const store = await Store.memory();
  const limits = testLimits(over.userDailyAsk ? { userDailyAsk: over.userDailyAsk } : {});
  const logs: string[] = [];
  const assist = new AssistService({ store, claude, limits, log: (l) => logs.push(JSON.stringify(l)), now: () => Date.parse("2026-11-09T10:00:00Z"), ...(over.once ? { once: over.once } : {}) });
  return { store, assist, logs, used: (user: string) => store.usage(`user:${user}:ask`, "day:2026-11-09") };
}

test("the same account and request id again returns the recorded answer: one generation, one quota unit", async () => {
  const claude = new CountingClaude();
  const r = await rig(claude);
  try {
    const first = await r.assist.answer(A, body());
    const again = await r.assist.answer(A, body());
    assert.deepEqual(again, first);
    assert.equal(claude.calls, 1, "the second request paid for nothing");
    assert.equal(await r.used(A), 1, "and used up no daily question");
    assert.ok(r.logs.some((l) => l.includes('"outcome":"replayed"')));
    assert.ok(!r.logs.join("\n").includes("two plus two"), "no question text in the log");
    // The request id is read case-insensitively, like the reply echoes it.
    await r.assist.answer(A, body({ requestId: REQUEST_ID.toUpperCase() }));
    assert.equal(claude.calls, 1);
  } finally {
    await r.store.close();
  }
});

test("a different account with the same request id never gets the first account's answer", async () => {
  let n = 0;
  const claude = new CountingClaude(() => ({ value: { answer: `call ${++n}` }, usage: { inputTokens: 1, outputTokens: 1 } }));
  const r = await rig(claude);
  try {
    const a = await r.assist.answer(A, body());
    const b = await r.assist.answer(B, body());
    assert.equal(claude.calls, 2);
    assert.equal(a.text, "call 1");
    assert.equal(b.text, "call 2");
    assert.equal(await r.used(A), 1);
    assert.equal(await r.used(B), 1);
  } finally {
    await r.store.close();
  }
});

test("the same request id with a different question is refused, not answered with the old answer", async () => {
  const claude = new CountingClaude();
  const r = await rig(claude);
  try {
    await r.assist.answer(A, body());
    await assert.rejects(r.assist.answer(A, body({ userText: "A different question" })), (e: AppError) => e.code === "invalid_request");
    await assert.rejects(r.assist.answer(A, body({ locale: "pl" })), (e: AppError) => e.code === "invalid_request");
    assert.equal(claude.calls, 1);
    assert.equal(await r.used(A), 1);
  } finally {
    await r.store.close();
  }
});

test("a duplicate that arrives while the first is running waits for it and shares its answer: one generation", async () => {
  const claude = new CountingClaude();
  let release!: () => void;
  claude.gate = new Promise<void>((res) => (release = res));
  const r = await rig(claude);
  try {
    const first = r.assist.answer(A, body());
    const second = r.assist.answer(A, body());
    const third = r.assist.answer(A, body());
    await new Promise((res) => setTimeout(res, 20));
    assert.equal(claude.calls, 1, "only one request reached Claude while the others waited");
    release();
    const results = await Promise.all([first, second, third]);
    assert.deepEqual(results[1], results[0]);
    assert.deepEqual(results[2], results[0]);
    assert.equal(claude.calls, 1);
    assert.equal(await r.used(A), 1);
  } finally {
    await r.store.close();
  }
});

test("a failure is never remembered as done: the same id runs again, and a waiting duplicate sees the same error", async () => {
  let fail = true;
  const claude = new CountingClaude(() => {
    if (fail) throw new ProviderError("provider_timeout");
    return { value: { answer: "Four." }, usage: { inputTokens: 1, outputTokens: 1 } };
  });
  let release!: () => void;
  claude.gate = new Promise<void>((res) => (release = res));
  const r = await rig(claude);
  try {
    const first = r.assist.answer(A, body()).then(() => "ok", (e: AppError) => e.code);
    const waiter = r.assist.answer(A, body()).then(() => "ok", (e: AppError) => e.code);
    await new Promise((res) => setTimeout(res, 20));
    release();
    assert.deepEqual(await Promise.all([first, waiter]), ["provider_timeout", "provider_timeout"]);
    assert.equal(claude.calls, 1, "the waiter didn't start its own generation");

    claude.gate = null;
    fail = false;
    const retry = await r.assist.answer(A, body());
    assert.equal(retry.text, "Four.");
    assert.equal(claude.calls, 2, "the retry ran for real");
  } finally {
    await r.store.close();
  }
});

test("a refusal and an unreadable answer are not remembered either", async () => {
  let mode: "refuse" | "junk" | "ok" = "refuse";
  const claude = new CountingClaude(() => {
    if (mode === "refuse") throw new ClaudeRefusal();
    if (mode === "junk") return { value: { nonsense: true }, usage: { inputTokens: 1, outputTokens: 1 } };
    return { value: { answer: "Fine." }, usage: { inputTokens: 1, outputTokens: 1 } };
  });
  const r = await rig(claude);
  try {
    await assert.rejects(r.assist.answer(A, body()), (e: AppError) => e.code === "refused");
    mode = "junk";
    await assert.rejects(r.assist.answer(A, body()), (e: AppError) => e.code === "malformed_provider_result");
    mode = "ok";
    assert.equal((await r.assist.answer(A, body())).text, "Fine.");
    assert.equal(claude.calls, 3);
  } finally {
    await r.store.close();
  }
});

test("a request refused for the daily limit is not remembered: it works the next day under the same id", async () => {
  const claude = new CountingClaude();
  const r = await rig(claude, { userDailyAsk: 1 });
  try {
    await r.assist.answer(A, body({ requestId: "11111111-1111-4111-8111-111111111111" }));
    await assert.rejects(r.assist.answer(A, body()), (e: AppError) => e.code === "quota_exceeded");
    // Not cached as an answer: after the limit frees, the same id runs.
    await r.store.releaseUsage([{ counter: `user:${A}:ask`, period: "day:2026-11-09" }], 1);
    assert.equal((await r.assist.answer(A, body())).text, "Four.");
  } finally {
    await r.store.close();
  }
});

test("deleting an account drops its remembered answers at once", async () => {
  const claude = new CountingClaude();
  const once = new RequestOnce<any>({ ttlMs: 600_000, maxEntries: 50, maxPerUser: 5 });
  const r = await rig(claude, { once });
  try {
    await r.assist.answer(A, body());
    await r.assist.answer(B, body());
    assert.equal(once.size, 2);
    const eraser = new AccountEraser({ store: r.store, removers: [], timeoutMs: 1_000, forget: (userId) => void once.forgetUser(userId) });
    await eraser.erase(A);
    assert.equal(once.size, 1, "only B's answer is left");
    await r.assist.answer(A, body());
    assert.equal(claude.calls, 3, "A's old answer wasn't replayed after deletion");
  } finally {
    await r.store.close();
  }
});

// ------------------------------------------------------------------ the memory itself

test("RequestOnce forgets after its time limit, caps entries in total and per account, and can drop an account", async () => {
  let now = 1_000;
  const once = new RequestOnce<string>({ ttlMs: 100, maxEntries: 4, maxPerUser: 2, now: () => now });
  let runs = 0;
  const go = (user: string, id: string) => once.run(user, id, "f", async () => `v${++runs}`);

  assert.equal((await go(A, "r1")).value, "v1");
  assert.deepEqual(await go(A, "r1"), { value: "v1", replayed: true });
  now += 101;
  assert.deepEqual(await go(A, "r1"), { value: "v2", replayed: false }, "after the window it runs again");

  // Per account: A's third entry pushes out A's oldest, never B's.
  await go(B, "b1");
  await go(A, "r2");
  await go(A, "r3");
  assert.equal((await go(B, "b1")).replayed, true, "B's entry is untouched by A's churn");
  assert.equal((await go(A, "r2")).replayed, true);
  assert.equal((await go(A, "r1")).replayed, false, "A's oldest was dropped");

  // Total cap.
  for (const id of ["x1", "x2", "x3", "x4", "x5"]) await go("other", id);
  assert.ok(once.size <= 4);

  assert.ok(once.forgetUser(A) >= 0);
  assert.equal((await go(A, "r2")).replayed, false, "an erased account's answers are gone");
});

test("RequestOnce: when the memory is full of running requests, a new one still runs, just without being remembered", async () => {
  const once = new RequestOnce<string>({ ttlMs: 1_000, maxEntries: 1, maxPerUser: 1 });
  let release!: () => void;
  const gate = new Promise<void>((res) => (release = res));
  const slow = once.run(A, "slow", "f", async () => (await gate, "slow"));
  const other = await once.run(B, "fast", "f", async () => "fast");
  assert.deepEqual(other, { value: "fast", replayed: false });
  release();
  assert.equal((await slow).value, "slow");
  assert.equal(once.size, 1);
});
