// Merged migrations are frozen (engineering audit, 7 Nov 2026). migrate() in src/db.ts records each
// file by its name and applies the files in name order. So renaming an applied file runs it a second
// time, and a new file that sorts before an applied one runs in one order on a fresh database and in
// another on an existing one. That was the hazard with 011_scheduled_calls.sql, which waited on old
// branches while 012 to 016 were applied on the live database; it is 020_scheduled_calls.sql now.
//
// FROZEN is every migration on `main`, in order. A pull request that adds a migration appends its
// file name here in the same commit; the new file's number must sort after the last entry. Never
// rename, reorder or remove an entry.
import assert from "node:assert/strict";
import { readdirSync } from "node:fs";
import path from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

// dist/test/migrationsFrozen.test.js → ../../migrations, as src/db.ts finds them from dist/src.
const migrationsDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../migrations");

const FROZEN = [
  "001_init.sql",
  "002_calls.sql",
  "003_news.sql",
  "004_news_in_app.sql",
  "005_security_hardening.sql",
  "006_idempotency_payload.sql",
  "007_outbound_body_encryption.sql",
  "008_call_cases.sql",
  "009_errands.sql",
  "010_assistant_usage.sql",
  "012_deals_usage.sql",
  "013_price_watches.sql",
  "014_sms_chat.sql",
  "015_server_usage.sql",
  "016_abuse_limits.sql",
  "017_calls_through_server.sql",
  "017_studio.sql",
  "018_approved_texts.sql",
  "019_texts_to_doddy.sql",
  "020_scheduled_calls.sql",
  "021_account_subject.sql",
  "022_call_tasks.sql",
  "023_file_watches.sql",
  "024_callback_routes.sql",
  "025_phone_recaps.sql",
  "026_radar_alerts.sql",
  "027_uber_deliveries.sql",
  "028_book_calls.sql",
  "029_leaflet_catalog.sql",
  "030_account_quotas.sql",
  "032_task_call_records.sql",
  "034_callback_route_limits.sql",
];

// 017 is shared by two files merged side by side. They sort the same on every database, so it is
// harmless, but it is the one number allowed to repeat. Neither had run on the live database when this
// was written (messaging was live at d1fe49b); once a deploy applies them, renaming either is a break.
const SHARED_NUMBER = "017";
const SHARED_FILES = ["017_calls_through_server.sql", "017_studio.sql"];

const migrationFiles = (): string[] =>
  readdirSync(migrationsDir).filter((f) => /^\d+_.+\.sql$/.test(f)).sort();

test("merged migrations keep their file names and their order", () => {
  const files = migrationFiles();
  assert.deepEqual(files.slice(0, FROZEN.length), FROZEN,
    "a merged migration was renamed or removed, or a new file sorts before one: give the new file a number after "
    + FROZEN[FROZEN.length - 1]);
});

test("every migration file is listed, so a rename after merge is caught", () => {
  assert.deepEqual(migrationFiles(), FROZEN, "append a new migration's file name to FROZEN in the same commit");
});

test("migration numbers are unique, except the two 017 files", () => {
  const files = migrationFiles();
  const numbers = files.map((f) => f.split("_")[0]).filter((n) => n !== SHARED_NUMBER);
  assert.equal(new Set(numbers).size, numbers.length, "two migration files share a number");
  assert.deepEqual(files.filter((f) => f.startsWith(`${SHARED_NUMBER}_`)), SHARED_FILES,
    "017 is shared by exactly these two files; give a new migration the next free number");
});
