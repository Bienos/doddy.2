#!/usr/bin/env node
// Rewrites every encrypted row to the current MEMORY_ENCRYPTION_KEY version, for a key rotation (README, "Rotating
// MEMORY_ENCRYPTION_KEY"). Run `npm run build` first, with the same settings as the server:
//
//   MEMORY_ENCRYPTION_KEY=<new> MEMORY_ENCRYPTION_KEY_VERSION=2 \
//   MEMORY_ENCRYPTION_KEY_PREVIOUS=<old> MEMORY_ENCRYPTION_KEY_PREVIOUS_VERSION=1 \
//   DATABASE_URL=... node scripts/reencrypt.mjs [--dry-run] [--batch 100]
//
// --dry-run only counts the rows of each encrypted column per key version. Otherwise each row not on the current
// version is opened with the key of its stored version, sealed with the current key, written and read back, a batch
// per transaction (src/reencrypt.ts); it is safe to run while the server runs, and again. Prints names and counts only,
// never a key, a value or the database address. Exit code: 0 when no row is left on another version, 1 when some are
// (or cannot be read), 64 for a bad option, 2 when the settings or the database can't be used.

import { pathToFileURL } from "node:url";

const USAGE = "usage: node scripts/reencrypt.mjs [--dry-run] [--batch N]   (N from 1 to 10000; default 100)";

/** Parses the options. Pure. Returns { dryRun, batch } or { error }. */
export function parseArgs(argv) {
  const out = { dryRun: false, batch: 100 };
  const args = [...argv];
  while (args.length) {
    const a = args.shift();
    if (a === "--dry-run") out.dryRun = true;
    else if (a === "--batch") {
      const n = Number(args.shift());
      if (!Number.isInteger(n) || n < 1 || n > 10_000) return { error: "--batch needs a whole number from 1 to 10000" };
      out.batch = n;
    } else return { error: `unknown option ${a}` };
  }
  return out;
}

/** Returns the exit code. `io` is for tests: env, stdout, stderr. */
export async function run(argv, io = {}) {
  const env = io.env ?? process.env;
  const stdout = io.stdout ?? ((s) => process.stdout.write(`${s}\n`));
  const stderr = io.stderr ?? ((s) => process.stderr.write(`${s}\n`));
  const opts = parseArgs(argv);
  if (opts.error) {
    stderr(`${opts.error}\n${USAGE}`);
    return 64;
  }
  const { loadConfig } = await import("../dist/src/config.js");
  const { cipherFrom } = await import("../dist/src/crypto.js");
  const { createPool } = await import("../dist/src/db.js");
  const { countByVersion, reencryptAll } = await import("../dist/src/reencrypt.js");
  let config;
  let cipher;
  try {
    config = loadConfig(env);
    cipher = cipherFrom(config);
  } catch (err) {
    // loadConfig's and the cipher's messages name variables, never values.
    stderr(`settings: ${err.message}`);
    return 2;
  }
  if (!cipher) {
    stderr("MEMORY_ENCRYPTION_KEY is not set: there is nothing to encrypt with.");
    return 2;
  }
  const db = createPool(config.databaseUrl);
  try {
    stdout(`current key version ${cipher.keyVersion}; keys for versions ${cipher.versions.join(", ")}`);
    if (opts.dryRun) {
      let behind = 0;
      for (const c of await countByVersion(db)) {
        const parts = Object.entries(c.versions).map(([v, n]) => `version ${v}: ${n}`);
        stdout(`${c.table}.${c.column}: ${c.total} row(s)${parts.length ? ` (${parts.join(", ")})` : ""}`);
        behind += Object.entries(c.versions).filter(([v]) => v !== String(cipher.keyVersion)).reduce((n, [, k]) => n + k, 0);
      }
      stdout(behind ? `${behind} row(s) to rewrite (dry run: nothing changed)` : "every row is on the current version (dry run)");
      return behind ? 1 : 0;
    }
    let left = 0;
    let unreadable = 0;
    for (const r of await reencryptAll(db, cipher, { batch: opts.batch })) {
      stdout(`${r.table}.${r.column}: ${r.rewritten} rewritten, ${r.unreadable} unreadable, ${r.left} left`);
      left += r.left;
      unreadable += r.unreadable;
    }
    if (unreadable) {
      stdout(`${unreadable} row(s) could not be opened with the key of their version: is MEMORY_ENCRYPTION_KEY_PREVIOUS (with `
        + "MEMORY_ENCRYPTION_KEY_PREVIOUS_VERSION) set to the key they were written with? Keep the previous key until this reports 0.");
    }
    stdout(left ? `${left} row(s) left on another version` : "every row is on the current version: MEMORY_ENCRYPTION_KEY_PREVIOUS can be removed");
    return left ? 1 : 0;
  } catch (err) {
    // A database error's message can hold the address; only its code is shown.
    stderr(`stopped: ${typeof err?.code === "string" ? `database error ${err.code}` : err?.message ?? "error"}`);
    return 2;
  } finally {
    await db.end().catch(() => {});
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) process.exit(await run(process.argv.slice(2)));
