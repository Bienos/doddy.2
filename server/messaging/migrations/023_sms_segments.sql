-- SMS segments (research item #4, docs/decisions/2026-11-09-sms-segment-budget.md). Twilio bills a text per
-- segment, and one Polish letter makes a 600-character text 9 segments, so the daily caps now also count the
-- estimated segments of every text queued. Counts and numbers only, no text. Additive: the previous release keeps
-- working against it (it never writes these columns or scopes).

-- 1. A wider list of counts: segments queued per account (keyed by the same hash as 'sms_account') and for the
--    server (like 'sms'). A superset of migrations 016 and 017.
ALTER TABLE daily_counters DROP CONSTRAINT daily_counters_scope_check;
ALTER TABLE daily_counters ADD CONSTRAINT daily_counters_scope_check CHECK (scope IN ('signup_ip', 'sms_account', 'sms_segments_account'));

ALTER TABLE server_daily_usage DROP CONSTRAINT server_daily_usage_feature_check;
ALTER TABLE server_daily_usage ADD CONSTRAINT server_daily_usage_feature_check CHECK (feature IN (
  'assistant', 'deals', 'errands', 'studio',
  'assistant_new', 'deals_new', 'errands_new', 'studio_new',
  'accounts', 'sms', 'sms_segments', 'outbound_calls'));

-- 2. Per text: the segments reserved when it was queued (our estimate from its encoding) and the segments Twilio
--    reports it used (num_segments, from the status callback when sent, or the message lookup). Both stay after the
--    text itself is erased, so a day's estimate can be reconciled with Twilio's bill. NULL = not known.
ALTER TABLE outbound_messages
  ADD COLUMN est_segments smallint CHECK (est_segments BETWEEN 1 AND 255),
  ADD COLUMN reported_segments smallint CHECK (reported_segments BETWEEN 1 AND 255);
