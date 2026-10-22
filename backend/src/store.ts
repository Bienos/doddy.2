import { createHash, randomBytes, randomUUID } from "node:crypto";
import type { ConnectionReason, ConnectionStatus, Receipt } from "./contracts.js";
import { type Database, type DatabaseOptions, openDatabase, type Queryable } from "./db.js";

/**
 * Small durable store (Postgres, ADR-525). Holds only what the backend needs: the internal-user →
 * Composio-user mapping, connection attempts, one connection per user, sanitized receipts, usage
 * counters and confirmation approvals. No calendar content, memories, chat or contacts.
 * Ownership changes, nonce consumption and usage reservations run inside SERIALIZABLE transactions.
 */

export interface AttemptRow {
  attempt_id: string;
  user_id: string;
  provider: string;
  auth_config_id: string;
  pending_connection_id: string | null;
  nonce_hash: string;
  created_at: number;
  expires_at: number;
  consumed_at: number | null;
  status_checks: number;
}

export interface ConnectionRow {
  user_id: string;
  provider: string;
  connection_id: string;
  status: ConnectionStatus;
  reason: ConnectionReason | null;
  account_label: string | null;
  scopes_json: string | null;
  connected_at: number;
  last_checked_at: number | null;
}

/** A remote connection Doddy queued for removal, and whose it is. */
export interface QueuedCleanup {
  connectionId: string;
  userId: string;
  provider: string;
}

export interface CleanupRow {
  connection_id: string;
  user_id: string;
  provider: string;
  state: "pending" | "failed";
  attempts: number;
  last_error: string | null;
  created_at: number;
}

const sha256 = (s: string) => createHash("sha256").update(s).digest("hex");

/**
 * The hourly sweep's retry of queued remote removals: only rows older than five minutes (a request
 * may still be working on a newer one), at most 20 a sweep, and 24 tries (a day) per row. A row
 * past that stays visible as `failed` and is still retried before the user's next Connect.
 */
export const CLEANUP_RETRY = { afterMs: 5 * 60_000, perSweep: 20, maxTries: 24 } as const;

/**
 * The schema, idempotent. Timestamps are milliseconds since 1970 (BIGINT). `seq` gives receipts a
 * stable order for rows written in the same millisecond.
 */
export const SCHEMA_SQL = `
  CREATE TABLE IF NOT EXISTS users (
    user_id TEXT PRIMARY KEY,
    composio_user_id TEXT NOT NULL UNIQUE,
    created_at BIGINT NOT NULL
  );
  CREATE TABLE IF NOT EXISTS attempts (
    attempt_id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES users(user_id),
    provider TEXT NOT NULL,
    auth_config_id TEXT NOT NULL,
    pending_connection_id TEXT,
    nonce_hash TEXT NOT NULL,
    created_at BIGINT NOT NULL,
    expires_at BIGINT NOT NULL,
    consumed_at BIGINT,
    status_checks INTEGER NOT NULL DEFAULT 0
  );
  CREATE INDEX IF NOT EXISTS attempts_open ON attempts(user_id, provider) WHERE consumed_at IS NULL;
  CREATE TABLE IF NOT EXISTS connections (
    user_id TEXT NOT NULL REFERENCES users(user_id),
    provider TEXT NOT NULL,
    connection_id TEXT NOT NULL UNIQUE,
    status TEXT NOT NULL,
    reason TEXT,
    account_label TEXT,
    scopes_json TEXT,
    connected_at BIGINT NOT NULL,
    last_checked_at BIGINT,
    PRIMARY KEY (user_id, provider)
  );
  CREATE TABLE IF NOT EXISTS cleanups (
    connection_id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    provider TEXT NOT NULL,
    state TEXT NOT NULL CHECK (state IN ('pending', 'failed')),
    attempts INTEGER NOT NULL,
    last_error TEXT,
    created_at BIGINT NOT NULL
  );
  CREATE TABLE IF NOT EXISTS receipts (
    operation_id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    created_at BIGINT NOT NULL,
    body TEXT NOT NULL,
    seq BIGINT GENERATED ALWAYS AS IDENTITY
  );
  CREATE INDEX IF NOT EXISTS receipts_user ON receipts(user_id, created_at);
  CREATE TABLE IF NOT EXISTS usage (
    counter TEXT NOT NULL,
    period TEXT NOT NULL,
    count INTEGER NOT NULL,
    PRIMARY KEY (counter, period)
  );
  CREATE TABLE IF NOT EXISTS approvals (
    approval_id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    capability TEXT NOT NULL,
    account_id TEXT NOT NULL,
    args_digest TEXT NOT NULL,
    created_at BIGINT NOT NULL,
    expires_at BIGINT NOT NULL,
    consumed_at BIGINT,
    outcome TEXT,
    external_id TEXT,
    finished_at BIGINT
  );
  CREATE INDEX IF NOT EXISTS approvals_writes ON approvals(user_id, capability, args_digest, finished_at);
  CREATE TABLE IF NOT EXISTS tool_switches (
    user_id TEXT NOT NULL,
    tool TEXT NOT NULL,
    enabled INTEGER NOT NULL,
    changed_at BIGINT NOT NULL,
    PRIMARY KEY (user_id, tool)
  );
  CREATE TABLE IF NOT EXISTS tool_receipts (
    operation_id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    created_at BIGINT NOT NULL,
    body TEXT NOT NULL,
    seq BIGINT GENERATED ALWAYS AS IDENTITY
  );
  CREATE INDEX IF NOT EXISTS tool_receipts_user ON tool_receipts(user_id, created_at);
  CREATE TABLE IF NOT EXISTS device_owner (
    slot INTEGER PRIMARY KEY CHECK (slot = 1),
    user_id TEXT NOT NULL,
    claimed_at BIGINT NOT NULL
  );
  CREATE TABLE IF NOT EXISTS documents (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    status TEXT NOT NULL,
    name TEXT NOT NULL,
    mime TEXT NOT NULL,
    body BYTEA,
    created_at BIGINT NOT NULL
  );
  CREATE INDEX IF NOT EXISTS documents_user ON documents(user_id, created_at);
  CREATE TABLE IF NOT EXISTS web_link_codes (
    code_hash TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    created_at BIGINT NOT NULL,
    expires_at BIGINT NOT NULL,
    consumed_at BIGINT
  );
  CREATE INDEX IF NOT EXISTS web_link_codes_user ON web_link_codes(user_id);
  CREATE TABLE IF NOT EXISTS web_sessions (
    session_id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    token_hash TEXT NOT NULL UNIQUE,
    browser TEXT NOT NULL,
    os TEXT NOT NULL,
    created_at BIGINT NOT NULL,
    last_seen_at BIGINT NOT NULL,
    expires_at BIGINT NOT NULL,
    revoked_at BIGINT
  );
  CREATE INDEX IF NOT EXISTS web_sessions_user ON web_sessions(user_id, created_at);
`;

