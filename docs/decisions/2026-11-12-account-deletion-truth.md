# Account deletion reports success only when each server confirms

- **Date:** 2026-11-12
- **Decided by:** proposal, owner approval pending (account data review, 12 Nov 2026)
- **Status:** proposed, applied in the pull request that adds this file
- **Replaces:** nothing; tightens decision `2026-11-08-required-account` (deleting the account) and ADR-674

## Why
- Deleting a Doddy account starts with the messaging server. `DoddyServerClient.deleteAccount()` returned without a request when this iPhone kept no messaging token, and counted a 401 as deleted. After a reinstall the messaging token is gone while the Doddy account still has its account on the messaging server, so "Your Doddy account was deleted" could be shown while that account stayed.
- `ServerAccountErasure` answered "nothing there" whenever the backend session was missing, even when this iPhone had a device ID, so "Delete voice account" went on to delete the voice account without the backend's erase.

## Decision
1. **Messaging server.** The Doddy-account deletion uses `AccountErasurePlan.run` (DoddyCore): delete with the token this iPhone keeps; with none, or a refused one (401), mint the account's own token (`POST /v1/accounts/sign-in` with the account, as after a sign-in; a refused account token is refreshed once) and delete once more. It counts as done only on a 204, or when the sign-in says the server takes no Doddy accounts (503 `not_configured`: it can hold none for this account). The server makes an empty account for a Doddy account it doesn't know yet; the delete that follows removes it, so the result is the same. Anything else: the existing failure message, nothing else is deleted, and the person stays signed in to try again. The minted token is used for that one delete and not kept. `deleteAccountWithStoredToken` and `deleteAccount(withToken:)` say exactly what the server answered.
2. **Backend.** `ServerAccountErasure` makes or renews the session first (`DeviceSession.ensure`) when something may be there: a device ID, or a backend that uses the Doddy account. Without a session after that, the outcome is "failed", not "nothing there". "Nothing there" only when this iPhone never made a device ID and doesn't use the account with the server (`AccountErasurePlan.backendStart`). A session that disappears during the erase is "failed" too (`backendOutcome`). No device ID is made just to erase.
3. **Words (DOD-08).** No new message: the existing ones already say "didn't confirm … you're still signed in" and "your voice account was kept".

## Consequences
- After a reinstall, deleting the account makes one more request to the messaging server (the sign-in) before the delete.
- If the messaging server's daily cap on new accounts is reached (429), a Doddy account it doesn't know can't be deleted until the next day; the app says it wasn't confirmed and keeps the person signed in.
- Not covered: an iPhone whose messaging token belongs to an older anonymous account (a server that wasn't set up for accounts at sign-in, or a link that was refused) deletes that account; the Doddy account's own account on the messaging server, if it has one from another iPhone, isn't asked about. Settings › Messaging › Delete (`UpdatesModel`, this iPhone's own messaging data) still uses `deleteAccount()` as before.
- No server change.

## Evidence
- DoddyCore on Linux (Swift 6.1.3): `AccountErasurePlanTests` (no token → mint and retry; 401 → mint and retry; second failure → not deleted; 204 → deleted; device ID without a session → failed; the client's own answers); counts in the pull request.
- Read: `server/messaging/src/routes/account.ts` (`POST /v1/accounts/sign-in` makes the account for a subject it doesn't know; `DELETE /v1/account` answers 204).
- Not compiled here: `DoddyAccountApp.swift`, `ServerAccountErasure.swift`; the hosted `ios-build` job is their first compile. Not run on a device or against the live servers.
