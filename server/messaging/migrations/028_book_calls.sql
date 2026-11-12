-- Booking calls (decision docs/decisions/2026-11-12-book-agent.md): a call case and a call task may be
-- of kind 'book', talked by the separate booking agent, which may accept exactly the booking on the
-- approved card. Only widens two CHECK constraints; every existing row is 'ask' and stays valid.
ALTER TABLE call_cases DROP CONSTRAINT IF EXISTS call_cases_kind_check;
ALTER TABLE call_cases ADD CONSTRAINT call_cases_kind_check CHECK (kind IN ('ask', 'book'));
ALTER TABLE call_tasks DROP CONSTRAINT IF EXISTS call_tasks_kind_check;
ALTER TABLE call_tasks ADD CONSTRAINT call_tasks_kind_check CHECK (kind IN ('ask', 'book'));
