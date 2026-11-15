# Calls Doddy makes for you have higher limits

- **Date:** 2026-11-15
- **Decided by:** owner ("zwiększ limity mi", then chose "Wyższe limity dla wszystkich" and "Merge i deploy od razu")
- **Status:** accepted
- **Replaces:** the per-user and per-number task-call limits in `calls.md` ("Rate limits") and `2026-11-12-call-back-limits` (the "2 a day from one user, 3 a day from all, 15 minutes apart" numbers); the single refusal code `limit_destination` stays

## Why
On 15 Nov 2026 the owner tested a call card to their own number. The voice failed (ElevenLabs returned error 3000), and every retry over the next 20 minutes was refused by the server: `limit_destination_gap` (15 minutes between dials to one number), then `no_more_attempts` (3 attempts per card). The per-number limit of 2 a day left one more dial until the next day. The limits are code ceilings, so an environment variable could only lower them; a value above a ceiling stops the server from starting.

## Decision
New code ceilings and defaults in `server/messaging/src/config.ts` (`DEFAULT_TASK_CALL_SETTINGS` matches):

| Limit | Variable | Before | Now |
|---|---|---|---|
| Calls per user per hour | `TASK_CALL_LIMIT_USER_HOUR` | 3 | 6 |
| Calls per user per day | `TASK_CALL_LIMIT_USER_DAY` | 10 | 10 |
| One number, one user, per day | `TASK_CALL_LIMIT_DEST_USER_DAY` | 2 | 5 |
| One number, all users, per day | `TASK_CALL_LIMIT_DEST_DAY` | 3 | 6 |
| Minutes between dials to one number | `TASK_CALL_DEST_GAP_MINUTES` (minimum) | 15 | 5 |
| Attempts per card | `MAX_ATTEMPTS` | 3 | 3 |

Variables can still only lower them.

## Consequences
- A business can be rung up to 6 times a day by Doddy across all users and 5 times by one user, 5 minutes apart. That is twice as much load on a callee and on Twilio and ElevenLabs costs at most per day; the per-user 10 a day and the server's 50 a day are unchanged.
- A refusal still says only "Doddy has called this number enough for now".

## Evidence
`npm test` in `server/messaging` with a disposable PostgreSQL 16 (`TEST_DATABASE_URL`): 1317 tests, 0 failures, 0 skipped. Not run: a real call after the change.
