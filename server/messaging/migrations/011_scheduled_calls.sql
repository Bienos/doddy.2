-- ADR-490 (unit U4, ADR-495): calls the user asks Doddy to make later, approved on a card with the
-- time and the exact reason Doddy will say, and quiet hours in the user's time zone.

-- The iPhone's current time zone, so quiet hours are checked where the user is when the call is due.
ALTER TABLE call_settings ADD COLUMN time_zone text;

CREATE TABLE scheduled_calls (
  id                 uuid PRIMARY KEY,
  account_id         uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  call_at            timestamptz NOT NULL,
  -- Exactly as the app hashed it (YYYY-MM-DDTHH:MM:SSZ), so the approval can be checked again.
  call_at_text       text NOT NULL CHECK (call_at_text ~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$'),
  -- The reason Doddy says when you answer, encrypted; erased once the call is over or won't happen.
  reason_ciphertext  bytea,
  reason_key_version smallint,
  time_zone          text NOT NULL,
  allow_quiet_hours  boolean NOT NULL DEFAULT false,
  language           text NOT NULL DEFAULT 'en' CHECK (language IN ('en', 'pl')),
  approval_hash      bytea NOT NULL CHECK (octet_length(approval_hash) = 32),
  idempotency_key    text NOT NULL,
  state              text NOT NULL CHECK (state IN (
                       'scheduled', 'placing', 'placed', 'cancelled', 'skipped_quiet_hours', 'missed', 'limit', 'failed', 'unknown')),
  error_code         text,
  call_id            uuid REFERENCES calls(id) ON DELETE SET NULL,
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now(),
  UNIQUE (account_id, idempotency_key),
  CHECK ((reason_ciphertext IS NULL) = (reason_key_version IS NULL)),
  CHECK (reason_ciphertext IS NOT NULL OR state NOT IN ('scheduled', 'placing'))
);
CREATE INDEX scheduled_calls_due ON scheduled_calls (call_at) WHERE state = 'scheduled';
CREATE INDEX scheduled_calls_account ON scheduled_calls (account_id, call_at);
CREATE INDEX scheduled_calls_call ON scheduled_calls (call_id) WHERE call_id IS NOT NULL;
