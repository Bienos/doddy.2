-- Messages by phone (decision docs/decisions/2026-11-27-voice-first-doddy.md, step 4): a call case and a call task may
-- be of kind 'tell', talked by the separate message agent, which passes on exactly the message on the approved card and
-- may take one short reply. Only widens two CHECK constraints; every existing row stays valid. The message itself lives
-- only in the encrypted payload.
ALTER TABLE call_cases DROP CONSTRAINT IF EXISTS call_cases_kind_check;
ALTER TABLE call_cases ADD CONSTRAINT call_cases_kind_check CHECK (kind IN ('ask', 'book', 'order', 'tell'));
ALTER TABLE call_tasks DROP CONSTRAINT IF EXISTS call_tasks_kind_check;
ALTER TABLE call_tasks ADD CONSTRAINT call_tasks_kind_check CHECK (kind IN ('ask', 'book', 'order', 'tell'));
