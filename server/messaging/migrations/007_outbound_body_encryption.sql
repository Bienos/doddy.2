-- Review 2026-10-11, finding 8 (DOD-11): queued message text is encrypted at rest when the server
-- has MEMORY_ENCRYPTION_KEY, like call notes and memory copies (AES-256-GCM, bound to the account
-- and message id). Plain `body` stays for servers without the key and for rows queued earlier.
-- Either form is kept only while the message is queued or sending.
ALTER TABLE outbound_messages ADD COLUMN body_ciphertext bytea, ADD COLUMN body_key_version smallint;
ALTER TABLE outbound_messages DROP CONSTRAINT outbound_messages_check, DROP CONSTRAINT outbound_messages_check1;
ALTER TABLE outbound_messages
  ADD CONSTRAINT outbound_messages_body_while_pending
    CHECK (state NOT IN ('queued', 'sending') OR body IS NOT NULL OR body_ciphertext IS NOT NULL),
  ADD CONSTRAINT outbound_messages_body_erased_when_final
    CHECK (state IN ('queued', 'sending') OR (body IS NULL AND body_ciphertext IS NULL)),
  ADD CONSTRAINT outbound_messages_one_body_form
    CHECK (body IS NULL OR body_ciphertext IS NULL),
  ADD CONSTRAINT outbound_messages_key_version
    CHECK ((body_ciphertext IS NULL) = (body_key_version IS NULL));
