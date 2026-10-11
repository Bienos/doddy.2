import { readdir, readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import path from "node:path";
import pg from "pg";

export type Db = pg.Pool;

/** How long a new connection may take before it fails. Without it an unreachable DATABASE_URL hangs
 * startup silently until the OS gives up (about 2 minutes on Render). */
export const CONNECT_TIMEOUT_MS = 10_000;

export function createPool(databaseUrl: string, connectTimeoutMs = CONNECT_TIMEOUT_MS): Db {
  return new pg.Pool({ connectionString: databaseUrl, max: 10, connectionTimeoutMillis: connectTimeoutMs });
}

/** First contact with the database at startup: applies migrations, or logs one line naming the
 * cause (never the URL, which holds the password) and exits, so a bad DATABASE_URL is obvious. */
export async function migrateOrExit(db: Db, log: (msg: string, extra?: object) => void): Promise<void> {
  try {
    await migrate(db);
  } catch (err) {
    log("database unreachable at startup: check DATABASE_URL (use the database's Internal URL)", dbErrorFields(err));
    await db.end().catch(() => {});
    process.exit(1);
  }
}

/** Safe fields for logging a connection error: code and message, never the connection string. */
export function dbErrorFields(err: unknown): { code: string; error: string } {
  const e = err as { code?: unknown; message?: unknown };
  return {
    code: typeof e?.code === "string" ? e.code : "unknown",
    error: (typeof e?.message === "string" ? e.message : String(err)).replace(/postgres(ql)?:\/\/\S+/gi, "<url>"),
  };
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
