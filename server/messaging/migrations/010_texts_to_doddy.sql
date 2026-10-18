-- ADR-490 (unit U3, ADR-494): texts the user sends to Doddy's number, AI replies behind their own
-- switch, and deleting Doddy's records at Twilio once they are final.

-- All off by default. Each switch needs the one before it (replies need texts to Doddy; memories
-- in replies need replies), and texts to Doddy need the consent wording the user agreed to.
CREATE TABLE text_settings (
  account_id            uuid PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE,
  inbound_enabled       boolean NOT NULL DEFAULT false,
  replies_enabled       boolean NOT NULL DEFAULT false,
  replies_use_memories  boolean NOT NULL DEFAULT false,
  -- The language of Doddy's fixed texts ("couldn't answer that just now"); replies follow the text.
  language              text NOT NULL DEFAULT 'en' CHECK (language IN ('en', 'pl')),
  consent_text_version  text,
  consent_at            timestamptz,
  updated_at            timestamptz NOT NULL DEFAULT now(),
  CHECK ((consent_at IS NULL) = (consent_text_version IS NULL)),
  CHECK (NOT inbound_enabled OR consent_at IS NOT NULL),
  CHECK (NOT replies_enabled OR inbound_enabled),
  CHECK (NOT replies_use_memories OR replies_enabled)
);

-- One row per text from the user's own number, with texts to Doddy on. Texts from anyone else are
-- never stored. The text itself is kept, encrypted, only while a reply is being written.
CREATE TABLE inbound_texts (
  id                uuid PRIMARY KEY,
  account_id        uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  -- Twilio's MessageSid: a text Twilio delivers twice is handled once.
  message_sid       text NOT NULL UNIQUE,
  state             text NOT NULL CHECK (state IN (
                      'noted', 'inbox_full', 'limited', 'reply_queued', 'replying', 'replied', 'reply_failed')),
  body_ciphertext   bytea,
  body_key_version  smallint,
  -- Why a text became a note instead of getting an answer (late, daily_limit, budget), or why a
  -- reply failed (too_long, refusal, anthropic_429, ...).
  error_code        text,
  -- What writing the reply cost, estimated from the tokens used (Claude's list price).
  cost_microusd     integer NOT NULL DEFAULT 0 CHECK (cost_microusd >= 0),
  received_at       timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  CHECK ((body_ciphertext IS NULL) = (body_key_version IS NULL)),
  CHECK (body_ciphertext IS NULL OR state IN ('reply_queued', 'replying'))
);
CREATE INDEX inbound_texts_account ON inbound_texts (account_id, received_at);
CREATE INDEX inbound_texts_queued ON inbound_texts (received_at) WHERE state = 'reply_queued';
CREATE INDEX inbound_texts_replying ON inbound_texts (updated_at) WHERE state = 'replying';
CREATE INDEX inbound_texts_cost ON inbound_texts (received_at) WHERE cost_microusd > 0;

-- Notes in the inbox now come from calls or from texts; the app labels them.
ALTER TABLE call_notes ADD COLUMN source text NOT NULL DEFAULT 'call' CHECK (source IN ('call', 'text'));

-- Message and call records Doddy deletes at Twilio. Only Twilio's id is kept: no number, no text.
CREATE TABLE provider_deletions (
  sid           text PRIMARY KEY,
  kind          text NOT NULL CHECK (kind IN ('message', 'call')),
  -- When the record became final; it is deleted a configured time after that.
  final_at      timestamptz NOT NULL DEFAULT now(),
  next_try_at   timestamptz,
  attempts      integer NOT NULL DEFAULT 0 CHECK (attempts >= 0),
  done_at       timestamptz,
  last_error    text
);
CREATE INDEX provider_deletions_due ON provider_deletions (final_at) WHERE done_at IS NULL;
