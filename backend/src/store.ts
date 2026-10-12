import { createHash, randomBytes, randomUUID } from "node:crypto";
import { mkdirSync } from "node:fs";
import { dirname } from "node:path";
import { DatabaseSync } from "node:sqlite";
import type { ConnectionReason, ConnectionStatus, Receipt } from "./contracts.js";

/**
 * Small durable store (node:sqlite). Holds only what the backend needs: the internal-user →
 * Composio-user mapping, connection attempts, one connection per user, sanitized receipts, usage
 * counters and confirmation approvals. No calendar content, memories, chat or contacts.
 * Ownership changes, nonce consumption and usage reservations run inside transactions.
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

export class Store {
  readonly db: DatabaseSync;

  constructor(path: string) {
    if (path !== ":memory:") mkdirSync(dirname(path), { recursive: true });
    this.db = new DatabaseSync(path);
    this.db.exec(`
      PRAGMA journal_mode = WAL;
      PRAGMA foreign_keys = ON;
      PRAGMA secure_delete = ON;
      CREATE TABLE IF NOT EXISTS users (
        user_id TEXT PRIMARY KEY,
        composio_user_id TEXT NOT NULL UNIQUE,
        created_at INTEGER NOT NULL
      );
      CREATE TABLE IF NOT EXISTS attempts (
        attempt_id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL REFERENCES users(user_id),
        provider TEXT NOT NULL,
        auth_config_id TEXT NOT NULL,
        pending_connection_id TEXT,
        nonce_hash TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        expires_at INTEGER NOT NULL,
        consumed_at INTEGER,
        status_checks INTEGER NOT NULL DEFAULT 0
      );
      CREATE TABLE IF NOT EXISTS connections (
        user_id TEXT NOT NULL REFERENCES users(user_id),
        provider TEXT NOT NULL,
        connection_id TEXT NOT NULL UNIQUE,
        status TEXT NOT NULL,
        reason TEXT,
        account_label TEXT,
        scopes_json TEXT,
        connected_at INTEGER NOT NULL,
        last_checked_at INTEGER,
        PRIMARY KEY (user_id, provider)
      );
      CREATE TABLE IF NOT EXISTS cleanups (
        connection_id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        provider TEXT NOT NULL,
        state TEXT NOT NULL,
        attempts INTEGER NOT NULL,
        last_error TEXT,
        created_at INTEGER NOT NULL
      );
      CREATE TABLE IF NOT EXISTS receipts (
        operation_id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        body TEXT NOT NULL
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
        created_at INTEGER NOT NULL,
        expires_at INTEGER NOT NULL,
        consumed_at INTEGER
      );
      CREATE TABLE IF NOT EXISTS tool_switches (
        user_id TEXT NOT NULL,
        tool TEXT NOT NULL,
        enabled INTEGER NOT NULL,
        changed_at INTEGER NOT NULL,
        PRIMARY KEY (user_id, tool)
      );
      CREATE TABLE IF NOT EXISTS tool_receipts (
        operation_id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        body TEXT NOT NULL
      );
      CREATE INDEX IF NOT EXISTS tool_receipts_user ON tool_receipts(user_id, created_at);
      CREATE TABLE IF NOT EXISTS payment_receipts (
        operation_id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        body TEXT NOT NULL
      );
      CREATE INDEX IF NOT EXISTS payment_receipts_user ON payment_receipts(user_id, created_at);
      -- One row per payment attempt, written BEFORE anything is sent, so a crash leaves a visible
      -- "unconfirmed" row instead of nothing. Host and amount only: never the page path or query.
      CREATE TABLE IF NOT EXISTS payments (
        payment_id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        host TEXT NOT NULL,
        amount INTEGER NOT NULL,
        network TEXT NOT NULL,
        url_hash TEXT NOT NULL,
        valid_before INTEGER NOT NULL,
        status TEXT NOT NULL,
        transaction_hash TEXT
      );
      CREATE INDEX IF NOT EXISTS payments_user ON payments(user_id, created_at);
    `);
  }

  close(): void {
    this.db.close();
  }

  transaction<T>(fn: () => T): T {
    this.db.exec("BEGIN IMMEDIATE");
    try {
      const result = fn();
      this.db.exec("COMMIT");
      return result;
    } catch (error) {
      this.db.exec("ROLLBACK");
      throw error;
    }
  }

  // ------------------------------------------------------------ identity

  /** Stable, random Composio user ID per internal user. Never an email, never shared. */
  composioUserId(userId: string, now: number): string {
    return this.transaction(() => {
      const row = this.db.prepare("SELECT composio_user_id FROM users WHERE user_id = ?").get(userId) as
        | { composio_user_id: string }
        | undefined;
      if (row) return row.composio_user_id;
      const id = `doddy_${randomBytes(16).toString("hex")}`;
      this.db.prepare("INSERT INTO users (user_id, composio_user_id, created_at) VALUES (?, ?, ?)").run(userId, id, now);
      return id;
    });
  }

  // ------------------------------------------------------------ attempts

  createAttempt(input: {
    userId: string;
    provider: string;
    authConfigId: string;
    now: number;
    ttlSeconds: number;
  }): { attemptId: string; nonce: string; expiresAt: number } {
    const attemptId = randomUUID();
    const nonce = randomBytes(32).toString("base64url");
    const expiresAt = input.now + input.ttlSeconds * 1000;
    this.transaction(() => {
      // A new attempt supersedes any unfinished one for the same user and provider.
      this.db
        .prepare("UPDATE attempts SET consumed_at = ? WHERE user_id = ? AND provider = ? AND consumed_at IS NULL")
        .run(input.now, input.userId, input.provider);
      this.db
        .prepare(
          `INSERT INTO attempts (attempt_id, user_id, provider, auth_config_id, nonce_hash, created_at, expires_at)
           VALUES (?, ?, ?, ?, ?, ?, ?)`,
        )
        .run(attemptId, input.userId, input.provider, input.authConfigId, sha256(nonce), input.now, expiresAt);
    });
    return { attemptId, nonce, expiresAt };
  }

  setPendingConnection(attemptId: string, pendingConnectionId: string | null): void {
    this.db.prepare("UPDATE attempts SET pending_connection_id = ? WHERE attempt_id = ?").run(pendingConnectionId, attemptId);
  }

  /**
   * Consumes the attempt exactly once. Fails for a wrong owner, provider, nonce, an expired or
   * already-consumed attempt. All checks and the consumption happen in one transaction.
   */
  consumeAttempt(input: { attemptId: string; userId: string; provider: string; nonce: string; now: number }): AttemptRow | null {
    return this.transaction(() => {
      const row = this.db.prepare("SELECT * FROM attempts WHERE attempt_id = ?").get(input.attemptId) as AttemptRow | undefined;
      if (!row) return null;
      const valid =
        row.user_id === input.userId &&
        row.provider === input.provider &&
        row.consumed_at === null &&
        row.expires_at > input.now &&
        row.nonce_hash === sha256(input.nonce);
      if (!valid) return null;
      const changed = this.db
        .prepare("UPDATE attempts SET consumed_at = ? WHERE attempt_id = ? AND consumed_at IS NULL")
        .run(input.now, input.attemptId);
      return changed.changes === 1 ? row : null;
    });
  }

  // ------------------------------------------------------------ connections

  getConnection(userId: string, provider: string): ConnectionRow | null {
    return (this.db.prepare("SELECT * FROM connections WHERE user_id = ? AND provider = ?").get(userId, provider) as
      | ConnectionRow
      | undefined) ?? null;
  }

  upsertConnection(row: ConnectionRow): void {
    this.transaction(() => {
      // A connection ID can belong to exactly one Doddy user.
      const owner = this.db.prepare("SELECT user_id FROM connections WHERE connection_id = ?").get(row.connection_id) as
        | { user_id: string }
        | undefined;
      if (owner && owner.user_id !== row.user_id) throw new Error("connection owned by another user");
      this.db
        .prepare(
          `INSERT INTO connections (user_id, provider, connection_id, status, reason, account_label, scopes_json, connected_at, last_checked_at)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
           ON CONFLICT (user_id, provider) DO UPDATE SET
             connection_id = excluded.connection_id, status = excluded.status, reason = excluded.reason,
             account_label = excluded.account_label, scopes_json = excluded.scopes_json,
             connected_at = excluded.connected_at, last_checked_at = excluded.last_checked_at`,
        )
        .run(
          row.user_id,
          row.provider,
          row.connection_id,
          row.status,
          row.reason,
          row.account_label,
          row.scopes_json,
          row.connected_at,
          row.last_checked_at,
        );
    });
  }

  updateConnectionStatus(userId: string, provider: string, status: ConnectionStatus, reason: ConnectionReason | null, now: number): void {
    this.db
      .prepare("UPDATE connections SET status = ?, reason = ?, last_checked_at = ? WHERE user_id = ? AND provider = ?")
      .run(status, reason, now, userId, provider);
  }

  setAccountLabel(userId: string, provider: string, label: string | null): void {
    this.db.prepare("UPDATE connections SET account_label = ? WHERE user_id = ? AND provider = ?").run(label, userId, provider);
  }

  /** Removes the local connection (blocking new reads at once) and queues remote cleanup, atomically. */
  removeConnectionForCleanup(userId: string, provider: string, now: number): ConnectionRow | null {
    return this.transaction(() => {
      const row = this.getConnection(userId, provider);
      if (!row) return null;
      this.db.prepare("DELETE FROM connections WHERE user_id = ? AND provider = ?").run(userId, provider);
      this.db
        .prepare(
          `INSERT OR REPLACE INTO cleanups (connection_id, user_id, provider, state, attempts, last_error, created_at)
           VALUES (?, ?, ?, 'pending', 0, NULL, ?)`,
        )
        .run(row.connection_id, userId, provider, now);
      return row;
    });
  }

  /** Queues remote removal of a connection Doddy never recorded (e.g. a completion that failed). */
  queueCleanup(connectionId: string, userId: string, provider: string, now: number): void {
    this.db
      .prepare(
        `INSERT OR REPLACE INTO cleanups (connection_id, user_id, provider, state, attempts, last_error, created_at)
         VALUES (?, ?, ?, 'pending', 0, NULL, ?)`,
      )
      .run(connectionId, userId, provider, now);
  }

  finishCleanup(connectionId: string): void {
    this.db.prepare("DELETE FROM cleanups WHERE connection_id = ?").run(connectionId);
  }

  failCleanup(connectionId: string, errorCode: string): void {
    this.db
      .prepare("UPDATE cleanups SET state = 'failed', attempts = attempts + 1, last_error = ? WHERE connection_id = ?")
      .run(errorCode, connectionId);
  }

  cleanupFor(userId: string, provider: string): CleanupRow | null {
    return (this.db
      .prepare("SELECT * FROM cleanups WHERE user_id = ? AND provider = ? ORDER BY created_at DESC LIMIT 1")
      .get(userId, provider) as CleanupRow | undefined) ?? null;
  }

  // ------------------------------------------------------------ receipts

  saveReceipt(userId: string, receipt: Receipt, now: number): void {
    this.db
      .prepare("INSERT INTO receipts (operation_id, user_id, created_at, body) VALUES (?, ?, ?, ?)")
      .run(receipt.operationId, userId, now, JSON.stringify(receipt));
  }

  receipts(userId: string, limit: number): Receipt[] {
    const rows = this.db
      .prepare("SELECT body FROM receipts WHERE user_id = ? ORDER BY created_at DESC, rowid DESC LIMIT ?")
      .all(userId, limit) as { body: string }[];
    return rows.map((r) => JSON.parse(r.body) as Receipt);
  }

  // ------------------------------------------------------------ online-account tools

  /** Tools start off. A missing row means off. */
  toolEnabled(userId: string, tool: string): boolean {
    const row = this.db.prepare("SELECT enabled FROM tool_switches WHERE user_id = ? AND tool = ?").get(userId, tool) as
      | { enabled: number }
      | undefined;
    return row?.enabled === 1;
  }

  enabledTools(userId: string): Set<string> {
    const rows = this.db.prepare("SELECT tool FROM tool_switches WHERE user_id = ? AND enabled = 1").all(userId) as { tool: string }[];
    return new Set(rows.map((r) => r.tool));
  }

  setToolEnabled(userId: string, tool: string, enabled: boolean, now: number): void {
    this.db
      .prepare(
        `INSERT INTO tool_switches (user_id, tool, enabled, changed_at) VALUES (?, ?, ?, ?)
         ON CONFLICT (user_id, tool) DO UPDATE SET enabled = excluded.enabled, changed_at = excluded.changed_at`,
      )
      .run(userId, tool, enabled ? 1 : 0, now);
  }

  /** Turns off every tool of the given names at once (used when an account is disconnected). */
  disableTools(userId: string, tools: readonly string[], now: number): void {
    this.transaction(() => {
      for (const tool of tools) this.setToolEnabled(userId, tool, false, now);
    });
  }

  saveToolReceipt(userId: string, receipt: { operationId: string }, now: number): void {
    this.db
      .prepare("INSERT INTO tool_receipts (operation_id, user_id, created_at, body) VALUES (?, ?, ?, ?)")
      .run(receipt.operationId, userId, now, JSON.stringify(receipt));
  }

  toolReceipts(userId: string, limit: number): unknown[] {
    const rows = this.db
      .prepare("SELECT body FROM tool_receipts WHERE user_id = ? ORDER BY created_at DESC, rowid DESC LIMIT ?")
      .all(userId, limit) as { body: string }[];
    return rows.map((r) => JSON.parse(r.body) as unknown);
  }

  // ------------------------------------------------------------ payments

  savePaymentReceipt(userId: string, receipt: { operationId: string }, now: number): void {
    this.db
      .prepare("INSERT INTO payment_receipts (operation_id, user_id, created_at, body) VALUES (?, ?, ?, ?)")
      .run(receipt.operationId, userId, now, JSON.stringify(receipt));
  }

  paymentReceipts(userId: string, limit: number): unknown[] {
    const rows = this.db
      .prepare("SELECT body FROM payment_receipts WHERE user_id = ? ORDER BY created_at DESC, rowid DESC LIMIT ?")
      .all(userId, limit) as { body: string }[];
    return rows.map((r) => JSON.parse(r.body) as unknown);
  }

  /** Written before the first byte of a payment is signed or sent. */
  insertPayment(row: { paymentId: string; userId: string; now: number; host: string; amount: number; network: string; urlHash: string; validBefore: number }): void {
    this.db
      .prepare(
        `INSERT INTO payments (payment_id, user_id, created_at, updated_at, host, amount, network, url_hash, valid_before, status)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'signing')`,
      )
      .run(row.paymentId, row.userId, row.now, row.now, row.host, row.amount, row.network, row.urlHash, row.validBefore);
  }

  setPaymentStatus(paymentId: string, status: "signing" | "sent" | "settled" | "declined" | "unknown" | "not_sent", now: number, transactionHash: string | null = null): void {
    this.db.prepare("UPDATE payments SET status = ?, updated_at = ?, transaction_hash = COALESCE(?, transaction_hash) WHERE payment_id = ?").run(status, now, transactionHash, paymentId);
  }

  /**
   * Payments that were sent but never confirmed: marked unknown, or still "signing"/"sent" long after
   * they should have finished (the server stopped mid-payment).
   */
  unresolvedPayments(userId: string, now: number, staleMs: number): number {
    const row = this.db
      .prepare(
        `SELECT COUNT(*) AS n FROM payments WHERE user_id = ?
           AND (status = 'unknown' OR (status IN ('signing', 'sent') AND updated_at < ?))`,
      )
      .get(userId, now - staleMs) as { n: number };
    return Number(row.n);
  }

  /** Same page paid (or maybe paid) recently and not confirmed either way: a second payment waits. */
  hasUnconfirmedPaymentFor(userId: string, urlHash: string, since: number): boolean {
    const row = this.db
      .prepare("SELECT 1 AS hit FROM payments WHERE user_id = ? AND url_hash = ? AND created_at >= ? AND status IN ('signing', 'sent', 'unknown') LIMIT 1")
      .get(userId, urlHash, since) as { hit: number } | undefined;
    return row !== undefined;
  }

  // ------------------------------------------------------------ usage

  /**
   * Reserves `units` against every (counter, period, limit) atomically: either all counters are
   * incremented or none are. Counters live in SQLite, so they survive restarts.
   */
  reserveUsage(checks: readonly { counter: string; period: string; limit: number }[], units: number): boolean {
    return this.transaction(() => {
      const get = this.db.prepare("SELECT count FROM usage WHERE counter = ? AND period = ?");
      for (const c of checks) {
        const row = get.get(c.counter, c.period) as { count: number } | undefined;
        if ((row?.count ?? 0) + units > c.limit) return false;
      }
      const add = this.db.prepare(
        `INSERT INTO usage (counter, period, count) VALUES (?, ?, ?)
         ON CONFLICT (counter, period) DO UPDATE SET count = count + excluded.count`,
      );
      for (const c of checks) add.run(c.counter, c.period, units);
      return true;
    });
  }

  /** Gives back a reservation that never turned into a provider call (floors at zero). */
  releaseUsage(checks: readonly { counter: string; period: string }[], units: number): void {
    this.transaction(() => {
      const sub = this.db.prepare("UPDATE usage SET count = MAX(0, count - ?) WHERE counter = ? AND period = ?");
      for (const c of checks) sub.run(units, c.counter, c.period);
    });
  }

  /**
   * Retention (review 2026-10-11): drops attempts and approvals a day after they expire, usage
   * periods no limit reads any more, and receipts older than 90 days or beyond the newest 200 per
   * user (per table). Returns how many rows went, per table.
   */
  prune(now: number): Record<string, number> {
    const DAY = 86_400_000;
    const dayCutoff = `day:${new Date(now - 62 * DAY).toISOString().slice(0, 10)}`;
    const monthCutoff = `month:${new Date(now - 400 * DAY).toISOString().slice(0, 7)}`;
    return this.transaction(() => {
      const run = (sql: string, ...params: (string | number)[]) => Number(this.db.prepare(sql).run(...params).changes);
      const receipts = (table: "receipts" | "tool_receipts" | "payment_receipts") =>
        run(`DELETE FROM ${table} WHERE created_at < ?`, now - 90 * DAY) +
        run(`DELETE FROM ${table} WHERE rowid IN (
               SELECT rowid FROM (SELECT rowid, ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY created_at DESC, rowid DESC) AS rn FROM ${table})
               WHERE rn > 200)`);
      return {
        attempts: run("DELETE FROM attempts WHERE expires_at < ?", now - DAY),
        approvals: run("DELETE FROM approvals WHERE expires_at < ?", now - DAY),
        usage:
          run("DELETE FROM usage WHERE period LIKE 'day:%' AND period < ?", dayCutoff) +
          run("DELETE FROM usage WHERE period LIKE 'month:%' AND period < ?", monthCutoff),
        receipts: receipts("receipts"),
        toolReceipts: receipts("tool_receipts"),
        paymentReceipts: receipts("payment_receipts"),
        payments: run("DELETE FROM payments WHERE created_at < ?", now - 90 * DAY),
      };
    });
  }

  usage(counter: string, period: string): number {
    const row = this.db.prepare("SELECT count FROM usage WHERE counter = ? AND period = ?").get(counter, period) as
      | { count: number }
      | undefined;
    return row?.count ?? 0;
  }

  // ------------------------------------------------------------ approvals

  createApproval(input: {
    userId: string;
    capability: string;
    accountId: string;
    argsDigest: string;
    now: number;
    ttlSeconds: number;
  }): { approvalId: string; expiresAt: number } {
    const approvalId = randomUUID();
    const expiresAt = input.now + input.ttlSeconds * 1000;
    this.db
      .prepare(
        `INSERT INTO approvals (approval_id, user_id, capability, account_id, args_digest, created_at, expires_at)
         VALUES (?, ?, ?, ?, ?, ?, ?)`,
      )
      .run(approvalId, input.userId, input.capability, input.accountId, input.argsDigest, input.now, expiresAt);
    return { approvalId, expiresAt };
  }

  consumeApproval(input: {
    approvalId: string;
    userId: string;
    capability: string;
    accountId: string;
    argsDigest: string;
    now: number;
  }, opts: { checkOnly?: boolean } = {}): boolean {
    return this.transaction(() => {
      const row = this.db.prepare("SELECT * FROM approvals WHERE approval_id = ?").get(input.approvalId) as
        | { user_id: string; capability: string; account_id: string; args_digest: string; expires_at: number; consumed_at: number | null }
        | undefined;
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
      return this.db.prepare("UPDATE approvals SET consumed_at = ? WHERE approval_id = ? AND consumed_at IS NULL").run(input.now, input.approvalId)
        .changes === 1;
    });
  }
}
