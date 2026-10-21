-- Errands (ADR-563, docs/implementation/ERRANDS.md): Doddy researches a task in the background
-- after one yes. The user's words, Doddy's brief and the title exist only as one encrypted blob whose
-- SHA-256 the user approved; the result card is encrypted too and is kept only until the app has
-- saved it (ack) or for 30 days. Content columns hold AES-256-GCM ciphertext only (no plaintext
-- fallback: without MEMORY_ENCRYPTION_KEY the feature is off). Only new tables: safe to apply on a
-- live database.

CREATE TABLE errands (
  id                    uuid PRIMARY KEY,
  account_id            uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  state                 text NOT NULL CHECK (state IN ('draft', 'queued', 'running', 'done', 'failed', 'cancelled')),
  language              text NOT NULL CHECK (language ~ '^[a-z]{2}$'),
  -- The canonical JSON of {brief, language, title, words}. AAD `${account}:errand:${id}`.
  -- Erased on ack, on DELETE, or 30 days after the errand finished.
  content_key_version   smallint CHECK (content_key_version > 0),
  content_ciphertext    bytea,
  content_deleted_at    timestamptz,
  -- SHA-256 of that canonical JSON: what the user approves. Never changes.
  payload_digest        bytea NOT NULL CHECK (octet_length(payload_digest) = 32),
  -- The ErrandResult card (canonical JSON). AAD `${account}:errand-result:${id}`.
  result_key_version    smallint CHECK (result_key_version > 0),
  result_ciphertext     bytea,
  -- SHA-256 of the canonical result JSON; the app echoes it in ack.
  result_digest         bytea CHECK (octet_length(result_digest) = 32),
  failure               text CHECK (failure IN ('interrupted', 'time_limit', 'refused', 'provider_error', 'unreadable_result')),
  -- Cost visibility: look-ups and tokens across both model calls. Counts only, never words.
  searches              integer NOT NULL DEFAULT 0 CHECK (searches >= 0),
  fetches               integer NOT NULL DEFAULT 0 CHECK (fetches >= 0),
  input_tokens          bigint NOT NULL DEFAULT 0 CHECK (input_tokens >= 0),
  cache_write_tokens    bigint NOT NULL DEFAULT 0 CHECK (cache_write_tokens >= 0),
  cache_read_tokens     bigint NOT NULL DEFAULT 0 CHECK (cache_read_tokens >= 0),
  output_tokens         bigint NOT NULL DEFAULT 0 CHECK (output_tokens >= 0),
  model                 text CHECK (length(model) BETWEEN 1 AND 64),
  -- The user's Cancel on a running errand; the runner stops at its next step.
  cancel_requested_at   timestamptz,
  created_at            timestamptz NOT NULL,
  -- A draft that isn't approved by then is deleted.
  expires_at            timestamptz NOT NULL,
  approved_at           timestamptz,
  started_at            timestamptz,
  finished_at           timestamptz,
  acknowledged_at       timestamptz,
  CONSTRAINT errands_content_key CHECK ((content_ciphertext IS NULL) = (content_key_version IS NULL)),
  CONSTRAINT errands_result_key CHECK ((result_ciphertext IS NULL) = (result_key_version IS NULL)),
  CONSTRAINT errands_content_marker CHECK ((content_ciphertext IS NULL) = (content_deleted_at IS NOT NULL)),
  -- Nothing runs without the approved content.
  CONSTRAINT errands_content_while_open CHECK (state NOT IN ('draft', 'queued', 'running') OR content_ciphertext IS NOT NULL),
  CONSTRAINT errands_draft_window CHECK (expires_at > created_at AND expires_at <= created_at + interval '10 minutes'),
  CONSTRAINT errands_approved CHECK (
    (state <> 'draft' OR approved_at IS NULL)
    AND (state NOT IN ('queued', 'running', 'done', 'failed') OR approved_at IS NOT NULL)),
  CONSTRAINT errands_started CHECK (
    (state NOT IN ('running', 'done', 'failed') OR started_at IS NOT NULL)
    AND (started_at IS NULL OR approved_at IS NOT NULL)),
  CONSTRAINT errands_finished CHECK ((finished_at IS NOT NULL) = (state IN ('done', 'failed', 'cancelled'))),
  CONSTRAINT errands_failure_iff_failed CHECK ((failure IS NOT NULL) = (state = 'failed')),
  -- A result exists only for a done errand, and goes together with the words (ack or expiry).
  CONSTRAINT errands_result_only_done CHECK ((result_ciphertext IS NULL AND result_digest IS NULL) OR state = 'done'),
  CONSTRAINT errands_done_has_result CHECK (state <> 'done'
    OR (result_digest IS NOT NULL AND (result_ciphertext IS NULL) = (content_ciphertext IS NULL))),
  CONSTRAINT errands_acked CHECK (acknowledged_at IS NULL
    OR (state = 'done' AND result_ciphertext IS NULL AND content_ciphertext IS NULL))
);
CREATE INDEX errands_account ON errands (account_id, created_at DESC);
-- The worker's claim: oldest approved first.
CREATE INDEX errands_queue ON errands (approved_at) WHERE state = 'queued';
CREATE INDEX errands_running ON errands (started_at) WHERE state = 'running';
CREATE INDEX errands_drafts ON errands (expires_at) WHERE state = 'draft';
CREATE INDEX errands_unacked ON errands (finished_at) WHERE content_ciphertext IS NOT NULL AND finished_at IS NOT NULL;

-- Receipts for each deletion of errand content: what and why, never the content. No foreign key to
-- errands, so a receipt outlives a deleted errand row; it goes with the account.
CREATE TABLE errand_deletions (
  id          uuid PRIMARY KEY,
  account_id  uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  errand_id   uuid NOT NULL,
  item        text NOT NULL CHECK (item IN ('words', 'brief', 'title', 'result')),
  reason      text NOT NULL CHECK (reason IN ('acked', 'expired', 'deleted')),
  deleted_at  timestamptz NOT NULL
);
CREATE INDEX errand_deletions_errand ON errand_deletions (errand_id, deleted_at);
CREATE INDEX errand_deletions_account ON errand_deletions (account_id);
