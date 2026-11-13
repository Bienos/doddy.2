-- Leaflet results and deal watches (owner, 13 Nov 2026; decision docs/decisions/2026-11-13-leaflet-results-and-deal-watches.md).
-- New tables and one new nullable column only: safe to apply on a live database. Nothing reads the new tables while
-- DEAL_WATCHES_ENABLED is "0", and the catalog writes the token ledger only while DEALS_CATALOG_ENABLED is "1".

-- 1. Why a catalog page couldn't be read (image_too_large, image_failed, image_refused, read_failed), so a snapshot can
--    say which pages are missing and why. Null for a page that was read, and for rows written before this.
ALTER TABLE leaflet_page_reads ADD COLUMN failure text CHECK (failure IS NULL OR failure ~ '^[a-z_]{1,40}$');

-- 2. The catalog scans' daily token budget: input plus output tokens per chain and Warsaw day. Counts only; rows older
--    than a week are deleted by the scan.
CREATE TABLE leaflet_catalog_tokens (
  chain   text NOT NULL CHECK (chain ~ '^[a-z]{2,20}$'),
  day     date NOT NULL,
  tokens  bigint NOT NULL DEFAULT 0 CHECK (tokens >= 0),
  PRIMARY KEY (chain, day)
);

-- 3. Deal watches: "let me know when butter is under 5 zł", checked in code against the leaflet catalog, never by reading
--    a page for it. Kept: the item's words (encrypted with MEMORY_ENCRYPTION_KEY, associated data
--    "{account}:deal-watch:{id}"), the optional price in grosze and chains, the language of the one push text, and the
--    account. Nothing else about the person. Deleted when it ends (DEAL_WATCHES_DAYS), on DELETE, and with the account.
CREATE TABLE deal_watches (
  id                 uuid PRIMARY KEY,
  account_id         uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  key_version        smallint NOT NULL CHECK (key_version BETWEEN 1 AND 32767),
  words_ciphertext   bytea NOT NULL,
  max_price_minor    integer CHECK (max_price_minor BETWEEN 1 AND 10000000),
  chains             text[] CHECK (chains IS NULL OR cardinality(chains) BETWEEN 1 AND 20),
  language           text NOT NULL CHECK (language IN ('pl', 'en')),
  created_at         timestamptz NOT NULL,
  ends_at            timestamptz NOT NULL,
  last_checked_at    timestamptz,
  CHECK (ends_at > created_at)
);
CREATE INDEX deal_watches_account ON deal_watches (account_id);
CREATE INDEX deal_watches_due ON deal_watches (last_checked_at NULLS FIRST);
CREATE INDEX deal_watches_ends ON deal_watches (ends_at);

-- The offers a watch has already found, once each: the idempotency of its pushes. `offer_key` is an HMAC (a key derived
-- from MEMORY_ENCRYPTION_KEY) of the watch and the offer, so the row says nothing about the offer by itself.
-- told_by: 'push' when one was queued for it, 'app' when it is only shown in the app (found when the watch was made,
-- more than one new offer at once, no device, the day's cap, or too late after quiet hours).
CREATE TABLE deal_watch_hits (
  watch_id    uuid NOT NULL REFERENCES deal_watches(id) ON DELETE CASCADE,
  account_id  uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  offer_key   bytea NOT NULL CHECK (length(offer_key) = 16),
  found_at    timestamptz NOT NULL,
  -- The offer's last day, when the leaflet gives one: the row is deleted a month after it.
  valid_to    date,
  told_at     timestamptz,
  told_by     text CHECK (told_by IN ('push', 'app')),
  PRIMARY KEY (watch_id, offer_key),
  CHECK ((told_at IS NULL) = (told_by IS NULL))
);
CREATE INDEX deal_watch_hits_untold ON deal_watch_hits (watch_id, found_at) WHERE told_at IS NULL;
CREATE INDEX deal_watch_hits_found ON deal_watch_hits (found_at);
