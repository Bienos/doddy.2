-- Call cases (ADR-500..507, docs/decisions/calls.md): short calls Doddy places for the user after
-- the user approves a brief. What reaches Twilio and ElevenLabs exists only as one encrypted payload
-- whose digest the user approved; the constraints below make a call outside that approval
-- impossible at the database level, not just in code.
-- Content columns hold AES-256-GCM ciphertext only (no plaintext fallback: without
-- MEMORY_ENCRYPTION_KEY the feature is off). Only new tables: safe to apply on a live database.

CREATE TABLE call_cases (
  id                    uuid PRIMARY KEY,
  account_id            uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  kind                  text NOT NULL CHECK (kind = 'ask'),
  language              text NOT NULL CHECK (language = 'pl'),
  state                 text NOT NULL CHECK (state IN ('awaiting_approval', 'active', 'finished', 'cancelled', 'expired')),
  -- The compiled provider payload: Twilio To/From/limits and the agent's exact variables.
  -- AAD `${account}:call-case:${id}`. Erased when the case is finished and acknowledged, or expires.
  payload_format        smallint NOT NULL CHECK (payload_format = 1),
  payload_key_version   smallint CHECK (payload_key_version > 0),
  payload_ciphertext    bytea,
  -- HMAC-SHA256 (derived key) of the canonical payload: what the user approves. Never changes.
  payload_digest        bytea NOT NULL CHECK (octet_length(payload_digest) = 32),
  -- HMAC of the destination number, for limits; the number itself is only in the payload.
  destination_hash      bytea NOT NULL CHECK (octet_length(destination_hash) = 32),
  destination_kind      text NOT NULL CHECK (destination_kind IN ('mobile', 'geographic', 'freephone')),
  destination_source    text NOT NULL CHECK (destination_source IN ('contacts', 'typed', 'note')),
  max_duration_secs     smallint NOT NULL CHECK (max_duration_secs BETWEEN 60 AND 300),
  -- An unapproved preview lapses; a case with a failed attempt stays retryable for a day.
  approvable_until      timestamptz NOT NULL,
  payload_purged_at     timestamptz,
  -- ActivityKit push token of the Live Activity showing this case (status and times only).
  live_activity_token   text CHECK (live_activity_token ~ '^[0-9a-f]{64,400}$'),
  live_activity_env     text CHECK (live_activity_env IN ('sandbox', 'production')),
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now(),
  UNIQUE (id, account_id),
  UNIQUE (id, payload_digest),
  CONSTRAINT call_cases_key_version CHECK ((payload_ciphertext IS NULL) = (payload_key_version IS NULL)),
  CONSTRAINT call_cases_purge_marker CHECK ((payload_ciphertext IS NULL) = (payload_purged_at IS NOT NULL)),
  CONSTRAINT call_cases_payload_while_open CHECK (state NOT IN ('awaiting_approval', 'active') OR payload_ciphertext IS NOT NULL),
  CONSTRAINT call_cases_preview_window CHECK (approvable_until <= created_at + interval '2 days'),
  CONSTRAINT call_cases_live_activity CHECK ((live_activity_token IS NULL) = (live_activity_env IS NULL))
);
CREATE INDEX call_cases_account ON call_cases (account_id, created_at DESC);
CREATE INDEX call_cases_unpurged ON call_cases (approvable_until) WHERE payload_ciphertext IS NOT NULL;

