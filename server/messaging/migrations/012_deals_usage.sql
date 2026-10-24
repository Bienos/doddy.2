-- Leaflets (shopping mode stage 1, docs/implementation/SHOPPING.md §2): POST /v1/deals/search reads the
-- chains' leaflets on request and keeps nothing but counts, per account and UTC day, so the daily caps
-- (DEALS_DAILY_PER_ACCOUNT, DEALS_DAILY_PER_SERVER) hold. No item, page image or offer is ever written.
-- 011 is reserved for the shopping errand. Only a new table: safe to apply on a live database.

CREATE TABLE deals_usage (
  account_id     uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  day            date NOT NULL,
  requests       integer NOT NULL DEFAULT 0 CHECK (requests >= 0),
  -- Leaflet pages sent to the reader (Claude Haiku), for cost visibility.
  pages_read     integer NOT NULL DEFAULT 0 CHECK (pages_read >= 0),
  input_tokens   bigint NOT NULL DEFAULT 0 CHECK (input_tokens >= 0),
  output_tokens  bigint NOT NULL DEFAULT 0 CHECK (output_tokens >= 0),
  PRIMARY KEY (account_id, day)
);

-- The server-wide cap sums one day across accounts.
CREATE INDEX deals_usage_day ON deals_usage (day);
