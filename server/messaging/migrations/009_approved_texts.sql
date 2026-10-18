-- ADR-490 (unit U2): texts the user approves on a card, bound to the exact recipient and text,
-- and a lookup at Twilio for a text whose outcome is unknown (DOD-07, DOD-09).
ALTER TABLE outbound_messages
  -- A text the user approved on a card (POST /v1/texts), not an update or a news digest.
  ADD COLUMN approved_text boolean NOT NULL DEFAULT false,
  -- SHA-256 over the approval encoding (src/approval.ts) of the number and the exact text the user
  -- approved. Checked again right before sending; erased once it is no longer needed.
  ADD COLUMN approval_hash bytea CHECK (octet_length(approval_hash) = 32),
  -- SHA-256 of an SMS's exact text, to find it in Twilio's message list if its outcome is unknown.
  -- Erased once the message has a known outcome.
  ADD COLUMN body_hash bytea CHECK (octet_length(body_hash) = 32),
  -- What the lookup at Twilio found for an unknown text.
  ADD COLUMN lookup text CHECK (lookup IN ('found', 'not_found', 'failed')),
  ADD COLUMN lookup_attempts integer NOT NULL DEFAULT 0 CHECK (lookup_attempts >= 0),
  ADD CONSTRAINT outbound_messages_approved_until_sent
    CHECK (NOT approved_text OR state NOT IN ('queued', 'sending') OR approval_hash IS NOT NULL);
CREATE INDEX outbound_messages_unknown_sms ON outbound_messages (updated_at)
  WHERE state = 'unknown' AND channel = 'sms' AND lookup IS NULL;
CREATE INDEX outbound_messages_approved_texts ON outbound_messages (created_at) WHERE approved_text;
