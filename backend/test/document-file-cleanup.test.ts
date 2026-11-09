import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import { AccountEraser } from "../src/account.js";
import { ANTHROPIC_FILE_CLEANUP, CLEANUP_RETRY, ERASED_TABLES, KEPT_ON_ERASE } from "../src/store.js";
import { ProviderError } from "../src/errors.js";
import { AnthropicClaudeProvider, DOCUMENT_TIMEOUT_MS, type ProviderFileLedger } from "../src/tools/claude.js";
import { DEV_IDENTITIES } from "../src/auth.js";
import { USER_A } from "./helpers.js";
import { type Rig, run, start } from "./toolsRig.js";

/**
 * Security audit 2026-11-09, finding 3: a copy of a person's document made at Anthropic must not outlive
 * the person's wish to have it gone. Each copy is written down (id only) the moment it is seen, deleted
 * whatever else fails, deleted only counts when Anthropic says so, and what is still owed survives a
 * restart and the person's account being erased.
 */

const ID_A = DEV_IDENTITIES[USER_A]!;
const doc = (title: string) => ({ kind: "doc", title, request: "Write it" });

let rig: Rig | undefined;
afterEach(async () => {
  await rig?.tools.settle();
  await rig?.close();
  rig = undefined;
});

type DeleteAnswer = number | "network";

/** Anthropic, as far as documents go. `deleteAnswers` is what DELETE says for each id (default 200). */
function fakeAnthropic(o: { files?: string[]; content?: "ok" | 500; pauseForever?: boolean; afterMessages?: () => void; deleteAnswers?: Record<string, DeleteAnswer> } = {}) {
  const files = o.files ?? ["file_a", "file_b"];
  const log: string[] = [];
  const deleteAnswers = { ...(o.deleteAnswers ?? {}) };
  const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
  const fetchImpl: typeof fetch = async (input, init) => {
    const url = new URL(String(input));
    const method = init?.method ?? "GET";
    log.push(`${method} ${url.pathname}`);
    // A real fetch refuses once the caller's signal has fired.
    if (init?.signal?.aborted) throw new DOMException("aborted", "AbortError");
    if (method === "POST" && url.pathname === "/v1/messages") {
      o.afterMessages?.();
      return json({
        content: files.map((file_id) => ({ type: "bash_code_execution_tool_result", content: { type: "bash_code_execution_result", content: [{ file_id }] } })),
        stop_reason: o.pauseForever ? "pause_turn" : "end_turn",
        container: { id: "cont_1" },
      });
    }
    const content = /^\/v1\/files\/([^/]+)\/content$/.exec(url.pathname);
    if (method === "GET" && content) return o.content === 500 ? json({ error: "boom" }, 500) : new Response(Buffer.from("DOC BYTES"));
    const one = /^\/v1\/files\/([^/]+)$/.exec(url.pathname);
    if (one && method === "GET") return json({ filename: `${one[1]}.docx`, mime_type: "x" });
    if (one && method === "DELETE") {
      const answer = deleteAnswers[decodeURIComponent(one[1]!)] ?? 200;
      if (answer === "network") throw new TypeError("fetch failed");
      return json(answer === 200 ? { id: one[1], type: "file_deleted" } : { error: { type: "x" } }, answer);
    }
    return json({}, 404);
  };
  return {
    provider: new AnthropicClaudeProvider({ apiKey: "sk-test", model: "m" }, fetchImpl, "https://anthropic.test"),
    log,
    deleteAnswers,
    deleted: () => log.filter((l) => l.startsWith("DELETE")).map((l) => l.split("/").pop()!),
  };
}

function ledger() {
  const events: string[] = [];
  const l: ProviderFileLedger = {
    track: async (id) => void events.push(`track:${id}`),
    confirmed: async (id) => void events.push(`confirmed:${id}`),
    failed: async (id) => void events.push(`failed:${id}`),
  };
  return { l, events };
}

const make = (p: AnthropicClaudeProvider, l?: ProviderFileLedger, signal: AbortSignal = AbortSignal.timeout(5_000)) =>
  p.makeDocument({ kind: "doc", title: "Plan", request: "Write it" }, signal, l);

// ------------------------------------------------------------------ the provider

test("a finished document: every copy is written down first, then deleted, and the ledger hears each confirmation", async () => {
  const api = fakeAnthropic();
  const { l, events } = ledger();
  const file = await make(api.provider, l);
  assert.equal(file.bytes.toString(), "DOC BYTES");
  assert.deepEqual(api.deleted().sort(), ["file_a", "file_b"]);
  assert.deepEqual(events.slice(0, 2), ["track:file_a", "track:file_b"], "written down before anything else happens to them");
  assert.deepEqual(events.slice(2).sort(), ["confirmed:file_a", "confirmed:file_b"]);
});

