-- Messages (ADR-585, ADR-586): the app's typed conversation asks Claude through this server. Only
-- counts are kept, per account and UTC day, so the daily caps hold; no question, answer or note is
-- ever written. Only a new table: safe to apply on a live database.

CREATE TABLE assistant_usage (
  account_id     uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  day            date NOT NULL,
  requests       integer NOT NULL DEFAULT 0 CHECK (requests >= 0),
  input_tokens   bigint NOT NULL DEFAULT 0 CHECK (input_tokens >= 0),
  output_tokens  bigint NOT NULL DEFAULT 0 CHECK (output_tokens >= 0),
  PRIMARY KEY (account_id, day)
);

-- The server-wide cap sums one day across accounts.
CREATE INDEX assistant_usage_day ON assistant_usage (day);
