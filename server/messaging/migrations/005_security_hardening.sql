-- Security review before first deploy (ADR-175).
-- 1. PIN lockouts escalate instead of resetting (15 min, 1 h, 4 h, 16 h, then 24 h).
ALTER TABLE call_settings ADD COLUMN pin_lock_count integer NOT NULL DEFAULT 0 CHECK (pin_lock_count >= 0);

-- 2. Verify codes per destination number, so new accounts can't be used to text one number
--    over and over (SMS pumping / harassment). Only a hash of the number is kept.
CREATE TABLE phone_verification_starts (
  phone_hash  bytea NOT NULL,
  started_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX phone_verification_starts_hash_time ON phone_verification_starts (phone_hash, started_at);
CREATE INDEX phone_verification_starts_time ON phone_verification_starts (started_at);

-- 3. The feed cache no longer keys on a user's raw feed URL (it can carry a private token);
--    old rows are simply dropped and refetched.
DELETE FROM news_cache;