test("a download that fails still deletes the copies (before the fix they were left behind)", async () => {
  const api = fakeAnthropic({ content: 500 });
  const { l, events } = ledger();
  await assert.rejects(make(api.provider, l), (e: unknown) => e instanceof ProviderError);
  assert.deepEqual(api.deleted().sort(), ["file_a", "file_b"]);
  assert.ok(events.includes("confirmed:file_a") && events.includes("confirmed:file_b"));
});

test("a job that never finishes (the pause never ends) still deletes the copies it saw", async () => {
  const api = fakeAnthropic({ pauseForever: true });
  const { l, events } = ledger();
  await assert.rejects(make(api.provider, l), (e: unknown) => e instanceof ProviderError && e.code === "provider_timeout");
  assert.deepEqual(api.deleted().sort(), ["file_a", "file_b"]);
  assert.ok(events.includes("confirmed:file_a"));
});

test("a job whose own time ran out after the copies existed still deletes them: the delete is not tied to the job's signal", async () => {
  const controller = new AbortController();
  const api = fakeAnthropic({ afterMessages: () => controller.abort() });
  const { l, events } = ledger();
  await assert.rejects(make(api.provider, l, controller.signal), (e: unknown) => e instanceof ProviderError && e.code === "provider_timeout");
  assert.deepEqual(api.deleted().sort(), ["file_a", "file_b"]);
  assert.ok(events.includes("confirmed:file_a") && events.includes("confirmed:file_b"));
});

test("a deletion Anthropic refuses is not a confirmation: 429, 5xx and no answer stay owed, 404 means already gone", async () => {
  const api = fakeAnthropic({ files: ["f429", "f500", "fnet", "f404", "f200"], deleteAnswers: { f429: 429, f500: 500, fnet: "network", f404: 404 } });
  const { l, events } = ledger();
  await make(api.provider, l);
  assert.deepEqual(events.filter((e) => e.startsWith("failed:")).sort(), ["failed:f429", "failed:f500", "failed:fnet"]);
  assert.deepEqual(events.filter((e) => e.startsWith("confirmed:")).sort(), ["confirmed:f200", "confirmed:f404"]);
});

test("a ledger that can't write doesn't lose the document, and the copies are still deleted", async () => {
  const api = fakeAnthropic();
  const broken: ProviderFileLedger = { track: async () => { throw new Error("db down"); }, confirmed: async () => {}, failed: async () => {} };
  const file = await make(api.provider, broken);
  assert.equal(file.bytes.length > 0, true);
  assert.deepEqual(api.deleted().sort(), ["file_a", "file_b"]);
});

test("deleteFile is checked on its own: the same answers, no ledger needed", async () => {
  const api = fakeAnthropic({ deleteAnswers: { x: 503, y: 404, z: 200 } });
  const s = AbortSignal.timeout(5_000);
  assert.equal(await api.provider.deleteFile("x", s), "failed");
  assert.equal(await api.provider.deleteFile("y", s), "removed");
  assert.equal(await api.provider.deleteFile("z", s), "removed");
});

// ------------------------------------------------------------------ the server: owed, kept, retried

const owed = async (r: Rig) =>
  (await r.store.db.query<{ connection_id: string; state: string; attempts: number; user_id: string }>(
    "SELECT connection_id, state, attempts, user_id FROM cleanups WHERE provider = $1 ORDER BY connection_id", [ANTHROPIC_FILE_CLEANUP])).rows;

test("a document made through the server leaves nothing owed when Anthropic confirms", async () => {
  const api = fakeAnthropic();
  rig = await start({}, { claude: api.provider });
  assert.equal((await run(rig, "make_document", doc("Plan"))).status, 200);
  await rig.tools.settle();
  assert.deepEqual(await owed(rig), []);
  assert.deepEqual(api.deleted().sort(), ["file_a", "file_b"]);
});

test("a deletion that fails stays owed with the person's id, the hourly sweep retries it, and it never ends a job still running", async () => {
  const api = fakeAnthropic({ deleteAnswers: { file_a: 500 } });
  rig = await start({}, { claude: api.provider });
  assert.equal((await run(rig, "make_document", doc("Plan"))).status, 200);
  await rig.tools.settle();
  const left = await owed(rig);
  assert.deepEqual(left.map((r) => [r.connection_id, r.state, r.user_id]), [["file_a", "failed", ID_A]], "ids only, and whose they are");

  // A sweep right away leaves it: a job could still be running.
  const before = api.deleted().length;
  await rig.tools.sweepAbandoned();
  assert.equal(api.deleted().length, before, "too young to be retried");

  // Later, Anthropic is back: the next sweep deletes it and the row goes.
  api.deleteAnswers.file_a = 200;
  rig.clock.advance(DOCUMENT_TIMEOUT_MS + 2 * 60_000);
  await rig.tools.sweepAbandoned();
  assert.deepEqual(await owed(rig), []);
  const line = rig.logs.find((l) => l.includes("document_files_swept"))!;
  assert.ok(line && !line.includes("file_a") && !line.includes(ID_A), "the log has counts only");
});

