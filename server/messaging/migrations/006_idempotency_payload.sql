-- Review 2026-10-11, finding 3 (DOD-07): an idempotency key is bound to the exact payload it was
-- first used with. Reusing it with different text or schedule is refused instead of silently
-- returning the older message. SHA-256 of the payload; NULL for rows queued before this migration.
ALTER TABLE outbound_messages ADD COLUMN payload_hash bytea CHECK (octet_length(payload_hash) = 32);
