// Two safety nets from the engineering audit of 7 Nov 2026 that need no database: the test helper refuses a
// database that isn't plainly disposable, and request log lines carry no client address or query string.
import assert from "node:assert/strict";
import { describe, test } from "node:test";
import { requestLogFields } from "../src/app.js";
import { assertDisposableTestDatabase } from "./helpers.js";

describe("the test database must be disposable", () => {
  test("CI's database and other *_test names are accepted", () => {
    for (const url of [
      "postgres://doddy:doddy@localhost:5432/doddy_test",
      "postgresql://u:p@127.0.0.1/messaging-test",
      "postgres://u@db.example/test",
      "postgres://u:p@localhost/DODDY_TEST?sslmode=disable",
    ]) assert.doesNotThrow(() => assertDisposableTestDatabase(url), url);
  });

  test("a real-looking database, or none, is refused before anything is dropped", () => {
    for (const url of [
      "postgres://doddy_messaging_db_9uh2_user:secret@dpg-x-a.frankfurt-postgres.render.com/doddy_messaging_db_9uh2",
      "postgresql://doddy_backend.ref:secret@aws-1-eu-central-1.pooler.supabase.com:5432/postgres",
      "postgres://u:p@localhost:5432/",
      "postgres://u:p@localhost/test_results",
      "not a url",
    ]) assert.throws(() => assertDisposableTestDatabase(url), /disposable database/, url);
  });

  test("the refusal never repeats the password", () => {
    try {
      assertDisposableTestDatabase("postgres://user:hunter2@host/prod");
      assert.fail("should refuse");
    } catch (error) {
      assert.ok(!String(error).includes("hunter2"));
    }
  });
});

describe("request log lines", () => {
  test("keep the method, the path and the request id", () => {
    assert.deepEqual(requestLogFields({ method: "GET", url: "/v1/updates", id: "req-1" }), { method: "GET", url: "/v1/updates", id: "req-1" });
  });

  test("drop the query string, so a capability like the takeover page's ?t= never reaches the log", () => {
    const fields = requestLogFields({ method: "GET", url: "/t/abc?t=secret-capability&x=1", id: "req-2" });
    assert.equal(fields.url, "/t/abc");
    assert.ok(!JSON.stringify(fields).includes("secret-capability"));
  });

  test("carry no client address, host or port", () => {
    const request = { method: "POST", url: "/v1/accounts", id: "req-3", ip: "203.0.113.7", hostname: "doddy.example", socket: { remotePort: 51234 } };
    const fields = requestLogFields(request);
    assert.deepEqual(Object.keys(fields).sort(), ["id", "method", "url"]);
    assert.ok(!JSON.stringify(fields).includes("203.0.113.7"));
  });
});
