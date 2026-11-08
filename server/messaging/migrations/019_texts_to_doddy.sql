-- ADR-753 (unit U3, renumbered; was migration 010 on the old branch): texts the user sends to Doddy's number become
-- notes in the inbox, and Doddy's records at Twilio are deleted once they are final.
-- Answers by text are NOT here: they are "Text with Doddy" (ADR-656, migration 014), which has its own consent and
-- sends nothing from memory. The old branch's AI replies (Claude with a note and a memory tool) were dropped when it
-- was brought up to date (ADR-755), so there is no replies switch, no reply job and no cost column.

-- Off by default. A text to Doddy needs the consent wording the user agreed to.
CREATE TABLE text_settings (
  account_id            uuid PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE,
  inbound_enabled       boolean NOT NULL DEFAULT false,
  -- The language of Doddy's fixed notifications ("note inbox is full").
  language              text NOT NULL DEFAULT 'en' CHECK (language IN ('en', 'pl')),
  consent_text_version  text,
  consent_at            timestamptz,
  updated_at            timestamptz NOT NULL DEFAULT now(),
  CHECK ((consent_at IS NULL) = (consent_text_version IS NULL)),
  CHECK (NOT inbound_enabled OR consent_at IS NOT NULL)
);

-- One row per text from the user's own number, with texts to Doddy on. Texts from anyone else are never stored.
-- The text itself is not kept here: it goes into the notes inbox (encrypted), or is dropped when the inbox is full.
CREATE TABLE inbound_texts (
  id                uuid PRIMARY KEY,
  account_id        uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  -- Twilio's MessageSid: a text Twilio delivers twice is handled once.
  message_sid       text NOT NULL UNIQUE,
  state             text NOT NULL CHECK (state IN ('noted', 'inbox_full', 'limited')),
  received_at       timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX inbound_texts_account ON inbound_texts (account_id, received_at);

-- Notes in the inbox now say where they came from, and the app labels them: a call, or a text kept word for word.
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