/** A browser signed in to Doddy Web (ADR-585). The cookie's token is stored only as a hash. */
export interface WebSessionRow {
  session_id: string;
  user_id: string;
  browser: string;
  os: string;
  created_at: number;
  last_seen_at: number;
  expires_at: number;
}

/** A document without its file, for lists (ADR-585). */
export interface DocumentSummaryRow {
  id: string;
  status: DocumentRow["status"];
  name: string;
  mime: string;
  size: number | null;
  created_at: number;
}

/** A file Claude makes for the user (ADR-564). Kept a week, then pruned. */
export interface DocumentRow {
  id: string;
  user_id: string;
  /** `working` while Claude makes it, then `ready` (with a body) or `failed`. */
  status: "working" | "ready" | "failed";
  name: string;
  mime: string;
  body: Buffer | null;
  created_at: number;
}

export class Store {
  private constructor(readonly db: Database) {}

  /** Opens the database and makes sure every table exists. */
  static async open(options: DatabaseOptions): Promise<Store> {
    const db = await openDatabase(options);
    try {
      await db.transaction(async (tx) => {
        for (const statement of SCHEMA_SQL.split(";").map((s) => s.trim()).filter(Boolean)) await tx.query(statement);
      });
    } catch (error) {
      await db.close().catch(() => {});
      throw error;
    }
    return new Store(db);
  }

  /** A fresh in-memory store (tests, mock mode). */
  static memory(): Promise<Store> {
    return Store.open({});
  }

  close(): Promise<void> {
    return this.db.close();
  }

  private async one<T>(q: Queryable, sql: string, params: readonly unknown[]): Promise<T | null> {
    return ((await q.query<T>(sql, params)).rows[0] as T | undefined) ?? null;
  }

  // ------------------------------------------------------------ identity

  /** Stable, random Composio user ID per internal user. Never an email, never shared. */
  composioUserId(userId: string, now: number): Promise<string> {
    return this.db.transaction(async (tx) => {
      const row = await this.one<{ composio_user_id: string }>(tx, "SELECT composio_user_id FROM users WHERE user_id = $1", [userId]);
      if (row) return row.composio_user_id;
      const id = `doddy_${randomBytes(16).toString("hex")}`;
      await tx.query("INSERT INTO users (user_id, composio_user_id, created_at) VALUES ($1, $2, $3)", [userId, id, now]);
      return id;
    });
  }

  // ------------------------------------------------------------ attempts

