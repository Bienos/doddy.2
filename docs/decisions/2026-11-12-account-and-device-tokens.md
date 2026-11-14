# Account and device tokens: production rules follow where the server runs, one key per purpose, devices you can see and revoke, tokens that expire

- **Date:** 2026-11-12
- **Decided by:** proposal, owner approval pending
- **Status:** proposed — waiting for the owner. No code, setting or live service is changed by this file.
- **Replaces:** nothing. Builds on ADR-563 (device sign-in), ADR-707 (owner claim), ADR-709 (token floors), ADR-819 (an iPhone using another account), `2026-11-08-required-account` and the open proposal `2026-11-09-sign-out-ends-the-messaging-device` (#279).

## Why
- **Production rules should follow from where the server runs, not from one setting.** The backend's settings are checked once at start-up (`backend/src/config.ts`). A server that is live and reachable from outside should get production rules by that fact alone, so a forgotten or mistyped setting can't change them.
- **Moving to production needs separate keys per purpose first, so files, linking and joins keep working.** File links (`DocumentLinks`, `backend/src/documents.ts`), the proof of an iPhone's earlier data (`AccountLinker`, `backend/src/app.ts`), and the routes that join an iPhone to another account (`backend/src/web/routes.ts`) should each have a key of their own, independent of how people sign in.
- **Keys should be rotatable.** On the backend, `DODDY_SESSION_SIGNING_KEY` serves several purposes: session tokens (`SignedSessionVerifier`, `backend/src/auth.ts`), each iPhone's user id (`deviceUserId`, `backend/src/deviceSession.ts`), invite-code counters, and file links. The voice server's own key of the same name signs access tokens, makes pseudonymous Apple ids and seals Apple's refresh tokens (`server/voice-token/src/voice-auth.js`). A key per purpose, with a key id and a previous key, lets each one be replaced on its own without anyone losing their data or sign-in.
- **People should see and revoke the iPhones on their account.** Browser sessions already have this: a list, a revoke, 30 days absolute and 14 days idle (`backend/src/web/sessions.ts`, `GET /v1/web/sessions`). iPhones, and iPhones that use another account (`device_joins`, ADR-819), should have the same.
- **Device tokens should expire and be revocable.** The messaging server's device tokens (`server/messaging/src/auth.ts`, `server/messaging/src/routes/account.ts`) should have an idle and an absolute lifetime, rotate, and be ended by the iPhone itself at sign-out.

## Decision (proposed)
**(a) Live on a public host means production rules.** When `DODDY_MODE=live` and `DODDY_HOST` is not loopback, the backend checks these settings at start-up and refuses to start with any of them, whatever `DODDY_ENV` says. The start log names the setting, never its value.
1. `DODDY_ENV` other than `production`.
2. `DODDY_AUTH_MODE=signed` (owner-minted tokens as the only sign-in).
3. Owner-minted tokens accepted next to Supabase (`AnyOfSessionVerifier` in `sessionVerifier`, `backend/src/app.ts`).
4. Device sign-in: `DODDY_DEVICE_SIGNUP=first-device` or `open` (including guest sessions, ADR-587), and `DODDY_DEVICE_INVITE_CODES`.
5. `DODDY_OWNER_CLAIM=open`.
6. `COMPOSIO_COMPLETION_MODE=callback`.

`render.yaml` is brought in line in the same pull request.

**(b) One key per purpose, with a key id and a previous key.**
- Each server derives a key per job from its master key with HKDF-SHA256 and a fixed label, for example `doddy/backend/session/v1`, `doddy/backend/file-link/v1`, `doddy/voice/access-token/v1`, `doddy/voice/apple-token-seal/v1`.
- Every signed thing carries a key id. An optional second setting, `DODDY_SESSION_SIGNING_KEY_PREVIOUS`, is accepted for checking, never for signing.
- Rotation has three steps: move the key to `_PREVIOUS`, set a new one, and remove `_PREVIOUS` once the longest token has run out (30 days for sessions, 7 days for file links, `DOCUMENT_LINK_TTL_SECONDS`). Earlier formats are accepted as the previous key until they expire.
- Identifiers (device user ids, Apple pseudonyms) keep a separate identifier key that is not rotated with the signing keys. After (c), the backend no longer needs it to find a person's data.
- File links and the proof of earlier data use their own derived keys, so they keep working under production rules.

**(c) Devices stored, listed and revocable.**
- The backend stores each iPhone it signs in: its device user id, the account it uses (its own or a joined one), how it joined (which linked sign-in), first and last seen, and when it was revoked.
- The account can list its iPhones and revoke one: in the Doddy account section of the iPhone's Settings, and under Settings › Sign-in methods on the web. A revoke ends that iPhone's tokens at once, as ADR-709's floor does for a whole person.
- A join expires (proposed 90 days) unless the iPhone signs in again with the same Apple or Google.
- Unlinking a sign-in (`unlinkWebIdentity`, `backend/src/store.ts`) ends every join made with it.
- Once the backend issues its own per-iPhone sessions (`2026-11-12-one-token-per-server`), the same list shows those.

**(d) Messaging device tokens expire, rotate and can be ended.**
- **Expiry:** a token of a Doddy account stops working after 60 days unseen (idle) or 180 days after it was issued (absolute). Anonymous accounts keep theirs: it is their only way in, and #375 stops new ones being made.
- **Rotation:** `POST /v1/accounts/sign-in` with the current token returns a fresh one and its `expiresAt`. The old one stops after a short overlap, so a lost answer doesn't sign the iPhone out. The app renews before expiry with the account it is signed in to, without asking the person.
- **Ending:** `DELETE /v1/device` ends the caller's own token, and the app calls it at sign-out.
- **Overlap with #279:** open pull request #279 (`claude/compassionate-darwin-rh03mv`) adds `DELETE /v1/device`. It deletes the caller's own device row and answers 409 for an anonymous account's only device. It also makes sign-out on the iPhone call that route, keeping the call owed in the Keychain until the server answers (`MessagingDeviceRevocation` in DoddyCore, with tests). Its decision file leaves idle expiry and a device list for later. If #279 merges first, (d) adds only expiry and rotation. If it is closed instead, (d)'s first pull request carries the same route and sign-out change.

**(e) Order of work, one small pull request each:**
1. Backend: keys per purpose, key ids, `_PREVIOUS` (b). No setting has to change.
2. Voice server: the same (b), with Apple pseudonyms unchanged.
3. Backend: stored devices, the device list and revoke, joins that expire and end on unlink (c).
4. Messaging server: expiry and rotation (d), on a new migration that sorts after every existing one. If #279 hasn't merged, this pull request also adds the route.
5. App: renew the messaging token ahead of expiry, revoke at sign-out (unless #279 did), and the device list screen.
6. Backend: the start-up check (a) and `render.yaml`. It is deployed only together with the settings below. Before the deploy, confirm on the Render dashboard that a deploy which refuses to start leaves the previous one running.

**Settings on the `doddy` service after that deploy, only after the owner's yes:**
- Set `DODDY_ENV=production`, `DODDY_AUTH_MODE=supabase`, `COMPOSIO_COMPLETION_MODE=verifier` and `DODDY_DEVICE_SIGNUP=off`.
- Remove `DODDY_DEVICE_INVITE_CODES` and `DODDY_OWNER_CLAIM` if they are set.
- Before that, `doddy`'s logs should show no iPhone still signing in with `POST /v1/session/device`: an iPhone still on a device session loses the backend until it signs in with its account.

## What the owner decides
1. Yes or no to (a) to (d), and the order in (e).
2. The numbers: 60 days idle and 180 days absolute for messaging tokens, 90 days for joins.
3. Whether device sessions end entirely with production (the guest path of ADR-587 and the device-session part of ADR-819 go with them), and from which date.
4. The settings on `doddy`, after the deploy (Render is the owner's console).
5. #279: rebase and merge it first, or fold it into (d).

## Consequences
- Keys can be replaced on a schedule, one purpose at a time, without anyone losing their data or sign-in. The voice server's Apple pseudonyms stay stable.
- Files, earlier-data linking and joins keep working under production rules.
- iPhones not opened for 60 days sign in to the messaging server again by themselves while the Doddy account is still signed in. A signed-out iPhone stays out.
- Turning device sign-in off ends guest Ask Doddy sessions on the backend.
- More rows (devices) and two more screens to keep honest: a revoke is shown as done only after the server confirmed it (DOD-08).

## Evidence
- Read: `backend/src/config.ts`, `backend/src/app.ts`, `backend/src/auth.ts`, `backend/src/deviceSession.ts`, `backend/src/documents.ts`, `backend/src/store.ts`, `backend/src/web/social.ts`, `backend/src/web/sessions.ts`, `backend/src/web/routes.ts`, `server/voice-token/src/voice-auth.js`, `server/messaging/src/auth.ts`, `server/messaging/src/routes/account.ts`, `server/messaging/migrations/001_init.sql`, `render.yaml`, `secrets/manifest.json`.
- Read the diff of #279 (`git fetch origin claude/compassionate-darwin-rh03mv`): `server/messaging/src/routes/account.ts`, `server/messaging/README.md` and its decision file.
- Not run: anything against Render or the live services.
