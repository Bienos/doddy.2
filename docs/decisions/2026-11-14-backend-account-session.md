# The backend gives a Doddy account its own session on each iPhone, in exchange for the account's token once

- **Date:** 2026-11-14
- **Decided by:** owner, "yes, as recommended" to `2026-11-12-one-token-per-server` (14 Nov 2026), to build it as separate server and app pull requests; this file records how the backend's half (items 1 to 3 of that decision) was built
- **Status:** applied in the pull request that adds it. Backend only: `doddy` has auto-deploy off, so nothing is live until the owner deploys, and no setting has to change. The app half and the later step that stops accepting the Supabase token on everyday requests are separate pull requests
- **Replaces:** nothing. Builds on `2026-11-12-one-token-per-server`, `2026-11-12-account-and-device-tokens` (part c), `2026-11-14-backend-keys-per-purpose`, `2026-11-14-stored-devices`, ADR-709 (token cut-offs), `2026-11-08-required-account`

## What was built
`POST /v1/session/account`. The Supabase token of the Doddy account is in the `Authorization` header and the iPhone's device id (the one `POST /v1/session/device` takes) is the body, `{ "deviceId": "<uuid>" }`, nothing else. The answer:

```json
{ "token": "ds1.…", "expiresAt": "2026-12-14T10:00:00.000Z", "access": "full", "deviceListId": "<uuid>" }
```

- `token`: an ordinary `ds1` token, signed exactly as every other one (the session key and its key id, `signingKeys.ts`; nothing about signing changed). Its claims are the earlier ones plus two: `dev`, the id of this iPhone's stored row (`devices.ts`), and `acc: 1`, which says it is an account session. `sub` is the Doddy account's own id (its Supabase user id).
- `expiresAt`: the expiry the server wrote into the token (30 days from the exchange), not an estimate (DOD-08).
- `access`: always `full`, so the answer has the shape of the device sign-in's.
- `deviceListId`: this iPhone's row, read back from the store in the transaction that wrote it. It is the `id` that `GET /v1/web/devices` lists and `DELETE /v1/web/devices/:id` names. It is not the device id the iPhone keeps.

