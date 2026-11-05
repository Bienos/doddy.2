import assert from "node:assert/strict";
import { test } from "node:test";
import { withoutTlsParams } from "../src/db.js";

test("TLS parameters in DATABASE_URL are dropped so certificate checks always apply (ADR-525)", () => {
  const url = "postgresql://doddy_backend.ref:pw@pooler.example.com:5432/postgres?sslmode=disable&application_name=doddy&sslrootcert=/x";
  const cleaned = new URL(withoutTlsParams(url));
  assert.equal(cleaned.searchParams.get("sslmode"), null);
  assert.equal(cleaned.searchParams.get("sslrootcert"), null);
  assert.equal(cleaned.searchParams.get("application_name"), "doddy", "other parameters stay");
  assert.equal(cleaned.username, "doddy_backend.ref");
  assert.equal(cleaned.password, "pw");
  assert.equal(cleaned.host, "pooler.example.com:5432");
  assert.equal(cleaned.pathname, "/postgres");
});
