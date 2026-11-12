-- Deliveries through Uber Direct (decision 2026-11-12-uber-direct-deliveries): a quote the user sees on
-- a card, then a delivery Uber creates only after the tap that card bound (approval_hash, DOD-07).

CREATE TABLE deliveries (
  id                 uuid PRIMARY KEY,
  account_id         uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  -- quoted: priced, waiting for the tap. creating: sent to Uber, no answer yet. created: Uber took it.
  -- unknown: Uber may or may not have taken it; never sent again on its own (DOD-08). delivered,
  -- cancelled, returned: over. failed: Uber refused, or the tap came too late. expired: never tapped.
  state              text NOT NULL CHECK (state IN (
                       'quoted', 'creating', 'created', 'unknown', 'delivered', 'cancelled', 'returned', 'failed', 'expired')),
  error_code         text,
  uber_quote_id      text NOT NULL,
  -- In the currency's minor units, as Uber quoted it.
  fee                integer NOT NULL CHECK (fee >= 0),
  currency           text NOT NULL CHECK (currency ~ '^[A-Z]{3}$'),
  quote_expires_at   timestamptz NOT NULL,
  dropoff_eta        timestamptz,
  -- Names, addresses, phone numbers, items, the note and the card's lines, encrypted; erased once the
  -- delivery is over or the quote lapsed.
  payload_ciphertext bytea,
  payload_key_version smallint,
  approval_hash      bytea NOT NULL CHECK (octet_length(approval_hash) = 32),
  confirm_key        text,
  confirmed_at       timestamptz,
  uber_delivery_id   text,
  uber_status        text,
  tracking_url       text CHECK (tracking_url IS NULL OR tracking_url LIKE 'https://%'),
  live_mode          boolean,
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now(),
  UNIQUE (account_id, confirm_key),
  CHECK ((payload_ciphertext IS NULL) = (payload_key_version IS NULL)),
  CHECK (payload_ciphertext IS NOT NULL OR state NOT IN ('quoted', 'creating')),
  -- Anything past the quote was tapped: there is no way to Uber without a confirmation.
  CHECK (confirmed_at IS NOT NULL OR state IN ('quoted', 'expired')),
  CHECK ((confirmed_at IS NULL) = (confirm_key IS NULL))
);
CREATE INDEX deliveries_account ON deliveries (account_id, created_at DESC);
-- The daily caps count confirmed deliveries; the prune finds lapsed quotes and finished ones.
CREATE INDEX deliveries_confirmed ON deliveries (confirmed_at) WHERE confirmed_at IS NOT NULL;
CREATE INDEX deliveries_open ON deliveries (state, updated_at) WHERE payload_ciphertext IS NOT NULL;
