-- Call-backs (decision 2026-11-09-call-backs-and-contact-calls, owner): someone Doddy called on a user's behalf who
-- calls Doddy's number back is put through to that user. One row per called number, keyed by the same keyed hash
-- call_attempts.destination_hash and call_dial_log use, never the number itself. The newest dial wins. Kept for as
-- long as the account exists (owner: "always"); deleting the account deletes its rows.
CREATE TABLE callback_routes (
  destination_hash bytea PRIMARY KEY,
  account_id       uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  last_dialed_at   timestamptz NOT NULL
);
CREATE INDEX callback_routes_account ON callback_routes (account_id);
