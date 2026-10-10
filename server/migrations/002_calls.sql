-- S2: phone calls with the ElevenLabs agent over a Twilio number.
-- Memory text that reaches the server (opt-in copy, notes taken on calls) is stored
-- encrypted (AES-256-GCM, key held by the server). It is NOT end-to-end encrypted: the
-- server must read it to answer on a call. Everything cascades on account deletion.

CREATE TABLE call_settings (
  account_id                      uuid PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE,
  inbound_enabled                 boolean NOT NULL DEFAULT false,
  -- scrypt$N$r$p$salt$hash; the PIN itself is never stored.
  pin_hash                        text,
  pin_failed_attempts             integer NOT NULL DEFAULT 0 CHECK (pin_failed_attempts >= 0),
  pin_locked_until                timestamptz,
  outbound_consent_at             timestamptz,
  outbound_consent_text_version   text,
  memory_copy_enabled_at          timestamptz,
  updated_at                      timestamptz NOT NULL DEFAULT now(),
  CHECK ((outbound_consent_at IS NULL) = (outbound_consent_text_version IS NULL))
);

CREATE TABLE memory_copies (
  account_id    uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  memory_id     uuid NOT NULL,
  key_version   smallint NOT NULL CHECK (key_version > 0),
  ciphertext    bytea NOT NULL,
  captured_at   timestamptz,
  PRIMARY KEY (account_id, memory_id)
);

-- Notes Doddy took during a call. They are not memories until the user confirms them in the app.
CREATE TABLE call_notes (
  id               uuid PRIMARY KEY,
  account_id       uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  key_version      smallint NOT NULL CHECK (key_version > 0),
  ciphertext       bytea NOT NULL,
  conversation_id  text,
  created_at       timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX call_notes_account_id ON call_notes (account_id, created_at);

-- One row per call (both directions), for the app's call list and cost control.
CREATE TABLE calls (
  id               uuid PRIMARY KEY,
  account_id       uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  direction        text NOT NULL CHECK (direction IN ('inbound', 'outbound')),
  status           text NOT NULL CHECK (status IN ('started', 'requested', 'failed', 'unknown')),
  conversation_id  text,
  call_sid         text,
  error_code       text,
  created_at       timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX calls_account_id ON calls (account_id, created_at);

-- Capability for one call: the agent sends the token (a secret__ dynamic variable, only ever
-- placed in a request header, never shown to the language model) with every tool request.
CREATE TABLE call_sessions (
  id               uuid PRIMARY KEY,
  account_id       uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  token_hash       bytea NOT NULL UNIQUE CHECK (octet_length(token_hash) = 32),
  call_id          uuid REFERENCES calls(id) ON DELETE SET NULL,
  pin_verified_at  timestamptz,
  created_at       timestamptz NOT NULL DEFAULT now(),
  expires_at       timestamptz NOT NULL
);
CREATE INDEX call_sessions_expires_at ON call_sessions (expires_at);