  async createAttempt(input: {
    userId: string;
    provider: string;
    authConfigId: string;
    now: number;
    ttlSeconds: number;
  }): Promise<{ attemptId: string; nonce: string; expiresAt: number; superseded: QueuedCleanup[] }> {
    const attemptId = randomUUID();
    const nonce = randomBytes(32).toString("base64url");
    const expiresAt = input.now + input.ttlSeconds * 1000;
    const superseded = await this.db.transaction(async (tx) => {
      // A new attempt supersedes any unfinished one for the same user and provider. Its pending
      // connection can still be finished at the provider, so it is queued for removal now.
      const open = (await tx.query<AttemptRow>(
        "SELECT * FROM attempts WHERE user_id = $1 AND provider = $2 AND consumed_at IS NULL",
        [input.userId, input.provider],
      )).rows;
      const queued = await this.endAttempts(tx, open, input.now);
      await tx.query(
        `INSERT INTO attempts (attempt_id, user_id, provider, auth_config_id, nonce_hash, created_at, expires_at)
         VALUES ($1, $2, $3, $4, $5, $6, $7)`,
        [attemptId, input.userId, input.provider, input.authConfigId, sha256(nonce), input.now, expiresAt],
      );
      return queued;
    });
    return { attemptId, nonce, expiresAt, superseded };
  }

  /**
   * Records the pending connection the provider made for an attempt. If the attempt ended while
   * the link was being made (a newer Connect superseded it), the connection is queued for removal
   * instead and this returns false: no one can complete it through Doddy.
   */
  setPendingConnection(attemptId: string, pendingConnectionId: string | null, now: number): Promise<boolean> {
    return this.db.transaction(async (tx) => {
      const row = await this.one<AttemptRow>(tx, "SELECT * FROM attempts WHERE attempt_id = $1", [attemptId]);
      if (!row) return false;
      if (row.consumed_at !== null) {
        if (pendingConnectionId) await this.endAttempts(tx, [{ ...row, pending_connection_id: pendingConnectionId }], now);
        return false;
      }
      await tx.query("UPDATE attempts SET pending_connection_id = $1 WHERE attempt_id = $2", [pendingConnectionId, attemptId]);
      return true;
    });
  }

  /**
   * Ends every unfinished attempt of these providers that has expired (the user never came back,
   * or came back too late) and queues its pending connection for removal. Called hourly and on a
   * completion that arrives after expiry; optionally for one user only.
   */
  async expireAttempts(now: number, providers: readonly string[], userId?: string): Promise<QueuedCleanup[]> {
    if (providers.length === 0) return [];
    return this.db.transaction(async (tx) => {
      const rows = (userId === undefined
        ? await tx.query<AttemptRow>(
            "SELECT * FROM attempts WHERE consumed_at IS NULL AND expires_at <= $1 AND provider = ANY($2::text[])",
            [now, [...providers]],
          )
        : await tx.query<AttemptRow>(
            "SELECT * FROM attempts WHERE consumed_at IS NULL AND expires_at <= $1 AND user_id = $2 AND provider = ANY($3::text[])",
            [now, userId, [...providers]],
          )).rows;
      return this.endAttempts(tx, rows, now);
    });
  }

  /**
   * Marks the attempts ended and queues each pending connection for removal, unless it is a
   * connection Doddy recorded. Every pending connection was made by Doddy for this user's own
   * Composio id, so removing it never touches anyone else's. Runs inside the caller's transaction.
   */
  private async endAttempts(tx: Queryable, rows: readonly AttemptRow[], now: number): Promise<QueuedCleanup[]> {
    const queued: QueuedCleanup[] = [];
    for (const row of rows) {
      await tx.query("UPDATE attempts SET consumed_at = $1 WHERE attempt_id = $2 AND consumed_at IS NULL", [now, row.attempt_id]);
      const connectionId = row.pending_connection_id;
      if (!connectionId) continue;
      const recorded = await this.one(tx, "SELECT 1 AS one FROM connections WHERE connection_id = $1", [connectionId]);
      if (recorded) continue;
      await this.queueCleanupIn(tx, connectionId, row.user_id, row.provider, now);
      queued.push({ connectionId, userId: row.user_id, provider: row.provider });
    }
    return queued;
  }

  /**
   * Consumes the attempt exactly once. Fails for a wrong owner, provider, nonce, an expired or
   * already-consumed attempt. All checks and the consumption happen in one transaction.
   */
  consumeAttempt(input: { attemptId: string; userId: string; provider: string; nonce: string; now: number }): Promise<AttemptRow | null> {
    return this.db.transaction(async (tx) => {
      const row = await this.one<AttemptRow>(tx, "SELECT * FROM attempts WHERE attempt_id = $1", [input.attemptId]);
      if (!row) return null;
      const valid =
        row.user_id === input.userId &&
        row.provider === input.provider &&
        row.consumed_at === null &&
        row.expires_at > input.now &&
        row.nonce_hash === sha256(input.nonce);
      if (!valid) return null;
      const changed = await tx.query(
        "UPDATE attempts SET consumed_at = $1 WHERE attempt_id = $2 AND consumed_at IS NULL",
        [input.now, input.attemptId],
      );
      return changed.rowCount === 1 ? row : null;
    });
  }

