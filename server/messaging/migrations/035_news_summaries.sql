-- Daily caps for the AI summary of one story a person taps in On my radar (13 Nov 2026). Counts only, no content, no
-- address: wider CHECKs on the two small count tables, a superset of 030's and 034's lists. Safe to apply on a live database,
-- and the previous release keeps working against it.

-- 1. Per UTC day for the whole server and, for accounts still new, in their own pool, like the digests (ADR-702).
ALTER TABLE server_daily_usage DROP CONSTRAINT server_daily_usage_feature_check;
ALTER TABLE server_daily_usage ADD CONSTRAINT server_daily_usage_feature_check CHECK (feature IN (
  'assistant', 'deals', 'errands', 'studio', 'news', 'news_summary',
  'assistant_new', 'deals_new', 'errands_new', 'studio_new', 'news_new', 'news_summary_new',
  'accounts', 'sms', 'outbound_calls', 'inbound_calls'));

-- 2. ...and per account and UTC day, keyed by a hash of the account id like the digests' count (030), so deleting the
--    account gives nothing back. Rows older than two days are deleted by the server.
ALTER TABLE daily_counters DROP CONSTRAINT daily_counters_scope_check;
ALTER TABLE daily_counters ADD CONSTRAINT daily_counters_scope_check CHECK (scope IN ('signup_ip', 'sms_account', 'news_account', 'news_summary_account'));
