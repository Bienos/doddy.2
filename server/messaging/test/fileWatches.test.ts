// File-ready pushes against real Postgres, through the HTTP route and the worker pass, with a fake backend in place of
// Doddy's document links and a clock the test moves. Nothing here reaches the network, Apple or Anthropic.
import assert from "node:assert/strict";
import { after, before, beforeEach, describe, test } from "node:test";
import type { Db } from "../src/db.js";
import { CHECK_EVERY_MS, MAX_OPEN_WATCHES, PUSH_TEXT, runFileWatchPass, watchedLink, WATCH_FOR_MS, type FileWatchContext } from "../src/fileWatches.js";
import { bodyAad } from "../src/outbox.js";
import { dbSkip, freshDb, testApp, testCipher } from "./helpers.js";

const ORIGIN = "https://doddy.example";
const id = (n: number) => String(n).padStart(24, "a");
const link = (n: number, sig = "S".repeat(43)) => `${ORIGIN}/v1/documents/${id(n)}?exp=1900000000&sig=${sig}`;

describe("watchedLink: only a Doddy document link on the configured origin", () => {
  test("accepts one and rebuilds it from its parts", () => {
    assert.deepEqual(watchedLink(ORIGIN, link(1) + "&status=1&x=y"), { documentId: id(1), link: link(1) });
  });
  test("refuses another host, scheme, path, credentials, a fragment or a missing signature", () => {
    for (const bad of [
      `https://evil.example/v1/documents/${id(1)}?exp=1&sig=${"S".repeat(43)}`,
      `http://doddy.example/v1/documents/${id(1)}?exp=1&sig=${"S".repeat(43)}`,
      `${ORIGIN}/v1/other/${id(1)}?exp=1&sig=${"S".repeat(43)}`,
      `${ORIGIN}/v1/documents/short?exp=1&sig=${"S".repeat(43)}`,
      `https://a:b@doddy.example/v1/documents/${id(1)}?exp=1&sig=${"S".repeat(43)}`,
      `${link(1)}#frag`,
      `${ORIGIN}/v1/documents/${id(1)}?exp=1`,
      `${ORIGIN}/v1/documents/${id(1)}?exp=x&sig=${"S".repeat(43)}`,
      "not a url",
    ]) assert.equal(watchedLink(ORIGIN, bad), null, bad);
  });
});

