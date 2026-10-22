-- Studio (ADR-584, docs/implementation/STUDIO.md): Doddy researches a topic and makes files from it
-- (S0: a research brief and an infographic) after one yes. Like errands, the job the user approved
-- exists only as one encrypted blob whose SHA-256 they approved, and what the run produced (title,
-- summary, sources, checks) is encrypted too. Unlike errands, the server keeps the item and its
-- files until the user deletes it: the Studio list reads them from here. Content columns hold
-- AES-256-GCM ciphertext only. Only new tables: safe to apply on a live database.

CREATE TABLE studio_items (
  id                    uuid PRIMARY KEY,
  account_id            uuid NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  kind                  text NOT NULL CHECK (kind IN ('brief')),
  state                 text NOT NULL CHECK (state IN ('draft', 'queued', 'running', 'ready', 'needs_look', 'failed', 'cancelled')),
  -- Where a running item is; null otherwise.
  stage                 text CHECK (stage IN ('plan', 'research', 'write', 'make', 'check', 'store')),
  language              text NOT NULL CHECK (language ~ '^[a-z]{2}$'),
  -- The canonical JSON of the job. AAD `${account}:studio-job:${id}`.
  job_key_version       smallint NOT NULL CHECK (job_key_version > 0),
  job_ciphertext        bytea NOT NULL,
  -- SHA-256 of that canonical JSON: what the user approves. Never changes.
  payload_digest        bytea NOT NULL CHECK (octet_length(payload_digest) = 32),
  -- What the run produced for the app (title, summary, sources, checks, skills), as JSON.
  -- AAD `${account}:studio-result:${id}`. Written when the run ends (ready, needs_look or failed).
  result_key_version    smallint CHECK (result_key_version > 0),
  result_ciphertext     bytea,
  failure               text CHECK (failure IN ('interrupted', 'time_limit', 'refused', 'provider_error',
                          'unreadable_result', 'too_little_found', 'cost_limit')),
  -- Cost: counts and dollars only, never words.
  searches              integer NOT NULL DEFAULT 0 CHECK (searches >= 0),
  fetches               integer NOT NULL DEFAULT 0 CHECK (fetches >= 0),
  input_tokens          bigint NOT NULL DEFAULT 0 CHECK (input_tokens >= 0),
  cache_write_tokens    bigint NOT NULL DEFAULT 0 CHECK (cache_write_tokens >= 0),
  cache_read_tokens     bigint NOT NULL DEFAULT 0 CHECK (cache_read_tokens >= 0),
  output_tokens         bigint NOT NULL DEFAULT 0 CHECK (output_tokens >= 0),
  container_seconds     integer NOT NULL DEFAULT 0 CHECK (container_seconds >= 0),
  cost_usd              numeric(10, 4) NOT NULL DEFAULT 0 CHECK (cost_usd >= 0),
  model                 text CHECK (length(model) BETWEEN 1 AND 64),
  -- Files the run left at Anthropic whose delete isn't confirmed yet; the worker keeps trying.
  anthropic_files_pending text[] NOT NULL DEFAULT '{}',
  cancel_requested_at   timestamptz,
  created_at            timestamptz NOT NULL,
  -- A draft that isn't approved by then is deleted.
  expires_at            timestamptz NOT NULL,
  approved_at           timestamptz,
  started_at            timestamptz,
  finished_at           timestamptz,
  CONSTRAINT studio_draft_window CHECK (expires_at > created_at AND expires_at <= created_at + interval '10 minutes'),
  CONSTRAINT studio_stage_only_running CHECK ((stage IS NOT NULL) = (state = 'running')),
  CONSTRAINT studio_approved CHECK (
    (state <> 'draft' OR approved_at IS NULL)
    AND (state NOT IN ('queued', 'running', 'ready', 'needs_look', 'failed') OR approved_at IS NOT NULL)),
  CONSTRAINT studio_started CHECK (
    (state NOT IN ('running', 'ready', 'needs_look', 'failed') OR started_at IS NOT NULL)
    AND (started_at IS NULL OR approved_at IS NOT NULL)),
  CONSTRAINT studio_finished CHECK ((finished_at IS NOT NULL) = (state IN ('ready', 'needs_look', 'failed', 'cancelled'))),
  CONSTRAINT studio_failure_iff_failed CHECK ((failure IS NOT NULL) = (state = 'failed')),
  CONSTRAINT studio_result_key CHECK ((result_ciphertext IS NULL) = (result_key_version IS NULL)),
  CONSTRAINT studio_result_when_made CHECK (state NOT IN ('ready', 'needs_look') OR result_ciphertext IS NOT NULL)
);
CREATE INDEX studio_items_account ON studio_items (account_id, created_at DESC);
CREATE INDEX studio_items_queue ON studio_items (approved_at) WHERE state = 'queued';
CREATE INDEX studio_items_running ON studio_items (started_at) WHERE state = 'running';
CREATE INDEX studio_items_drafts ON studio_items (expires_at) WHERE state = 'draft';
CREATE INDEX studio_items_pending_files ON studio_items (id) WHERE anthropic_files_pending <> '{}';

-- The files of an item, encrypted (AAD `${account}:studio-file:${item}:${name}`). S0 keeps them in
-- this database because no object storage has been chosen yet (STUDIO_AUDIT.md decision 4).
CREATE TABLE studio_files (
  item_id       uuid NOT NULL REFERENCES studio_items(id) ON DELETE CASCADE,
  name          text NOT NULL CHECK (name ~ '^[a-z0-9][a-z0-9.-]{0,63}$'),
  role          text NOT NULL CHECK (role IN ('brief', 'infographic', 'infographic_png', 'infographic_print')),
  mime          text NOT NULL CHECK (length(mime) BETWEEN 3 AND 100),
  bytes         integer NOT NULL CHECK (bytes > 0 AND bytes <= 15728640),
  sha256        bytea NOT NULL CHECK (octet_length(sha256) = 32),
  key_version   smallint NOT NULL CHECK (key_version > 0),
  ciphertext    bytea NOT NULL,
  created_at    timestamptz NOT NULL,
  PRIMARY KEY (item_id, name)
);

-- Copies left at Anthropic (Files API) by an item that was deleted before their delete was read
-- back. No foreign key: they outlive the item and the account until the worker confirms each one.
CREATE TABLE studio_orphan_files (
  file_id     text PRIMARY KEY CHECK (length(file_id) BETWEEN 1 AND 200),
  account_id  uuid NOT NULL,
  since       timestamptz NOT NULL
);