-- One approval = one attempt to dial, inside its own 10-minute window. A retry is a new approval.
CREATE TABLE call_attempts (
  id                  uuid PRIMARY KEY,
  case_id             uuid NOT NULL,
  account_id          uuid NOT NULL,
  attempt_no          smallint NOT NULL CHECK (attempt_no BETWEEN 1 AND 3),
  -- Postgres itself refuses an approval of anything but the case's stored payload.
  approved_digest     bytea NOT NULL,
  approved_at         timestamptz NOT NULL DEFAULT now(),
  approved_device_id  uuid REFERENCES devices(id) ON DELETE SET NULL,
  dial_not_before     timestamptz NOT NULL,
  dial_deadline       timestamptz NOT NULL,
  state               text NOT NULL CHECK (state IN ('scheduled', 'dialing', 'ringing', 'connecting', 'in_progress',
                                                     'taken_over', 'ended', 'not_placed', 'unknown', 'expired', 'cancelled')),
  twilio_call_sid     text UNIQUE CHECK (twilio_call_sid ~ '^CA[0-9a-f]{32}$'),
  -- Twilio's SequenceNumber of the last status applied, so late or replayed callbacks change nothing.
  twilio_seq          integer,
  el_conversation_id  text UNIQUE CHECK (length(el_conversation_id) BETWEEN 1 AND 128),
  time_limit_secs     smallint NOT NULL CHECK (time_limit_secs BETWEEN 80 AND 320),
  dial_started_at     timestamptz,
  answered_at         timestamptz,
  voice_connected_at  timestamptz,
  -- When our server plays the goodbye (answered + approved max duration).
  hangup_due_at       timestamptz,
  ending_at           timestamptz,
  taken_over_at       timestamptz,
  ended_at            timestamptz,
  settled_at          timestamptz,
  end_reason          text CHECK (end_reason IN ('completed', 'no_answer', 'busy', 'failed', 'canceled', 'time_limit',
                        'voicemail', 'user_ended', 'kill_switch', 'voice_unavailable', 'gate_refused', 'account_deleted',
                        'twilio_refused', 'expired')),
  duration_secs       integer CHECK (duration_secs >= 0),
  error_code          text CHECK (length(error_code) <= 64),
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now(),
  UNIQUE (case_id, attempt_no),
  FOREIGN KEY (case_id, account_id) REFERENCES call_cases (id, account_id) ON DELETE CASCADE,
  FOREIGN KEY (case_id, approved_digest) REFERENCES call_cases (id, payload_digest) ON DELETE CASCADE,
  CONSTRAINT call_attempts_window CHECK (dial_deadline > dial_not_before AND dial_deadline <= dial_not_before + interval '10 minutes'),
  CONSTRAINT call_attempts_dial_in_window CHECK (dial_started_at IS NULL OR dial_started_at <= dial_deadline),
  CONSTRAINT call_attempts_dialed_iff CHECK ((dial_started_at IS NULL) = (state IN ('scheduled', 'expired', 'cancelled'))),
  CONSTRAINT call_attempts_sid_when_live CHECK (twilio_call_sid IS NOT NULL OR state IN ('scheduled', 'expired', 'cancelled', 'dialing', 'not_placed', 'unknown')),
  CONSTRAINT call_attempts_answered CHECK (state NOT IN ('connecting', 'in_progress', 'taken_over') OR answered_at IS NOT NULL),
  CONSTRAINT call_attempts_takeover_after_voice CHECK (taken_over_at IS NULL OR voice_connected_at IS NOT NULL),
  CONSTRAINT call_attempts_settled CHECK (
    (state NOT IN ('ended', 'not_placed', 'expired', 'cancelled') OR settled_at IS NOT NULL)
    AND (settled_at IS NULL OR state IN ('ended', 'not_placed', 'expired', 'cancelled', 'unknown')))
);
CREATE UNIQUE INDEX call_attempts_one_open_per_case ON call_attempts (case_id)
  WHERE state IN ('scheduled', 'dialing', 'ringing', 'connecting', 'in_progress', 'taken_over')
     OR (state = 'unknown' AND settled_at IS NULL);
CREATE UNIQUE INDEX call_attempts_one_live_per_account ON call_attempts (account_id)
  WHERE state IN ('dialing', 'ringing', 'connecting', 'in_progress', 'taken_over')
     OR (state = 'unknown' AND settled_at IS NULL);
CREATE INDEX call_attempts_due ON call_attempts (dial_not_before) WHERE state = 'scheduled';
CREATE INDEX call_attempts_live ON call_attempts (updated_at)
  WHERE state IN ('dialing', 'ringing', 'connecting', 'in_progress', 'taken_over') OR (state = 'unknown' AND settled_at IS NULL);
CREATE INDEX call_attempts_hangup_due ON call_attempts (hangup_due_at) WHERE state = 'in_progress' AND ending_at IS NULL;
CREATE INDEX call_attempts_account ON call_attempts (account_id, created_at);

