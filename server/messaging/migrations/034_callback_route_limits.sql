-- Call-back routes per number and account, with an expiry and a daily cap (decision
-- docs/decisions/2026-11-12-call-back-limits.md, src/callbacks.ts). Until now one row per number held the account that
-- dialled it last, so a call-back reached whichever user called that number most recently. Now every account that
-- dialled the number has its own row; a call-back is put through only when exactly one of them is fresh (dialled within
-- CALLBACK_ROUTE_DAYS, 7 by default; older rows are deleted by the worker's hourly tidy), and each row counts its
-- forwards per UTC day. Existing rows are one per number, so they are unique per number and account too.
-- server_daily_usage also counts calls to Doddy's number put through per UTC day (INBOUND_CALLS_DAILY_PER_SERVER).
-- A small table re-keyed, two new columns with a constant default and a wider CHECK on a small table: safe to apply on
-- a live database. The previous release's single-row upsert (ON CONFLICT (destination_hash)) no longer has a matching
-- key, so deploy this release together with its migration, as every release here is (migrate() runs on start).

ALTER TABLE callback_routes DROP CONSTRAINT callback_routes_pkey;
ALTER TABLE callback_routes ADD PRIMARY KEY (destination_hash, account_id);
ALTER TABLE callback_routes ADD COLUMN forwards_day date;
ALTER TABLE callback_routes ADD COLUMN forwards integer NOT NULL DEFAULT 0 CHECK (forwards >= 0);
CREATE INDEX callback_routes_last_dialed ON callback_routes (last_dialed_at);

ALTER TABLE server_daily_usage DROP CONSTRAINT server_daily_usage_feature_check;
ALTER TABLE server_daily_usage ADD CONSTRAINT server_daily_usage_feature_check CHECK (feature IN (
  'assistant', 'deals', 'errands', 'studio', 'news',
  'assistant_new', 'deals_new', 'errands_new', 'studio_new', 'news_new',
  'accounts', 'sms', 'outbound_calls', 'inbound_calls'));
