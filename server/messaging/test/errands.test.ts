// Errands end to end against real Postgres, through the HTTP API, with a fake researcher in place of
// Claude (ADR-563, docs/implementation/ERRANDS.md). Nothing here calls Anthropic or APNs.
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { after, before, beforeEach, describe, test } from "node:test";
import { DEFAULT_ERRAND_SETTINGS, type ErrandSettings } from "../src/config.js";
import type { ErrandContext } from "../src/errands/context.js";
import type { ErrandResearcher, ErrandTask, ResearchControl, ResearchOutcome } from "../src/errands/researcher.js";
import { ErrandResultSchema, resultJson, type ErrandResult } from "../src/errands/schema.js";
import { claimNext, newErrandLoopState, researchNext, runErrandPasses, stopErrandRuns } from "../src/errands/worker.js";
import type { Db } from "../src/db.js";
import { dispatchDue } from "../src/outbox.js";
import { dbSkip, freshDb, testApp, testCipher } from "./helpers.js";

const stats = { usage: { inputTokens: 12000, cacheWriteTokens: 3000, cacheReadTokens: 40000, outputTokens: 2500 }, searches: 7, fetches: 4, model: "claude-opus-5-5" };

function sampleResult(): ErrandResult {
  return ErrandResultSchema.parse({
    answer: "Najlepszy układ: wylot 12.11, powrót 19.11.",
    sections: [{ heading: "Loty", kind: "options", items: [{ title: "Ryanair WAW–CIA", detail: "bezpośredni, 2 h 20 min", when: "12.11–19.11",
      price: "389 zł / os.", url: "https://flights.example/waw-cia", site: "flights.example" }] }],
    recommendation: "Trastevere, Hotel Roma.",
    budget: { asked: "hotele do 2000 zł", within: "yes" },
    next: ["Zawęzić do Trastevere?"],
    sources: [{ title: "Loty", url: "https://flights.example/waw-cia", site: "flights.example" }],
    checkedAt: "2026-10-21T09:12:00.000Z",
  });
}

type Step = (task: ErrandTask, control: ResearchControl) => Promise<ResearchOutcome>;
/** Stands in for Claude: each run takes the next step (default: a finished card). */
class FakeResearcher implements ErrandResearcher {
  readonly provider = "anthropic" as const;
  readonly model = "claude-opus-5-5";
  tasks: ErrandTask[] = [];
  steps: Step[] = [];
  async research(task: ErrandTask, control: ResearchControl): Promise<ResearchOutcome> {
    this.tasks.push(task);
    const step = this.steps.shift();
    return step ? step(task, control) : { kind: "done", result: sampleResult(), ...stats };
  }
}

const words = "chcę jechać do Rzymu w przyszłym miesiącu na 7 dni, sprawdź loty i hotele do 2000 zł";
const body = (over: object = {}) => ({ words, brief: "Loty z Warszawy i hotele w Rzymie, 7 nocy (założenie: z Warszawy).", title: "Rzym w listopadzie", language: "pl", ...over });
const sha = (s: string) => createHash("sha256").update(s, "utf8").digest("hex");