-- "Przejmij": the user's verified phone is rung; only after they press 1 is the callee moved into a
-- conference with them.
CREATE TABLE call_takeovers (
  id                uuid PRIMARY KEY,
  attempt_id        uuid NOT NULL REFERENCES call_attempts(id) ON DELETE CASCADE,
  account_id        uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  try_no            smallint NOT NULL CHECK (try_no BETWEEN 1 AND 2),
  state             text NOT NULL CHECK (state IN ('dialing', 'ringing', 'prompted', 'joining', 'joined', 'declined', 'failed', 'unknown', 'ended')),
  twilio_call_sid   text UNIQUE CHECK (twilio_call_sid ~ '^CA[0-9a-f]{32}$'),
  conference_name   text NOT NULL UNIQUE CHECK (conference_name ~ '^doddy-[A-Za-z0-9_-]{22,}$'),
  requested_at      timestamptz NOT NULL DEFAULT now(),
  callee_joined_at  timestamptz,
  user_joined_at    timestamptz,
  joined_at         timestamptz,
  settled_at        timestamptz,
  UNIQUE (attempt_id, try_no),
  CHECK (state <> 'joined' OR (joined_at IS NOT NULL AND twilio_call_sid IS NOT NULL)),
  CHECK ((settled_at IS NOT NULL) = (state IN ('declined', 'failed', 'ended')))
);
CREATE UNIQUE INDEX call_takeovers_one_open ON call_takeovers (attempt_id) WHERE state IN ('dialing', 'ringing', 'prompted', 'joining');

-- What was said, live, from Twilio's transcription. Deleted once the result is built (24 h at most).
CREATE TABLE call_live_lines (
  attempt_id         uuid NOT NULL REFERENCES call_attempts(id) ON DELETE CASCADE,
  account_id         uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  transcription_sid  text NOT NULL CHECK (length(transcription_sid) BETWEEN 1 AND 64),
  seq                integer NOT NULL CHECK (seq >= 0),
  speaker            text NOT NULL CHECK (speaker IN ('doddy', 'callee')),
  key_version        smallint NOT NULL CHECK (key_version > 0),
  -- AAD `${account}:call-live:${attempt}:${transcription_sid}:${seq}`
  ciphertext         bytea NOT NULL,
  received_at        timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (attempt_id, transcription_sid, seq)
);
CREATE INDEX call_live_lines_received ON call_live_lines (received_at);

-- The answer card. `input_*` holds the provider transcript until the result is built; the result
-- itself is kept only until the app has saved it (ack) or for 7 days.
CREATE TABLE call_results (
  attempt_id          uuid PRIMARY KEY REFERENCES call_attempts(id) ON DELETE CASCADE,
  account_id          uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  state               text NOT NULL CHECK (state IN ('waiting', 'ready', 'acked', 'expired')),
  input_source        text CHECK (input_source IN ('elevenlabs')),
  input_key_version   smallint CHECK (input_key_version > 0),
  input_ciphertext    bytea,                -- AAD `${account}:call-input:${attempt}`
  process_after       timestamptz NOT NULL, -- build from what we have once this passes
  outcome             text CHECK (outcome IN ('answered', 'no_answer', 'busy', 'failed', 'not_placed', 'voicemail', 'ivr',
                        'wrong_number', 'no_conversation', 'taken_over', 'voice_unavailable', 'stopped', 'unknown')),
  source              text CHECK (source IN ('elevenlabs', 'twilio_live', 'none')),
  confidence          text CHECK (confidence IN ('high', 'medium', 'low', 'none')),
  warning_count       smallint NOT NULL DEFAULT 0 CHECK (warning_count >= 0),
  key_version         smallint CHECK (key_version > 0),
  ciphertext          bytea,                -- AAD `${account}:call-result:${attempt}`
  result_digest       bytea CHECK (octet_length(result_digest) = 32),
  ready_at            timestamptz,
  expires_at          timestamptz,
  settled_at          timestamptz,
  CHECK ((input_ciphertext IS NULL) = (input_key_version IS NULL)),
  CHECK ((input_ciphertext IS NULL) = (input_source IS NULL)),
  CHECK ((ciphertext IS NULL) = (key_version IS NULL)),
  CHECK (state <> 'waiting' OR ciphertext IS NULL),
  CHECK (state <> 'ready' OR (ciphertext IS NOT NULL AND result_digest IS NOT NULL AND outcome IS NOT NULL
                              AND expires_at IS NOT NULL AND input_ciphertext IS NULL)),
  CHECK (state NOT IN ('acked', 'expired') OR (ciphertext IS NULL AND input_ciphertext IS NULL AND settled_at IS NOT NULL)),
  CHECK (expires_at IS NULL OR expires_at <= ready_at + interval '7 days')
);
CREATE INDEX call_results_waiting ON call_results (process_after) WHERE state = 'waiting';
CREATE INDEX call_results_expiry ON call_results (expires_at) WHERE state = 'ready';

