-- Call tasks (decision docs/decisions/2026-11-09-restaurant-calls-one-tap.md): up to three places,
-- each an ordinary call case with its own encrypted payload and digest, approved together with one
-- tap. The task's digest covers every case digest in order and the "text me the result" choice,
-- so the one approval is bound to exactly those calls. Places are called one after another; the
-- task stops at the first clear yes, or at an answer Doddy can't read as yes or no.
-- New table and nullable columns only: safe to apply on a live database.

CREATE TABLE call_tasks (
  id                  uuid PRIMARY KEY,
  account_id          uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  kind                text NOT NULL CHECK (kind = 'ask'),
  state               text NOT NULL CHECK (state IN ('awaiting_approval', 'active', 'finished', 'cancelled', 'expired')),
  places              smallint NOT NULL CHECK (places BETWEEN 1 AND 3),
  -- HMAC-SHA256 (derived key) of the canonical {kind, text_result, case digests in order}: what the user approves.
  task_digest         bytea NOT NULL CHECK (octet_length(task_digest) = 32),
  text_result         boolean NOT NULL,
  approvable_until    timestamptz NOT NULL,
  approved_at         timestamptz,
  approved_device_id  uuid REFERENCES devices(id) ON DELETE SET NULL,
  -- After this, no further place is called on the strength of the approval.
  chain_until         timestamptz,
  -- yes: a place said yes; none: every place was tried and none did; unclear: an answer that needs the user;
  -- stopped: the task ended early (taken over, outside calling hours, past chain_until, cancelled mid-way).
  outcome             text CHECK (outcome IN ('yes', 'none', 'unclear', 'stopped')),
  outcome_position    smallint CHECK (outcome_position BETWEEN 1 AND 3),
  finished_at         timestamptz,
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now(),
  UNIQUE (id, account_id),
  CONSTRAINT call_tasks_preview_window CHECK (approvable_until <= created_at + interval '2 days'),
  CONSTRAINT call_tasks_approved CHECK ((approved_at IS NULL) = (chain_until IS NULL)),
  CONSTRAINT call_tasks_approved_when_running CHECK (state NOT IN ('active', 'finished') OR approved_at IS NOT NULL),
  CONSTRAINT call_tasks_chain_window CHECK (chain_until IS NULL OR chain_until <= approved_at + interval '4 hours'),
  CONSTRAINT call_tasks_outcome_when_finished CHECK ((state = 'finished') = (outcome IS NOT NULL)),
  CONSTRAINT call_tasks_finished_at CHECK ((state = 'finished') = (finished_at IS NOT NULL))
);
CREATE INDEX call_tasks_account ON call_tasks (account_id, created_at DESC);
CREATE INDEX call_tasks_open ON call_tasks (approvable_until) WHERE state IN ('awaiting_approval', 'active');

-- A case belongs to at most one task, at one position. Its own digest is still what its attempt references.
ALTER TABLE call_cases ADD COLUMN task_id uuid;
ALTER TABLE call_cases ADD COLUMN task_position smallint CHECK (task_position BETWEEN 1 AND 3);
-- The callee's answer to the task's question as the result step read it; only for task cases.
ALTER TABLE call_cases ADD COLUMN task_answer text CHECK (task_answer IN ('yes', 'no', 'unclear', 'none'));
ALTER TABLE call_cases ADD CONSTRAINT call_cases_task_fk
  FOREIGN KEY (task_id, account_id) REFERENCES call_tasks (id, account_id) ON DELETE CASCADE;
ALTER TABLE call_cases ADD CONSTRAINT call_cases_task_position CHECK ((task_id IS NULL) = (task_position IS NULL));
ALTER TABLE call_cases ADD CONSTRAINT call_cases_task_answer CHECK (task_answer IS NULL OR task_id IS NOT NULL);
CREATE UNIQUE INDEX call_cases_task_slot ON call_cases (task_id, task_position) WHERE task_id IS NOT NULL;

-- A number found by Doddy's place search is a fourth source, shown on the card as such.
ALTER TABLE call_cases DROP CONSTRAINT call_cases_destination_source_check;
ALTER TABLE call_cases ADD CONSTRAINT call_cases_destination_source_check
  CHECK (destination_source IN ('contacts', 'typed', 'note', 'places'));
