-- Timers that end with a Live Activity push (ADR-483). The app starts a timer's Live Activity with
-- a push token and sends it here with the end time. The worker sends the update when the time is
-- due, so the island opens up and plays the alert even when the app is not running. One row per
-- timer. The push token is kept only until the update is sent or cancelled, then erased.
CREATE TABLE live_activity_timers (
  id               uuid PRIMARY KEY,
  account_id       uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  activity_token   text,
  environment      text NOT NULL CHECK (environment IN ('sandbox', 'production')),
  label            text CHECK (label IS NULL OR length(label) <= 60),
  send_at          timestamptz NOT NULL,
  state            text NOT NULL CHECK (state IN ('queued', 'sending', 'sent', 'failed', 'cancelled')),
  attempts         smallint NOT NULL DEFAULT 0,
  last_error       text,
  created_at       timestamptz NOT NULL DEFAULT now(),
  -- The token exists only while the timer can still be sent.
  CONSTRAINT live_activity_timers_token_while_pending
    CHECK (state IN ('queued', 'sending') OR activity_token IS NULL)
);
CREATE INDEX live_activity_timers_due ON live_activity_timers (send_at) WHERE state = 'queued';
CREATE INDEX live_activity_timers_account ON live_activity_timers (account_id);
