// Studio end to end against real Postgres, through the HTTP API, with a fake Claude (ADR-584,
// docs/implementation/STUDIO.md). Nothing here calls Anthropic or APNs.
import assert from "node:assert/strict";
import { after, before, beforeEach, describe, test } from "node:test";
import type { Db } from "../src/db.js";
import { dispatchDue } from "../src/outbox.js";
import { DEFAULT_STUDIO_SETTINGS, type StudioContext, type StudioSettings } from "../src/studio/context.js";
import { claimNext, newStudioLoopState, reapInterrupted, runNext, runStudioPasses, stopStudioRuns, tidyAnthropicFiles } from "../src/studio/worker.js";
import { dbSkip, freshDb, testApp, testCipher } from "./helpers.js";
import { content, FakeStudioApi, goodFiles, job, png } from "./studioFakes.js";

describe("studio against real Postgres", { skip: dbSkip }, () => {
  let db: Db;
  before(async () => { db = await freshDb(); });
  after(async () => { await db?.end(); });
  beforeEach(async () => { await db.query("DELETE FROM studio_items; DELETE FROM studio_orphan_files;"); });

  async function world(opts: { settings?: Partial<StudioSettings>; api?: FakeStudioApi | null } = {}) {
    const api = opts.api === null ? undefined : opts.api ?? new FakeStudioApi();
    const clock = { now: new Date(Date.now() - 3600_000) };
    const logs: { msg: string; extra?: object }[] = [];
    const base = await testApp(db, {
      studio: { settings: { ...DEFAULT_STUDIO_SETTINGS, ...opts.settings }, api, now: () => clock.now, cancelPollMs: 10 },
      studioLog: (msg, extra) => logs.push({ msg, extra }),
    });
    const r = await base.app.inject({ method: "POST", url: "/v1/accounts" });
    const { accountId, deviceToken } = r.json() as { accountId: string; deviceToken: string };
    const h = { authorization: `Bearer ${deviceToken}` };
    const call = (method: "GET" | "POST" | "DELETE" | "PUT", url: string, payload?: unknown, headers: object = h) =>
      base.app.inject({ method, url, headers: headers as Record<string, string>, payload: payload as never });
    return { ...base, api, clock, logs, accountId, h, call, ctx: base.app.studioContext as StudioContext };
  }
  type World = Awaited<ReturnType<typeof world>>;

  async function approveJob(w: World, body: object = job) {
    const created = await w.call("POST", "/v1/studio", body);
    assert.equal(created.statusCode, 201, created.body);
    const draft = created.json() as { id: string; digest: string };
    const approved = await w.call("POST", `/v1/studio/${draft.id}/approve`, { digest: draft.digest });
    assert.equal(approved.statusCode, 202, approved.body);
    return draft;
  }
  const row = async (id: string) => (await db.query("SELECT * FROM studio_items WHERE id = $1", [id])).rows[0];

  test("make → approve → run → ready: files stored encrypted, read back, served; a push with no words", async () => {
    const w = await world();
    assert.equal((await w.call("PUT", "/v1/device/push-token", { token: "ab".repeat(32), environment: "sandbox" })).statusCode, 204);
    const created = await w.call("POST", "/v1/studio", job);
    assert.equal(created.statusCode, 201);
    const draft = created.json();
    assert.deepEqual(draft.job, job, "the job comes back exactly as given");
    assert.equal((await row(draft.id)).job_ciphertext.includes(Buffer.from("Pompy")), false, "stored encrypted");
    assert.equal((await w.call("GET", "/v1/studio")).json().items.length, 0, "drafts aren't listed");
    assert.equal((await w.call("GET", `/v1/studio/${draft.id}`)).statusCode, 404, "a draft isn't an item yet");

    assert.equal((await w.call("POST", `/v1/studio/${draft.id}/approve`, { digest: "0".repeat(64) })).json().error, "digest_mismatch");
    assert.equal((await w.call("POST", `/v1/studio/${draft.id}/approve`, { digest: draft.digest })).statusCode, 202);
    assert.equal((await w.call("GET", "/v1/studio")).json().items[0].state, "queued");

    w.clock.now = new Date(w.clock.now.getTime() + 5000);
    assert.equal(await runNext(w.ctx), draft.id);
    const item = (await w.call("GET", `/v1/studio/${draft.id}`)).json();
    assert.equal(item.state, "ready", JSON.stringify(item).slice(0, 400));
    assert.equal(item.title, "Pompy ciepła w Polsce");
    assert.deepEqual(item.job, job);
    assert.equal(item.summary.confidence, "medium");
    assert.equal(item.summary.altText, content().infographic.altText, "the alt text reaches the app for VoiceOver");
    assert.equal(item.sources.length, 3);
    assert.ok(item.checks.every((c: { passed: boolean }) => c.passed));
    assert.deepEqual(item.files.map((f: { name: string }) => f.name), ["brief.pdf", "infographic-a4.png", "infographic.png", "infographic.svg"]);
    assert.ok(item.cost.usd > 0 && item.cost.searches === 3);
    assert.equal(item.model, "claude-opus-5-5");

    const files = await db.query("SELECT name, ciphertext FROM studio_files WHERE item_id = $1", [draft.id]);
    assert.equal(files.rows.find((f) => f.name === "infographic.svg")!.ciphertext.includes(Buffer.from("<svg")), false, "files stored encrypted");
    const pngFile = await w.call("GET", `/v1/studio/${draft.id}/files/infographic.png`);
    assert.equal(pngFile.statusCode, 200);
    assert.equal(pngFile.headers["content-type"], "image/png");
    assert.equal(pngFile.headers["cache-control"], "private, no-store");
    assert.deepEqual(pngFile.rawPayload, png(1080, 1350));
    const svg = await w.call("GET", `/v1/studio/${draft.id}/files/infographic.svg`);
    assert.match(String(svg.headers["content-security-policy"]), /sandbox/);
    assert.equal((await w.call("GET", `/v1/studio/${draft.id}/files/notes.txt`)).statusCode, 404);
    assert.equal(JSON.stringify(w.logs).includes("Pompy"), false, "logs carry ids and counts, never words");

    await dispatchDue(db, { push: w.push, cipher: testCipher });
    assert.deepEqual(w.push.sent.map((p) => p.body), ["Gotowe. Twój materiał czeka w Studiu."]);
    const list = (await w.call("GET", "/v1/studio")).json().items;
    assert.deepEqual(list.map((i: { title: string; state: string }) => [i.title, i.state]), [["Pompy ciepła w Polsce", "ready"]]);
    assert.ok(list[0].costUsd > 0);
  });

  test("another account can't see, download, cancel or delete it", async () => {
    const w = await world();
    const draft = await approveJob(w);
    await runNext(w.ctx);
    const other = (await w.app.inject({ method: "POST", url: "/v1/accounts" })).json() as { deviceToken: string };
    const oh = { authorization: `Bearer ${other.deviceToken}` };
    assert.equal((await w.call("GET", `/v1/studio/${draft.id}`, undefined, oh)).statusCode, 404);
    assert.equal((await w.call("GET", `/v1/studio/${draft.id}/files/brief.pdf`, undefined, oh)).statusCode, 404);
    assert.equal((await w.call("DELETE", `/v1/studio/${draft.id}`, undefined, oh)).statusCode, 404);
    assert.equal((await w.call("POST", `/v1/studio/${draft.id}/cancel`, undefined, oh)).statusCode, 404);
    assert.equal((await w.call("GET", "/v1/studio", undefined, oh)).json().items.length, 0);
    assert.equal((await w.call("GET", "/v1/studio", undefined, {})).statusCode, 401);
  });

  test("delete removes the item and its files and says so only after reading back; pending copies go on being deleted", async () => {
    const api = new FakeStudioApi();
    api.stubborn.add("file_1");
    const w = await world({ api });
    const draft = await approveJob(w);
    await runNext(w.ctx);
    assert.deepEqual((await row(draft.id)).anthropic_files_pending, ["file_1"]);
    const del = await w.call("DELETE", `/v1/studio/${draft.id}`);
    assert.equal(del.statusCode, 200, del.body);
    assert.deepEqual(del.json(), { deleted: true, files: 4, anthropicFiles: { pending: 1 } });
    assert.equal((await db.query("SELECT 1 FROM studio_files WHERE item_id = $1", [draft.id])).rowCount, 0);
    assert.equal((await w.call("GET", `/v1/studio/${draft.id}`)).statusCode, 404);
    assert.deepEqual((await db.query("SELECT file_id FROM studio_orphan_files")).rows.map((r) => r.file_id), ["file_1"]);
    assert.equal(await tidyAnthropicFiles(w.ctx), 0, "still not gone");
    api.stubborn.delete("file_1");
    assert.equal(await tidyAnthropicFiles(w.ctx), 1);
    assert.equal((await db.query("SELECT 1 FROM studio_orphan_files")).rowCount, 0);
    assert.equal((await w.call("DELETE", `/v1/studio/${draft.id}`)).statusCode, 404);
  });

  test("checks that fail twice store the item as needs_look with its checks, never ready", async () => {
    const api = new FakeStudioApi();
    const bad = { ...goodFiles(content()), "infographic.png": png(10, 10) };
    api.makes.push({ files: bad }, { files: bad });
    const w = await world({ api });
    const draft = await approveJob(w);
    await runNext(w.ctx);
    const item = (await w.call("GET", `/v1/studio/${draft.id}`)).json();
    assert.equal(item.state, "needs_look");
    assert.ok(item.checks.some((c: { name: string; passed: boolean }) => c.name === "png_phone_size" && !c.passed));
    assert.equal(item.files.length, 4, "kept so the owner can look");
  });

  test("a failed job keeps no files and says why; a refusal is refused", async () => {
    const api = new FakeStudioApi();
    api.plans.push({ kind: "refused", usage: {} });
    const w = await world({ api });
    const draft = await approveJob(w);
    await runNext(w.ctx);
    const item = (await w.call("GET", `/v1/studio/${draft.id}`)).json();
    assert.equal(item.state, "failed");
    assert.equal(item.failure, "refused");
    assert.deepEqual(item.files, []);
  });

  test("the daily cap and the open-job limit are checked at approve, with a reserve per open job", async () => {
    const w = await world({ settings: { dailyCapUsd: 2.5, maxOpen: 3 } });
    await approveJob(w);
    await approveJob(w);
    const third = (await w.call("POST", "/v1/studio", job)).json();
    const refused = await w.call("POST", `/v1/studio/${third.id}/approve`, { digest: third.digest });
    assert.equal(refused.statusCode, 409);
    assert.deepEqual(refused.json(), { error: "daily_cap_reached", capUsd: 2.5, spentUsd: 0 });
    await db.query("UPDATE studio_items SET state = 'ready', stage = NULL, started_at = approved_at, finished_at = approved_at, cost_usd = 1.25, result_key_version = 1, result_ciphertext = '\\x00' WHERE state = 'queued'");
    // Spent 2.50 today on two finished jobs: no room for another reserve.
    const again = await w.call("POST", `/v1/studio/${third.id}/approve`, { digest: third.digest });
    assert.deepEqual(again.json(), { error: "daily_cap_reached", capUsd: 2.5, spentUsd: 2.5 });

    const roomy = await world({ settings: { dailyCapUsd: 100, maxOpen: 1 } });
    await approveJob(roomy);
    const next = (await roomy.call("POST", "/v1/studio", job)).json();
    assert.equal((await roomy.call("POST", `/v1/studio/${next.id}/approve`, { digest: next.digest })).json().error, "too_many_open_items");
  });

  test("a draft expires after 10 minutes; off, unconfigured or without skills answers 503", async () => {
    const w = await world();
    const draft = (await w.call("POST", "/v1/studio", job)).json();
    w.clock.now = new Date(w.clock.now.getTime() + 10 * 60_000 + 1);
    const late = await w.call("POST", `/v1/studio/${draft.id}/approve`, { digest: draft.digest });
    assert.deepEqual(late.json(), { error: "not_approvable", state: "expired" });
    assert.equal((await w.call("POST", "/v1/studio", { ...job, extra: 1 })).statusCode, 400);

    const off = await world({ settings: { enabled: false } });
    assert.equal((await off.call("POST", "/v1/studio", job)).json().error, "studio_disabled");
    const noApi = await world({ api: null });
    assert.equal((await noApi.call("POST", "/v1/studio", job)).statusCode, 503);
    const noSkills = new FakeStudioApi();
    (noSkills as { skills: unknown[] }).skills = [];
    assert.equal((await (await world({ api: noSkills })).call("POST", "/v1/studio", job)).statusCode, 503);
  });

  test("cancel: a queued job never starts; a running one stops at its next step and keeps no files", async () => {
    const w = await world();
    const queued = await approveJob(w);
    assert.equal((await w.call("POST", `/v1/studio/${queued.id}/cancel`)).statusCode, 204);
    assert.equal((await w.call("GET", `/v1/studio/${queued.id}`)).json().state, "cancelled");
    assert.equal(await runNext(w.ctx), undefined);

    const api = w.api!;
    const running = await approveJob(w);
    api.onCall = async (step) => {
      if (step === "write") await w.call("POST", `/v1/studio/${running.id}/cancel`);
    };
    await runNext(w.ctx);
    const item = (await w.call("GET", `/v1/studio/${running.id}`)).json();
    assert.equal(item.state, "cancelled");
    assert.deepEqual(item.files, []);
  });

  test("a worker that died mid-run is reaped as interrupted and never re-run; the loop runs queued jobs", async () => {
    const w = await world({ settings: { timeLimitMinutes: 20 } });
    const draft = await approveJob(w);
    assert.ok(await claimNext(w.ctx));
    w.clock.now = new Date(w.clock.now.getTime() + 26 * 60_000);
    assert.equal(await reapInterrupted(w.ctx), 1);
    const item = (await w.call("GET", `/v1/studio/${draft.id}`)).json();
    assert.equal(item.state, "failed");
    assert.equal(item.failure, "interrupted");

    const loop = await world();
    const queued = await approveJob(loop);
    const state = newStudioLoopState();
    await runStudioPasses(loop.ctx, state);
    await Promise.all(state.runs.values());
    await stopStudioRuns(state);
    assert.equal((await loop.call("GET", `/v1/studio/${queued.id}`)).json().state, "ready");
  });

  test("deleting the account keeps track of copies still at Anthropic", async () => {
    const api = new FakeStudioApi();
    api.stubborn.add("file_2");
    const w = await world({ api });
    await approveJob(w);
    await runNext(w.ctx);
    assert.equal((await w.call("DELETE", "/v1/account")).statusCode, 204);
    assert.equal((await db.query("SELECT 1 FROM studio_items")).rowCount, 0);
    assert.deepEqual((await db.query("SELECT file_id FROM studio_orphan_files")).rows.map((r) => r.file_id), ["file_2"]);
  });
});
