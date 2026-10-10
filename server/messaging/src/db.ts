import { readdir, readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import path from "node:path";
import pg from "pg";

export type Db = pg.Pool;

export function createPool(databaseUrl: string): Db {
  return new pg.Pool({ connectionString: databaseUrl, max: 10 });
}

export async function inTransaction<T>(db: Db, fn: (c: pg.PoolClient) => Promise<T>): Promise<T> {
  const client = await db.connect();
  try {
    await client.query("BEGIN");
    const result = await fn(client);
    await client.query("COMMIT");
    return result;
  } catch (err) {
    await client.query("ROLLBACK").catch(() => {});
    throw err;
  } finally {
    client.release();
  }
}

// dist/src/db.js → ../../migrations
const migrationsDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../migrations");

/** Applies pending `migrations/NNN_*.sql` files in order, each in its own transaction. */
export async function migrate(db: Db): Promise<string[]> {
  await db.query(
    "CREATE TABLE IF NOT EXISTS schema_migrations (name text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now())");
  const files = (await readdir(migrationsDir)).filter((f) => /^\d+_.+\.sql$/.test(f)).sort();
  const applied: string[] = [];
  for (const name of files) {
    const sql = await readFile(path.join(migrationsDir, name), "utf8");
    const ran = await inTransaction(db, async (c) => {
      // Serialises concurrent deploys (web + worker starting together).
      await c.query("SELECT pg_advisory_xact_lock(4242001)");
      const done = await c.query("SELECT 1 FROM schema_migrations WHERE name = $1", [name]);
      if (done.rowCount) return false;
      await c.query(sql);
      await c.query("INSERT INTO schema_migrations (name) VALUES ($1)", [name]);
      return true;
    });
    if (ran) applied.push(name);
  }
  return applied;
}
