import { Store } from "./store.js";

/**
 * Operator-only: lists the removals owed at a provider that are stuck (ADR-674): an online account's
 * connection at Composio, or a Supabase user (`supabase_auth`), that failed CLEANUP_RETRY.stuckAfter
 * times, or that this server has no way to remove (`no_remover`). The hourly sweeps keep trying each
 * one; this shows which to look at by hand. Read-only.
 *
 *   DATABASE_URL=postgres://… npm run cleanups:stuck
 *
 * Prints one line per removal: its kind, the provider's id for it (what to remove at the provider),
 * tries so far, the last error code, and when it was queued, reported stuck and is next tried. It
 * never prints whose it was. Without DATABASE_URL it opens the local PGlite directory (DODDY_DB_PATH).
 */
const url = process.env.DATABASE_URL?.trim() || undefined;
const store = await Store.open({
  url,
  caCert: process.env.DATABASE_CA_CERT?.trim() || undefined,
  dataDir: url ? undefined : (process.env.DODDY_DB_PATH ?? "./data/doddy-backend.pglite"),
});
const iso = (ms: number | null) => (ms === null ? "-" : new Date(Number(ms)).toISOString());
try {
  const stuck = await store.stuckCleanups();
  process.stdout.write(`${stuck.length} stuck removal(s).\n`);
  for (const row of stuck) {
    process.stdout.write(
      `${row.provider}\t${row.connection_id}\ttries ${row.attempts}\t${row.last_error ?? "-"}\tqueued ${iso(row.created_at)}\tstuck ${iso(row.stuck_at)}\tnext ${iso(row.next_try_at)}\n`,
    );
  }
} finally {
  await store.close();
}
