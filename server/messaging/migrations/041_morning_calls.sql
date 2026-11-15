-- Decision docs/decisions/2026-11-14-morning-call.md: a call from Doddy's number on each chosen day at one local
-- time, with a short plan of the day. The person approves the exact schedule on a card (time, days, zone, number,
-- the quiet-hours choice and the language: morningCallApprovalHash). Each day the worker turns it into a normal
-- scheduled call (020_scheduled_calls.sql), so every check of a booked call still runs when it is due: the number
-- and consent, quiet hours where the person is, the hourly and daily caps, too late. One active schedule per account.
-- Only a new table and two new columns with no rewrite: safe to apply while the old code runs.

CREATE TABLE morning_calls (
  id                uuid PRIMARY KEY,
  account_id        uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  -- Exactly as the card showed it and the approval hashed it.
  local_time        text NOT NULL CHECK (local_time ~ '^([01]\d|2[0-3]):[0-5]\d$'),
  -- ISO weekdays, Monday = 1, ascending, each at most once: "12345" (weekdays), "1234567" (every day).
  days              text NOT NULL CHECK (days ~ '^1?2?3?4?5?6?7?$' AND days <> ''),
  time_zone         text NOT NULL CHECK (length(time_zone) BETWEEN 1 AND 64),
  allow_quiet_hours boolean NOT NULL,
  language          text NOT NULL CHECK (language IN ('en', 'pl')),
  approval_hash     bytea NOT NULL CHECK (octet_length(approval_hash) = 32),
  idempotency_key   text NOT NULL,
  state             text NOT NULL CHECK (state IN ('active', 'stopped')),
  -- Why it stopped: stopped_by_user, replaced, number_changed, consent_off, no_verified_phone, country_not_allowed.
  stop_code         text,
  -- The next day's call, which the worker turns into a scheduled call when it is due. None once stopped.
  next_call_at      timestamptz,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  stopped_at        timestamptz,
  UNIQUE (account_id, idempotency_key),
  CHECK ((state = 'active') = (next_call_at IS NOT NULL)),
  CHECK ((state = 'stopped') = (stopped_at IS NOT NULL)),
  CHECK ((state = 'stopped') = (stop_code IS NOT NULL))
);
-- One morning call per account, even if two requests race.
CREATE UNIQUE INDEX morning_calls_one_active ON morning_calls (account_id) WHERE state = 'active';
CREATE INDEX morning_calls_due ON morning_calls (next_call_at) WHERE state = 'active';

-- A day's call made from a morning call is a scheduled call of kind 'morning', linked to its schedule. Its reason is
-- the plan the server wrote for that day (encrypted, erased like any other reason), and its approval hash is the
-- schedule's: the worker checks it against the schedule and the number when the call is due.
ALTER TABLE scheduled_calls ADD COLUMN kind text NOT NULL DEFAULT 'once' CHECK (kind IN ('once', 'morning'));
ALTER TABLE scheduled_calls ADD COLUMN morning_call_id uuid REFERENCES morning_calls(id) ON DELETE SET NULL;
CREATE INDEX scheduled_calls_morning ON scheduled_calls (morning_call_id) WHERE morning_call_id IS NOT NULL;
