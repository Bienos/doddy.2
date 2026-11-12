-- Records at Twilio are deleted on the account they live on, with that account's own credentials: `main` (texts,
-- calls to and from Doddy's number, forwarded call-backs) or `task` (the calls Doddy places for the user and their
-- takeover legs, on TWILIO_TASK_ACCOUNT_SID, possibly a subaccount). Still only Twilio's id: no number, no text.
-- A new column with a constant default (no table rewrite): safe on a live database, and the previous release keeps
-- working against it (its rows are all `main`).
ALTER TABLE provider_deletions ADD COLUMN account text NOT NULL DEFAULT 'main' CHECK (account IN ('main', 'task'));

-- Task calls and takeover legs that ended before this release were never queued: they are now, as final from today.
INSERT INTO provider_deletions (sid, kind, account)
SELECT twilio_call_sid, 'call', 'task' FROM call_attempts WHERE twilio_call_sid IS NOT NULL AND settled_at IS NOT NULL
UNION
SELECT twilio_call_sid, 'call', 'task' FROM call_takeovers WHERE twilio_call_sid IS NOT NULL AND settled_at IS NOT NULL
ON CONFLICT (sid) DO NOTHING;
