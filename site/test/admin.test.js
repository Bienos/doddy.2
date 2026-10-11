import assert from "node:assert/strict";
import { beforeEach, test } from "node:test";
import { basic, reset, store } from "./fake-blob.js";

process.env.WAITLIST_ADMIN_PASSWORD = "correct-horse-battery";
const { GET: exportCsv } = await import("../api/waitlist-export.js");
const admin = await import("../api/waitlist-admin.js");

const ID = "a".repeat(64);
const request = (url, { method = "GET", password } = {}) =>
  new Request(`https://doddy.test${url}`, { method, headers: password ? { authorization: basic(password) } : {} });
const seed = (id, record) => store.set(`waitlist/${id}.json`, { body: JSON.stringify(record), etag: '"1"' });

beforeEach(reset);

test("export without or with a wrong password is refused with a login prompt", async () => {
  for (const password of [undefined, "wrong"]) {
    const response = await exportCsv(request("/api/waitlist-export", { password }));
    assert.equal(response.status, 401);
    assert.match(response.headers.get("www-authenticate"), /^Basic realm=/);
  }
});

test("export neutralises formulas and quotes every cell", async () => {
  seed(ID, {
    email: "ana@example.com", page: "+page", consent: "-v1", createdAt: "2026-10-11T10:00:00.000Z", answerKeyHash: "f".repeat(64),
    answers: { phone: "iphone", heard: "friend", wish: "=1+1 say \"hi\"", answeredAt: "@later" },
  });
  const response = await exportCsv(request("/api/waitlist-export", { password: "correct-horse-battery" }));
  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type"), /^text\/csv/);
  // Raw bytes: Response.text() would drop the BOM while decoding.
  const bytes = Buffer.from(await response.arrayBuffer());
  assert.deepEqual([...bytes.subarray(0, 3)], [0xef, 0xbb, 0xbf], "BOM for Excel");
  const csv = bytes.subarray(3).toString("utf8");
  const row = csv.trim().split("\r\n")[1];
  assert.equal(row, [
    "2026-10-11T10:00:00.000Z", "ana@example.com", "iPhone", "A friend", "'=1+1 say \"\"hi\"\"", "'@later", "'+page", "'-v1",
  ].map((c) => `"${c}"`).join(","));
  assert.ok(!csv.includes("answerKeyHash") && !csv.includes("f".repeat(64)));
});

test("admin GET without the password is refused without a browser prompt", async () => {
  const response = await admin.GET(request("/api/waitlist-admin"));
  assert.equal(response.status, 401);
  assert.equal(response.headers.get("www-authenticate"), null);
});

test("admin GET lists signups without the answer-key hash", async () => {
  seed(ID, { email: "ana@example.com", createdAt: "2026-10-11T10:00:00.000Z", answerKeyHash: "f".repeat(64) });
  const response = await admin.GET(request("/api/waitlist-admin", { password: "correct-horse-battery" }));
  const body = await response.json();
  assert.equal(response.status, 200);
  assert.deepEqual(body.records, [{ id: ID, email: "ana@example.com", createdAt: "2026-10-11T10:00:00.000Z" }]);
});

test("admin DELETE checks the password and the id, then removes one signup", async () => {
  seed(ID, { email: "ana@example.com" });
  const del = (id, password = "correct-horse-battery") =>
    admin.DELETE(request(`/api/waitlist-admin?id=${id}`, { method: "DELETE", password }));
  assert.equal((await del(ID, "wrong")).status, 401);
  assert.equal((await del("not-a-hash")).status, 400);
  assert.equal((await del("../" + ID)).status, 400);
  assert.equal((await del("b".repeat(64))).status, 404);
  const response = await del(ID);
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { ok: true, deleted: ID });
  assert.equal(store.size, 0);
});
