// File-ready pushes (owner, 9 Nov 2026). The app registers the signed link of a file Doddy's backend is making
// (`make_document`, ADR-564); a worker pass asks that link, with `?status=1`, whether the file is ready, and queues one
// push with no words. Nothing here sees the file. The link is a capability, so it is stored encrypted and only a link on
// the configured origin is accepted (a client can't make this server fetch an address of its choosing).
import { randomUUID } from "node:crypto";
import type pg from "pg";
import { z } from "zod";
import type { TextCipher } from "./crypto.js";
import { inTransaction, type Db } from "./db.js";
import { canPush, enqueue } from "./outbox.js";
import type { PushSender } from "./providers/types.js";

export const MAX_OPEN_WATCHES = 10;
/** A file is asked about this often. The backend's reply is a few bytes. */
export const CHECK_EVERY_MS = 12_000;
/** A file still "working" after this is dropped without a push; the backend marks it interrupted on its own. */
export const WATCH_FOR_MS = 15 * 60_000;
const BATCH = 20;
const STATUS_TIMEOUT_MS = 8_000;
const LINK_MAX = 400;
const KEEP_FINISHED_MS = 24 * 3600_000;

export const PUSH_TEXT = {
  ready: { pl: "Gotowe. Twój plik czeka w aplikacji.", en: "Ready. Your file is waiting in the app." },
  failed: { pl: "Nie udało się przygotować pliku.", en: "Doddy couldn't finish a file." },
} as const;
export const pushText = (kind: keyof typeof PUSH_TEXT, language: string) => (language === "pl" ? PUSH_TEXT[kind].pl : PUSH_TEXT[kind].en);

export interface FileWatchContext {
  db: Db;
  cipher: TextCipher;
  push: PushSender | undefined;
  /** `DOCUMENTS_ORIGIN`, no trailing slash. */
  origin: string;
  fetcher: typeof fetch;
  now: () => Date;
  log: (msg: string, extra?: object) => void;
}

export interface FileWatchDeps {
  origin: string | null;
  fetcher?: typeof fetch;
  now?: () => Date;
}

/** Off without a cipher (the link is stored encrypted) or without the backend's address. */
export function fileWatchContext(db: Db, deps: FileWatchDeps | undefined, cipher: TextCipher | undefined, push: PushSender | undefined,
  log: (msg: string, extra?: object) => void): FileWatchContext | undefined {
  if (!cipher || !deps?.origin) return undefined;
  return { db, cipher, push, origin: deps.origin, fetcher: deps.fetcher ?? fetch, now: deps.now ?? (() => new Date()), log };
}

export const linkAad = (accountId: string, watchId: string) => `${accountId}:file-watch:${watchId}`;

const body = z.strictObject({ url: z.string().min(20).max(LINK_MAX), language: z.enum(["pl", "en"]) });

/** The document id and the link to ask about, or null for anything that is not a Doddy document link on `origin`. */
export function watchedLink(origin: string, text: string): { documentId: string; link: string } | null {
  let url: URL;
  try {
    url = new URL(text);
  } catch {
    return null;
  }
  if (url.origin !== origin || url.username || url.password || url.hash) return null;
  const match = /^\/v1\/documents\/([A-Za-z0-9_-]{24})$/.exec(url.pathname);
  if (!match) return null;
  const exp = url.searchParams.get("exp");
  const sig = url.searchParams.get("sig");
  if (!exp || !/^\d{1,12}$/.test(exp) || !sig || !/^[A-Za-z0-9_-]{20,64}$/.test(sig)) return null;
  // Rebuilt from its parts, so nothing else the client sent rides along.
  return { documentId: match[1]!, link: `${origin}/v1/documents/${match[1]}?exp=${exp}&sig=${sig}` };
}

export type RegisterResult = { ok: true; id: string } | { ok: false; status: number; error: string };