  // ------------------------------------------------------------ connections

  getConnection(userId: string, provider: string): Promise<ConnectionRow | null> {
    return this.one<ConnectionRow>(this.db, "SELECT * FROM connections WHERE user_id = $1 AND provider = $2", [userId, provider]);
  }

  async upsertConnection(row: ConnectionRow): Promise<void> {
    await this.db.transaction(async (tx) => {
      // A connection ID can belong to exactly one Doddy user.
      const owner = await this.one<{ user_id: string }>(tx, "SELECT user_id FROM connections WHERE connection_id = $1", [row.connection_id]);
      if (owner && owner.user_id !== row.user_id) throw new Error("connection owned by another user");
      await tx.query(
        `INSERT INTO connections (user_id, provider, connection_id, status, reason, account_label, scopes_json, connected_at, last_checked_at)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
         ON CONFLICT (user_id, provider) DO UPDATE SET
           connection_id = EXCLUDED.connection_id, status = EXCLUDED.status, reason = EXCLUDED.reason,
           account_label = EXCLUDED.account_label, scopes_json = EXCLUDED.scopes_json,
           connected_at = EXCLUDED.connected_at, last_checked_at = EXCLUDED.last_checked_at`,
        [
          row.user_id,
          row.provider,
          row.connection_id,
          row.status,
          row.reason,
          row.account_label,
          row.scopes_json,
          row.connected_at,
          row.last_checked_at,
        ],
      );
    });
  }

  async updateConnectionStatus(userId: string, provider: string, status: ConnectionStatus, reason: ConnectionReason | null, now: number): Promise<void> {
    await this.db.query(
      "UPDATE connections SET status = $1, reason = $2, last_checked_at = $3 WHERE user_id = $4 AND provider = $5",
      [status, reason, now, userId, provider],
    );
  }

  async setAccountLabel(userId: string, provider: string, label: string | null): Promise<void> {
    await this.db.query("UPDATE connections SET account_label = $1 WHERE user_id = $2 AND provider = $3", [label, userId, provider]);
  }

  /** Removes the local connection (blocking new reads at once) and queues remote cleanup, atomically. */
  removeConnectionForCleanup(userId: string, provider: string, now: number): Promise<ConnectionRow | null> {
    return this.db.transaction(async (tx) => {
      const row = await this.one<ConnectionRow>(tx, "SELECT * FROM connections WHERE user_id = $1 AND provider = $2", [userId, provider]);
      if (!row) return null;
      await tx.query("DELETE FROM connections WHERE user_id = $1 AND provider = $2", [userId, provider]);
      await this.queueCleanupIn(tx, row.connection_id, userId, provider, now);
      return row;
    });
  }

  /** Queues remote removal of a connection Doddy never recorded (e.g. a completion that failed). */
  async queueCleanup(connectionId: string, userId: string, provider: string, now: number): Promise<void> {
    await this.queueCleanupIn(this.db, connectionId, userId, provider, now);
  }

  private async queueCleanupIn(q: Queryable, connectionId: string, userId: string, provider: string, now: number): Promise<void> {
    await q.query(
      `INSERT INTO cleanups (connection_id, user_id, provider, state, attempts, last_error, created_at)
       VALUES ($1, $2, $3, 'pending', 0, NULL, $4)
       ON CONFLICT (connection_id) DO UPDATE SET
         user_id = EXCLUDED.user_id, provider = EXCLUDED.provider, state = 'pending', attempts = 0,
         last_error = NULL, created_at = EXCLUDED.created_at`,
      [connectionId, userId, provider, now],
    );
  }

  async finishCleanup(connectionId: string): Promise<void> {
    await this.db.query("DELETE FROM cleanups WHERE connection_id = $1", [connectionId]);
  }

  async failCleanup(connectionId: string, errorCode: string): Promise<void> {
    await this.db.query(
      "UPDATE cleanups SET state = 'failed', attempts = attempts + 1, last_error = $1 WHERE connection_id = $2",
      [errorCode, connectionId],
    );
  }

  /**
   * Queued removals of these providers to try again: older than `before` (so a request still
   * working on one isn't raced), tried fewer than `maxAttempts` times, oldest first.
   */
  async cleanupsToRetry(providers: readonly string[], before: number, maxAttempts: number, limit: number): Promise<QueuedCleanup[]> {
    if (providers.length === 0) return [];
    const rows = (await this.db.query<{ connection_id: string; user_id: string; provider: string }>(
      `SELECT connection_id, user_id, provider FROM cleanups
       WHERE provider = ANY($1::text[]) AND created_at < $2 AND attempts < $3
       ORDER BY created_at ASC LIMIT $4`,
      [[...providers], before, maxAttempts, limit],
    )).rows;
    return rows.map((r) => ({ connectionId: r.connection_id, userId: r.user_id, provider: r.provider }));
  }

