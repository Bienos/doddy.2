-- Texting Doddy (docs/implementation/SMS_CHAT.md): a text from the person's own verified number gets
-- an answer by text, from the same Claude as Messages, with no tools and no notes. A second, separate
-- in-app consent on top of the SMS consent: when, and which wording. Nothing the person wrote or
-- Doddy answered is kept here; the reply waits encrypted in outbound_messages and is erased once sent.
-- Only new nullable columns: safe to apply on a live database.

ALTER TABLE phone_numbers
  ADD COLUMN sms_chat_consent_at           timestamptz,
  ADD COLUMN sms_chat_consent_text_version text,
  ADD CHECK ((sms_chat_consent_at IS NULL) = (sms_chat_consent_text_version IS NULL));