describe("file-ready pushes against real Postgres", { skip: dbSkip }, () => {
  let db: Db;
  before(async () => { db = await freshDb(); });
  after(async () => { await db?.end(); });
  beforeEach(async () => { await db.query("DELETE FROM file_watches; DELETE FROM outbound_messages;"); });

  async function world() {
    const clock = { now: new Date(Math.floor(Date.now() / 1000) * 1000 - 3_600_000) };
    const asked: string[] = [];
    const backend = new Map<string, { code: number; body: unknown } | "down">();
    const fetcher = (async (url: string | URL | Request) => {
      const u = String(url);
      asked.push(u);
      const reply = backend.get(new URL(u).pathname.split("/").pop()!) ?? { code: 404, body: { status: "gone" } };
      if (reply === "down") throw new Error("connection refused");
      return new Response(JSON.stringify(reply.body), { status: reply.code, headers: { "content-type": "application/json" } });
    }) as typeof fetch;
    const base = await testApp(db, { fileWatches: { origin: ORIGIN, fetcher, now: () => clock.now } });
    const created = await base.app.inject({ method: "POST", url: "/v1/accounts" });
    const { accountId, deviceToken } = created.json() as { accountId: string; deviceToken: string };
    const h = { authorization: `Bearer ${deviceToken}` };
    const ctx = base.app.fileWatchContext as FileWatchContext;
    const api = (payload: unknown, headers: Record<string, string> = h) =>
      base.app.inject({ method: "POST", url: "/v1/file-watches", headers, payload: payload as never });
    const pushToken = () => base.app.inject({ method: "PUT", url: "/v1/device/push-token", headers: h, payload: { token: "ab".repeat(32), environment: "sandbox" } });
    const tick = (ms = CHECK_EVERY_MS + 1) => { clock.now = new Date(clock.now.getTime() + ms); return runFileWatchPass(ctx); };
    async function queued(): Promise<string[]> {
      const { rows } = await db.query<{ id: string; body_ciphertext: Buffer }>(
        "SELECT id, body_ciphertext FROM outbound_messages WHERE account_id = $1 ORDER BY send_at, id", [accountId]);
      return rows.map((r) => testCipher.decrypt(r.body_ciphertext, bodyAad(accountId, r.id)));
    }
    return { ...base, clock, asked, backend, accountId, h, api, pushToken, tick, queued, ctx };
  }

  test("a file that finishes sends exactly one push with a fixed sentence, and never asks again", async () => {
    const w = await world();
    assert.ok([200, 204].includes((await w.pushToken()).statusCode));
    const r = await w.api({ url: link(1), language: "en" });
    assert.equal(r.statusCode, 201, r.body);
    w.backend.set(id(1), { code: 200, body: { status: "working" } });
    assert.deepEqual(await w.tick(), {});
    assert.deepEqual(await w.queued(), []);
    w.backend.set(id(1), { code: 200, body: { status: "ready" } });
    assert.deepEqual(await w.tick(), { ready: 1 });
    assert.deepEqual(await w.queued(), [PUSH_TEXT.ready.en]);
    assert.ok(w.asked.every((u) => u.endsWith("&status=1") && u.startsWith(`${ORIGIN}/v1/documents/`)));
    const before = w.asked.length;
    assert.deepEqual(await w.tick(), {});
    assert.equal(w.asked.length, before, "a finished watch is not asked about again");
    assert.deepEqual(await w.queued(), [PUSH_TEXT.ready.en], "one push only");
  });

  test("Polish accounts get the Polish sentence; a failed file gets the failure sentence", async () => {
    const w = await world();
    await w.pushToken();
    await w.api({ url: link(2), language: "pl" });
    w.backend.set(id(2), { code: 200, body: { status: "failed" } });
    assert.deepEqual(await w.tick(), { failed: 1 });
    assert.deepEqual(await w.queued(), [PUSH_TEXT.failed.pl]);
  });

  test("no device that can receive pushes: the watch ends quietly and nothing is queued", async () => {
    const w = await world();
    await w.api({ url: link(3), language: "en" });
    w.backend.set(id(3), { code: 200, body: { status: "ready" } });
    assert.deepEqual(await w.tick(), { ready: 1 });
    assert.deepEqual(await w.queued(), []);
  });

  test("an unreachable backend is asked again; a file that never finishes is dropped without a push", async () => {
    const w = await world();
    await w.pushToken();
    await w.api({ url: link(4), language: "en" });
    w.backend.set(id(4), "down");
    assert.deepEqual(await w.tick(), {});
    w.backend.set(id(4), { code: 200, body: { status: "ready" } });
    assert.deepEqual(await w.tick(), { ready: 1 }, "it recovered, so the push goes");
    await w.api({ url: link(5), language: "en" });
    w.backend.set(id(5), { code: 200, body: { status: "working" } });
    assert.deepEqual(await w.tick(WATCH_FOR_MS + 1), { dropped: 1 });
    assert.deepEqual((await w.queued()).length, 1);
  });

  test("a link that is gone ends the watch without a push", async () => {
    const w = await world();
    await w.pushToken();
    await w.api({ url: link(6), language: "en" });
    assert.deepEqual(await w.tick(), { dropped: 1 });
    assert.deepEqual(await w.queued(), []);
  });

  test("the route is strict: a bad body, another host, too many open files, and no token", async () => {
    const w = await world();
    assert.equal((await w.api({ url: link(7) })).statusCode, 400);
    assert.equal((await w.api({ url: link(7), language: "de" })).statusCode, 400);
    assert.equal((await w.api({ url: link(7), language: "en", extra: 1 })).statusCode, 400);
    const other = await w.api({ url: link(7).replace("doddy.example", "evil.example"), language: "en" });
    assert.equal(other.statusCode, 400);
    assert.equal(other.json().error, "invalid_link");
    assert.equal((await w.api({ url: link(7), language: "en" }, {})).statusCode, 401);
    for (let n = 10; n < 10 + MAX_OPEN_WATCHES; n++) assert.equal((await w.api({ url: link(n), language: "en" })).statusCode, 201);
    assert.equal((await w.api({ url: link(99), language: "en" })).statusCode, 409);
    // Registering the same file again is the same watch, not a second one.
    const again = await w.api({ url: link(10), language: "en" });
    assert.equal(again.statusCode, 201);
    const { rows } = await db.query("SELECT count(*)::int AS n FROM file_watches WHERE account_id = $1", [w.accountId]);
    assert.equal(rows[0].n, MAX_OPEN_WATCHES);
  });

  test("the link is stored encrypted, never in the clear", async () => {
    const w = await world();
    await w.api({ url: link(8), language: "en" });
    const { rows } = await db.query<{ link_ciphertext: Buffer }>("SELECT link_ciphertext FROM file_watches WHERE account_id = $1", [w.accountId]);
    assert.ok(!rows[0]!.link_ciphertext.includes(Buffer.from("sig=")), "no plain signature in the row");
  });

  test("off without the backend's address: the route says so", async () => {
    const base = await testApp(db, {});
    const created = await base.app.inject({ method: "POST", url: "/v1/accounts" });
    const { deviceToken } = created.json() as { deviceToken: string };
    const r = await base.app.inject({ method: "POST", url: "/v1/file-watches", headers: { authorization: `Bearer ${deviceToken}` },
      payload: { url: link(1), language: "en" } });
    assert.equal(r.statusCode, 503);
  });
});
