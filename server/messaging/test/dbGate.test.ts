import assert from "node:assert/strict";
import { test } from "node:test";
import { dbGate } from "./dbGate.js";

test("database tests: run with a database, fail loudly in CI without one, warn when run locally without one", () => {
  assert.equal(dbGate({ TEST_DATABASE_URL: "postgres://x/y" }), "run");
  assert.equal(dbGate({ TEST_DATABASE_URL: "postgres://x/y", CI: "true" }), "run");
  assert.equal(dbGate({ CI: "true" }), "fail");
  assert.equal(dbGate({ CI: "true", TEST_DATABASE_URL: "" }), "fail");
  assert.equal(dbGate({}), "skip-with-warning");
  assert.equal(dbGate({ TEST_DATABASE_URL: "" }), "skip-with-warning");
});