describe("errands against real Postgres", { skip: dbSkip }, () => {
  let db: Db;
  before(async () => { db = await freshDb(); });
  after(async () => { await db?.end(); });
  // The worker claims the oldest queued errand of any account: each test starts with none.
  beforeEach(async () => { await db.query("DELETE FROM errands; DELETE FROM errand_deletions;"); });

  async function world(opts: { settings?: Partial<ErrandSettings>; researcher?: FakeResearcher | null; cipher?: null } = {}) {
    const researcher = opts.researcher === null ? undefined : opts.researcher ?? new FakeResearcher();
    // A little in the past, so queued pushes are already due for the dispatcher (which uses the DB clock).
    const clock = { now: new Date(Date.now() - 3600_000) };
    const logs: { msg: string; extra?: object }[] = [];
    const base = await testApp(db, {
      ...(opts.cipher === null ? { cipher: undefined } : {}),
      errands: { settings: { ...DEFAULT_ERRAND_SETTINGS, ...opts.settings }, researcher, now: () => clock.now, cancelPollMs: 10 },
      errandLog: (msg, extra) => logs.push({ msg, extra }),
    });
    const r = await base.app.inject({ method: "POST", url: "/v1/accounts" });
    const { accountId, deviceToken } = r.json() as { accountId: string; deviceToken: string };
    const h = { authorization: `Bearer ${deviceToken}` };
    const api = (method: "GET" | "POST" | "DELETE" | "PUT", url: string, payload?: unknown, headers: object = h) =>
      base.app.inject({ method, url, headers: headers as Record<string, string>, payload: payload as never });
    return { ...base, researcher: researcher as FakeResearcher | undefined, clock, logs, accountId, h, api, ctx: base.app.errandContext as ErrandContext };
  }
  type World = Awaited<ReturnType<typeof world>>;

  async function handOver(w: World, over: object = {}) {
    const created = await w.api("POST", "/v1/errands", body(over));
    assert.equal(created.statusCode, 201, created.body);
    const draft = created.json() as { id: string; digest: string };
    const approved = await w.api("POST", `/v1/errands/${draft.id}/approve`, { digest: draft.digest });
    assert.equal(approved.statusCode, 202, approved.body);
    return draft;
  }
  const row = async (id: string) => (await db.query("SELECT * FROM errands WHERE id = $1", [id])).rows[0];
  const pushToken = (w: World) => w.api("PUT", "/v1/device/push-token", { token: "ab".repeat(32), environment: "sandbox" });

  test("hand over → approve → research → result → ack: the server's copy is gone, with receipts", async () => {
    const w = await world();
    assert.equal((await pushToken(w)).statusCode, 204);
    const created = await w.api("POST", "/v1/errands", body());
    assert.equal(created.statusCode, 201);
    const draft = created.json();
    assert.equal(draft.words, words, "the user's words come back exactly as given");
    assert.equal(draft.digest, sha(`{"brief":${JSON.stringify(body().brief)},"language":"pl","title":"Rzym w listopadzie","words":${JSON.stringify(words)}}`));
    assert.equal(new Date(draft.expiresAt).getTime() - w.clock.now.getTime(), 10 * 60_000);
    const stored = await row(draft.id);
    assert.equal(stored.state, "draft");
    assert.equal(stored.content_ciphertext.includes(Buffer.from("Rzym")), false, "the words are stored encrypted");
    assert.equal((await w.api("GET", "/v1/errands")).json().errands.length, 0, "drafts are left out of the list");

    const approved = await w.api("POST", `/v1/errands/${draft.id}/approve`, { digest: draft.digest });
    assert.equal(approved.statusCode, 202);
    assert.deepEqual(approved.json(), { id: draft.id, state: "queued" });
    const list = (await w.api("GET", "/v1/errands")).json().errands;
    assert.deepEqual(list.map((e: { title: string; state: string }) => [e.title, e.state]), [["Rzym w listopadzie", "queued"]]);

    w.clock.now = new Date(w.clock.now.getTime() + 5000);
    assert.equal(await researchNext(w.ctx), draft.id);
    assert.equal(w.researcher!.tasks.length, 1);
    assert.deepEqual(w.researcher!.tasks[0], { id: draft.id, words, brief: body().brief, language: "pl" }, "the title isn't sent to the researcher");

    const got = (await w.api("GET", `/v1/errands/${draft.id}`)).json();
    assert.equal(got.state, "done");
    assert.equal(got.words, words);
    assert.equal(got.searches, 7);
    assert.equal(got.fetches, 4);
    assert.deepEqual(got.result, sampleResult());
    assert.equal(got.resultDigest, sha(resultJson(sampleResult())));
    assert.ok(got.startedAt && got.finishedAt && got.approvedAt);
    const done = await row(draft.id);
    assert.equal(Number(done.input_tokens), 12000);
    assert.equal(Number(done.cache_read_tokens), 40000);
    assert.equal(Number(done.output_tokens), 2500);
    assert.equal(done.model, "claude-opus-5-5");
    assert.equal(JSON.stringify(w.logs).includes("Rzym"), false, "logs carry ids and counts, never words");

    // The push says only that a result is waiting.
    await dispatchDue(db, { push: w.push, cipher: testCipher });
    assert.deepEqual(w.push.sent.map((p) => p.body), ["Gotowe. Wynik sprawy czeka w aplikacji."]);

    assert.equal((await w.api("POST", `/v1/errands/${draft.id}/ack`, { resultDigest: "0".repeat(64) })).statusCode, 409);
    const acked = await w.api("POST", `/v1/errands/${draft.id}/ack`, { resultDigest: got.resultDigest });
    assert.equal(acked.statusCode, 200, acked.body);
    const deletions = acked.json().deletions as { what: string; deletedAt: string }[];
    assert.deepEqual(deletions.map((d) => d.what).sort(), ["brief", "result", "title", "words"]);
    const after = (await w.api("GET", `/v1/errands/${draft.id}`)).json();
    for (const k of ["words", "brief", "title", "result", "resultDigest", "digest"]) assert.equal(k in after, false, k);
    assert.equal(after.state, "done");
    assert.ok(after.createdAt && after.finishedAt && after.acknowledgedAt);
    const wiped = await row(draft.id);
    assert.equal(wiped.content_ciphertext, null);
    assert.equal(wiped.result_ciphertext, null);
    // Ack again: same receipts, nothing new.
    const again = await w.api("POST", `/v1/errands/${draft.id}/ack`, { resultDigest: got.resultDigest });
    assert.deepEqual(again.json().deletions, deletions);
    assert.equal((await w.api("GET", "/v1/errands")).json().errands[0].title, null);
    await w.app.close();
  });

  test("approval: only its own digest, only a draft, only within 10 minutes, only the owner", async () => {
    const w = await world();
    const draft = (await w.api("POST", "/v1/errands", body())).json();
    const wrong = await w.api("POST", `/v1/errands/${draft.id}/approve`, { digest: sha("something else") });
    assert.equal(wrong.statusCode, 409);
    assert.equal(wrong.json().error, "digest_mismatch");
    const other = await world();
    assert.equal((await other.api("POST", `/v1/errands/${draft.id}/approve`, { digest: draft.digest })).statusCode, 404);
    assert.equal((await other.api("GET", `/v1/errands/${draft.id}`)).statusCode, 404);
    assert.equal((await w.api("POST", `/v1/errands/${draft.id}/approve`, { digest: draft.digest })).statusCode, 202);
    const twice = await w.api("POST", `/v1/errands/${draft.id}/approve`, { digest: draft.digest });
    assert.deepEqual([twice.statusCode, twice.json()], [409, { error: "not_approvable", state: "queued" }]);

    const late = (await w.api("POST", "/v1/errands", body())).json();
    w.clock.now = new Date(w.clock.now.getTime() + 10 * 60_000 + 1);
    const expired = await w.api("POST", `/v1/errands/${late.id}/approve`, { digest: late.digest });
    assert.deepEqual([expired.statusCode, expired.json()], [409, { error: "not_approvable", state: "expired" }]);
    // The draft is deleted by the next pass.
    await runErrandPasses(w.ctx, newErrandLoopState());
    assert.equal(await row(late.id), undefined);

    for (const bad of [{ digest: "AB".repeat(32) }, { digest: draft.digest, extra: 1 }, {}]) {
      assert.equal((await w.api("POST", `/v1/errands/${draft.id}/approve`, bad)).statusCode, 400);
    }
    assert.equal((await w.api("POST", "/v1/errands", body({ words: "x".repeat(1001) }))).statusCode, 400);
    assert.equal((await w.api("POST", "/v1/errands", body({ title: "" }))).statusCode, 400);
    assert.equal((await w.api("POST", "/v1/errands", body(), {})).statusCode, 401);
    await w.app.close();
    await other.app.close();
  });

  test("at most ERRANDS_MAX_OPEN queued or running errands per account", async () => {
    const w = await world({ settings: { maxOpen: 2 } });
    const a = await handOver(w);
    const b = await handOver(w);
    const third = (await w.api("POST", "/v1/errands", body())).json();
    const refused = await w.api("POST", `/v1/errands/${third.id}/approve`, { digest: third.digest });
    assert.deepEqual([refused.statusCode, refused.json()], [409, { error: "too_many_open_errands" }]);
    // One finishes: there is room again.
    assert.ok([a.id, b.id].includes((await researchNext(w.ctx))!));
    assert.equal((await w.api("POST", `/v1/errands/${third.id}/approve`, { digest: third.digest })).statusCode, 202);
    await w.app.close();
  });

  test("switched off or not set up: 503 errands_disabled and nothing stored", async () => {
    const count = async () => (await db.query<{ n: number }>("SELECT count(*)::int AS n FROM errands")).rows[0]!.n;
    const before = await count();
    for (const opts of [{ researcher: null }, { settings: { enabled: false } }, { cipher: null }] as const) {
      const w = await world(opts);
      const r = await w.api("POST", "/v1/errands", body());
      assert.deepEqual([r.statusCode, r.json()], [503, { error: "errands_disabled" }], JSON.stringify(opts));
      if (opts !== undefined && "cipher" in opts) assert.equal((await w.api("GET", "/v1/errands")).statusCode, 503);
      await w.app.close();
    }
    assert.equal(await count(), before);

    // Switched off after approval: the queued errand waits and starts nothing.
    const on = await world();
    const queued = await handOver(on);
    const off = await world({ settings: { enabled: false } });
    assert.equal(await researchNext(off.ctx), undefined);
    await runErrandPasses(off.ctx, newErrandLoopState());
    assert.equal((await row(queued.id)).state, "queued");
    assert.equal(off.researcher!.tasks.length, 0);
    await on.api("POST", `/v1/errands/${queued.id}/cancel`);
    await on.app.close();
    await off.app.close();
  });

  test("cancel: a queued errand never starts; a running one stops at its next step; nothing is pushed", async () => {
    const w = await world();
    await pushToken(w);
    const q = await handOver(w);
    assert.equal((await w.api("POST", `/v1/errands/${q.id}/cancel`)).statusCode, 204);
    assert.equal((await w.api("POST", `/v1/errands/${q.id}/cancel`)).statusCode, 204, "again is fine");
    assert.equal(await researchNext(w.ctx), undefined);
    assert.equal(w.researcher!.tasks.length, 0);
    assert.equal((await w.api("GET", `/v1/errands/${q.id}`)).json().state, "cancelled");

    // A running errand: the fake waits for the Cancel the way the real runner polls for it.
    const r = await handOver(w);
    w.researcher!.steps.push(async (_task, control) => {
      for (let i = 0; i < 500 && !(await control.isCancelled()); i++) await new Promise((res) => setTimeout(res, 5));
      return { kind: "cancelled", ...stats };
    });
    const state = newErrandLoopState();
    await runErrandPasses(w.ctx, state);
    assert.equal((await row(r.id)).state, "running");
    assert.equal((await w.api("POST", `/v1/errands/${r.id}/cancel`)).statusCode, 204);
    assert.equal((await w.api("GET", `/v1/errands/${r.id}`)).json().cancelRequested, true);
    await Promise.all(state.runs.values());
    const e = (await w.api("GET", `/v1/errands/${r.id}`)).json();
    assert.equal(e.state, "cancelled");
    assert.equal(e.words, words, "the words stay until deleted");
    await dispatchDue(db, { push: w.push, cipher: testCipher });
    assert.equal(w.push.sent.length, 0);

    // A result that arrives after Cancel isn't kept.
    const late = await handOver(w);
    w.researcher!.steps.push(async () => {
      await db.query("UPDATE errands SET cancel_requested_at = now() WHERE id = $1", [late.id]);
      return { kind: "done", result: sampleResult(), ...stats };
    });
    await researchNext(w.ctx);
    const lateRow = await row(late.id);
    assert.equal(lateRow.state, "cancelled");
    assert.equal(lateRow.result_ciphertext, null);

    // Finished errands can't be cancelled; a draft is simply deleted.
    const done = await handOver(w);
    await researchNext(w.ctx);
    const refused = await w.api("POST", `/v1/errands/${done.id}/cancel`);
    assert.deepEqual([refused.statusCode, refused.json()], [409, { error: "not_cancellable", state: "done" }]);
    const draft = (await w.api("POST", "/v1/errands", body())).json();
    assert.equal((await w.api("POST", `/v1/errands/${draft.id}/cancel`)).statusCode, 204);
    assert.equal((await w.api("GET", `/v1/errands/${draft.id}`)).statusCode, 404);
    assert.equal((await w.api("POST", `/v1/errands/${q.id}/cancel`, { reason: "x" })).statusCode, 400);
    await w.app.close();
  });

  test("a failed run: its code, a push with no words in the errand's language, words kept until deleted", async () => {
    const w = await world();
    await pushToken(w);
    const pl = await handOver(w);
    w.researcher!.steps.push(async () => ({ kind: "failed", code: "time_limit", ...stats }));
    await researchNext(w.ctx);
    const en = await handOver(w, { language: "en", words: "find flights to Rome", title: "Rome" });
    w.researcher!.steps.push(async () => ({ kind: "failed", code: "refused", ...stats }));
    await researchNext(w.ctx);
    const got = (await w.api("GET", `/v1/errands/${pl.id}`)).json();
    assert.equal(got.state, "failed");
    assert.equal(got.failure, "time_limit");
    assert.equal("result" in got, false);
    assert.equal(got.words, words);
    assert.equal((await w.api("GET", `/v1/errands/${en.id}`)).json().failure, "refused");
    const ack = await w.api("POST", `/v1/errands/${pl.id}/ack`, { resultDigest: "0".repeat(64) });
    assert.deepEqual([ack.statusCode, ack.json()], [409, { error: "no_result", state: "failed" }]);
    await dispatchDue(db, { push: w.push, cipher: testCipher });
    assert.deepEqual(w.push.sent.map((p) => p.body).sort(), ["Doddy couldn't finish a task.", "Nie udało się dokończyć sprawy."]);
    await w.app.close();
  });

  test("a worker that died mid-run: failed interrupted after the time limit + 5 minutes, never re-run", async () => {
    const w = await world({ settings: { timeLimitMinutes: 30 } });
    await pushToken(w);
    const e = await handOver(w);
    const claimed = await claimNext(w.ctx); // the worker claims it, then dies
    assert.equal(claimed?.id, e.id);
    w.clock.now = new Date(w.clock.now.getTime() + 34 * 60_000);
    await runErrandPasses(w.ctx, newErrandLoopState());
    assert.equal((await row(e.id)).state, "running", "not before the grace period");
    w.clock.now = new Date(w.clock.now.getTime() + 2 * 60_000);
    const state = newErrandLoopState();
    const counts = await runErrandPasses(w.ctx, state);
    assert.equal(counts.interrupted, 1);
    assert.equal(state.runs.size, 0, "nothing re-run");
    const got = (await w.api("GET", `/v1/errands/${e.id}`)).json();
    assert.deepEqual([got.state, got.failure], ["failed", "interrupted"]);
    assert.equal(await researchNext(w.ctx), undefined);
    assert.equal(w.researcher!.tasks.length, 0);
    await dispatchDue(db, { push: w.push, cipher: testCipher });
    assert.deepEqual(w.push.sent.map((p) => p.body), ["Nie udało się dokończyć sprawy."]);

    // The same with a Cancel pending: it ends cancelled, no push.
    const c = await handOver(w);
    await claimNext(w.ctx);
    await w.api("POST", `/v1/errands/${c.id}/cancel`);
    w.clock.now = new Date(w.clock.now.getTime() + 36 * 60_000);
    await runErrandPasses(w.ctx, newErrandLoopState());
    assert.equal((await row(c.id)).state, "cancelled");
    await w.app.close();
  });

  test("shutdown stops running errands as interrupted right away", async () => {
    const w = await world();
    const e = await handOver(w);
    w.researcher!.steps.push((_t, control) => new Promise((resolve) => {
      control.signal!.addEventListener("abort", () => resolve({ kind: "failed", code: "interrupted", ...stats }));
    }));
    const state = newErrandLoopState();
    await runErrandPasses(w.ctx, state);
    assert.equal(state.runs.size, 1);
    await stopErrandRuns(state);
    assert.deepEqual([(await row(e.id)).state, (await row(e.id)).failure], ["failed", "interrupted"]);
    await w.app.close();
  });

  test("up to three runs at once in one process; the rest wait their turn", async () => {
    const w = await world();
    const ids: string[] = [];
    for (let i = 0; i < 4; i++) ids.push((await handOver(w)).id);
    const release: (() => void)[] = [];
    for (let i = 0; i < 4; i++) {
      w.researcher!.steps.push(() => new Promise((resolve) => release.push(() => resolve({ kind: "done", result: sampleResult(), ...stats }))));
    }
    const state = newErrandLoopState();
    assert.equal((await runErrandPasses(w.ctx, state)).started, 3);
    const states = async () => (await db.query<{ state: string }>("SELECT state FROM errands WHERE id = ANY($1) ORDER BY state", [ids])).rows.map((r) => r.state);
    assert.deepEqual(await states(), ["queued", "running", "running", "running"]);
    while (release.length < 3) await new Promise((r) => setTimeout(r, 5));
    release.splice(0).forEach((f) => f());
    await Promise.all(state.runs.values());
    assert.equal((await runErrandPasses(w.ctx, state)).started, 1);
    while (release.length < 1) await new Promise((r) => setTimeout(r, 5));
    release.splice(0).forEach((f) => f());
    await Promise.all(state.runs.values());
    for (const id of ids) assert.equal((await row(id)).state, "done");
    await w.app.close();
  });

  test("only exactly what was approved runs: a changed digest stops the run", async () => {
    const w = await world();
    const e = await handOver(w);
    await db.query("UPDATE errands SET payload_digest = $2 WHERE id = $1", [e.id, Buffer.alloc(32, 1)]);
    await researchNext(w.ctx);
    assert.equal(w.researcher!.tasks.length, 0);
    assert.deepEqual([(await row(e.id)).state, (await row(e.id)).failure], ["failed", "interrupted"]);
    await w.app.close();
  });

  test("results never acknowledged are deleted after 30 days, with receipts; DELETE removes the row", async () => {
    const w = await world();
    const e = await handOver(w);
    await researchNext(w.ctx);
    w.clock.now = new Date(w.clock.now.getTime() + 29 * 24 * 3600_000);
    await runErrandPasses(w.ctx, newErrandLoopState());
    assert.ok((await w.api("GET", `/v1/errands/${e.id}`)).json().result);
    w.clock.now = new Date(w.clock.now.getTime() + 2 * 24 * 3600_000);
    assert.equal((await runErrandPasses(w.ctx, newErrandLoopState())).unacked, 1);
    const got = (await w.api("GET", `/v1/errands/${e.id}`)).json();
    assert.equal(got.state, "done");
    assert.equal("result" in got || "words" in got, false);
    const { rows: receipts } = await db.query("SELECT item, reason FROM errand_deletions WHERE errand_id = $1 ORDER BY item", [e.id]);
    assert.deepEqual(receipts, ["brief", "result", "title", "words"].map((item) => ({ item, reason: "expired" })));

    const d = await handOver(w);
    assert.equal((await w.api("DELETE", `/v1/errands/${d.id}`)).statusCode, 204);
    assert.equal((await w.api("GET", `/v1/errands/${d.id}`)).statusCode, 404);
    assert.equal((await w.api("DELETE", `/v1/errands/${d.id}`)).statusCode, 404);
    const { rows: gone } = await db.query("SELECT item, reason FROM errand_deletions WHERE errand_id = $1 ORDER BY item", [d.id]);
    assert.deepEqual(gone, ["brief", "title", "words"].map((item) => ({ item, reason: "deleted" })));
    assert.equal(await researchNext(w.ctx), undefined, "a deleted errand never runs");
    await w.app.close();
  });

  test("a running errand deleted mid-run stores nothing and pushes nothing", async () => {
    const w = await world();
    await pushToken(w);
    const e = await handOver(w);
    w.researcher!.steps.push(async (_t, control) => {
      await w.api("DELETE", `/v1/errands/${e.id}`);
      assert.equal(await control.isCancelled(), true, "the runner sees the errand is gone");
      return { kind: "done", result: sampleResult(), ...stats };
    });
    await researchNext(w.ctx);
    assert.equal(await row(e.id), undefined);
    await dispatchDue(db, { push: w.push, cipher: testCipher });
    assert.equal(w.push.sent.length, 0);
    await w.app.close();
  });

  test("deleting the account deletes its errands and receipts", async () => {
    const w = await world();
    const e = await handOver(w);
    await researchNext(w.ctx);
    const digest = (await w.api("GET", `/v1/errands/${e.id}`)).json().resultDigest;
    await w.api("POST", `/v1/errands/${e.id}/ack`, { resultDigest: digest });
    await handOver(w);
    assert.equal((await w.api("DELETE", "/v1/account")).statusCode, 204);
    const n = async (sql: string) => (await db.query<{ n: number }>(sql, [w.accountId])).rows[0]!.n;
    assert.equal(await n("SELECT count(*)::int AS n FROM errands WHERE account_id = $1"), 0);
    assert.equal(await n("SELECT count(*)::int AS n FROM errand_deletions WHERE account_id = $1"), 0);
    await w.app.close();
  });

  test("the table refuses states the code must never write", async () => {
    const w = await world();
    const e = await handOver(w);
    const refuse = async (sql: string) => assert.rejects(db.query(sql, [e.id]), /violates check constraint/, sql);
    await refuse("UPDATE errands SET state = 'done', finished_at = now() WHERE id = $1"); // done without a result
    await refuse("UPDATE errands SET state = 'failed', finished_at = now() WHERE id = $1"); // failed without a code
    await refuse("UPDATE errands SET content_ciphertext = NULL, content_key_version = NULL, content_deleted_at = now() WHERE id = $1"); // queued without its words
    await refuse("UPDATE errands SET failure = 'time_limit' WHERE id = $1"); // a code on a queued errand
    await refuse("UPDATE errands SET state = 'draft' WHERE id = $1"); // a draft with an approval
    await w.app.close();
  });
});
