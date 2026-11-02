-- Daily caps on texts (SMS_DAILY_PER_ACCOUNT, SMS_DAILY_PER_SERVER): every text queued (updates, news,
-- texting-Doddy replies) is counted per account and UTC day, and nothing else is kept: no number, no
-- text. A deleted account's counts stay without its id, so the server-wide cap for that day still
-- holds. Only a new table: safe to apply on a live database.

CREATE TABLE sms_daily_usage (
  account_id  uuid REFERENCES accounts(id) ON DELETE SET NULL,
  day         date NOT NULL,
  texts       integer NOT NULL DEFAULT 0 CHECK (texts >= 0)
);

-- One row per account and day (rows of deleted accounts, with no id, never conflict).
CREATE UNIQUE INDEX sms_daily_usage_account_day ON sms_daily_usage (account_id, day);
-- The server-wide cap sums one day across accounts.
CREATE INDEX sms_daily_usage_day ON sms_daily_usage (day);
