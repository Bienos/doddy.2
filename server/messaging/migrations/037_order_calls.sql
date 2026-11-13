-- Food orders by phone (decision docs/decisions/2026-11-12-food-by-phone.md): a call case and a call
-- task may be of kind 'order', talked by the separate order agent, which may accept exactly the order
-- on the approved card. Only widens two CHECK constraints; every existing row is 'ask' or 'book' and
-- stays valid. The order itself (lines, delivery address, phone) lives only in the encrypted payload.
ALTER TABLE call_cases DROP CONSTRAINT IF EXISTS call_cases_kind_check;
ALTER TABLE call_cases ADD CONSTRAINT call_cases_kind_check CHECK (kind IN ('ask', 'book', 'order'));
ALTER TABLE call_tasks DROP CONSTRAINT IF EXISTS call_tasks_kind_check;
ALTER TABLE call_tasks ADD CONSTRAINT call_tasks_kind_check CHECK (kind IN ('ask', 'book', 'order'));
