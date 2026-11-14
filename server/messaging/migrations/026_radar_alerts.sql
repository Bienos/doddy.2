-- On my radar alerts (owner, 10 Nov 2026; decision 2026-11-10-radar-alerts): "say when Doddy should tell
-- them about an event, by keywords". Follows stay on the iPhone (ADR-656); only a follow the person
-- explicitly lets "Doddy's server check for you" is stored here, with the words to look out for and how
-- to be told (as it happens, or once a day). A worker reads its feeds through the shared news_cache and,
-- when a new story matches, records it (the app lists it) and queues at most one push.
-- New tables only: safe to apply on a live database. Everything cascades on account deletion.

CREATE TABLE radar_alerts (
  id               uuid PRIMARY KEY,
  account_id       uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  -- The iPhone's own id for the follow ("topic:crypto", "words:tesla", "feed:…"), so a change replaces the row.
  follow_key       text NOT NULL CHECK (length(follow_key) BETWEEN 1 AND 120),
  label            text NOT NULL CHECK (length(label) BETWEEN 1 AND 60),
  catalog_id       text CHECK (length(catalog_id) <= 32),
  keywords         text[] NOT NULL DEFAULT '{}' CHECK (cardinality(keywords) <= 10),
  feed_url         text CHECK (length(feed_url) <= 500),
  -- "Tell me when": a story must mention one of these. Empty: any new story of the follow.
  alert_words      text[] NOT NULL DEFAULT '{}' CHECK (cardinality(alert_words) <= 10),
  mode             text NOT NULL CHECK (mode IN ('instant', 'daily')),
  daily_time       time,
  time_zone        text NOT NULL CHECK (length(time_zone) BETWEEN 1 AND 64),
  language         text NOT NULL CHECK (language IN ('en', 'pl')),
  -- Only stories published after this count: turning an alert on never reports the day before.
  watch_from       timestamptz NOT NULL,
  next_check_at    timestamptz NOT NULL,
  -- Daily: when the next summary is due.
  next_tell_at     timestamptz,
  last_checked_at  timestamptz,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  UNIQUE (account_id, follow_key),
  CHECK (catalog_id IS NULL OR feed_url IS NULL),
  CHECK (catalog_id IS NOT NULL OR feed_url IS NOT NULL OR cardinality(keywords) > 0),
  CHECK (mode <> 'daily' OR (daily_time IS NOT NULL AND next_tell_at IS NOT NULL)),
  -- "As it happens" needs words to look out for: a whole topic as it happens would be a push per story.
  CHECK (mode <> 'instant' OR cardinality(alert_words) > 0 OR cardinality(keywords) > 0)
);
CREATE INDEX radar_alerts_due ON radar_alerts (next_check_at);

-- Stories an alert found. One row per account and story, ever, which is also the dedupe; pruned after 14 days.
-- told_at/told_by: null until the person was told; 'push' when one was queued, 'app' when it is shown in
-- the app only (no notification possible, too late, or over the day's cap).
CREATE TABLE radar_hits (
  id            uuid PRIMARY KEY,
  account_id    uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  alert_id      uuid NOT NULL REFERENCES radar_alerts(id) ON DELETE CASCADE,
  url_hash      bytea NOT NULL,
  -- The publisher's headline and summary, word for word (public text from its feed, data not instructions).
  title         text NOT NULL CHECK (length(title) <= 300),
  summary       text NOT NULL DEFAULT '' CHECK (length(summary) <= 400),
  url           text NOT NULL CHECK (length(url) <= 2000),
  source        text NOT NULL CHECK (length(source) <= 120),
  published_at  timestamptz NOT NULL,
  matched       text[] NOT NULL DEFAULT '{}',
  found_at      timestamptz NOT NULL,
  told_at       timestamptz,
  told_by       text CHECK (told_by IN ('push', 'app')),
  seen_at       timestamptz,
  UNIQUE (account_id, url_hash),
  CHECK ((told_at IS NULL) = (told_by IS NULL))
);
CREATE INDEX radar_hits_alert ON radar_hits (alert_id, found_at) WHERE told_at IS NULL;
CREATE INDEX radar_hits_account ON radar_hits (account_id, found_at DESC);