  cleanupFor(userId: string, provider: string): Promise<CleanupRow | null> {
    return this.one<CleanupRow>(
      this.db,
      "SELECT * FROM cleanups WHERE user_id = $1 AND provider = $2 ORDER BY created_at DESC LIMIT 1",
      [userId, provider],
    );
  }

  // ------------------------------------------------------------ receipts

  async saveReceipt(userId: string, receipt: Receipt, now: number): Promise<void> {
    await this.db.query(
      "INSERT INTO receipts (operation_id, user_id, created_at, body) VALUES ($1, $2, $3, $4)",
      [receipt.operationId, userId, now, JSON.stringify(receipt)],
    );
  }

  async receipts(userId: string, limit: number): Promise<Receipt[]> {
    const rows = (await this.db.query<{ body: string }>(
      "SELECT body FROM receipts WHERE user_id = $1 ORDER BY created_at DESC, seq DESC LIMIT $2",
      [userId, limit],
    )).rows;
    return rows.map((r) => JSON.parse(r.body) as Receipt);
  }

  // ------------------------------------------------------------ online-account tools

  /** A missing row means off for an account tool; connecting writes every row on (ADR-563). Web tools read `toolSwitch` and default to on. */
  async toolEnabled(userId: string, tool: string): Promise<boolean> {
    const row = await this.one<{ enabled: number }>(this.db, "SELECT enabled FROM tool_switches WHERE user_id = $1 AND tool = $2", [userId, tool]);
    return row?.enabled === 1;
  }

  /** The switch as stored: true, false, or null when the user never touched it (ADR-563 defaults). */
  async toolSwitch(userId: string, tool: string): Promise<boolean | null> {
    const row = await this.one<{ enabled: number }>(this.db, "SELECT enabled FROM tool_switches WHERE user_id = $1 AND tool = $2", [userId, tool]);
    return row ? row.enabled === 1 : null;
  }

  async enabledTools(userId: string): Promise<Set<string>> {
    const rows = (await this.db.query<{ tool: string }>("SELECT tool FROM tool_switches WHERE user_id = $1 AND enabled = 1", [userId])).rows;
    return new Set(rows.map((r) => r.tool));
  }

  async setToolEnabled(userId: string, tool: string, enabled: boolean, now: number): Promise<void> {
    await this.setToolEnabledIn(this.db, userId, tool, enabled, now);
  }

  private async setToolEnabledIn(q: Queryable, userId: string, tool: string, enabled: boolean, now: number): Promise<void> {
    await q.query(
      `INSERT INTO tool_switches (user_id, tool, enabled, changed_at) VALUES ($1, $2, $3, $4)
       ON CONFLICT (user_id, tool) DO UPDATE SET enabled = EXCLUDED.enabled, changed_at = EXCLUDED.changed_at`,
      [userId, tool, enabled ? 1 : 0, now],
    );
  }

  /** Turns off every tool of the given names at once (used when an account is disconnected). */
  async disableTools(userId: string, tools: readonly string[], now: number): Promise<void> {
    await this.db.transaction(async (tx) => {
      for (const tool of tools) await this.setToolEnabledIn(tx, userId, tool, false, now);
    });
  }

  async saveToolReceipt(userId: string, receipt: { operationId: string }, now: number): Promise<void> {
    await this.db.query(
      "INSERT INTO tool_receipts (operation_id, user_id, created_at, body) VALUES ($1, $2, $3, $4)",
      [receipt.operationId, userId, now, JSON.stringify(receipt)],
    );
  }

  async toolReceipts(userId: string, limit: number): Promise<unknown[]> {
    const rows = (await this.db.query<{ body: string }>(
      "SELECT body FROM tool_receipts WHERE user_id = $1 ORDER BY created_at DESC, seq DESC LIMIT $2",
      [userId, limit],
    )).rows;
    return rows.map((r) => JSON.parse(r.body) as unknown);
  }

  // ------------------------------------------------------------ usage

  /**
   * Reserves `units` against every (counter, period, limit) atomically: either all counters are
   * incremented or none are. Counters live in the database, so they survive restarts.
   */
  reserveUsage(checks: readonly { counter: string; period: string; limit: number }[], units: number): Promise<boolean> {
    return this.db.transaction(async (tx) => {
      for (const c of checks) {
        const row = await this.one<{ count: number }>(tx, "SELECT count FROM usage WHERE counter = $1 AND period = $2", [c.counter, c.period]);
        if ((row?.count ?? 0) + units > c.limit) return false;
      }
      for (const c of checks) {
        await tx.query(
          `INSERT INTO usage (counter, period, count) VALUES ($1, $2, $3)
           ON CONFLICT (counter, period) DO UPDATE SET count = usage.count + EXCLUDED.count`,
          [c.counter, c.period, units],
        );
      }
      return true;
    });
  }