The Supabase token is checked as the server checks it for every account-bound request (`SupabaseSessionVerifier`: the project's published keys, issuer, audience, role, expiry, no anonymous sign-in, no password sign-in), plus the account's cut-off second (an account deleted a moment ago gets nothing), as `POST /v1/account/link-device` does. Only a Supabase token is taken here: an account session, a device session and an owner-minted token are all refused, so a session that has ended can't be used to get a new one. Every refusal is the same plain 401 with the existing error shape and no reason.

## Rules
1. **It is the same account as its Supabase token.** `LinkedAccountVerifier` handles an account session as it handles the Supabase token: the same cut-off check, and the same mapping to the data the account took over from an iPhone (`account_links`), read on every request, so a link made after the session was issued counts at once. Tests run both tokens against the same data, and two accounts against each other (cross-user isolation).
2. **Both tokens work this release.** Everyday routes accept the Supabase token and the account session (`AnyOfSessionVerifier`, as before: a session is one more `ds1` token), and nothing in this change stops accepting the Supabase token. The exchange route is the only place that has to take it.
3. **One row per account and iPhone.** An account session is a row of `devices`, with the new column `account_id` (the account) and, as its `device_user_id`, a key derived from the account and the device id together with the identifier key (`accountDeviceUserId`). The device id is never stored. So: an iPhone exchanged twice is one row; a second account on the same iPhone is a second row of its own; and the row never meets the device-session path's row for the same iPhone (its own rule, below). The row appears in `GET /v1/web/devices` for the account, `current` for the session that asks, `joined` null.
4. **Renewal is the same exchange.** 30 days from the exchange, like the device sessions. The app renews two days before the expiry (`DeviceSession`), by asking again with a fresh Supabase token: the same row, a new token, the earlier token valid until it expires. The server needs nothing else for renewal, and an iPhone that doesn't ask again ends by itself.
5. **Ending it.**
   - **Sign-out of an iPhone** is the existing `DELETE /v1/web/devices/:id`, called with the iPhone's own session: that route takes the `Authorization` header, so the iPhone can end its own session without a new route. The very next request with it is refused. The account's other iPhones are not touched, and no cut-off is written (every account session names its row).
   - **A revoke from another iPhone or a browser** is the same call and the same effect.
   - **Account deletion** removes the account's rows (`Store.eraseUser`) and writes the cut-off second for the account and the data behind it, so every account session of the account is refused on the next request, and a fresh Supabase token dated before the deletion can't be exchanged. Deleting with an account session also queues the Supabase user's removal as deleting with the Supabase token does (`accountSubjectOf` reads the account from an account session).
6. **A revoked iPhone and #485's rule.** #485's rule 3 is about the device-session path (`POST /v1/session/device`, where the device id alone is the credential): a revoked iPhone is refused there however often it asks, and no route clears that. That is unchanged, and an account session never reads or writes the device-session row (tested both ways). For the account-session row the rule is: a revoke is final for what it ended, and the way back is deliberate. An exchange with a fresh Supabase token of the same account, from that iPhone, makes the row live again **under a new id**. Everything made before the revoke names the old id, which no longer exists, so none of it comes back; a session can't bring itself back, because it is not a Supabase token; and a device id alone brings nothing back. This is what signing in again after signing out looks like (sign-out is the revoke), and what a person does on an iPhone they revoked by mistake. It is safe because the deliberate act needs the account's own valid token, which is the account signing in on that iPhone. **What it does not do:** a revoke ends the iPhone's backend session; it does not end the account's Supabase session there, which is Supabase's. While that stays signed in, the iPhone can ask for a new backend session. Keeping an iPhone out for good means ending its Supabase session as well.
7. **Limits** (no new setting; the numbers are the ones the other sign-in routes use, in `ACCOUNT_SESSION_LIMITS`):
   - 20 tries per address per hour (an IPv6 address by its /64, as `clientKey` does), counted before the token is looked at, right or wrong, as the guest and invite sign-ins count (20 an hour);
   - 20 exchanges per account per hour, counted after the token checks out, as sign-in codes and tickets are (20 an hour per account). Both answer 429 `rate_limited` with `Retry-After: 3600`;
   - 20 iPhones per account that are not revoked. At the limit a **new** iPhone is refused with 429 `quota_exceeded` and the message "This Doddy account is signed in on as many iPhones as it allows. Remove one in Doddy's settings, then try again.", and nothing is written. An iPhone the account already has still renews. A revoked iPhone takes no place: when an account's rows (live and revoked) reach the limit, its revoked rows are cleared first, so they can't pile up. The list's own cap (100) is never reached. An account-session row not seen for 180 days is dropped by the hourly sweep, revoked or not (`pruneDevices`).
8. **What is written.** Ids and times only, in `devices`; counters of tries under a hash of the address and a hash of the account; one log line per exchange, `account_session` with `outcome` (`new`, `renewed`, `returned`), and the usual content-free access line. No token, key, device id, row id or account id is written to a log or an answer apart from the token and `deviceListId` the caller asked for (tested).
9. **An account session is not the iPhone's earlier device session.** `POST /v1/account/link-device/start` and `/undo` need that earlier device session and refuse an account session (401), even though both are `ds1` tokens.

## Where the route exists
Where the server checks Supabase tokens (`DODDY_AUTH_MODE=supabase`, `SUPABASE_URL`) and has a session key to sign with. Today the key is loaded only where owner tokens are allowed (not under `DODDY_ENV=production`, `config.ts`), which is the hosted service's setting (`DODDY_ENV=development`); anywhere else the route is not found (404) and nothing changes. How production gets a session key is step 6 of `2026-11-12-account-and-device-tokens`: the `acc` claim and the row let it accept account sessions only, without owner-minted or device tokens, in one small change.

## What the app half must know
- An account session starts with `ds1.` like the earlier device session. `DoddyAccountApp.swift` takes any Keychain token that starts with `ds1.` as "the iPhone's earlier device session" for linking. The server refuses an account session at the link routes (rule 9), so that read is safe, but the app should keep the two apart.
- Sign-out: `DELETE /v1/web/devices/{deviceListId}` with the account session, before the Supabase sign-out. The iPhone keeps `deviceListId` next to the token.
- A refusal at the exchange (401) means "use the Supabase token it still holds" this release.

## Rollback
Additive: one nullable column and one index on `devices`, and a route and claims the earlier code does not have. What the earlier code does with account sessions that are already out:
- a build from #485 knows `dev` but not `acc`: it refuses them (the row names a key, not the account), so the app falls back to the Supabase token it still holds;
- an earlier build that does not know `dev` accepts them as plain device tokens of the account, without the revoke, and without the mapping to data the account took over, until they expire (30 days at most).
Rows are ignored by the earlier code. Nothing the Supabase token does is affected.

## Evidence
- Read: `backend/src/auth.ts`, `accountLinks.ts`, `app.ts`, `http.ts`, `deviceSession.ts`, `devices.ts`, `signingKeys.ts`, `store.ts` (`devices`, `eraseUser`, `revokeDevice`), `web/routes.ts`, `web/social.ts`, `account.ts`, `requestCredential.ts`, `DoddyApp/Infrastructure/DeviceSession.swift`, `DoddyApp/Features/Account/DoddyAccountApp.swift`, `Packages/DoddyCore/.../DeviceSessionClient.swift`.
- Run: `backend/test/account-session.test.ts` (25 tests, written first and seen red, then green; six mutation checks), the whole backend suite and `scripts/ci.sh --only checks`; results are in the pull request.
- Not run: anything against Render, Supabase or a device; the app.
