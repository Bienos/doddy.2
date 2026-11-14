import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { after, before, describe, test } from "node:test";
import type { FastifyInstance } from "fastify";
import { hashToken } from "../src/auth.js";
import { migrate, type Db } from "../src/db.js";
import { dbSkip, freshDb, testApp } from "./helpers.js";

// Migration 040 (device token lifetimes) on a database that already has devices in it, the way the live one does:
// the columns are added, nobody is cut off the day it is applied, and code from before it keeps working against the
// new schema (a rollback of the server leaves the columns, which old code ignores).

const MIGRATION = "040_device_token_lifetimes.sql";
const DAY = 86_400_000;

describe("migration 040 on a database that already has device tokens (real Postgres)", { skip: dbSkip }, () => {
  let db: Db;
  let app: FastifyInstance;
  // 43 characters, as a device token is; obviously made up.
  const doddyToken = "D".repeat(43);
  const anonToken = "A".repeat(43);
  const legacyToken = "L".repeat(43);
  const pairToken = "P".repeat(43);

  before(async () => {
    db = await freshDb();
    // Back to the schema as it was before this migration: its columns (and with them its constraint and index) are removed
    // and it is not recorded as applied. Then devices as they are on a live server: one of a Doddy account, one anonymous,
    // both unseen for 100 days (a Doddy account's token that long unseen would be refused the moment expiry was on).
    await db.query("ALTER TABLE devices DROP COLUMN token_issued_at, DROP COLUMN previous_token_hash, DROP COLUMN previous_valid_until");
    await db.query("DELETE FROM schema_migrations WHERE name = $1", [MIGRATION]);
    const doddy = randomUUID();
    const anon = randomUUID();
    await db.query("INSERT INTO accounts (id, auth_subject) VALUES ($1, 'migration-subject-not-real')", [doddy]);
    await db.query("INSERT INTO accounts (id) VALUES ($1)", [anon]);
    for (const [account, token] of [[doddy, doddyToken], [anon, anonToken]] as const) {
      await db.query(
        `INSERT INTO devices (id, account_id, token_hash, created_at, last_seen_at)
         VALUES ($1, $2, $3, now() - interval '300 days', now() - interval '100 days')`,
        [randomUUID(), account, hashToken(token)]);
    }
  });
  after(async () => {
    await app?.close();
    await db.end();
  });

  const row = async (token: string) =>
    (await db.query<{ last_seen_at: Date; created_at: Date; token_issued_at: Date; previous_token_hash: Buffer | null; previous_valid_until: Date | null }>(
      "SELECT last_seen_at, created_at, token_issued_at, previous_token_hash, previous_valid_until FROM devices WHERE token_hash = $1",
      [hashToken(token)])).rows[0]!;
  const near = (date: Date, ms: number, slack = 120_000) => Math.abs(date.getTime() - ms) <= slack;

  test("it applies on its own, after every earlier one", async () => {
    assert.deepEqual(await migrate(db), [MIGRATION]);
    assert.deepEqual(await migrate(db), [], "and only once");
  });

  test("a Doddy account's token is counted as issued and seen when the migration ran; an anonymous one keeps its last-seen time", async () => {
    const now = Date.now();
    const doddy = await row(doddyToken);
    assert.ok(near(doddy.last_seen_at, now), "seen: now, so the 60 days start today");
    assert.ok(near(doddy.token_issued_at, now), "issued: now, so the 180 days start today");
    assert.ok(near(doddy.created_at, now - 300 * DAY), "its creation time is not touched");
    assert.equal(doddy.previous_token_hash, null);
    assert.equal(doddy.previous_valid_until, null);

    const anon = await row(anonToken);
    assert.ok(near(anon.last_seen_at, now - 100 * DAY), "an anonymous account's last-seen time is left as it was");
    assert.ok(near(anon.token_issued_at, now), "every row has an issue time");
  });

  test("nobody is cut off: both tokens work on the new code, though one had been unseen for 100 days", async () => {
    ({ app } = await testApp(db));
    for (const token of [doddyToken, anonToken]) {
      const r = await app.inject({ method: "GET", url: "/v1/calls/settings", headers: { authorization: `Bearer ${token}` } });
      assert.equal(r.statusCode, 200, token.slice(0, 4));
    }
  });

  test("code from before the migration keeps working on the new schema: it inserts and updates devices without the new columns", async () => {
    const account = randomUUID();
    await db.query("INSERT INTO accounts (id) VALUES ($1)", [account]);
    // The statements the earlier server ran (src/routes/account.ts, src/auth.ts before this change).
    await db.query("INSERT INTO devices (id, account_id, token_hash) VALUES ($1, $2, $3)", [randomUUID(), account, hashToken(legacyToken)]);
    await db.query("UPDATE devices SET last_seen_at = now() WHERE token_hash = $1", [hashToken(legacyToken)]);
    const r = await db.query("SELECT id, account_id, last_seen_at < now() - interval '1 hour' AS stale FROM devices WHERE token_hash = $1",
      [hashToken(legacyToken)]);
    assert.equal(r.rowCount, 1);
    const legacy = await row(legacyToken);
    assert.ok(near(legacy.token_issued_at, Date.now()), "the new column fills itself");
  });

  test("the two columns that go together do, and a previous token is one hash", async () => {
    const account = randomUUID();
    await db.query("INSERT INTO accounts (id) VALUES ($1)", [account]);
    const id = randomUUID();
    await db.query("INSERT INTO devices (id, account_id, token_hash) VALUES ($1, $2, $3)", [id, account, hashToken(pairToken)]);
    await assert.rejects(db.query("UPDATE devices SET previous_token_hash = $2 WHERE id = $1", [id, hashToken("x")]), /devices_previous_token_pair/);
    await assert.rejects(db.query("UPDATE devices SET previous_valid_until = now() WHERE id = $1", [id]), /devices_previous_token_pair/);
    await assert.rejects(db.query("UPDATE devices SET previous_token_hash = $2, previous_valid_until = now() WHERE id = $1", [id, Buffer.from("short")]), /check/i);
  });
});
