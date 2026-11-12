-- Daily caps for digests and byte quotas for memory on calls. Counts and sizes only, no content. Wider CHECKs on two
-- small tables, and a new column with a constant default on call_settings (no table rewrite): safe to apply on a live
-- database, and the previous release keeps working against it.

-- 1. Digests the AI writer writes (manual, scheduled, On my radar's daily summaries) count per UTC day for the whole
--    server and, for accounts still new, in their own pool, like Messages (ADR-702, ADR-673). A superset of 017's list.
ALTER TABLE server_daily_usage DROP CONSTRAINT server_daily_usage_feature_check;
ALTER TABLE server_daily_usage ADD CONSTRAINT server_daily_usage_feature_check CHECK (feature IN (
  'assistant', 'deals', 'errands', 'studio', 'news',
  'assistant_new', 'deals_new', 'errands_new', 'studio_new', 'news_new',
  'accounts', 'sms', 'outbound_calls'));

-- 2. ...and per account and UTC day, keyed by a hash of the account id like the per-account text count (016), so
--    deleting the account gives nothing back. Rows older than two days are deleted by the server.
ALTER TABLE daily_counters DROP CONSTRAINT daily_counters_scope_check;
ALTER TABLE daily_counters ADD CONSTRAINT daily_counters_scope_check CHECK (scope IN ('signup_ip', 'sms_account', 'news_account'));

-- 3. Memory on calls: the bytes of ciphertext each account stores in memory_copies, set by the snapshot that writes them
--    (octet_length, in the same transaction) and 0 when the copy is turned off. Their sum is the server's total, read
--    without scanning every copy. Rows with a copy already are counted now.
ALTER TABLE call_settings ADD COLUMN memory_copy_bytes bigint NOT NULL DEFAULT 0 CHECK (memory_copy_bytes >= 0);
UPDATE call_settings s SET memory_copy_bytes = m.bytes
  FROM (SELECT account_id, sum(octet_length(ciphertext))::bigint AS bytes FROM memory_copies GROUP BY account_id) m
 WHERE m.account_id = s.account_id;
