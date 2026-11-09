import assert from "node:assert/strict";
import { test } from "node:test";
import { FILE_BACKOFF_BASE_MS, FILE_STUCK_AFTER, type ProviderFileQueue } from "../src/providerFiles.js";
import { Store } from "../src/store.js";
import { AnthropicClaudeProvider } from "../src/tools/claude.js";

/**
 * Anthropic's copies of generated files are a durable debt (research item 14): written down before the
 * first try, confirmed only by a read-back, retried with backoff, reported when stuck, and never able to
 * fail the user's document or leak a file id into a log.
 */

const FILE_ID = "file_011CPMxVD3fHLUPFanTgEXAMPLE";
const T0 = 1_800_000_000_000;
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
const madeFile = () =>
  json({
    content: [
      { type: "bash_code_execution_tool_result", content: { type: "bash_code_execution_result", content: [{ type: "bash_code_execution_output", file_id: FILE_ID }] } },
      { type: "text", text: "A deck." },
    ],
    stop_reason: "end_turn",
    usage: { input_tokens: 5, output_tokens: 5 },
  });

type Handler = (method: string, url: string) => Response | Promise<Response>;

async function rig(handler: Handler, o: { queue?: ProviderFileQueue } = {}) {
  const store = await Store.memory();
  const logs: string[] = [];
  const seen: string[] = [];
  const impl = (async (url: unknown, init: RequestInit) => {
    const method = init?.method ?? "GET";
    seen.push(`${method} ${String(url)}`);
    return handler(method, String(url));
  }) as typeof fetch;
  let now = T0;
  const files = o.queue ?? store.providerFileQueue();
  const provider = new AnthropicClaudeProvider({ apiKey: "sk-ant-test-key-1234", model: "claude-sonnet-5-5" }, impl, "https://anthropic.test", {
    files,
    log: (l) => logs.push(JSON.stringify(l)),
    now: () => now,
  });
  const rows = () => store.db.query<Record<string, any>>("SELECT * FROM provider_file_deletions ORDER BY file_id", []).then((r) => r.rows);
  return { store, provider, logs, seen, rows, setNow: (n: number) => (now = n), files };
}

/** A transport where creating the deck works, downloading it works, and `fileApi` decides what deleting does. */
const deckHandler = (fileApi: Handler): Handler => (method, url) => (url.endsWith("/v1/messages") ? madeFile() : fileApi(method, url));

const deck = (p: AnthropicClaudeProvider) => p.makeDocument({ kind: "deck", title: "Plan", request: "A plan" }, AbortSignal.timeout(5_000));

test("a document made: the deletion is recorded, tried, read back as gone, and the debt is cleared", async () => {
  let deleted = false;
  const r = await rig(
    deckHandler((method, url) => {
      if (method === "DELETE") return ((deleted = true), json({ id: FILE_ID, type: "file_deleted" }));
      if (url.endsWith("/content")) return new Response(Buffer.from("PPTX"));
      // Metadata before the delete, a 404 read-back after it.
      return deleted ? json({ error: { type: "not_found_error" } }, 404) : json({ filename: "plan.pptx", mime_type: "x" });
    }),
  );
  try {
    const file = await deck(r.provider);
    assert.equal(file.bytes.toString(), "PPTX");
    assert.deepEqual(await r.rows(), [], "confirmed gone: nothing is owed");
    assert.ok(r.seen.some((s) => s.startsWith("DELETE ")));
    assert.ok(!r.logs.join("\n").includes(FILE_ID));
  } finally {
    await r.store.close();
  }
});

test("a failed deletion never fails the document; the debt stays, with a backoff, and no log names the file", async () => {
  const r = await rig(
    deckHandler((method, url) => {
      if (method === "DELETE") return json({ error: { type: "api_error", message: `secret ${FILE_ID}` } }, 500);
      if (url.endsWith("/content")) return new Response(Buffer.from("PPTX"));
      return json({ filename: "plan.pptx", mime_type: "x" });
    }),
  );
  try {
    const file = await deck(r.provider);
    assert.equal(file.name, "Plan.pptx", "the user's document is unaffected");
    const [row] = await r.rows();
    assert.equal(row!.file_id, FILE_ID);
    assert.equal(row!.attempts, 1);
    assert.equal(row!.last_error, "delete_failed");
    assert.equal(row!.next_attempt_at, T0 + FILE_BACKOFF_BASE_MS);
    assert.deepEqual(await r.files.due(T0 + 1, 10), [], "not due before its backoff");
    assert.deepEqual(await r.files.due(T0 + FILE_BACKOFF_BASE_MS, 10), [FILE_ID]);
    assert.ok(!r.logs.join("\n").includes(FILE_ID));
  } finally {
    await r.store.close();
  }
});

test("a delete the provider accepted but a read-back still finds is not confirmed; a 404 on delete is", async () => {
  const still = await rig(
    deckHandler((method, url) => {
      if (method === "DELETE") return json({ id: FILE_ID, type: "file_deleted" });
      if (url.endsWith("/content")) return new Response(Buffer.from("PPTX"));
      return json({ filename: "plan.pptx", mime_type: "x" }); // still there after the delete
    }),
  );
  try {
    await deck(still.provider);
    assert.equal((await still.rows())[0]!.last_error, "still_present");
  } finally {
    await still.store.close();
  }
  const absent = await rig(
    deckHandler((method, url) => {
      if (method === "DELETE") return json({}, 404);
      if (url.endsWith("/content")) return new Response(Buffer.from("PPTX"));
      return json({ filename: "plan.pptx", mime_type: "x" });
    }),
  );
  try {
    await deck(absent.provider);
    assert.deepEqual(await absent.rows(), []);
  } finally {
    await absent.store.close();
  }
});

