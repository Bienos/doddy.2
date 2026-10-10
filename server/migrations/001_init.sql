-- Doddy server schema v1: anonymous accounts, devices, one phone number per account,
-- and an outbox of updates (push / SMS). Memories are NOT stored here; they stay on the phone.
-- Deleting an account purges every row that belongs to it (ON DELETE CASCADE).

CREATE TABLE accounts (
  id          uuid PRIMARY KEY,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE devices (
  id                     uuid PRIMARY KEY,
  account_id             uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  -- SHA-256 of the bearer token; the token itself is never stored.
  token_hash             bytea NOT NULL UNIQUE CHECK (octet_length(token_hash) = 32),
  apns_token             text UNIQUE CHECK (apns_token ~ '^[0-9a-f]{64,200}$'),
  apns_environment       text CHECK (apns_environment IN ('sandbox', 'production')),
  apns_token_invalid_at  timestamptz,
  created_at             timestamptz NOT NULL DEFAULT now(),
  last_seen_at           timestamptz NOT NULL DEFAULT now(),
  CHECK ((apns_token IS NULL) = (apns_environment IS NULL))
);
CREATE INDEX devices_account_id ON devices (account_id);

CREATE TABLE phone_numbers (
  account_id                uuid PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE,
  e164                      text NOT NULL UNIQUE CHECK (e164 ~ '^\+[1-9][0-9]{6,14}$'),
  verified_at               timestamptz NOT NULL,
  -- Explicit in-app SMS opt-in: when, and which wording the user agreed to.
  sms_consent_at            timestamptz,
  sms_consent_text_version  text,
  -- Set by an inbound STOP; cleared only by an inbound START (carrier rules).
  sms_opted_out_at          timestamptz,
  updated_at                timestamptz NOT NULL DEFAULT now(),
  CHECK ((sms_consent_at IS NULL) = (sms_consent_text_version IS NULL))
);

CREATE TABLE outbound_messages (
  id                   uuid PRIMARY KEY,
  account_id           uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  channel              text NOT NULL CHECK (channel IN ('push', 'sms')),
  idempotency_key      text NOT NULL CHECK (length(idempotency_key) BETWEEN 1 AND 128),
  -- Message text is kept only until the message reaches a final state, then erased.
  body                 text,
  send_at              timestamptz NOT NULL,
  state                text NOT NULL CHECK (state IN ('queued', 'sending', 'sent', 'failed', 'unknown', 'cancelled')),
  attempts             integer NOT NULL DEFAULT 0 CHECK (attempts >= 0),
  provider_message_id  text,
  delivery_status      text,
  error_code           text,
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now(),
  UNIQUE (account_id, channel, idempotency_key),
  CHECK (state NOT IN ('queued', 'sending') OR body IS NOT NULL),
  CHECK (state IN ('queued', 'sending') OR body IS NULL)
);
CREATE INDEX outbound_messages_account_id ON outbound_messages (account_id);
CREATE INDEX outbound_messages_due ON outbound_messages (send_at) WHERE state = 'queued';
CREATE INDEX outbound_messages_in_flight ON outbound_messages (updated_at) WHERE state = 'sending';
CREATE UNIQUE INDEX outbound_messages_provider_id ON outbound_messages (provider_message_id)
  WHERE provider_message_id IS NOT NULL;