  /**
   * Retention (review 2026-10-11): drops attempts and approvals a day after they expire, usage
   * periods no limit reads any more, and receipts older than 90 days or beyond the newest 200 per
   * user (per table). Returns how many rows went, per table.
   */
  prune(now: number): Promise<Record<string, number>> {
    const DAY = 86_400_000;
    const dayCutoff = `day:${new Date(now - 62 * DAY).toISOString().slice(0, 10)}`;
    const monthCutoff = `month:${new Date(now - 400 * DAY).toISOString().slice(0, 7)}`;
    return this.db.transaction(async (tx) => {
      const run = async (sql: string, ...params: (string | number)[]) => (await tx.query(sql, params)).rowCount;
      const receipts = async (table: "receipts" | "tool_receipts") =>
        (await run(`DELETE FROM ${table} WHERE created_at < $1`, now - 90 * DAY)) +
        (await run(`DELETE FROM ${table} WHERE seq IN (
               SELECT seq FROM (SELECT seq, ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY created_at DESC, seq DESC) AS rn FROM ${table}) ranked
               WHERE rn > 200)`));
      return {
        attempts: await run("DELETE FROM attempts WHERE expires_at < $1", now - DAY),
        approvals: await run("DELETE FROM approvals WHERE expires_at < $1", now - DAY),
        usage:
          (await run("DELETE FROM usage WHERE period LIKE 'day:%' AND period < $1", dayCutoff)) +
          (await run("DELETE FROM usage WHERE period LIKE 'month:%' AND period < $1", monthCutoff)),
        receipts: await receipts("receipts"),
        toolReceipts: await receipts("tool_receipts"),
      };
    });
  }

  // ------------------------------------------------------------ device owner (ADR-563)

  /**
   * "Only me" for the beta: the first device user to sign in claims the server; the answer is the
   * owner's user ID afterwards. One row, slot 1; a second claim never replaces the first.
   */
  async claimDeviceOwner(userId: string, now: number): Promise<string> {
    await this.db.query("INSERT INTO device_owner (slot, user_id, claimed_at) VALUES (1, $1, $2) ON CONFLICT (slot) DO NOTHING", [userId, now]);
    const row = await this.one<{ user_id: string }>(this.db, "SELECT user_id FROM device_owner WHERE slot = 1", []);
    return row?.user_id ?? userId;
  }

  // ------------------------------------------------------------ documents (ADR-564)

  /** A new document while Claude works on it. Returns its unguessable ID (144 random bits). */
  async startDocument(userId: string, name: string, mime: string, now: number): Promise<string> {
    const id = randomBytes(18).toString("base64url");
    await this.db.query(
      "INSERT INTO documents (id, user_id, status, name, mime, body, created_at) VALUES ($1, $2, 'working', $3, $4, NULL, $5)",
      [id, userId, name, mime, now],
    );
    return id;
  }

  async finishDocument(id: string, name: string, mime: string, body: Buffer): Promise<void> {
    await this.db.query("UPDATE documents SET status = 'ready', name = $2, mime = $3, body = $4 WHERE id = $1", [id, name, mime, body]);
  }

  async failDocument(id: string): Promise<void> {
    await this.db.query("UPDATE documents SET status = 'failed', body = NULL WHERE id = $1 AND status = 'working'", [id]);
  }

  async getDocument(id: string): Promise<DocumentRow | null> {
    const row = await this.one<DocumentRow>(this.db, "SELECT id, user_id, status, name, mime, body, created_at FROM documents WHERE id = $1", [id]);
    if (!row) return null;
    return { ...row, body: row.body === null ? null : Buffer.from(row.body as unknown as Uint8Array) };
  }

  /** The user's own documents, newest first, without their files (ADR-585). */
  async listDocuments(userId: string, limit: number): Promise<DocumentSummaryRow[]> {
    return (
      await this.db.query<DocumentSummaryRow>(
        `SELECT id, status, name, mime, octet_length(body) AS size, created_at FROM documents
         WHERE user_id = $1 ORDER BY created_at DESC, id LIMIT $2`,
        [userId, limit],
      )
    ).rows;
  }

  /** One document, only when it belongs to `userId`; another user's ID reads as missing (the filter is in the query). */
  async getOwnDocument(userId: string, id: string): Promise<DocumentRow | null> {
    const row = await this.one<DocumentRow>(
      this.db,
      "SELECT id, user_id, status, name, mime, body, created_at FROM documents WHERE id = $1 AND user_id = $2",
      [id, userId],
    );
    if (!row) return null;
    return { ...row, body: row.body === null ? null : Buffer.from(row.body as unknown as Uint8Array) };
  }

