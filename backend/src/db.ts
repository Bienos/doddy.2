import { PGlite } from "@electric-sql/pglite";
import pg from "pg";

/**
 * The backend's database: Postgres. Production uses a hosted Postgres (DATABASE_URL); tests, mock
 * mode and local development use PGlite, the same Postgres engine in-process, so there is one SQL
 * dialect everywhere. Every table lives in its own schema (`doddy_backend`) so a shared database
 * (e.g. a Supabase project that also holds other tables) stays separated.
 */

export const SCHEMA = "doddy_backend";

export interface QueryResult<T> {
  rows: T[];
  /** Rows changed by INSERT/UPDATE/DELETE. */
  rowCount: number;
}

export interface Queryable {
  query<T = Record<string, unknown>>(sql: string, params?: readonly unknown[]): Promise<QueryResult<T>>;
}

export interface Database extends Queryable {
  readonly kind: "postgres" | "pglite";
  /**
   * Runs `fn` in one SERIALIZABLE transaction and commits, or rolls back on any error. A
   * serialization conflict with a concurrent transaction is retried a few times, so callers see the
   * same all-or-nothing behaviour SQLite's single writer gave.
   */
  transaction<T>(fn: (tx: Queryable) => Promise<T>): Promise<T>;
  close(): Promise<void>;
}

export interface DatabaseOptions {
  /** postgres://… Hosted Postgres. Absent: PGlite. */
  url?: string | undefined;
  /** PEM of the CA that signed the server certificate, when it isn't a public one. */
  caCert?: string | undefined;
  /** PGlite only: a data directory to keep data across restarts. Absent or ":memory:": in memory. */
  dataDir?: string | undefined;
}

const SERIALIZATION_FAILURE = new Set(["40001", "40P01"]);
const MAX_TX_TRIES = 5;

// int8 columns hold millisecond timestamps and counters, far below 2^53: read them as numbers.
const INT8_OID = 20;
pg.types.setTypeParser(INT8_OID, (value: string) => Number(value));

export async function openDatabase(options: DatabaseOptions): Promise<Database> {
  return options.url ? openPostgres(options.url, options.caCert) : openPglite(options.dataDir);
}

// ------------------------------------------------------------------ hosted Postgres

async function openPostgres(url: string, caCert: string | undefined): Promise<Database> {
  const local = /^postgres(ql)?:\/\/[^@]*@(localhost|127\.0\.0\.1)(:\d+)?\//.test(url);
  const pool = new pg.Pool({
    connectionString: url,
    // Certificates are always verified outside loopback; a private CA can be supplied.
    ssl: local ? undefined : caCert ? { ca: caCert, rejectUnauthorized: true } : { rejectUnauthorized: true },
    max: 5,
    idleTimeoutMillis: 30_000,
    connectionTimeoutMillis: 10_000,
    statement_timeout: 10_000,
  });
  // A dropped idle connection must not crash the process; the pool replaces it.
  pool.on("error", () => {});

  const run = async <T>(client: Pick<pg.PoolClient, "query">, sql: string, params?: readonly unknown[]): Promise<QueryResult<T>> => {
    const result = await client.query(sql, params as unknown[] | undefined);
    return { rows: result.rows as T[], rowCount: result.rowCount ?? 0 };
  };

  const db: Database = {
    kind: "postgres",
    async query<T>(sql: string, params?: readonly unknown[]) {
      const client = await pool.connect();
      try {
        await client.query(`SET search_path TO ${SCHEMA}`);
        return await run<T>(client, sql, params);
      } finally {
        client.release();
      }
    },
    async transaction<T>(fn: (tx: Queryable) => Promise<T>): Promise<T> {
      for (let attempt = 1; ; attempt++) {
        const client = await pool.connect();
        try {
          await client.query(`SET search_path TO ${SCHEMA}`);
          await client.query("BEGIN ISOLATION LEVEL SERIALIZABLE");
          const tx: Queryable = { query: <R>(sql: string, params?: readonly unknown[]) => run<R>(client, sql, params) };
          const result = await fn(tx);
          await client.query("COMMIT");
          return result;
        } catch (error) {
          await client.query("ROLLBACK").catch(() => {});
          const code = (error as { code?: unknown }).code;
          if (typeof code === "string" && SERIALIZATION_FAILURE.has(code) && attempt < MAX_TX_TRIES) continue;
          throw error;
        } finally {
          client.release();
        }
      }
    },
    async close() {
      await pool.end();
    },
  };
  return db;
}

// ------------------------------------------------------------------ PGlite (tests, mock, local)

async function openPglite(dataDir: string | undefined): Promise<Database> {
  const memory = !dataDir || dataDir === ":memory:";
  const lite = await PGlite.create(memory ? undefined : dataDir, {
    parsers: { [INT8_OID]: (value: string) => Number(value) },
  });
  await lite.exec(`CREATE SCHEMA IF NOT EXISTS ${SCHEMA}; SET search_path TO ${SCHEMA};`);

  const run = async <T>(target: Pick<PGlite, "query">, sql: string, params?: readonly unknown[]): Promise<QueryResult<T>> => {
    const result = await target.query<T>(sql, params as unknown[] | undefined);
    return { rows: result.rows, rowCount: result.affectedRows ?? 0 };
  };

  return {
    kind: "pglite",
    query: <T>(sql: string, params?: readonly unknown[]) => run<T>(lite, sql, params),
    async transaction<T>(fn: (tx: Queryable) => Promise<T>): Promise<T> {
      // PGlite has one connection and runs one transaction at a time, so there is nothing to retry.
      return lite.transaction(async (inner) => {
        await inner.query("SET TRANSACTION ISOLATION LEVEL SERIALIZABLE");
        return fn({ query: <R>(sql: string, params?: readonly unknown[]) => run<R>(inner, sql, params) });
      });
    },
    async close() {
      await lite.close();
    },
  };
}
