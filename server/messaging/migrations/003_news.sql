-- News digests: the user picks topics (curated feeds and/or own keywords) and custom feeds;
-- once a day at their local time Doddy sends a short message with the most relevant stories.
-- No memories are involved. Everything personal cascades on account deletion.

CREATE TABLE news_settings (
  account_id    uuid PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE,
  enabled       boolean NOT NULL DEFAULT false,
  send_time     time NOT NULL DEFAULT '08:00',
  timezone      text NOT NULL DEFAULT 'Europe/Warsaw' CHECK (length(timezone) BETWEEN 1 AND 64),
  channels      text[] NOT NULL DEFAULT '{push}'
                CHECK (channels <@ ARRAY['push', 'sms']::text[] AND cardinality(channels) BETWEEN 1 AND 2),
  language      text NOT NULL DEFAULT 'en' CHECK (language IN ('en', 'pl')),
  next_run_at   timestamptz,
  updated_at    timestamptz NOT NULL DEFAULT now(),
  CHECK (NOT enabled OR next_run_at IS NOT NULL)
);
CREATE INDEX news_settings_due ON news_settings (next_run_at) WHERE enabled;

CREATE TABLE news_topics (
  id          uuid PRIMARY KEY,
  account_id  uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  catalog_id  text CHECK (length(catalog_id) <= 32),        -- a curated topic, or NULL for the user's own
  label       text NOT NULL CHECK (length(label) BETWEEN 1 AND 60),
  keywords    text[] NOT NULL DEFAULT '{}' CHECK (cardinality(keywords) <= 10),
  position    smallint NOT NULL,
  CHECK (catalog_id IS NOT NULL OR cardinality(keywords) > 0)
);
CREATE INDEX news_topics_account_id ON news_topics (account_id);
CREATE UNIQUE INDEX news_topics_catalog ON news_topics (account_id, catalog_id) WHERE catalog_id IS NOT NULL;

CREATE TABLE news_feeds (
  id          uuid PRIMARY KEY,
  account_id  uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  url         text NOT NULL CHECK (length(url) <= 500),
  UNIQUE (account_id, url)
);

CREATE TABLE news_digests (
  id          uuid PRIMARY KEY,
  account_id  uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  kind        text NOT NULL CHECK (kind IN ('scheduled', 'manual')),
  local_date  date NOT NULL,
  status      text NOT NULL CHECK (status IN ('building', 'queued', 'empty', 'failed')),
  ai_written  boolean NOT NULL DEFAULT false,
  error_code  text,
  created_at  timestamptz NOT NULL DEFAULT now()
);
-- At most one scheduled digest per local day, even if two workers race.
CREATE UNIQUE INDEX news_digests_one_per_day ON news_digests (account_id, local_date) WHERE kind = 'scheduled';
CREATE INDEX news_digests_account_id ON news_digests (account_id, created_at);

CREATE TABLE news_digest_items (
  digest_id     uuid NOT NULL REFERENCES news_digests(id) ON DELETE CASCADE,
  position      smallint NOT NULL,
  title         text NOT NULL,
  line          text NOT NULL,
  url           text NOT NULL,
  source        text NOT NULL,
  published_at  timestamptz,
  PRIMARY KEY (digest_id, position)
);

-- Stories already sent, so the same story isn't sent twice. Pruned after 14 days.
CREATE TABLE news_sent (
  account_id  uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  url_hash    bytea NOT NULL,
  sent_at     timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (account_id, url_hash)
);

-- Shared caches (not linked to any account): a feed or search is fetched at most every 30 min.
CREATE TABLE news_cache (
  key         text PRIMARY KEY,
  fetched_at  timestamptz NOT NULL,
  ok          boolean NOT NULL,
  title       text,
  items       jsonb NOT NULL DEFAULT '[]'
);
