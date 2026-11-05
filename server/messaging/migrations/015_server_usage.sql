-- Review of 29 Oct (ADR-673): server-wide daily caps that deleting an account can't reset. The caps used
-- to sum the per-account rows of assistant_usage and deals_usage, which go with the account (ON DELETE
-- CASCADE): make an account, use it, delete it, and the server's count for the day went down again.
-- Counts only, per feature and UTC day, with no account in them (like call_dial_log). New tables and a
-- backfill from the rows that exist: safe to apply on a live database.

CREATE TABLE server_daily_usage (
  feature   text NOT NULL CHECK (feature IN ('assistant', 'deals', 'errands')),
  day       date NOT NULL,
  requests  integer NOT NULL DEFAULT 0 CHECK (requests >= 0),
  PRIMARY KEY (feature, day)
);

-- Errand approvals per account and UTC day (ERRANDS_DAILY_PER_ACCOUNT). Deleting an errand doesn't give
-- the day's approval back; deleting the account does, but the server's count above stays.
CREATE TABLE errand_usage (
  account_id  uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  day         date NOT NULL,
  approvals   integer NOT NULL DEFAULT 0 CHECK (approvals >= 0),
  PRIMARY KEY (account_id, day)
);

INSERT INTO server_daily_usage (feature, day, requests)
  SELECT 'assistant', day, SUM(requests)::int FROM assistant_usage GROUP BY day
  UNION ALL
  SELECT 'deals', day, SUM(requests)::int FROM deals_usage GROUP BY day
  UNION ALL
  SELECT 'errands', (approved_at AT TIME ZONE 'utc')::date, count(*)::int FROM errands WHERE approved_at IS NOT NULL GROUP BY 2;

INSERT INTO errand_usage (account_id, day, approvals)
  SELECT account_id, (approved_at AT TIME ZONE 'utc')::date, count(*)::int FROM errands WHERE approved_at IS NOT NULL GROUP BY 1, 2;
