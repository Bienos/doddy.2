// The device token is checked before a large request body is read, and requests whose token is missing or unknown
// are counted by the client's address (server/messaging/README.md, "Request limits"). Also: the default hourly limit
// on signed-in routes, the post-call webhook's early signature check and its limit, and the request timeout.
import assert from "node:assert/strict";
import { randomBytes, randomUUID } from "node:crypto";
import http from "node:http";
import type { AddressInfo } from "node:net";
import { after, before, describe, test } from "node:test";
import type { FastifyInstance } from "fastify";
import { requireDevice } from "../src/auth.js";
import type { Db } from "../src/db.js";
import { signElevenLabs } from "../src/taskCalls/elevenLabsSignature.js";
import { dbSkip, EL_WEBHOOK_SECRET, freshDb, taskTestApp, testApp } from "./helpers.js";

/** A well-formed device token that belongs to no device. */
const madeUpToken = () => randomBytes(32).toString("base64url");
/** A body that is not JSON: reading it as JSON fails, so a 401 for it shows the body was never parsed. */
const notJson = (bytes: number) => "{" + "x".repeat(bytes - 1);

let ips = 0;
const nextIp = () => `10.91.${++ips >> 8}.${ips & 255}`;

describe("the device token before the body, and limits by address", { skip: dbSkip }, () => {
  let db: Db;
  before(async () => { db = await freshDb(); });
  after(async () => { await db?.end(); });

  async function withApp<T>(fn: (app: FastifyInstance) => Promise<T>): Promise<T> {
    const { app } = await testApp(db);
    try { return await fn(app); } finally { await app.close(); }
  }
  /** A device whose account is linked to a Doddy account, as `POST /v1/accounts/sign-in` does (memory on calls needs one). */
  async function account(app: FastifyInstance) {
    const r = await app.inject({ method: "POST", url: "/v1/accounts", remoteAddress: nextIp() });
    assert.equal(r.statusCode, 201, r.body);
    const { accountId, deviceToken } = r.json() as { accountId: string; deviceToken: string };
    await db.query("UPDATE accounts SET auth_subject = $2 WHERE id = $1", [accountId, randomUUID()]);
    return { authorization: `Bearer ${deviceToken}` };
  }

  const largeRoutes = [
    { method: "PUT" as const, url: "/v1/memory-copy/snapshot", bytes: 8 * 1024 * 1024 - 1024 },
    { method: "POST" as const, url: "/v1/assistant/ask", bytes: 4_000_000 },
    { method: "POST" as const, url: "/v1/screen/look", bytes: 1_000_000 },
    { method: "POST" as const, url: "/v1/recaps", bytes: 100_000 },
  ];

  test("a large route refuses a missing or unknown token with the usual 401, without parsing the body", () => withApp(async (app) => {
    for (const route of largeRoutes) {
      const payload = notJson(route.bytes);
      for (const headers of [{}, { authorization: `Bearer ${madeUpToken()}` }, { authorization: "Bearer not-a-token" }]) {
        const r = await app.inject({
          method: route.method, url: route.url, remoteAddress: nextIp(), payload,
          headers: { ...headers, "content-type": "application/json" },
        });
        assert.equal(r.statusCode, 401, `${route.url}: ${r.body}`);
        assert.deepEqual(r.json(), { error: "unauthorized" });
      }
    }
  }));

  test("over a real connection the 401 comes while the body is still on its way", () => withApp(async (app) => {
    await app.listen({ port: 0, host: "127.0.0.1" });
    const { port } = app.server.address() as AddressInfo;
    let req: http.ClientRequest | undefined;
    try {
      const res = await new Promise<http.IncomingMessage>((resolve, reject) => {
        req = http.request({
          host: "127.0.0.1", port, method: "PUT", path: "/v1/memory-copy/snapshot",
          headers: { authorization: `Bearer ${madeUpToken()}`, "content-type": "application/json", "content-length": String(8 * 1024 * 1024) },
        });
        req.on("response", resolve);
        req.on("error", reject);
        // 64 KB of the announced 8 MB, then nothing: a server that waits for the body never answers.
        req.write('{"items":[' + " ".repeat(64 * 1024));
        setTimeout(() => reject(new Error("no answer while the body was incomplete")), 5000).unref();
      });
      assert.equal(res.statusCode, 401);
      const chunks: Buffer[] = [];
      for await (const chunk of res) chunks.push(chunk as Buffer);
      assert.deepEqual(JSON.parse(Buffer.concat(chunks).toString("utf8")), { error: "unauthorized" });
    } finally {
      req?.destroy();
    }
    // A client that sends all of it (an iPhone whose token was revoked) still reads the 401, not a dropped connection.
    const whole = await fetch(`http://127.0.0.1:${port}/v1/memory-copy/snapshot`, {
      method: "PUT", body: notJson(8 * 1024 * 1024 - 1024),
      headers: { authorization: `Bearer ${madeUpToken()}`, "content-type": "application/json" },
    });
    assert.equal(whole.status, 401);
    assert.deepEqual(await whole.json(), { error: "unauthorized" });
  }));

  test("with a valid token the large routes read and check the body as before", () => withApp(async (app) => {
    const h = await account(app);
    for (const route of largeRoutes) {
      // A body that isn't JSON is still a 400 for a signed-in device: only the order changed.
      const bad = await app.inject({ method: route.method, url: route.url, payload: notJson(1000), headers: { ...h, "content-type": "application/json" } });
      assert.equal(bad.statusCode, 400, `${route.url}: ${bad.body}`);
    }
    assert.equal((await app.inject({ method: "PUT", url: "/v1/memory-copy", headers: h, payload: { enabled: true } })).statusCode, 204);
    const items = Array.from({ length: 3 }, (_, n) => ({ id: randomUUID(), text: `memory ${n}` }));
    const ok = await app.inject({ method: "PUT", url: "/v1/memory-copy/snapshot", headers: h, payload: { items } });
    assert.equal(ok.statusCode, 200, ok.body);
    assert.deepEqual(ok.json(), { count: 3 });
    // Messages and the screen look aren't configured in this app: past the token, they say so in their own wire.
    for (const url of ["/v1/assistant/ask", "/v1/screen/look", "/v1/recaps"]) {
      const r = await app.inject({ method: "POST", url, headers: h, payload: { schemaVersion: 1 } });
      assert.equal(r.statusCode, 503, `${url}: ${r.body}`);
      assert.equal((r.json() as { error: { code: string } }).error.code, "notConfigured");
    }
  }));

  test("made-up tokens share their address's count; a real device keeps its own", () => withApp(async (app) => {
    const ip = nextIp();
    const pin = (headers: Record<string, string>) => app.inject({ method: "PUT", url: "/v1/calls/pin", remoteAddress: ip, headers, payload: { pin: "482619" } });
    const statuses: number[] = [];
    // PUT /v1/calls/pin allows 10 an hour. A missing header, a malformed one and well-formed unknown ones all count for the address.
    statuses.push((await pin({})).statusCode);
    statuses.push((await pin({ authorization: "Bearer short" })).statusCode);
    for (let i = 0; i < 9; i++) statuses.push((await pin({ authorization: `Bearer ${madeUpToken()}` })).statusCode);
    assert.deepEqual(statuses, [...Array(10).fill(401), 429]);

    const h = await account(app);
    const own = await pin(h);
    assert.equal(own.statusCode, 204, own.body);
    assert.equal(own.headers["x-ratelimit-remaining"], "9", "a device's requests are counted by its token");
  }));

  test("on a large route too, unknown tokens are counted by address before the body is read", () => withApp(async (app) => {
    const ip = nextIp();
    const remaining: unknown[] = [];
    for (let i = 0; i < 3; i++) {
      const r = await app.inject({
        method: "PUT", url: "/v1/memory-copy/snapshot", remoteAddress: ip, payload: notJson(1000),
        headers: { authorization: `Bearer ${madeUpToken()}`, "content-type": "application/json" },
      });
      assert.equal(r.statusCode, 401);
      remaining.push(r.headers["x-ratelimit-remaining"]);
    }
    assert.deepEqual(remaining, ["59", "58", "57"]);
  }));

  test("signed-in routes without a limit of their own get the default: 3600 an hour per device", () => withApp(async (app) => {
    const h = await account(app);
    for (const [method, url] of [["GET", "/v1/calls/settings"], ["GET", "/v1/phone"], ["GET", "/v1/news/settings"], ["DELETE", "/v1/calls/pin"]] as const) {
      const r = await app.inject({ method, url, headers: h });
      assert.ok(r.statusCode < 400, `${url}: ${r.statusCode} ${r.body}`);
      assert.equal(r.headers["x-ratelimit-limit"], "3600", url);
    }
    // A route's own limit is kept.
    const pin = await app.inject({ method: "PUT", url: "/v1/calls/pin", headers: h, payload: { pin: "482619" } });
    assert.equal(pin.headers["x-ratelimit-limit"], "10");
  }));

  test("a route that accepts a large body can't check the device token only after reading it", () => withApp(async (app) => {
    assert.throws(() => app.put("/v1/test-large", { preHandler: requireDevice(db), bodyLimit: 1024 * 1024 }, async () => ({})),
      /before the body/);
    // Within the default body limit, preHandler is fine.
    app.put("/v1/test-small", { preHandler: requireDevice(db) }, async () => ({}));
  }));

  test("requests may take at most 120 s to arrive", () => withApp(async (app) => {
    assert.equal(app.server.requestTimeout, 120_000);
    assert.equal(app.server.headersTimeout, 60_000, "Node's default for the headers stays");
    assert.equal(app.server.timeout, 0, "no idle-socket limit: handlers may wait on Claude for up to 45 s");
  }));

  describe("the ElevenLabs post-call webhook", () => {
    const url = "/webhooks/elevenlabs/post-call";
    const big = "x".repeat(3 * 1024 * 1024);

    test("a request without a fresh signature header is refused before its body is read", async () => {
      const s = await taskTestApp(db);
      try {
        const stale = `t=${Math.floor(Date.now() / 1000) - 3600},v0=${"a".repeat(64)}`;
        for (const sig of [undefined, "nonsense", stale]) {
          // Over the 2 MB limit: read first, this would be a 413.
          const r = await s.app.inject({
            method: "POST", url, remoteAddress: nextIp(), payload: big,
            headers: { "content-type": "application/json", ...(sig ? { "elevenlabs-signature": sig } : {}) },
          });
          assert.equal(r.statusCode, 401, `${sig}: ${r.body}`);
          assert.deepEqual(r.json(), { error: "bad_signature" });
        }
        // A fresh header with the wrong digest is refused once the bytes are checked, still before any JSON parsing.
        const forged = `t=${Math.floor(Date.now() / 1000)},v0=${"a".repeat(64)}`;
        const r = await s.app.inject({ method: "POST", url, payload: "{not json", headers: { "content-type": "application/json", "elevenlabs-signature": forged } });
        assert.equal(r.statusCode, 401);
        // Correctly signed: accepted as before (an unknown conversation is still answered 200).
        const body = JSON.stringify({ type: "post_call_transcription", data: { agent_id: "agent_other", conversation_id: "conv_x" } });
        const ok = await s.app.inject({ method: "POST", url, payload: body, headers: { "content-type": "application/json", "elevenlabs-signature": signElevenLabs(EL_WEBHOOK_SECRET, body) } });
        assert.equal(ok.statusCode, 200, ok.body);
      } finally {
        await s.app.close();
      }
    });

    test("it is limited to 120 a minute per address, whatever Authorization header comes with it", async () => {
      const s = await taskTestApp(db);
      try {
        const ip = nextIp();
        const remaining: unknown[] = [];
        for (let i = 0; i < 2; i++) {
          const r = await s.app.inject({ method: "POST", url, remoteAddress: ip, payload: "{}",
            headers: { "content-type": "application/json", authorization: `Bearer ${madeUpToken()}` } });
          assert.equal(r.statusCode, 401);
          assert.equal(r.headers["x-ratelimit-limit"], "120");
          remaining.push(r.headers["x-ratelimit-remaining"]);
        }
        assert.deepEqual(remaining, ["119", "118"]);
      } finally {
        await s.app.close();
      }
    });
  });
});
