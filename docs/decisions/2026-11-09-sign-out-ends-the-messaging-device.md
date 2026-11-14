# Signing out ends this iPhone's messaging-server token, and stays owed until the server says it did

- **Date:** 2026-11-09
- **Decided by:** proposal, owner approval pending (follows the security audit of 9 Nov 2026, finding 1; `docs/security/AUDIT_2026-11-09_REMEDIATION.md`)
- **Status:** proposed
- **Replaces:** nothing (it adds to `2026-11-08-required-account`)

## Why
Signing out deleted only the iPhone's copy of its messaging-server token. The server kept the token and the iPhone's push address, so a copied token kept working and the account's notifications kept reaching a signed-out phone.

## Decision
- The messaging server has `DELETE /v1/device`: the caller's own token ends itself and its push binding (one row). Only an iPhone that belongs to a Doddy account can do it; an anonymous account's only device is refused (409).
- Signing out is immediate and local. The server's side is a debt written to the Keychain before the token leaves the slot the app uses, paid at once and again at each launch and sign-in, and cleared only by an answer from the server (`204`, `401` or `409`). The app does not say "signed out everywhere" until it is.
- A different account signing in over a kept one runs the same sign-out first, and an answer from a server that arrives after a sign-out is not kept (`DoddyAccountModel.identityEpoch`).

## Consequences
One more request at sign-out; a debt slot in the Keychain (at most 5 tokens, this device only). Server first in a deploy: an app ahead of its server keeps the debt and revokes nothing. Idle expiry of device tokens, a device list and neutral previews are not part of this and stay recommendations.

## Evidence
`server/messaging/test/deviceRevocation.test.ts` (7, real Postgres), `MessagingDeviceRevocationTests` (12) and `DoddyAccountRaceTests` (9), all run. The app glue is parsed, not compiled, and not run on a device.
