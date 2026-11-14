# A live server on a public host starts only under production rules; production keeps account sessions, file links and the link proof

- **Date:** 2026-11-14
- **Decided by:** owner, "yes, as recommended" to `2026-11-12-account-and-device-tokens` (14 Nov 2026), with the settings on the live service changing only on a separate yes after the deploy; this file records how part (a) and step 6 of (e) were built
- **Status:** applied in the pull request that adds it. Backend only. `doddy` has auto-deploy off, so merging changes nothing on the live service; only a deploy does, and the owner decides when and with which settings (`docs/OWNER_QUEUE.md` 113)
- **Replaces:** nothing. Builds on `2026-11-12-account-and-device-tokens`, `2026-11-14-backend-keys-per-purpose`, `2026-11-14-stored-devices`, `2026-11-14-backend-account-session`, ADR-526, ADR-563, ADR-587, ADR-707

## What was built

### The start-up check
When `DODDY_MODE=live` and `DODDY_HOST` is not loopback (`127.0.0.1`, `::1`, `localhost`; the same test the database check already used), `loadConfig` reports a problem for each of these, whatever `DODDY_ENV` says, and the server refuses to start (exit code 78, as for every refused configuration). Names are the code's own:

| # | Refused | The line says |
|---|---|---|
| 1 | `DODDY_ENV` other than `production` | `DODDY_ENV must be production when DODDY_MODE=live and DODDY_HOST is not loopback` |
| 2 | `DODDY_AUTH_MODE=signed` | `DODDY_AUTH_MODE must be supabase …` |
| 3 | owner-minted tokens accepted next to Supabase sign-in (`AnyOfSessionVerifier` in `sessionVerifier`; in the code that is `DODDY_SESSION_SIGNING_KEY` set with `DODDY_ENV` other than `production`) | `Owner-minted tokens beside Supabase sign-in are not allowed …` |
| 4 | device sign-in: `DODDY_DEVICE_SIGNUP` `first-device` or `open` (guest sessions, ADR-587, are `open`), and `DODDY_DEVICE_INVITE_CODES` set | one line each: `DODDY_DEVICE_SIGNUP must be off …`, `DODDY_DEVICE_INVITE_CODES must be unset …` |
| 5 | `DODDY_OWNER_CLAIM=open` | `DODDY_OWNER_CLAIM must be closed or unset …` |
| 6 | `COMPOSIO_COMPLETION_MODE=callback` | `COMPOSIO_COMPLETION_MODE must be verifier …` |

- **Names, never values.** A line names the setting and the state it has to be in; it never says what the setting is now and never prints a value (a test sets a fake invite code, key and database password and checks none appears). The server's stderr has one line per problem, `Not starting. <problem>` (`notStartingLines`, `startLine.ts`; before, all problems were joined on one line).
- **How it differs from the decision's wording.** The decision's item 4 is two settings, so it is two lines. Item 3 cannot be reached alone through the settings: owner tokens beside Supabase exist only outside `production` with the key set, so with `DODDY_ENV` wrong it appears next to item 1 (with the key unset, item 1 is the only line). It is still its own check, on the resolved fact, so any later way of turning owner tokens on beside Supabase is refused on a public host too; it is tested alone on that fact and through `loadConfig` next to item 1. Where `loadConfig` already refused `callback` outside development, that older line is now skipped on a live public host, so the setting is named once.
- **The listening line** gains `productionRules` (true when the check applied to this start): after a deploy, a start with `"productionRules":true` is the proof the check passed. A mock server and a loopback host are never refused by it (tests).
- **Refused configurations are not "started and degraded".** The check runs in `loadConfig`, before the database or any socket is opened.

### What production still serves
Before: under `DODDY_ENV=production` the signing key was never read (owner tokens are off there), so the account-session route (`POST /v1/session/account`), links to files Doddy made, and the proof of an iPhone's earlier data (`POST /v1/account/link-device/start`, `/undo`) were not served at all.

