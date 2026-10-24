-- Price watches (shopping stage 2, docs/implementation/SHOPPING_WATCH.md): after one yes, the server
-- reads one shop page a few times a day for 30 days and tells the user once when the confirmed price
-- is at or below the user's number. It never buys or fills in anything.
--
-- The title, shop and page address exist only as one encrypted blob (AES-256-GCM, AAD
-- `${account}:watch:${id}`) whose canonical JSON, with the plain price columns, hashes to
-- payload_digest: the SHA-256 the user approved. There is no plaintext fallback: without
-- MEMORY_ENCRYPTION_KEY the feature is off. The content lives exactly as long as the row: a finished
-- watch is deleted 30 days after it ended (row, content and all), DELETE removes it at once, and so
-- does deleting the account. The server keeps no page content, only the price read, times and counts.
-- Only a new table: safe to apply on a live database. (011 is reserved for the shopping errand.)

CREATE TABLE price_watches (
  id                      uuid PRIMARY KEY,
  account_id              uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  state                   text NOT NULL CHECK (state IN ('draft', 'active', 'triggered', 'expired', 'stopped', 'failed')),
  -- The canonical JSON of {language, shop, title, url}. Never null: the content goes only with the row.
  content_key_version     smallint NOT NULL CHECK (content_key_version > 0),
  content_ciphertext      bytea NOT NULL,
  -- SHA-256 of the canonical JSON of {checksPerDay, currency, days, language, shop, thresholdMinor,
  -- title, url}: what the user approves. Never changes.
  payload_digest          bytea NOT NULL CHECK (octet_length(payload_digest) = 32),
  -- The user's price, in minor units (grosze), and its currency. Not words: kept plain for the checks.
  threshold_minor         bigint NOT NULL CHECK (threshold_minor BETWEEN 1 AND 1000000000),
  currency                text NOT NULL CHECK (currency ~ '^[A-Z]{3}$'),
  language                text NOT NULL CHECK (language ~ '^[a-z]{2}$'),
  -- The last price read on the page in that currency while it was not out of stock. Only a confirmed
  -- read ever writes it: a failed check, another currency or an out-of-stock page leave it alone.
  last_price_minor        bigint CHECK (last_price_minor > 0),
  triggered_price_minor   bigint CHECK (triggered_price_minor > 0),
  checks_done             integer NOT NULL DEFAULT 0 CHECK (checks_done >= 0),
  -- Checks in a row that could not read a usable page; 8 end the watch as failed.
  consecutive_failures    integer NOT NULL DEFAULT 0 CHECK (consecutive_failures BETWEEN 0 AND 8),
  -- When the next check is due (active only). While a worker holds a watch it is moved to the end of
  -- that claim, so two workers never check one due time twice.
  next_check_at           timestamptz,
  last_checked_at         timestamptz,
  ends_at                 timestamptz,
  triggered_at            timestamptz,
  finished_at             timestamptz,
  failure                 text CHECK (failure IN ('unreadable')),
  created_at              timestamptz NOT NULL,
  -- A draft that isn't approved by then is deleted.
  expires_at              timestamptz NOT NULL,
  approved_at             timestamptz,
  CONSTRAINT price_watches_draft_window CHECK (expires_at > created_at AND expires_at <= created_at + interval '10 minutes'),
  CONSTRAINT price_watches_approved CHECK ((state = 'draft') = (approved_at IS NULL)),
  -- 30 days, as exact hours so a daylight-saving change can't move it.
  CONSTRAINT price_watches_ends CHECK ((state = 'draft') = (ends_at IS NULL)
    AND (ends_at IS NULL OR ends_at = approved_at + interval '720 hours')),
  CONSTRAINT price_watches_next_check CHECK ((state = 'active') = (next_check_at IS NOT NULL)),
  CONSTRAINT price_watches_finished CHECK ((state IN ('triggered', 'expired', 'stopped', 'failed')) = (finished_at IS NOT NULL)),
  CONSTRAINT price_watches_counts CHECK (consecutive_failures <= checks_done
    AND (checks_done = 0) = (last_checked_at IS NULL)
    AND (last_price_minor IS NULL OR checks_done > 0)),
  -- Nothing has been checked before the approval.
  CONSTRAINT price_watches_draft_unchecked CHECK (state <> 'draft'
    OR (checks_done = 0 AND consecutive_failures = 0 AND last_price_minor IS NULL)),
  -- "Dropped" exists only for a confirmed read at or below the user's number.
  -- (IS NOT DISTINCT FROM, because a CHECK that evaluates to NULL passes.)
  CONSTRAINT price_watches_triggered CHECK ((state = 'triggered') = (triggered_at IS NOT NULL)
    AND (state = 'triggered') = (triggered_price_minor IS NOT NULL)
    AND (state <> 'triggered' OR (triggered_price_minor <= threshold_minor
      AND last_price_minor IS NOT DISTINCT FROM triggered_price_minor AND consecutive_failures = 0))),
  CONSTRAINT price_watches_failed CHECK ((state = 'failed') = (failure IS NOT NULL)
    AND (state <> 'failed' OR consecutive_failures = 8)
    AND (state = 'failed' OR consecutive_failures < 8))
);

-- The worker's due query: active watches by due time.
CREATE INDEX price_watches_due ON price_watches (next_check_at, id) WHERE state = 'active';
CREATE INDEX price_watches_account ON price_watches (account_id, created_at DESC);
CREATE INDEX price_watches_drafts ON price_watches (expires_at) WHERE state = 'draft';
-- The sweep of finished watches (30 days after they ended).
CREATE INDEX price_watches_finished ON price_watches (finished_at) WHERE finished_at IS NOT NULL;
