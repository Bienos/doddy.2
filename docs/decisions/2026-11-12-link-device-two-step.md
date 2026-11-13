# Linking an iPhone's earlier data to a Doddy account takes a code the iPhone asks for

- **Date:** 2026-11-12
- **Decided by:** owner ("fix everything from the 12 Nov review", 12 Nov 2026), applied as below
- **Status:** applied in the pull request that adds this file
- **Replaces:** the one-step `POST /v1/account/link-device {deviceToken}` of decision `2026-11-08-required-account`

## Why
When a person signs in with a Doddy account, the backend links the data their iPhone kept under its device session to that account. Until now one request did this, carrying the device's session token in its body. A link is permanent and moves who owns the data, so it should need a fresh step from the iPhone's own session, and it should be reversible for a while.

## Decision
- `POST /v1/account/link-device/start`, signed with the device session (not a guest session), returns a one-time code: 32 random bytes, 5 minutes, single use, stored only as a hash, at most 10 an hour per iPhone.
- `POST /v1/account/link-device` takes the Doddy account's token and `{linkCode}`. The code is used up in the same transaction as the link, whatever the outcome.
- `POST /v1/account/link-device/undo`, signed with the device session, reverses a link for 24 hours. It also ends the browser sessions, sign-ins, joined iPhones and web codes made since the link.
- Operators can unlink at any time: `npm run account:unlink -- <uuid>` in `backend/`.
- The iPhone (`DoddyAccountLink.linkBackend`) does the two steps; its signature is unchanged.

## Consequences
- Builds before this change can't link until they update. Their one-step request gets 400, which they treat as "try later", and they keep their device session. Deploy the server first, then ship the app.
- The code shows that a live, non-guest device session asked within five minutes. It can't tell the iPhone from a copy of its session token; the undo window and the operator unlink are the remedy there.

## Evidence
- `backend`: `npm run typecheck`; `npm test` (800 pass). The tests cover the two-step flow, guest refusal, single use, expiry and undo.
- DoddyCore Swift changes: compiled and tested by CI's `swift` job, not locally.