Now, under `DODDY_ENV=production` with Supabase sign-in **and `DODDY_SESSION_SIGNING_KEY` set**, `loadConfig` reads the same key (and `DODDY_SESSION_SIGNING_KEY_PREVIOUS` / `DODDY_IDENTIFIER_KEY`, with the same checks) into a second field, `config.accountKeys`, and leaves `config.signingKeys` null. `signingKeys` is what owner-minted tokens and device sign-in are built from, so they are impossible in production by construction, not by a flag:

| Job | Built from | Production, before | Production, now |
|---|---|---|---|
| Account sessions (`POST /v1/session/account`) | `accountKeys` | route not found | served |
| Everyday routes' sign-in | `AccountSessionOrSupabaseVerifier` | Supabase token only | Supabase token, or a `ds1` token **that is an account session** (`acc` claim, an iPhone row that is live) |
| File links (`GET /v1/documents/:id`) | `accountKeys` (file-link key) | off, `make_document` says "not set up" | on (still also needs `DODDY_MEMORY_KEY` to make files) |
| Proof of earlier data (`link-device/start`, `/undo`) | `accountKeys` (session key) | not served | served; takes a `ds1` token that is not an account session, as in development |
| Owner-minted tokens, device and guest sessions at everyday routes | `signingKeys` | refused | refused (no verifier of them exists) |
| `POST /v1/session/device` and invite codes | `signingKeys` | not served | not served |

With no key set, production is exactly what it was.

