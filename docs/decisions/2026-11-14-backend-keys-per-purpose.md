# The backend signs each job with its own key, with a key id and a previous key for rotation

- **Date:** 2026-11-14
- **Decided by:** owner, "yes, as recommended" to `2026-11-12-account-and-device-tokens`; this file records how step (b) and step 1 of (e) were built
- **Status:** applied in the pull request that adds it (backend only; not deployed, no setting changes)
- **Replaces:** nothing. Builds on `2026-11-12-account-and-device-tokens`, ADR-563, ADR-564, ADR-707, ADR-709.

## Why
The backend's one master secret, `DODDY_SESSION_SIGNING_KEY`, was used directly as the HMAC key for session tokens and for links to files Doddy made, and as the key for each iPhone's user id. Replacing it for any one reason replaced it for all of them, which signed everyone out and moved every iPhone to a new user id (`docs/OWNER_QUEUE.md` 6 said not to rotate it). Moving the server to production rules needs each job to have its own key and each key to be replaceable.

## Where the backend signs or derives from its master secret
Read from `backend/src` (`createHmac`, `hkdfSync`, `DODDY_SESSION_SIGNING_KEY`, `sign(`, `secret`):

| What | Where | Before | Now |
|---|---|---|---|
| Session tokens: device sessions (ADR-563), guest sessions (ADR-587), owner-minted tokens (`npm run session:mint`) | `auth.ts` `SignedSessionVerifier`, `deviceSession.ts`, `mintSession.ts`, `app.ts` | HMAC with the master | session key (below) |
| The iPhone's own device token as proof of its earlier data, for linking it to a Doddy account and for undoing the link | `app.ts` (`AccountLinker.devices`), `accountLinks.ts` | same verifier | same session key |
| Links to files Doddy made (`DOCUMENT_LINK_TTL_SECONDS`, one day) | `documents.ts` `DocumentLinks` | HMAC with the master | file-link key |
| An iPhone's user id | `deviceSession.ts` `deviceUserId` | HMAC with the master | **unchanged**: identifier key, which is the master unless `DODDY_IDENTIFIER_KEY` is set |
| The user id a join, a device-account lookup and a leave look up for an iPhone (ADR-819) | `deviceSession.ts` `userIdFor`, `web/routes.ts`, `web/social.ts` | HMAC with the master | **unchanged**: identifier key (the same `deviceUserId`) |
| An invite code's counter id | `deviceSession.ts` | HMAC with the master | **unchanged**: identifier key |

Not derived from the master, so not touched: browser sessions and link codes (random values, kept as hashes, `web/sessions.ts`, `accountLinks.ts`, `web/social.ts`), kept memory and files at rest (their own `DODDY_MEMORY_KEY` and key version, `memory/crypto.ts`), the Coinbase request token (its own key, `payments/coinbase.ts`), and the unkeyed digests used for de-duplication and for equal-length comparison.

## Decision
- **One module, `backend/src/signingKeys.ts`.** A key per purpose from the master with HKDF-SHA256 and a fixed label: `doddy/backend/session/v1` and `doddy/backend/file-link/v1`. A key made for one purpose neither signs nor verifies another's; a test re-derives the keys with `node:crypto` alone so a changed label or KDF fails.
- **Key id.** The first 8 characters of every new signature are the id of the key that made it, a 48-bit one-way fingerprint of the derived key (HKDF with its own label), so it names the key without helping anyone find it. Checking looks the id up among the keys the server holds and refuses an unknown one; it never tries every key.
- **Previous key.** Optional `DODDY_SESSION_SIGNING_KEY_PREVIOUS`: accepted for checking, never for signing. The server refuses to start, naming the settings and never a value, if it is too short, the same key as the current one, or set while `DODDY_IDENTIFIER_KEY` is not (so a rotation can't move identifiers by mistake). The voice token server's keys change (step 2) uses the same two setting names and meanings. The `listening` line says whether one is in use (`signingKeyPrevious`).
- **Formats, so nothing is signed out at deploy.**
  - A session token is still `ds1.<claims>.<signature>` with the same claims: the iPhone app accepts only a `ds1.` token of at most 2048 characters (`DeviceSessionClient`), and the cut-off after an account is erased reads the date from the claims. Only the signature changes: 51 characters (key id and MAC) instead of 43.
  - A file link keeps the two parameters `exp` and `sig`: the messaging server rebuilds a link from those two alone and takes a `sig` of 20 to 64 characters (`server/messaging/src/fileWatches.ts`), so the key id sits in front of the MAC inside `sig`.
  - A signature of the earlier 43-character shape (the master used directly) still verifies with the current or the previous master until the token expires: 30 days for a session, a day for a file link. A later change can delete that path once those days have passed.
- **Identifiers stay where they were.** `deviceUserId` and the invite code ids are computed exactly as before, from the identifier key. Optional `DODDY_IDENTIFIER_KEY`; unset, it is the master itself, so every stored id resolves to the same person. A test with fixed stored values (made by the earlier code from an obviously fake key) proves it. A rotation of the signing keys does not touch identifiers, as long as `DODDY_IDENTIFIER_KEY` was set to the old master first (recipe: `docs/integrations/DEPLOY_RENDER.md`, "Rotating the signing key").
- **Which features are on where is unchanged.** Session tokens, device sign-in, the link's proof and file links are still switched on only where owner tokens are (`DODDY_AUTH_MODE=signed`, or development next to Supabase), as before; production rules and the start-up check are step 6 of `2026-11-12-account-and-device-tokens`, which also decides how file links and the link's proof get their keys there.
- **No new `render.yaml` setting and no change to `secrets/manifest.json`.** Both new settings are optional secrets that the owner sets by hand on Render only while rotating; they are named in `backend/.env.example` comments and in `docs/integrations/DEPLOY_RENDER.md`, not as `NAME=` lines, so the manifest check is unchanged. If the owner wants them kept in 1Password and synced, entries like the existing `DODDY_SESSION_SIGNING_KEY` one (with `push: false`) are added when the first rotation is planned.

## Consequences
- A signing key can be replaced on a schedule without signing anyone out and without moving anyone's data. The longest wait before removing the previous key is 30 days.
- **Rolling back** to a build from before this change keeps every earlier token and link valid. A token or link made by this build carries a key id the earlier code doesn't accept, so while the earlier build runs those stop working until they would have expired (sessions up to 30 days, links a day). An iPhone on a device session asks for a new one by itself when the server answers 401 (`DeviceSession.renew`), a token made with `session:mint` has to be made again, and a link is replaced the next time the app asks for one.
- Until the previous key is removed, a leaked old key still verifies old tokens. That is the price of not signing people out, and why the wait is the token lifetime and no longer.

## Evidence
- Read: `backend/src/auth.ts`, `deviceSession.ts`, `documents.ts`, `mintSession.ts`, `config.ts`, `app.ts`, `startLine.ts`, `accountLinks.ts`, `requestCredential.ts`, `server/messaging/src/fileWatches.ts`, `DoddyApp/Infrastructure/DeviceSession.swift`, `Packages/DoddyCore/Sources/DoddyCore/OnlineAccounts/DeviceSessionClient.swift`.
- Run: `backend/test/signing-keys.test.ts` (written first), the whole backend suite and `scripts/ci.sh --only checks`; results are in the pull request.
- Not run: anything against Render, the live service or a device.
