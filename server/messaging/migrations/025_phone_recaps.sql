-- Recaps of calls to and from Doddy's phone line (decision docs/decisions/2026-11-09-conversation-recaps.md,
-- step 5). After a call, ElevenLabs' post-call webhook brings the transcript here; the server asks Claude for
-- three short lists (discussed, agreed, to do) and keeps ONLY those, encrypted, until the iPhone has saved
-- them as a note and said so (DELETE), or for 30 days. The transcript is used in memory for that one call and
-- is never stored. A recap is made only for an account that turned it on (recaps_enabled_at).
-- A new column (null) and a new table: safe to apply on a live database.

ALTER TABLE call_settings ADD COLUMN recaps_enabled_at timestamptz;

CREATE TABLE phone_recaps (
  call_id      uuid PRIMARY KEY REFERENCES calls(id) ON DELETE CASCADE,
  account_id   uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  key_version  smallint NOT NULL CHECK (key_version > 0),
  -- {discussed, agreed, to_do, endedAt, durationSecs, direction}, bound to the account and the call.
  ciphertext   bytea NOT NULL,
  created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX phone_recaps_account ON phone_recaps (account_id, created_at);
