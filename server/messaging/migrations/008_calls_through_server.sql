-- ADR-490 (unit U1): calls reach this server first, and Twilio reports how each call went.
-- New statuses come from Twilio's call status callbacks; a status never moves backwards
-- (src/routes/twilioVoice.ts). Twilio's CallSid identifies a call in those callbacks.
ALTER TABLE calls DROP CONSTRAINT calls_status_check;
ALTER TABLE calls ADD CONSTRAINT calls_status_check CHECK (status IN (
  'started', 'requested', 'ringing', 'answered', 'completed', 'busy', 'no_answer', 'canceled', 'failed', 'unknown'));
CREATE UNIQUE INDEX calls_call_sid ON calls (call_sid) WHERE call_sid IS NOT NULL;