-- Cost per attempt and part. Pending rows are written in the same transaction that claims an
-- attempt for dialling, so a dialled call can't end up without a cost.
CREATE TABLE call_cost_items (
  attempt_id     uuid NOT NULL REFERENCES call_attempts(id) ON DELETE CASCADE,
  account_id     uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  component      text NOT NULL CHECK (component IN ('twilio_call', 'twilio_takeover', 'twilio_transcription',
                                                    'twilio_conference', 'elevenlabs_voice', 'model')),
  ref            text NOT NULL DEFAULT '',  -- e.g. the takeover id for per-leg rows
  status         text NOT NULL CHECK (status IN ('pending', 'reported', 'estimated', 'zero', 'unknown')),
  amount_micros  bigint CHECK (amount_micros >= 0),
  currency       text CHECK (currency ~ '^[A-Z]{3}$'),
  quantity       numeric(14, 3) CHECK (quantity >= 0),
  unit           text CHECK (unit IN ('call', 'minute', 'participant_minute', 'credit', 'token')),
  tries          smallint NOT NULL DEFAULT 0 CHECK (tries >= 0),
  next_try_at    timestamptz,
  due_by         timestamptz NOT NULL,
  settled_at     timestamptz,
  PRIMARY KEY (attempt_id, component, ref),
  CHECK ((status IN ('reported', 'estimated', 'zero')) = (amount_micros IS NOT NULL AND currency IS NOT NULL)),
  CHECK (status <> 'zero' OR amount_micros = 0),
  CHECK ((status = 'pending') = (settled_at IS NULL))
);
CREATE INDEX call_cost_items_pending ON call_cost_items (next_try_at) WHERE status = 'pending';

-- Content-free and not tied to an account (like phone_verification_starts), so limits per
-- destination and per verified phone survive deleting an account.
CREATE TABLE call_dial_log (
  destination_hash   bytea NOT NULL CHECK (octet_length(destination_hash) = 32),
  caller_phone_hash  bytea NOT NULL CHECK (octet_length(caller_phone_hash) = 32),
  dialed_at          timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX call_dial_log_destination ON call_dial_log (destination_hash, dialed_at);
CREATE INDEX call_dial_log_caller ON call_dial_log (caller_phone_hash, dialed_at);
CREATE INDEX call_dial_log_time ON call_dial_log (dialed_at);

-- Receipts for every deletion of call content: what, where, why, and whether it was confirmed.
-- No content. Jobs at providers outlive the account (ON DELETE SET NULL).
CREATE TABLE server_data_deletions (
  id             uuid PRIMARY KEY,
  account_id     uuid REFERENCES accounts(id) ON DELETE SET NULL,
  case_id        uuid REFERENCES call_cases(id) ON DELETE SET NULL,
  attempt_id     uuid REFERENCES call_attempts(id) ON DELETE SET NULL,
  item           text NOT NULL CHECK (item IN ('call_payload', 'live_lines', 'call_input', 'call_result', 'elevenlabs_conversation')),
  location       text NOT NULL CHECK (location IN ('doddy_server', 'elevenlabs')),
  reason         text NOT NULL CHECK (reason IN ('acked', 'expired', 'processed', 'cancelled', 'orphan', 'account_deleted')),
  result         text NOT NULL CHECK (result IN ('pending', 'deleted', 'not_found', 'failed', 'unknown')),
  provider_ref   text CHECK (length(provider_ref) <= 128),
  row_count      integer CHECK (row_count >= 0),
  tries          smallint NOT NULL DEFAULT 0 CHECK (tries BETWEEN 0 AND 20),
  next_try_at    timestamptz,
  requested_at   timestamptz NOT NULL DEFAULT now(),
  settled_at     timestamptz,
  CHECK ((result = 'pending') = (settled_at IS NULL)),
  CHECK (result <> 'pending' OR next_try_at IS NOT NULL),
  CHECK (location = 'doddy_server' OR provider_ref IS NOT NULL),
  CHECK (location <> 'doddy_server' OR result IN ('deleted', 'not_found'))
);
CREATE INDEX server_data_deletions_due ON server_data_deletions (next_try_at) WHERE result = 'pending';
CREATE INDEX server_data_deletions_case ON server_data_deletions (case_id);
CREATE UNIQUE INDEX server_data_deletions_provider_job ON server_data_deletions (location, item, provider_ref)
  WHERE location <> 'doddy_server';
