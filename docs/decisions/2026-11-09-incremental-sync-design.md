# Notes sync should be versioned and incremental, so two iPhones cannot overwrite each other

- **Date:** 2026-11-09
- **Decided by:** proposal, owner approval pending
- **Status:** proposed (nothing here is implemented)
- **Replaces:** none

## Why

Today's sync of kept notes to Doddy's server is a whole-list replacement with no revision:

- The iPhone (`WebMemoryModel.sendNotes`, `Packages/DoddyCore/.../WebMemoryModel.swift`) sends its full current list on every change (debounced 2 s), at launch, and on foreground, through `WebMemoryClient.replaceNotes` -> `PUT /v1/web/memory/notes`.
- The server (`MemoryService.replaceNotes`, `Store.replaceMemoryNotes`) deletes every note of the account and inserts the list it was sent, in one transaction. It stores `captured_at` and `received_at` but no revision, device id, or deletion marker. A note missing from the list is deleted.
- The browser only reads and deletes (`/v1/web/memory/...`); it cannot put notes.
- The iPhone sync switch is behind `IPHONE_SYNCS_MEMORY = false` in `web/src/memory/config.ts` until a device test passes (`docs/product/CLOUD_MEMORY.md`).

Consequences when one account has two iPhones (or one phone restored from a backup):

1. Phone 1 sends [A, B]; phone 2, which has not synced, sends [A]. The server now holds [A]; B is gone with no conflict reported to either phone (the success reply is `{count: 1}`).
2. An edit made on phone 1 is rolled back by phone 2's older copy of the same note (the server keeps whichever PUT arrived last).

Reproduced in `backend/test/memory-sync-overwrite.test.ts`. The repo has no xfail pattern, so the two tests are written as characterization tests that pass while the limitation exists and are named `KNOWN LIMITATION`. They must be replaced by the stale-device tests below when this is built. This matches the "cross-device correctness" caveat in the research file (item 9). It is not measured against real usage: the sync is off by default, so no production account is known to be affected.

## Decision (proposed)

### Server model

Add a per-account monotonically increasing revision and per-note version metadata. Prepared SQL for the migration (not applied anywhere; the backend currently creates its schema with `CREATE ... IF NOT EXISTS` in `store.ts`, so this needs either a new idempotent block there or a migration runner, an owner/engineering choice):

```sql
ALTER TABLE memory_state ADD COLUMN notes_rev BIGINT NOT NULL DEFAULT 0;
ALTER TABLE memory_notes
  ADD COLUMN rev BIGINT NOT NULL DEFAULT 0,          -- account revision at which this row last changed
  ADD COLUMN version INTEGER NOT NULL DEFAULT 1,     -- per-note edit counter
  ADD COLUMN deleted_at BIGINT,                      -- tombstone: ciphertext may be emptied, row kept
  ADD COLUMN device_id TEXT;                         -- who wrote it (opaque, no content)
CREATE INDEX memory_notes_rev ON memory_notes (user_id, rev);
```

Tombstones are kept for a fixed window (proposal: 90 days, then purged by the existing hourly sweep), and `ciphertext` is replaced with an empty value on delete so deleted text does not linger. Reads (list, search, export, chat) filter `deleted_at IS NULL`; counts do the same.

### API (additive; old endpoint stays during migration)

- `GET /v1/web/memory/notes/changes?since=<rev>&limit=` returns `{ rev, notes: [...], deleted: [ids], more }` for rows with `rev > since`, ordered by `rev`. A `since` older than the tombstone horizon returns `410 resync_required`, and the client does a full fetch.
- `POST /v1/web/memory/notes/sync` with `{ baseRev, upserts: [{ id, text, ..., baseVersion }], deletes: [{ id, baseVersion }] }`. One transaction. For each item the server compares `baseVersion` with the stored version: match -> apply, bump `version`, stamp the new account `rev`; mismatch -> not applied, returned in `conflicts: [{ id, serverVersion, serverNote }]`. Reply: `{ rev, applied, conflicts }`. Success is reported only for what the transaction committed (constitution rule: never claim saved without a verified storage operation).
- Conflict policy (proposal): for an edit conflict the newer `captured_at`/edit wins on the server and the losing text is returned to the phone to keep as a separate note; a delete against a newer edit loses (the note is kept); a delete against an older version wins. Never silently drop text.
- Ids stay UUIDs; encryption and AAD (`userId:note:id`) are unchanged. The server still stores no plaintext metadata beyond what it already has.
- Private notes (ADR-310) remain excluded by the phone.

### Client (Swift, for a later change; not touched here)

Keep per-note `version` and a `lastRev` cursor; send only changed or deleted notes since the last acknowledged sync; pull `changes` first, merge, then push. The "once per launch send the whole list" behaviour in `retryIfNeeded` becomes a pull plus a diff. A failed read of local notes must still never trigger deletes (DOD-06).

### Migration plan

1. Ship the schema change and the new endpoints behind a server flag, with `PUT /notes` unchanged. Existing rows get `rev = 0`, `version = 1`.
2. Make `PUT /notes` (old clients) bump `rev`/`version` per changed row and write tombstones for rows it drops, instead of hard-deleting, so new and old clients can coexist. An old client's whole-list send still wins, as today, but is now at least recorded.
3. Ship the iPhone build that uses `changes`/`sync`; keep the old path as fallback for a release or two (the server cannot tell the caller's version except by endpoint use).
4. Flip `IPHONE_SYNCS_MEMORY` only after a two-device test on real iPhones.
5. After clients have moved, make `PUT /notes` refuse (`409 upgrade_required`) when more than one `device_id` has written in the last 30 days.

### Tests to add with the implementation

Stale device cannot delete a newer note; edit on both devices produces one winner plus a kept loser, no text lost; delete tombstone replicates to the other device; `since` older than the horizon returns `resync_required`; account isolation on `changes` and `sync`; tombstoned text is not readable or searchable; retry of the same `sync` request is idempotent (request id); unknown/timeout outcome on the phone is retried only by re-pulling, never by blind resend.

## Consequences

Removes silent loss between devices and cuts upload size (only changed notes). Costs: a schema change, two endpoints, a conflict UI or rule on the phone, and tombstone retention (deleted-note metadata outlives the delete for the horizon; the content does not). Deletion via the account eraser (`AccountEraser`) and "delete everything" must also remove tombstones. Not justified yet by usage data since the sync is off; do it before `IPHONE_SYNCS_MEMORY` is turned on for accounts with more than one device.

## Evidence

Read: `backend/src/memory/service.ts`, `backend/src/memory/routes.ts`, `backend/src/store.ts` (`replaceMemoryNotes`), `Packages/DoddyCore/.../WebMemoryModel.swift` and `WebMemoryClient.swift`, `DoddyApp/App/RootView.swift` (send on every store revision), `docs/product/CLOUD_MEMORY.md`. Run: `backend/test/memory-sync-overwrite.test.ts` (2 pass, documenting the overwrite). Not run: any real two-device test, any Swift build. No implementation of incremental sync was made.
