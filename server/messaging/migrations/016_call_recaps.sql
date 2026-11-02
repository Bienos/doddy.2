-- ADR-693: a recap after every S2 call with Doddy (a call to Doddy's number, or "Call me now").
-- ElevenLabs' post-call webhook brings the transcript; the worker builds the recap; the app saves it on
-- the iPhone and acknowledges it, and the server then deletes its copy and keeps a receipt. Only calls
-- that already have a `calls` row get one (a verified number with calls on): unknown callers and callers
-- with calls off have no row, so nothing about their call is stored. New tables and one new column:
-- safe to apply on a live database.

CREATE TABLE call_recaps (
  call_id            uuid PRIMARY KEY REFERENCES calls(id) ON DELETE CASCADE,
  account_id         uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  conversation_id    text NOT NULL,
  -- waiting: the transcript is stored, the recap isn't built yet; building: a worker has it (until
  -- lease_until); ready: the recap waits for the app; acked: the app saved it and both copies are gone.
  state              text NOT NULL CHECK (state IN ('waiting', 'building', 'ready', 'acked', 'deleted', 'expired')),
  key_version        smallint CHECK (key_version > 0),
  -- The transcript and call facts from ElevenLabs, encrypted; deleted once the recap is built.
  input_ciphertext   bytea,
  recap_ciphertext   bytea,
  -- SHA-256 over the stored recap JSON; the app sends it back with the ack.
  recap_digest       bytea CHECK (recap_digest IS NULL OR octet_length(recap_digest) = 32),
  summary_by         text CHECK (summary_by IN ('doddy_model', 'rules')),
  attempts           integer NOT NULL DEFAULT 0 CHECK (attempts >= 0),
  process_after      timestamptz NOT NULL DEFAULT now(),
  lease_until        timestamptz,
  -- When the model wrote this recap's summary; counts toward the account's daily cap.
  model_used_at      timestamptz,
  created_at         timestamptz NOT NULL DEFAULT now(),
  ready_at           timestamptz,
  finished_at        timestamptz,
  CHECK (state NOT IN ('waiting', 'building') OR input_ciphertext IS NOT NULL),
  CHECK (state <> 'ready' OR (recap_ciphertext IS NOT NULL AND recap_digest IS NOT NULL)),
  CHECK ((input_ciphertext IS NULL AND recap_ciphertext IS NULL) OR key_version IS NOT NULL)
);
CREATE UNIQUE INDEX call_recaps_conversation ON call_recaps (conversation_id);
CREATE INDEX call_recaps_due ON call_recaps (process_after) WHERE state IN ('waiting', 'building');
CREATE INDEX call_recaps_account ON call_recaps (account_id, created_at);
-- The 30-day sweep looks only at rows that still hold words from a call.
CREATE INDEX call_recaps_content_age ON call_recaps (created_at)
  WHERE input_ciphertext IS NOT NULL OR recap_ciphertext IS NOT NULL;

-- What the server deleted, and why. Kept until the account goes.
CREATE TABLE call_recap_deletions (
  id          uuid PRIMARY KEY,
  account_id  uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  call_id     uuid NOT NULL,
  item        text NOT NULL CHECK (item IN ('input', 'recap')),
  reason      text NOT NULL CHECK (reason IN ('recap_built', 'acked', 'deleted', 'expired')),
  deleted_at  timestamptz NOT NULL
);
CREATE INDEX call_recap_deletions_call ON call_recap_deletions (call_id, deleted_at);
CREATE INDEX call_recap_deletions_account ON call_recap_deletions (account_id);

-- Notes said on a call now know their call, so the recap can list them. Older notes keep NULL.
ALTER TABLE call_notes ADD COLUMN call_id uuid REFERENCES calls(id) ON DELETE SET NULL;
CREATE INDEX call_notes_call ON call_notes (call_id) WHERE call_id IS NOT NULL;

-- The server-wide daily cap on model-written recaps (ADR-673's table).
ALTER TABLE server_daily_usage DROP CONSTRAINT server_daily_usage_feature_check;
ALTER TABLE server_daily_usage ADD CONSTRAINT server_daily_usage_feature_check
  CHECK (feature IN ('assistant', 'deals', 'errands', 'call_recaps'));
