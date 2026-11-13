-- Phone-line recaps only for calls on which the caller said the right PIN (src/phoneRecaps.ts). The call's
-- session (call_sessions.pin_verified_at) ends with the call, usually before ElevenLabs' post-call webhook
-- arrives, so the call keeps its own mark: set by the verify-pin tool, cleared with the session's when the
-- PIN is changed or removed while the call goes on.
-- recap_not_created says why a call of an account with recaps on has no recap; the app reads it from
-- GET /v1/calls. Two new null columns: safe to apply on a live database (calls is small).

ALTER TABLE calls ADD COLUMN pin_verified_at timestamptz;
ALTER TABLE calls ADD COLUMN recap_not_created text CHECK (recap_not_created IN ('pin_not_verified'));
