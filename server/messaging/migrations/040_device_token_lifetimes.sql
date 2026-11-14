-- Device tokens of Doddy accounts expire and rotate (decision 2026-11-12-account-and-device-tokens, part d).
--
-- Additive only, so the server from before this file keeps working against this schema: it never names these columns,
-- inserts devices without them (they fill themselves), and ignores them when it reads. Reverting the server leaves them in place.
--
-- token_issued_at: when the device's current token was issued (a rotation resets it), or, for an iPhone whose anonymous account
--   was linked to a Doddy account, when it was linked. The 180 days of a Doddy account's token count from here; the 60 days
--   unseen count from last_seen_at (001), which the server writes at most once an hour. Existing rows get the time this ran,
--   one value for all of them (a default that is not volatile is evaluated once, without rewriting the table).
-- previous_token_hash, previous_valid_until: a rotation keeps the token it replaced working until previous_valid_until (5 minutes
--   by default), so a lost answer does not sign the iPhone out. Only the hash is kept, as for token_hash.
ALTER TABLE devices
  ADD COLUMN token_issued_at       timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN previous_token_hash   bytea CHECK (previous_token_hash IS NULL OR octet_length(previous_token_hash) = 32),
  ADD COLUMN previous_valid_until  timestamptz,
  ADD CONSTRAINT devices_previous_token_pair CHECK ((previous_token_hash IS NULL) = (previous_valid_until IS NULL));

-- A token that was replaced belongs to one device only: the lookup by it finds one row.
CREATE UNIQUE INDEX devices_previous_token_hash ON devices (previous_token_hash) WHERE previous_token_hash IS NOT NULL;

-- Nobody is cut off the day this ships: every iPhone of a Doddy account counts as seen now, so the 60 days start today.
-- (token_issued_at above already says now.) Anonymous accounts never expire; their last-seen time is left as it was.
UPDATE devices d SET last_seen_at = now()
  FROM accounts a
 WHERE a.id = d.account_id AND a.auth_subject IS NOT NULL;
