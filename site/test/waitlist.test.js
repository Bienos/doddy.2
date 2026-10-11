import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { beforeEach, test } from "node:test";
import { hooks, post, reset, store } from "./fake-blob.js";

const { POST } = await import("../api/waitlist.js");
const sha = (value) => createHash("sha256").update(value).digest("hex");
const join = async (body, headers) => {
  const response = await POST(post("/api/waitlist", body, headers));
  return { status: response.status, body: await response.json() };
};
const signup = { email: "Ana@Example.com ", page: "https://doddy.test/", consent: "waitlist-note-v1", website: "" };

beforeEach(reset);

test("a new email is stored under its hash and gets an answer key", async () => {
  const { status, body } = await join(signup);
  assert.equal(status, 200);
  assert.equal(body.status, "added");
  assert.equal(body.id, sha("ana@example.com"));
  assert.ok(body.key.length >= 16);
  const record = JSON.parse(store.get(`waitlist/${body.id}.json`).body);
  assert.equal(record.email, "ana@example.com");
  assert.equal(record.answerKeyHash, sha(body.key));
  assert.ok(!JSON.stringify(record).includes(body.key), "only the key's hash is stored");
});

test("an email already on the list gets the same reply, without id or key, and is not changed", async () => {
  await join(signup);
  const before = store.get(`waitlist/${sha("ana@example.com")}.json`).body;
  const { status, body } = await join({ ...signup, email: "ana@example.com" });
  assert.equal(status, 200);
  assert.deepEqual(body, { ok: true, status: "added" });
  assert.equal(store.get(`waitlist/${sha("ana@example.com")}.json`).body, before);
});

test("a duplicate that wins the race between head and put gets the same reply", async () => {
  hooks.beforePut = (pathname) => store.set(pathname, { body: "{}", etag: '"other"' });
  const { status, body } = await join(signup);
  assert.equal(status, 200);
  assert.deepEqual(body, { ok: true, status: "added" });
});

test("a filled honeypot pretends to succeed and stores nothing", async () => {
  const { status, body } = await join({ ...signup, website: "https://spam.example" });
  assert.equal(status, 200);
  assert.deepEqual(body, { ok: true, status: "added" });
  assert.equal(store.size, 0);
});

test("a POST from another site is refused", async () => {
  const { status, body } = await join(signup, { origin: "https://evil.example" });
  assert.equal(status, 403);
  assert.equal(body.error, "forbidden");
  assert.equal(store.size, 0);
});

test("invalid and formula-like emails are refused", async () => {
  for (const email of ["", "not-an-email", "a b@c.de", "=cmd@example.com", `${"a".repeat(250)}@x.de`]) {
    const { status, body } = await join({ ...signup, email });
    assert.equal(status, 400, email);
    assert.equal(body.error, "invalid_email");
  }
  assert.equal(store.size, 0);
});

test("an oversized body and broken JSON are refused", async () => {
  assert.equal((await join({ ...signup, page: "x".repeat(3000) })).status, 413);
  assert.equal((await join("{not json")).status, 400);
  assert.equal(store.size, 0);
});

test("a failed write is reported, not hidden", async () => {
  hooks.beforePut = () => { throw new Error("store down"); };
  const { status, body } = await join(signup);
  assert.equal(status, 503);
  assert.equal(body.error, "unavailable");
});
