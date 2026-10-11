import assert from "node:assert/strict";
import { beforeEach, test } from "node:test";
import { hooks, post, reset, store } from "./fake-blob.js";

const { POST: join } = await import("../api/waitlist.js");
const { POST: answer } = await import("../api/waitlist-answers.js");

async function signup() {
  const response = await join(post("/api/waitlist", { email: "ana@example.com", consent: "waitlist-note-v1" }));
  return response.json();
}
const send = async (body, headers) => {
  const response = await answer(post("/api/waitlist-answers", body, headers));
  return { status: response.status, body: await response.json() };
};
const recordOf = (id) => JSON.parse(store.get(`waitlist/${id}.json`).body);

beforeEach(reset);

test("the right key stores the answers, cleaned, and keeps the signup", async () => {
  const { id, key } = await signup();
  const { status, body } = await send({ id, key, phone: "iphone", heard: "radio", wish: "=HYPERLINK(\"x\")\nremind me" });
  assert.equal(status, 200);
  assert.deepEqual(body, { ok: true });
  const record = recordOf(id);
  assert.equal(record.email, "ana@example.com");
  assert.equal(record.answers.phone, "iphone");
  assert.equal(record.answers.heard, "", "unknown choices are dropped");
  assert.equal(record.answers.wish, "HYPERLINK(\"x\") remind me");
});

test("a wrong or missing key is refused and nothing changes", async () => {
  const { id } = await signup();
  const before = store.get(`waitlist/${id}.json`).body;
  for (const key of ["", "short", "x".repeat(24)]) {
    const { status, body } = await send({ id, key, phone: "android" });
    assert.equal(status, 403, key);
    assert.equal(body.error, "forbidden");
  }
  assert.equal(store.get(`waitlist/${id}.json`).body, before);
});

test("answers for an unknown id or from another site are refused", async () => {
  const { id, key } = await signup();
  assert.equal((await send({ id: "0".repeat(64), key, phone: "iphone" })).status, 403);
  assert.equal((await send({ id, key, phone: "iphone" }, { origin: "https://evil.example" })).status, 403);
  assert.equal(recordOf(id).answers, undefined);
});

test("answers after the signup was deleted don't bring it back", async () => {
  const { id, key } = await signup();
  store.delete(`waitlist/${id}.json`);
  const { status } = await send({ id, key, phone: "iphone" });
  assert.equal(status, 403);
  assert.equal(store.size, 0);
});

test("a delete between the read and the write doesn't bring the signup back", async () => {
  const { id, key } = await signup();
  hooks.beforePut = (pathname) => store.delete(pathname);
  const { status, body } = await send({ id, key, wish: "hello" });
  assert.equal(status, 403);
  assert.equal(body.error, "forbidden");
  assert.equal(store.size, 0);
});
