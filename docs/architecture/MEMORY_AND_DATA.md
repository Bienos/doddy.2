# Local memory, database, lifecycle and provenance
## Scope M1
Local-only records. Avoid syncing or uploading local memory unless the user explicitly enables a separately disclosed feature. No silent NLP memory extraction, no undisclosed use of chat history.

## Proposed normalized schema (SQLite)
```
CREATE TABLE memories (
  id TEXT PRIMARY KEY,       -- UUID
  raw_text TEXT NOT NULL,    -- exact accepted text, immutable until deletion
  current_text TEXT NOT NULL,
  category TEXT NOT NULL DEFAULT 'other',
  source TEXT NOT NULL,      -- explicit_text | explicit_voice | shared_content | imported
  captured_at_ms INTEGER,    -- null allowed only for imported legacy with unknown date
  updated_at_ms INTEGER,
  user_edited INTEGER NOT NULL DEFAULT 0 CHECK(user_edited IN (0,1)),
  deleted_at_ms INTEGER,     -- optional tombstone if required; define purge policy
  schema_version INTEGER NOT NULL DEFAULT 1
);
CREATE TABLE outbox_actions (
  operation_id TEXT PRIMARY KEY,
  type TEXT NOT NULL,
  state TEXT NOT NULL,
  external_id TEXT,
  payload_digest TEXT,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL
);
```
Search should index `current_text`, not immutable original by default. GRDB migration definitions and FTS5 SQL should be written/tested against the selected GRDB release and SQLite configuration. Outbox is not needed before M4.

## Memory invariants
- User requested `Save` or equivalent explicit intent, never auto-learn from casual chat.
- `rawText` remains unchanged through edits; `currentText` is the correction. Both deleted on explicit erasure.
- No success toast until durable transaction completes; show precise failure, preserve draft.
- Search returns existing record identifiers only; index sync and transaction rollback tested.
- If two memories conflict, display both with sources; recency is not a truth proof.
- If import has unknown capture date, show 'date unavailable'; *never* use import time as historical capture.
- Deletion must invalidate in-memory caches, search indexes and any queued retrieval snippets.

## Source types and private sessions
`explicit_text`, `explicit_voice`, `shared_content`, `imported_legacy_unknown`, `sample_fixture` (sample never returned for personal recall). `private_session` is ephemeral, does not persist by default and does not become another source type for long-term memory.

## Security on device
Use protected app container, configure appropriate `NSFileProtection*` policies, coordinate lock/unlock, use Keychain only for secrets, and document SQLite WAL/SHM protection and OS-backup rules. iOS Data Protection is *not* equivalent to application-layer end-to-end encryption. Validate behavior after force-quit, disk-full, locked device and interrupted migration; never delete original import data before read-back and checksum verification.

## Migration and data rights
M0/M1 starts clean; **do not import the old demo app's UserDefaults automatically**. If user later asks to migrate real records, write explicit versioned adapter and reversible backup. Export JSON with stable schema and plain text human-readable option. The JSON export can be restored on the phone (ADR-135): whole file checked first, existing notes never replaced, all-or-nothing write with read-back. Deletion applies to all local tables, attachments and transient caches. If backups/system copies/provider logs exist, present accurate scope/retention limitations; do not advertise absolute erasure absent verification.

## Recall evaluation
Use deterministic fixture corpus including Polish diacritics, typos, duplicate people, ambiguous locations, edited notes, deleted notes, long text, case variations and unsupported date queries. Track precision@k / recall@k for labelled set, false positives, provenance correctness and conflict recognition. FTS5 is lexical; semantic retrieval and embeddings are **later opt-in research**, never a prerequisite.

## Future-only cloud
When sync is justified, design identity, encryption/key rotation, device revocation, GDPR deletion, per-tenant isolation and backup lifecycle before a centralized PostgreSQL store. Do not create PostgreSQL infrastructure in M0/M1 simply because an earlier architecture memo mentions it.
