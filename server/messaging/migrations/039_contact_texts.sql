-- Texts from Doddy's number to one of the user's iPhone contacts (decision docs/decisions/2026-11-09-texts-to-contacts.md).
-- to_e164 is the contact's number, kept like the text itself: while the text is queued or sending, and while an unknown
-- outcome is looked up in Twilio's message list; then erased. NULL means the account's own verified number, as before.
ALTER TABLE outbound_messages ADD COLUMN to_e164 text CHECK (to_e164 IS NULL OR to_e164 ~ '^\+[1-9][0-9]{7,14}$');

-- A number that answered STOP to Doddy's number is never texted as a contact again, until it answers START.
-- Only a keyed hash of the number is kept, never the number.
CREATE TABLE contact_text_opt_outs (
  number_hash  bytea PRIMARY KEY CHECK (octet_length(number_hash) = 32),
  opted_out_at timestamptz NOT NULL DEFAULT now()
);

-- Texts to contacts have their own daily count per account (50 a day), next to the account's texts to itself.
-- The list keeps every scope earlier migrations allow (030 added news_account).
ALTER TABLE daily_counters DROP CONSTRAINT daily_counters_scope_check,
  ADD CONSTRAINT daily_counters_scope_check CHECK (scope IN ('signup_ip', 'sms_account', 'news_account', 'sms_contact_account'));
