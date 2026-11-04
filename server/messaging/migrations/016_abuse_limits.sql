-- Security review of 4 Nov 2026 (ADR-702, ADR-704, ADR-705): caps on what anonymous accounts can spend.
-- Counts only, hashed keys only, nothing with content. New table, new nullable columns and a wider CHECK on a
-- tiny table: safe to apply on a live database, and the previous release keeps working against it.

-- 1. Server-wide daily counts for the new caps: account creation, queued texts, "call me" calls, and the part of each
--    paid feature's cap that accounts still new may use (errands_new, deals_new, assistant_new). Same table and
--    meaning as migration 015: per feature and UTC day, no account in it. A superset of the old list.
ALTER TABLE server_daily_usage DROP CONSTRAINT server_daily_usage_feature_check;
ALTER TABLE server_daily_usage ADD CONSTRAINT server_daily_usage_feature_check CHECK (feature IN (
  'assistant', 'deals', 'errands',
  'assistant_new', 'deals_new', 'errands_new',
  'accounts', 'sms', 'outbound_calls'));

-- 2. Counts per key and UTC day: account creation per client address, queued texts per account. The key is a
--    keyed hash (HMAC with a key derived from MEMORY_ENCRYPTION_KEY when set, SHA-256 otherwise), never the
--    address or the account id. Rows older than two days are deleted by the server.
CREATE TABLE daily_counters (
  scope  text NOT NULL CHECK (scope IN ('signup_ip', 'sms_account')),
  key    text NOT NULL CHECK (length(key) BETWEEN 1 AND 128),
  day    date NOT NULL,
  n      integer NOT NULL DEFAULT 0 CHECK (n >= 0),
  PRIMARY KEY (scope, key, day)
);
CREATE INDEX daily_counters_day ON daily_counters (day);

-- 3. Verification codes per client address and per account and day, next to the per-number counts. Hashes only,
--    like phone_hash; rows are deleted after two days as before. Rows written before this have NULL here.
ALTER TABLE phone_verification_starts ADD COLUMN ip_hash bytea, ADD COLUMN account_hash bytea;
CREATE INDEX phone_verification_starts_ip_time ON phone_verification_starts (ip_hash, started_at) WHERE ip_hash IS NOT NULL;
CREATE INDEX phone_verification_starts_account_time ON phone_verification_starts (account_hash, started_at) WHERE account_hash IS NOT NULL;

-- 4. The task-call dial log also keeps a keyed hash of the account, so the per-user limits survive a change of the
--    verified number (they were keyed by the number only). Rows older than a day have no account hash and are not
--    counted by account; they stop mattering within a day.
ALTER TABLE call_dial_log ADD COLUMN caller_account_hash bytea CHECK (octet_length(caller_account_hash) = 32);
CREATE INDEX call_dial_log_account ON call_dial_log (caller_account_hash, dialed_at) WHERE caller_account_hash IS NOT NULL;