  /** Documents older than a week go. Separate from `prune` so its counts stay as they were. */
  async pruneDocuments(now: number): Promise<number> {
    return (await this.db.query("DELETE FROM documents WHERE created_at < $1", [now - 7 * 86_400_000])).rowCount;
  }

  // ------------------------------------------------------------ Doddy Web (ADR-585)

  /** A new sign-in code for `userId`. Any earlier code of theirs stops working. */
  async createWebLinkCode(userId: string, codeHash: string, now: number, ttlMs: number): Promise<void> {
    await this.db.transaction(async (tx) => {
      await tx.query("DELETE FROM web_link_codes WHERE user_id = $1", [userId]);
      await tx.query("INSERT INTO web_link_codes (code_hash, user_id, created_at, expires_at) VALUES ($1, $2, $3, $4)", [codeHash, userId, now, now + ttlMs]);
    });
  }

  /**
   * Uses a sign-in code once and opens a browser session for its user, in one transaction: a code
   * that is unknown, used or expired opens nothing. Beyond `maxSessions`, the user's oldest live
   * sessions are signed out. Returns the user ID, or null.
   */
  async redeemWebLinkCode(input: {
    codeHash: string;
    session: { sessionId: string; tokenHash: string; browser: string; os: string; expiresAt: number };
    now: number;
    idleMs: number;
    maxSessions: number;
  }): Promise<string | null> {
    return this.db.transaction(async (tx) => {
      const used = await this.one<{ user_id: string }>(
        tx,
        "UPDATE web_link_codes SET consumed_at = $2 WHERE code_hash = $1 AND consumed_at IS NULL AND expires_at > $2 RETURNING user_id",
        [input.codeHash, input.now],
      );
      if (!used) return null;
      const s = input.session;
      await tx.query(
        `INSERT INTO web_sessions (session_id, user_id, token_hash, browser, os, created_at, last_seen_at, expires_at)
         VALUES ($1, $2, $3, $4, $5, $6, $6, $7)`,
        [s.sessionId, used.user_id, s.tokenHash, s.browser, s.os, input.now, s.expiresAt],
      );
      await tx.query(
        `UPDATE web_sessions SET revoked_at = $2 WHERE session_id IN (
           SELECT session_id FROM web_sessions
           WHERE user_id = $1 AND revoked_at IS NULL AND expires_at > $2 AND last_seen_at > $3
           ORDER BY created_at DESC, session_id OFFSET $4)`,
        [used.user_id, input.now, input.now - input.idleMs, input.maxSessions],
      );
      return used.user_id;
    });
  }

  /** The live session behind a cookie's token hash: not revoked, not expired, not idle too long. */
  async webSessionByToken(tokenHash: string, now: number, idleMs: number): Promise<WebSessionRow | null> {
    return this.one<WebSessionRow>(
      this.db,
      `SELECT session_id, user_id, browser, os, created_at, last_seen_at, expires_at FROM web_sessions
       WHERE token_hash = $1 AND revoked_at IS NULL AND expires_at > $2 AND last_seen_at > $3`,
      [tokenHash, now, now - idleMs],
    );
  }

  async touchWebSession(sessionId: string, now: number): Promise<void> {
    await this.db.query("UPDATE web_sessions SET last_seen_at = $2 WHERE session_id = $1 AND revoked_at IS NULL", [sessionId, now]);
  }

  /** The user's live browser sessions, newest first. */
  async webSessions(userId: string, now: number, idleMs: number, limit: number): Promise<WebSessionRow[]> {
    return (
      await this.db.query<WebSessionRow>(
        `SELECT session_id, user_id, browser, os, created_at, last_seen_at, expires_at FROM web_sessions
         WHERE user_id = $1 AND revoked_at IS NULL AND expires_at > $2 AND last_seen_at > $3
         ORDER BY created_at DESC, session_id LIMIT $4`,
        [userId, now, now - idleMs, limit],
      )
    ).rows;
  }

  /** Signs one browser out. False when it isn't one of `userId`'s live sessions. */
  async revokeWebSession(userId: string, sessionId: string, now: number): Promise<boolean> {
    const changed = await this.db.query("UPDATE web_sessions SET revoked_at = $3 WHERE session_id = $1 AND user_id = $2 AND revoked_at IS NULL", [sessionId, userId, now]);
    return changed.rowCount === 1;
  }

  /** Codes a day past their expiry, and sessions a day past being revoked, expiring or going idle. */
  async pruneWeb(now: number, idleMs: number): Promise<number> {
    const DAY = 86_400_000;
    return this.db.transaction(async (tx) => {
      const codes = (await tx.query("DELETE FROM web_link_codes WHERE expires_at < $1", [now - DAY])).rowCount;
      const sessions = (
        await tx.query("DELETE FROM web_sessions WHERE revoked_at < $1 OR expires_at < $1 OR last_seen_at < $2", [now - DAY, now - idleMs - DAY])
      ).rowCount;
      return codes + sessions;
    });
  }

