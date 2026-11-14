# Messaging device tokens expire after 60 days unseen or 180 days old, rotate in place, and the check is on by default

- **Date:** 2026-11-14
- **Decided by:** owner approved building part (d) of `2026-11-12-account-and-device-tokens` with its numbers ("yes, as recommended"); the choices below are the build's, for the owner to change.
- **Status:** built in the pull request that adds this file; not live until `doddy-messaging` is deployed (auto-deploy is off).
- **Replaces:** nothing. Completes part (d) of `2026-11-12-account-and-device-tokens`; `DELETE /v1/device` came earlier (`2026-11-09-sign-out-ends-the-messaging-device`).

## Why
A messaging device token never expired: only its hash is stored, and `last_seen_at` only throttled a write. A token should have a lifetime, and Doddy accounts sign in again by themselves, so a lifetime costs the person little.

## Decision
- **Which tokens:** the current device token of a Doddy account (`accounts.auth_subject` set). Anonymous accounts never expire.
- **Numbers (settings, `DEVICE_TOKEN_*`):** idle 60 days, absolute 180 days, overlap 300 seconds. The idle limit may not be longer than the absolute one.
- **On by default**, with `DEVICE_TOKEN_EXPIRY=0` as the switch. Reason: in the app a refused token is dropped and the next call signs in again with the Doddy account, without asking (`DoddyServerClient.authorized` deletes the token and fails once with `accountMissing`; `ensureAccount` then calls `DoddyAccountServers.messagingToken`, which calls `POST /v1/accounts/sign-in` while the account is signed in). Read in the code; not run on a device. The cost is one failed call on screens that don't retry (recaps and Messages do).
- **"Seen" is written at most once an hour** (the existing throttle), only for a token that is accepted; a refused token is never marked seen.
- **Rotation is in place:** the device row stays, `token_hash` becomes the fresh token, the replaced hash moves to `previous_token_hash` with `previous_valid_until`. One statement does it, so two calls with the same token can't both win. Asking again with the replaced token inside the window gives another fresh token and leaves the window as the first rotation set it.
- **`expiresAt` is the absolute end** (issue time plus 180 days), `null` while expiry is off. Idle expiry moves with use, so it isn't promised.
- **A run-out token is an unknown token at sign-in:** presenting it doesn't revive it; the answer is a new iPhone of the same account.
- **Linking an anonymous iPhone** keeps its token and starts the 60 and 180 days then.
- **The migration backfills** every Doddy-account device to "issued and seen now", so the first expiries come 60 days after the deploy.

## Consequences
- The app's renewal ahead of expiry (a rotation call) is a later change; until then every iPhone's token ends at its 180-day mark, then signs in again by itself, once.
- A push still goes to a device row whose token has run out, until the app re-registers its push token (which moves the binding) or the 10-iPhone limit removes the row. And `DELETE /v1/device` can't use a token that has run out. Choice for the owner: stop pushing to run-out devices and let a run-out token end its own row.
- Rolling back is safe: the columns are ignored by the earlier code.

## Evidence
- Tests: `server/messaging/test/deviceTokenExpiry.test.ts`, `deviceTokenMigration.test.ts`, the changed `accountSignIn.test.ts`; results in the pull request.
- Read, not run: the iPhone's handling of a refused token (`Packages/DoddyCore/Sources/DoddyCore/ServerClient.swift`, `DoddyApp/Features/Account/DoddyAccountApp.swift`). Nothing was run against Render or a device.