test("an unreachable provider leaves the debt; the hourly sweep retries it later and clears it when the file is gone", async () => {
  let up = false;
  const r = await rig(
    deckHandler((method, url) => {
      if (url.endsWith("/content")) return new Response(Buffer.from("PPTX"));
      if (method === "GET" && url.endsWith(`/v1/files/${FILE_ID}`) && !up) return json({ filename: "plan.pptx", mime_type: "x" });
      if (!up) throw new TypeError("network down");
      return json({}, 404);
    }),
  );
  try {
    await deck(r.provider);
    assert.equal((await r.rows())[0]!.last_error, "unreachable");

    const early = await r.provider.sweepFiles(T0 + 1_000);
    assert.deepEqual([early.confirmed, early.failed, early.pending], [0, 0, 1], "not due yet: nothing is tried");

    up = true;
    const later = await r.provider.sweepFiles(T0 + FILE_BACKOFF_BASE_MS + 1);
    assert.deepEqual([later.confirmed, later.failed, later.pending, later.stuck], [1, 0, 0, 0]);
    assert.deepEqual(await r.rows(), []);
  } finally {
    await r.store.close();
  }
});

test("repeated failures back off up to a cap and are reported as stuck, never dropped, with counts and no file id", async () => {
  const r = await rig(
    deckHandler((method, url) => {
      if (url.endsWith("/content")) return new Response(Buffer.from("PPTX"));
      if (method === "GET") return json({ filename: "plan.pptx", mime_type: "x" });
      return json({}, 500);
    }),
  );
  try {
    await deck(r.provider);
    let now = T0;
    let lastGap = 0;
    for (let i = 0; i < FILE_STUCK_AFTER + 2; i++) {
      const [row] = await r.rows();
      now = row!.next_attempt_at;
      await r.provider.sweepFiles(now);
      const [after] = await r.rows();
      lastGap = after!.next_attempt_at - now;
    }
    assert.equal(lastGap, 6 * 60 * 60_000, "the wait stops growing at six hours");
    const [row] = await r.rows();
    assert.ok(row!.attempts >= FILE_STUCK_AFTER);
    const backlog = await r.files.backlog(FILE_STUCK_AFTER, now);
    assert.equal(backlog.stuck, 1);
    assert.ok(backlog.oldestAgeMs > 0);
    const stuckLog = r.logs.filter((l) => l.includes("provider_file_deletion_stuck"));
    assert.ok(stuckLog.length > 0);
    assert.ok(!r.logs.join("\n").includes(FILE_ID), "no log line names the file");
  } finally {
    await r.store.close();
  }
});

test("files made before a failure are still owed a deletion (a document that then fails)", async () => {
  const r = await rig((method, url) => {
    if (url.endsWith("/v1/messages")) return madeFile();
    if (method === "GET") return json({}, 500); // metadata lookup fails: the document fails
    return json({}, 500); // and deleting fails too
  });
  try {
    await assert.rejects(deck(r.provider));
    const [row] = await r.rows();
    assert.equal(row!.file_id, FILE_ID, "the file made before the failure is queued");
    assert.equal(row!.attempts, 1);
  } finally {
    await r.store.close();
  }
});

test("if the debt can't even be written, the document still works, the deletion is still tried, and the log says only how many", async () => {
  const broken: ProviderFileQueue = {
    queue: async () => Promise.reject(new Error(`db down ${FILE_ID}`)),
    confirm: async () => {},
    failed: async () => Promise.reject(new Error("db down")),
    due: async () => [],
    backlog: async () => ({ pending: 0, stuck: 0, oldestAgeMs: 0 }),
  };
  let tried = 0;
  const r = await rig(
    deckHandler((method, url) => {
      if (method === "DELETE") return (tried++, json({}, 500));
      if (url.endsWith("/content")) return new Response(Buffer.from("PPTX"));
      return json({ filename: "plan.pptx", mime_type: "x" });
    }),
    { queue: broken },
  );
  try {
    const file = await deck(r.provider);
    assert.equal(file.bytes.toString(), "PPTX");
    assert.equal(tried, 1);
    assert.ok(r.logs.some((l) => l.includes("provider_file_untracked") && l.includes('"files":1')));
    assert.ok(!r.logs.join("\n").includes(FILE_ID));
  } finally {
    await r.store.close();
  }
});

test("the same file queued twice is one debt, and the queue holds no account or content", async () => {
  const store = await Store.memory();
  try {
    const q = store.providerFileQueue();
    await q.queue([FILE_ID, FILE_ID], T0);
    await q.failed(FILE_ID, "delete_failed", T0);
    await q.queue([FILE_ID], T0 + 5);
    const rows = (await store.db.query<Record<string, unknown>>("SELECT * FROM provider_file_deletions", [])).rows;
    assert.equal(rows.length, 1);
    assert.equal(rows[0]!.attempts, 1, "re-queueing keeps the counters");
    assert.deepEqual(Object.keys(rows[0]!).sort(), ["attempts", "created_at", "file_id", "last_error", "next_attempt_at"]);
    await q.failed(FILE_ID, "Some free text with secrets!", T0);
    assert.equal(((await store.db.query<Record<string, unknown>>("SELECT last_error FROM provider_file_deletions", [])).rows[0] as any).last_error, "unknown", "only a plain word is kept as the reason");
  } finally {
    await store.close();
  }
});
