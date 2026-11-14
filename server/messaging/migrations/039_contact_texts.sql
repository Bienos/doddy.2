-- Texts from Doddy's number to one of the user's iPhone contacts (decision docs/decisions/2026-11-09-texts-to-contacts.md).
-- to_e164 is the contact's number, kept like the text itself: while the text is queued or sending, and while an unknown
-- outcome is looked up in Twilio's message list; then erased. NULL means the account's own verified number, as before.
ALTER TABLE outbound_messages ADD COLUMN to_e164 text CHECK (to_e164 IS NULL OR to_e164 ~ '^\+[1-9][0-9]{7,14}$');

-- A number that answered STOP to Doddy's number is never texted as a contact again, until it answers START.
-- It is found by a keyed hash. The number itself is kept only encrypted, so that a rotation of MEMORY_ENCRYPTION_KEY
-- can re-hash it under the new key (scripts/reencrypt.mjs); without it a rotation would forget every STOP.
-- Both are NULL only for a row written without a key (local runs and tests).
CREATE TABLE contact_text_opt_outs (
  number_hash       bytea PRIMARY KEY CHECK (octet_length(number_hash) = 32),
  number_ciphertext bytea,
  key_version       integer,
  opted_out_at      timestamptz NOT NULL DEFAULT now(),
  CHECK ((number_ciphertext IS NULL) = (key_version IS NULL))
);

-- Texts to contacts have their own daily count per account (50 a day), next to the account's texts to itself.
-- The list keeps every scope earlier migrations allow (030 added news_account).
ALTER TABLE daily_counters DROP CONSTRAINT daily_counters_scope_check,
  ADD CONSTRAINT daily_counters_scope_check CHECK (scope IN ('signup_ip', 'sms_account', 'news_account', 'sms_contact_account'));
