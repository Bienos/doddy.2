import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, test } from "node:test";
import { SCHEMA } from "../src/db.js";
import { Store } from "../src/store.js";

/**
 * Row level security on the backend's schema (decision 2026-11-12-backend-schema-not-exposed): every
 * table has it on, without FORCE, so the tables' owner (the backend) reads and writes as before and any
 * other role that isn't BYPASSRLS sees no rows; Supabase's API roles lose any use of the schema at every
 * start. PGlite has no `anon` or `authenticated` role, so the test makes them.
 */

const stores: Store[] = [];
const dirs: string[] = [];
afterEach(async () => {
  for (const store of stores.splice(0)) await store.close();
  for (const dir of dirs.splice(0)) rmSync(dir, { recursive: true, force: true });
});

const tables = async (store: Store) =>
  (
    await store.db.query<{ name: string; rls: boolean; forced: boolean }>(
      `SELECT c.relname AS name, c.relrowsecurity AS rls, c.relforcerowsecurity AS forced
       FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname = $1 AND c.relkind IN ('r', 'p') ORDER BY c.relname`,
      [SCHEMA],
    )
  ).rows;

const usage = async (store: Store, role: string) =>
  (await store.db.query<{ ok: boolean }>("SELECT has_schema_privilege($1, $2, 'USAGE') AS ok", [role, SCHEMA])).rows[0]!.ok;

test("after the migrations every table in the backend's schema has row level security on, not forced", async () => {
  const store = await Store.memory();
  stores.push(store);
  const all = await tables(store);
  assert.ok(all.length >= 30, `found ${all.length} tables`);
  assert.deepEqual(all.filter((t) => !t.rls).map((t) => t.name), [], "every table has row level security");
  assert.deepEqual(all.filter((t) => t.forced).map((t) => t.name), [], "none is forced, so the owner isn't held to it");
  // The backend, as the tables' owner, still reads and writes.
  await store.composioUserId("u-1", 1);
  assert.equal(Number((await store.db.query<{ n: string }>("SELECT count(*) AS n FROM users")).rows[0]!.n), 1);
});

test("Supabase's API roles lose any use of the schema at every start, and a role let in sees no rows", async () => {
  const dir = mkdtempSync(join(tmpdir(), "doddy-rls-"));
  dirs.push(dir);
  const first = await Store.open({ dataDir: dir });
  await first.composioUserId("u-1", 1);
  // Roles like Supabase's, given what a careless grant would give them.
  await first.db.query("CREATE ROLE anon NOLOGIN");
  await first.db.query("CREATE ROLE authenticated NOLOGIN");
  await first.db.query(`GRANT USAGE ON SCHEMA ${SCHEMA} TO anon, authenticated`);
  await first.db.query(`GRANT SELECT ON ALL TABLES IN SCHEMA ${SCHEMA} TO anon, authenticated`);
  assert.equal(await usage(first, "anon"), true);
  // Even with the schema and a table granted, row level security without a policy shows such a role nothing.
  const seen = await first.db.transaction(async (tx) => {
    await tx.query("SET LOCAL ROLE anon");
    return Number((await tx.query<{ n: string }>(`SELECT count(*) AS n FROM ${SCHEMA}.users`)).rows[0]!.n);
  });
  assert.equal(seen, 0, "no rows for a role that isn't the owner");
  await first.close();

  const again = await Store.open({ dataDir: dir });
  stores.push(again);
  assert.equal(await usage(again, "anon"), false, "anon has no use of the schema after a start");
  assert.equal(await usage(again, "authenticated"), false, "authenticated neither");
  const granted = await again.db.query<{ role: string; name: string }>(
    `SELECT r.rolname AS role, c.relname AS name FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace, pg_roles r
     WHERE n.nspname = $1 AND c.relkind IN ('r', 'p') AND r.rolname IN ('anon', 'authenticated') AND has_table_privilege(r.rolname, c.oid, 'SELECT')`,
    [SCHEMA],
  );
  assert.deepEqual(granted.rows, [], "and no table privilege either");
  assert.equal(Number((await again.db.query<{ n: string }>("SELECT count(*) AS n FROM users")).rows[0]!.n), 1, "the owner still sees its rows");
  await again.composioUserId("u-2", 2);
  assert.deepEqual((await tables(again)).filter((t) => !t.rls), []);
  // A start with nothing left to change changes nothing and still starts.
  await again.close();
  stores.pop();
  const third = await Store.open({ dataDir: dir });
  stores.push(third);
  assert.equal(Number((await third.db.query<{ n: string }>("SELECT count(*) AS n FROM users")).rows[0]!.n), 2);
});
