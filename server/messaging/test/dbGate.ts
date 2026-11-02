import { closeSync, openSync, readdirSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

export type DbGate = "run" | "skip-with-warning" | "fail";

/** What the database-backed suites do: run with a database, fail loudly in CI without one, otherwise skip with a warning. */
export function dbGate(env: { TEST_DATABASE_URL?: string; CI?: string }): DbGate {
  if (env.TEST_DATABASE_URL) return "run";
  return env.CI ? "fail" : "skip-with-warning";
}

/** The compiled test files that use the database. */
function dbSuites(): string[] {
  const dir = path.dirname(fileURLToPath(import.meta.url));
  return readdirSync(dir).filter((f) => f.endsWith(".test.js") && readFileSync(path.join(dir, f), "utf8").includes("dbSkip"));
}

/** Applies dbGate to the real environment: throws in CI, warns once per test run (every test file is its own process). */
export function enforceDbGate(env: NodeJS.ProcessEnv = process.env): string | false {
  const gate = dbGate(env);
  if (gate === "run") return false;
  const suites = dbDescribe();
  if (gate === "fail") {
    throw new Error(`TEST_DATABASE_URL is not set in CI: ${suites} database-backed test files would be skipped silently. Set it to a disposable Postgres database.`);
  }
  const message = `WARNING: TEST_DATABASE_URL is not set, so ${suites} database-backed test files are skipped (the summary still says "skipped 0"). `
    + "Run them with: TEST_DATABASE_URL=postgres://user@host:port/disposable_db npm test";
  try {
    // node --test starts one process per file; the first one to get here prints, the others stay quiet.
    closeSync(openSync(path.join(tmpdir(), `doddy-db-skip-warned-${process.ppid}`), "wx"));
  } catch (err) {
    if ((err as NodeJS.ErrnoException).code === "EEXIST") return message;
  }
  console.error(message);
  return message;
}

function dbDescribe(): string {
  const files = dbSuites();
  return `${files.length} (${files.map((f) => f.replace(/\.test\.js$/, "")).join(", ")})`;
}