**Why this is safe.**
- Key loading adds nothing that signs a device session: the issuer is built from `signingKeys` (null), so there is no way to make one, with a guest body, an invite code or anything else (test: 404 and no row stored).
- The everyday verifier looks at a `ds1` token only to see whether it carries the `acc` claim, which only `POST /v1/session/account` writes, and refuses every other `ds1` token (owner-minted, device, guest, another key's) without falling through to another verifier. `AccountSessionOrSupabaseVerifier` is its own class, not an `AnyOfSessionVerifier`, so no refused token is retried elsewhere.
- An account session is also checked against its iPhone row (`RevocableSessionVerifier`, `DeviceRegistry.allows`): a revoke, a sign-out and an account deletion end it on the next request, as in development.
- **The link proof is the one place an earlier device token is still read.** It lets an iPhone that used Doddy before production hand its earlier data to the Doddy account its owner is signed in to; the second step needs that account's own Supabase token as well. It signs nothing in: the same token is refused at every everyday route (test). It takes any `ds1` token that is not an account session, which includes an owner-minted one, because the two are not told apart without a claim; the token only names data its holder already has a token for.
- **The key stays a secret.** It was already set on the live service; the difference is that a production start now reads it. It stays in the Render environment and rotates as `docs/integrations/DEPLOY_RENDER.md` says.

## The design choice the owner might disagree with
How does production get the key for exactly those three jobs?

1. **A second keyring field, `accountKeys`, beside the existing `signingKeys` (built).** Owner tokens, device sign-in and the owner's tools keep reading `signingKeys`, which stays null in production, so nothing can be turned on there by mistake; the three jobs read `accountKeys`. The existing tests that say "production loads no signing keys" stay true. A small second field and one new verifier class.
2. **Load `signingKeys` in production and switch features off by flags.** Smaller diff, but one forgotten flag makes owner tokens or device sign-in work in production, which is what the check exists to prevent. Rejected.
3. **A new setting that turns account sessions on in production.** One more thing to forget, and a deploy that sets nothing would still serve no account sessions. Rejected: the key being set is already the owner's signal, and the route's other precondition, Supabase, is a setting.
4. **Leave production without the key and give the account session another key.** Needs a new secret on Render and a new rotation story for one purpose. Rejected: decision (b) already says one master, derived per purpose.

Recommendation, built: 1. If the owner prefers that production never reads the key until a setting says so, say so: it is one condition in `loadConfig` (`accountSessionsOnly`).

## What merging ships, and what a deploy changes
- **Merging ships nothing live.** `doddy` has `autoDeploy: false`; a merge changes no setting and no running service.
- **The deploy of this build** (owner's step, `docs/OWNER_QUEUE.md` 113) changes nothing while the live service still runs `DODDY_ENV=development` with device sign-in `open`: the check does not accept that configuration on a public host. **The new build refuses to start with the settings the live service has today** (`DODDY_ENV=development`, `DODDY_AUTH_MODE=signed`, `DODDY_DEVICE_SIGNUP=open`, `COMPOSIO_COMPLETION_MODE=callback`). That is the point of the check, and why the settings are changed first or at the same time (the order is in the queue row), and why the owner confirms on Render that a deploy which refuses to start leaves the previous one running.
- **The settings on `doddy`** after the owner's yes: `DODDY_ENV=production`, `DODDY_AUTH_MODE=supabase` (with `SUPABASE_URL` set), `COMPOSIO_COMPLETION_MODE=verifier`, `DODDY_DEVICE_SIGNUP=off`; remove `DODDY_DEVICE_INVITE_CODES` and `DODDY_OWNER_CLAIM`; keep `DODDY_SESSION_SIGNING_KEY`, `DATABASE_URL` and `DODDY_PUBLIC_BASE_URL`. An iPhone still on a device session loses the backend until it signs in with its account.
- **`render.yaml` is not changed in value.** It names the live service's settings today (`development`, `signed`, `open`, `callback`) and Render can apply a Blueprint's values to the live service; putting the production values there would change that service on a sync, before the owner's yes. A comment says what the check refuses and points at the queue row. The same settings would make a Blueprint-made service refuse to start, which is the check doing its job.

## What happens to what exists
- **Development and mock:** unchanged. Every existing configuration that is not live on a public host loads as before; `config.signingKeys` is the same object as `config.accountKeys` there.
- **A live server on a public host with today's settings** will not start. This is the one behaviour that changes, and only for a build someone deploys.
- **Tests that described a live public development server as valid** (`config-auth.test.ts`) were changed to a production-shaped one; each is named in the pull request.

## Rollback
Revert the pull request and redeploy: nothing is stored differently (no migration, no new column, no new table). While the new build runs under production settings, account sessions it made stay valid on an older build that knows `acc` (#486); on one that does not, see `2026-11-14-backend-account-session`. If a deploy refuses to start, the previous deploy keeps running on Render (to be confirmed on the dashboard before the deploy, `docs/OWNER_QUEUE.md` 113) and the log names the settings to change.

## Constitution evidence log
- **DOD-07 (scoped tools, typed code enforces):** the verifier of production takes two kinds of token and refuses every other `ds1` token in code (`AccountSessionOrSupabaseVerifier`), and the issuer of device sessions is not built without `signingKeys`; neither is a prompt or a flag. Tests: `backend/test/production-rules.test.ts`.
- **DOD-11 (no secret in logs or errors):** the refusal lines name settings only; the listening line adds one boolean. Tests: fake values for every secret checked absent from problems, the real server's stderr and stdout, and the access log of a production server.
- **DOD-08:** nothing here says anything is saved or done; the start log says "Not starting" and exits.
- **Gaps:** nothing was run against Render, Supabase or a device. Whether Render keeps the previous deploy when a new one refuses to start is read from Render's documentation by the owner, not here.

## Evidence
- Read: `backend/src/config.ts`, `app.ts`, `auth.ts`, `accountSession.ts`, `accountLinks.ts`, `documents.ts`, `devices.ts`, `signingKeys.ts`, `startLine.ts`, `server.ts`, `http.ts`, `mintSession.ts`, `render.yaml`, `docs/integrations/DEPLOY_RENDER.md`, the four decision files named above.
- Run: `backend/test/production-rules.test.ts` (written first and seen red, then green; mutation checks of each rule), the whole backend suite and `scripts/ci.sh --only checks`; results are in the pull request.
- Not run: anything against Render, Supabase or a device.
