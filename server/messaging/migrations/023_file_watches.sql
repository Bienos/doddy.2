-- File-ready pushes (owner, 9 Nov 2026): "when Doddy makes me a file, tell me when it is done". The app registers
-- the file's signed link (the capability link of Doddy's backend, ADR-564); the worker asks that link whether the
-- file is ready and sends one push with no words. The link is stored encrypted (anyone who holds it can open the
-- file until it expires), and only links on the configured DOCUMENTS_ORIGIN are accepted.
-- New table only: safe to apply on a live database.

CREATE TABLE file_watches (
  id               uuid PRIMARY KEY,
  account_id       uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  document_id      text NOT NULL CHECK (document_id ~ '^[A-Za-z0-9_-]{24}$'),
  link_ciphertext  bytea NOT NULL,
  language         text NOT NULL CHECK (language IN ('pl', 'en')),
  state            text NOT NULL DEFAULT 'watching' CHECK (state IN ('watching', 'notified', 'gone')),
  created_at       timestamptz NOT NULL,
  -- After this a file that is still not ready is dropped without a push (the backend marks it interrupted).
  expires_at       timestamptz NOT NULL,
  last_checked_at  timestamptz,
  finished_at      timestamptz,
  UNIQUE (account_id, document_id)
);

CREATE INDEX file_watches_due ON file_watches (last_checked_at NULLS FIRST) WHERE state = 'watching';