export async function registerWatch(ctx: FileWatchContext, accountId: string, raw: unknown): Promise<RegisterResult> {
  const parsed = body.safeParse(raw);
  if (!parsed.success) return { ok: false, status: 400, error: "invalid_request" };
  const watched = watchedLink(ctx.origin, parsed.data.url);
  if (!watched) return { ok: false, status: 400, error: "invalid_link" };
  const now = ctx.now();
  return inTransaction(ctx.db, async (c) => {
    const existing = await c.query<{ id: string }>(
      "SELECT id FROM file_watches WHERE account_id = $1 AND document_id = $2", [accountId, watched.documentId]);
    if (existing.rows[0]) return { ok: true as const, id: existing.rows[0].id };
    const open = await c.query<{ n: string }>(
      "SELECT count(*) AS n FROM file_watches WHERE account_id = $1 AND state = 'watching'", [accountId]);
    if (Number(open.rows[0]!.n) >= MAX_OPEN_WATCHES) return { ok: false as const, status: 409, error: "too_many_open" };
    const id = randomUUID();
    await c.query(
      `INSERT INTO file_watches (id, account_id, document_id, link_ciphertext, language, created_at, expires_at)
       VALUES ($1, $2, $3, $4, $5, $6, $7)`,
      [id, accountId, watched.documentId, ctx.cipher.encrypt(watched.link, linkAad(accountId, id)), parsed.data.language, now,
        new Date(now.getTime() + WATCH_FOR_MS)]);
    return { ok: true as const, id };
  });
}

type Status = "working" | "ready" | "failed" | "gone" | "unknown";

/** Asks the backend about one link. A network error or an odd reply is "unknown": asked again next time. */
async function askStatus(ctx: FileWatchContext, link: string): Promise<Status> {
  try {
    const res = await ctx.fetcher(`${link}&status=1`, {
      method: "GET", redirect: "error", signal: AbortSignal.timeout(STATUS_TIMEOUT_MS), headers: { accept: "application/json" },
    });
    if (res.status === 404) return "gone";
    if (res.status !== 200) return "unknown";
    const text = (await res.text()).slice(0, 200);
    const value = (JSON.parse(text) as { status?: unknown }).status;
    return value === "working" || value === "ready" || value === "failed" ? value : "unknown";
  } catch {
    return "unknown";
  }
}

interface WatchRow { id: string; account_id: string; link_ciphertext: Buffer; language: string; expires_at: Date }

/** One pass: asks about the files that are due, pushes for the ones that finished, drops the old and the gone. */
export async function runFileWatchPass(ctx: FileWatchContext): Promise<Record<string, number>> {
  const now = ctx.now();
  const counts: Record<string, number> = {};
  const due = await inTransaction(ctx.db, async (c) => {
    const { rows } = await c.query<WatchRow>(
      `SELECT id, account_id, link_ciphertext, language, expires_at FROM file_watches
        WHERE state = 'watching' AND (last_checked_at IS NULL OR last_checked_at < $1)
        ORDER BY last_checked_at NULLS FIRST LIMIT ${BATCH} FOR UPDATE SKIP LOCKED`,
      [new Date(now.getTime() - CHECK_EVERY_MS)]);
    if (rows.length) await c.query("UPDATE file_watches SET last_checked_at = $2 WHERE id = ANY($1::uuid[])", [rows.map((r) => r.id), now]);
    return rows;
  });
  for (const row of due) {
    let link: string;
    try {
      link = ctx.cipher.decrypt(row.link_ciphertext, linkAad(row.account_id, row.id));
    } catch {
      await finish(ctx.db, row.id, "gone", now);
      counts.undecryptable = (counts.undecryptable ?? 0) + 1;
      continue;
    }
    const status = await askStatus(ctx, link);
    if (status === "ready" || status === "failed") {
      await inTransaction(ctx.db, async (c) => {
        await notify(ctx, c, row, status, now);
        await c.query("UPDATE file_watches SET state = 'notified', finished_at = $2 WHERE id = $1", [row.id, now]);
      });
      counts[status] = (counts[status] ?? 0) + 1;
    } else if (status === "gone" || now >= row.expires_at) {
      await finish(ctx.db, row.id, "gone", now);
      counts.dropped = (counts.dropped ?? 0) + 1;
    }
  }
  const tidied = await ctx.db.query(
    "DELETE FROM file_watches WHERE state <> 'watching' AND finished_at < $1", [new Date(now.getTime() - KEEP_FINISHED_MS)]);
  if (tidied.rowCount) counts.tidied = tidied.rowCount;
  return counts;
}

async function finish(db: Db, id: string, state: "notified" | "gone", now: Date) {
  await db.query("UPDATE file_watches SET state = $2, finished_at = $3 WHERE id = $1 AND state = 'watching'", [id, state, now]);
}

/** One push with a fixed sentence, never a file name or any words of the file; dropped if no device can receive it. */
async function notify(ctx: FileWatchContext, c: pg.PoolClient, row: WatchRow, kind: "ready" | "failed", now: Date) {
  if (ctx.push && await canPush(c, row.account_id)) {
    await enqueue(c, row.account_id, ["push"], pushText(kind, row.language), now, `file-watch:${row.id}`, { cipher: ctx.cipher });
  }
}