  async usage(counter: string, period: string): Promise<number> {
    const row = await this.one<{ count: number }>(this.db, "SELECT count FROM usage WHERE counter = $1 AND period = $2", [counter, period]);
    return row?.count ?? 0;
  }

  // ------------------------------------------------------------ approvals

  async createApproval(input: {
    userId: string;
    capability: string;
    accountId: string;
    argsDigest: string;
    now: number;
    ttlSeconds: number;
  }): Promise<{ approvalId: string; expiresAt: number }> {
    const approvalId = randomUUID();
    const expiresAt = input.now + input.ttlSeconds * 1000;
    await this.db.query(
      `INSERT INTO approvals (approval_id, user_id, capability, account_id, args_digest, created_at, expires_at)
       VALUES ($1, $2, $3, $4, $5, $6, $7)`,
      [approvalId, input.userId, input.capability, input.accountId, input.argsDigest, input.now, expiresAt],
    );
    return { approvalId, expiresAt };
  }

  consumeApproval(input: {
    approvalId: string;
    userId: string;
    capability: string;
    accountId: string;
    argsDigest: string;
    now: number;
  }, opts: { checkOnly?: boolean } = {}): Promise<boolean> {
    return this.db.transaction(async (tx) => {
      const row = await this.one<{ user_id: string; capability: string; account_id: string; args_digest: string; expires_at: number; consumed_at: number | null }>(
        tx,
        "SELECT * FROM approvals WHERE approval_id = $1",
        [input.approvalId],
      );
      if (
        !row ||
        row.user_id !== input.userId ||
        row.capability !== input.capability ||
        row.account_id !== input.accountId ||
        row.args_digest !== input.argsDigest ||
        row.consumed_at !== null ||
        row.expires_at <= input.now
      ) {
        return false;
      }
      // checkOnly: would it be accepted? Lets the caller pass its limits first without burning it.
      if (opts.checkOnly) return true;
      const changed = await tx.query(
        "UPDATE approvals SET consumed_at = $1 WHERE approval_id = $2 AND consumed_at IS NULL",
        [input.now, input.approvalId],
      );
      return changed.rowCount === 1;
    });
  }

  /** Records what happened after a used approval ran (ADR-322). Only the first record counts. */
  async finishApproval(approvalId: string, outcome: WriteOutcome, externalId: string | null, now: number): Promise<void> {
    await this.db.query(
      "UPDATE approvals SET outcome = $1, external_id = $2, finished_at = $3 WHERE approval_id = $4 AND consumed_at IS NOT NULL AND outcome IS NULL",
      [outcome, externalId, now, approvalId],
    );
  }

  /**
   * What happened when this approval was used, for the same user, tool, account and (unless
   * `argsDigest` is null, for a tool whose approval is bound to a looked-up target) arguments.
   * Null when it was never used. `outcome` null: used, but its run hasn't finished (or the server
   * stopped mid-run), so it may or may not have gone through.
   */
  async approvalOutcome(input: { approvalId: string; userId: string; capability: string; accountId: string; argsDigest: string | null }): Promise<{
    outcome: WriteOutcome | null;
    externalId: string | null;
  } | null> {
    const row = await this.one<{ outcome: WriteOutcome | null; external_id: string | null }>(
      this.db,
      `SELECT outcome, external_id FROM approvals
       WHERE approval_id = $1 AND user_id = $2 AND capability = $3 AND account_id = $4
         AND ($5::text IS NULL OR args_digest = $5) AND consumed_at IS NOT NULL`,
      [input.approvalId, input.userId, input.capability, input.accountId, input.argsDigest],
    );
    return row ? { outcome: row.outcome, externalId: row.external_id } : null;
  }

  /** The newest run of the same write (user, tool, arguments) since `since` that did or may have gone through. */
  async latestWrite(input: { userId: string; capability: string; argsDigest: string; since: number }): Promise<{ outcome: WriteOutcome; finishedAt: number } | null> {
    const row = await this.one<{ outcome: WriteOutcome; finished_at: number }>(
      this.db,
      `SELECT outcome, finished_at FROM approvals
       WHERE user_id = $1 AND capability = $2 AND args_digest = $3 AND finished_at >= $4 AND outcome IN ('succeeded', 'outcome_unknown')
       ORDER BY finished_at DESC LIMIT 1`,
      [input.userId, input.capability, input.argsDigest, input.since],
    );
    return row ? { outcome: row.outcome, finishedAt: row.finished_at } : null;
  }
}

/** How a used approval's run ended (ADR-322). */
export type WriteOutcome = "succeeded" | "outcome_unknown" | "failed";
