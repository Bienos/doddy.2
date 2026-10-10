-- Daily news readable in the app without notifications or texts (D, ADR-174).
-- channels may now be empty: the digest is built and kept for the app, nothing is sent.
-- 'ready' = built and kept for the app, nothing was sent (none chosen, or none available).
ALTER TABLE news_settings DROP CONSTRAINT IF EXISTS news_settings_channels_check;
ALTER TABLE news_settings ADD CONSTRAINT news_settings_channels_check
  CHECK (channels <@ ARRAY['push', 'sms']::text[] AND cardinality(channels) <= 2);

ALTER TABLE news_digests DROP CONSTRAINT IF EXISTS news_digests_status_check;
ALTER TABLE news_digests ADD CONSTRAINT news_digests_status_check
  CHECK (status IN ('building', 'queued', 'ready', 'empty', 'failed'));