test("a failure that keeps happening is kept, visible as failed, and given up on after the usual number of tries", async () => {
  const api = fakeAnthropic({ deleteAnswers: { file_a: 429 } });
  rig = await start({}, { claude: api.provider });
  assert.equal((await run(rig, "make_document", doc("Plan"))).status, 200);
  await rig.tools.settle();
  for (let i = 0; i < CLEANUP_RETRY.maxTries + 3; i++) {
    rig.clock.advance(DOCUMENT_TIMEOUT_MS + 2 * 60_000);
    await rig.tools.sweepAbandoned();
  }
  const [row] = await owed(rig);
  assert.equal(row?.state, "failed", "never silently dropped");
  assert.equal(row?.attempts, CLEANUP_RETRY.maxTries);
});

test("a process that died mid-job leaves the ids owed, and the next process's sweep deletes them", async () => {
  const api = fakeAnthropic();
  rig = await start({}, { claude: api.provider });
  // What a crash leaves: the ids written down at the moment they were seen, never deleted, never confirmed.
  const old = rig.clock.ms;
  await rig.store.queueCleanup("file_crashed", ID_A, ANTHROPIC_FILE_CLEANUP, old);
  rig.clock.advance(DOCUMENT_TIMEOUT_MS + 2 * 60_000);
  await rig.tools.sweepAbandoned();
  assert.deepEqual(api.deleted(), ["file_crashed"]);
  assert.deepEqual(await owed(rig), []);
});

test("the sweep leaves other providers' removals alone", async () => {
  const api = fakeAnthropic();
  rig = await start({}, { claude: api.provider });
  await rig.store.queueCleanup("conn_x", ID_A, "gmail", rig.clock.ms - 10 * DOCUMENT_TIMEOUT_MS);
  await rig.store.queueCleanup("file_y", ID_A, ANTHROPIC_FILE_CLEANUP, rig.clock.ms - 10 * DOCUMENT_TIMEOUT_MS);
  await rig.tools.sweepAbandoned();
  assert.ok(!api.deleted().includes("conn_x"), "a connection id is never sent to Anthropic");
  assert.deepEqual(api.deleted(), ["file_y"]);
});

// ------------------------------------------------------------------ erasing the account

test("erasing the account keeps what is owed at Anthropic until it is confirmed, and says so", async () => {
  const api = fakeAnthropic();
  rig = await start({}, { claude: api.provider });
  assert.ok((KEPT_ON_ERASE as readonly string[]).includes("cleanups"));
  assert.ok(!(ERASED_TABLES as readonly string[]).includes("cleanups"));
  await rig.store.queueCleanup("file_a", ID_A, ANTHROPIC_FILE_CLEANUP, rig.clock.ms);
  const eraser = (fail: boolean) =>
    new AccountEraser({
      store: rig!.store,
      removers: [{ providers: [ANTHROPIC_FILE_CLEANUP], remove: (id, s) => (fail ? Promise.resolve("failed" as const) : api.provider.deleteFile(id, s)) }],
      timeoutMs: 1_000,
      now: rig!.clock.now,
    });

  const first = await eraser(true).erase(ID_A);
  assert.equal(first.complete, false, "a copy still at Anthropic is not a finished deletion");
  assert.deepEqual(first.onlineAccounts.pending, [ANTHROPIC_FILE_CLEANUP]);
  assert.equal((await owed(rig)).length, 1, "the account is gone, the obligation is not");

  rig.clock.advance(CLEANUP_RETRY.afterMs + 1);
  await eraser(false).sweep([ANTHROPIC_FILE_CLEANUP]);
  assert.deepEqual(await owed(rig), []);
  assert.deepEqual(api.deleted(), ["file_a"]);
});

test("erasing with a copy owed and Anthropic answering is complete in one go", async () => {
  const api = fakeAnthropic();
  rig = await start({}, { claude: api.provider });
  await rig.store.queueCleanup("file_a", ID_A, ANTHROPIC_FILE_CLEANUP, rig.clock.ms);
  const eraser = new AccountEraser({
    store: rig.store,
    removers: [{ providers: [ANTHROPIC_FILE_CLEANUP], remove: (id, s) => api.provider.deleteFile(id, s) }],
    timeoutMs: 1_000,
    now: rig.clock.now,
  });
  const done = await eraser.erase(ID_A);
  assert.equal(done.complete, true);
  assert.deepEqual(await owed(rig), []);
});
