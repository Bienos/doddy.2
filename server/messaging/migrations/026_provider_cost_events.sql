-- Provider cost ledger (research item 1, messaging half): one row per provider call (or per
-- aggregated run for errands), linked to the Doddy account, so the owner can see which accounts,
-- features and models cost money. Numbers and ids only: no prompt, answer, note, URL or user text is
-- ever written here. A new table: safe to apply on a live database.
--
-- Unknown is not zero: a call whose usage the provider never reported (a failed or timed-out request)
-- has NULL token counts and usage_known = false; a model without a price in the code has cost_usd NULL
-- and cost_basis = 'unknown_model'. Sums over the table must treat NULL as "not known", not as 0.
--
-- account_id is SET NULL when the account is deleted, so the row no longer says whose it was but the
-- server's real spend stays counted (the same reason server_daily_usage has no account, ADR-673).
-- The Doddy account (Supabase subject) is reached through accounts.auth_subject (migration 021); the
-- subject itself is not copied here.

CREATE TABLE provider_cost_events (
  id                 bigserial PRIMARY KEY,
  occurred_at        timestamptz NOT NULL DEFAULT now(),
  account_id         uuid REFERENCES accounts(id) ON DELETE SET NULL,
  provider           text NOT NULL CHECK (provider IN ('anthropic', 'openai')),
  model              text NOT NULL,
  -- Which product feature made the call, e.g. assistant, errand, news_digest, deals_vision.
  feature            text NOT NULL CHECK (feature ~ '^[a-z][a-z0-9_]{0,39}$'),
  -- The provider's own request id (Anthropic's request-id header), when the call got a response.
  provider_request_id text,
  -- Our own id for the job the call belongs to (an errand id, a digest id): an id, never content.
  ref_id             text,
  -- success: a usable answer. refused/unparsed: the provider answered but nothing usable came of it (still billed).
  -- failure: the call ended in an error, usage unknown. retry: an earlier attempt of a call that was tried again.
  outcome            text NOT NULL CHECK (outcome IN ('success', 'refused', 'unparsed', 'failure', 'retry')),
  attempts           integer NOT NULL DEFAULT 1 CHECK (attempts >= 1),
  error_code         text,
  usage_known        boolean NOT NULL,
  input_tokens       bigint CHECK (input_tokens >= 0),
  output_tokens      bigint CHECK (output_tokens >= 0),
  cache_read_tokens  bigint CHECK (cache_read_tokens >= 0),
  cache_write_tokens bigint CHECK (cache_write_tokens >= 0),
  -- Web searches billed on top of tokens ($10 per 1,000); counted in cost_usd. NULL: not applicable or unknown.
  web_searches       integer CHECK (web_searches >= 0),
  cost_usd           numeric(14, 8) CHECK (cost_usd >= 0),
  cost_basis         text NOT NULL CHECK (cost_basis IN ('list_price', 'unknown_model', 'unknown_usage')),
  price_version      text,
  -- Known usage always has all four counts; unknown usage has none.
  CHECK ((usage_known AND input_tokens IS NOT NULL AND output_tokens IS NOT NULL
          AND cache_read_tokens IS NOT NULL AND cache_write_tokens IS NOT NULL)
         OR (NOT usage_known AND input_tokens IS NULL AND output_tokens IS NULL
             AND cache_read_tokens IS NULL AND cache_write_tokens IS NULL AND cost_usd IS NULL))
);

CREATE INDEX provider_cost_events_account_time ON provider_cost_events (account_id, occurred_at);
CREATE INDEX provider_cost_events_time ON provider_cost_events (occurred_at);
