# DODDY voice service

**Live** on Vercel as the project `doddy-voice-token`; the app's voice screen uses it. An old copy on Render is unused (`STATUS.md`).

This service verifies Sign in with Apple once, keeps a revocable DODDY voice session, and exchanges
that session for a provider-scoped credential. Apple and provider credentials stay on the server;
the app never asks for a provider API key, tester code, or server URL. Voice transcripts, audio,
notes, profile data, and conversation prompts are not sent to this service for credential requests.

The app calls two routes:

- `POST /api/voice-auth`: Apple identity-token verification, refresh-token rotation, sign-out, and
  DODDY voice-session deletion. ElevenLabs must be configured before a voice account
  session can be created.
- `POST /api/voice-token`: validates an active DODDY session and returns an ElevenLabs conversation
  token. ElevenLabs is the only voice (9 Nov 2026); a request that names OpenAI gets `400 unknown_provider`.

Access tokens last 10 minutes and stay in app memory. Opaque refresh tokens rotate on use and last
30 days; the app stores the current refresh token and Apple user identifier in the iOS Keychain with
device-only accessibility. A revoked Apple credential, DODDY sign-out, or invalid refresh token
requires a new Apple sign-in. The server stores only a keyed pseudonymous Apple subject, session
records, refresh-token hashes (the current one and the one it replaced), and replay/rate-limit
counters (the sign-in ones are keyed by a hash of the caller's address, never the address), plus, when the Apple key below is set,
Apple's refresh token for the person, sealed (AES-256-GCM) with a key derived from the signing key.
Request logs contain action/provider, outcome, status, and duration only (and, for account deletion,
whether Apple revoked the link).

## Owner configuration required before deployment

Set these as server environment variables in the owner-controlled host. Do not put values in this
repository, app configuration, or build settings. The secret ones live in 1Password and reach the
Vercel project `doddy-voice-token` through `tools/secrets/sync.mjs` (ADR-493,
`docs/security/SECRETS_1PASSWORD.md`). The signing key is recorded there but never written by the tool.

| Name | Purpose |
|---|---|
| `APPLE_BUNDLE_ID` | Exact bundle identifier for the app build signing in (for example, the development bundle identifier). |
| `SUPABASE_URL` | Optional. The Doddy accounts project (`https://<ref>.supabase.co`, decision `2026-11-08-required-account`). With it, `/api/voice-token` also accepts a Doddy account's access token (Apple, Google or a code by email), checked against the project's published keys (`src/doddy-account.js`): no secret is needed. Its limits count per account (`account:<id>`), apart from the Apple voice accounts. Unreadable keys answer 503 `account_check_unavailable`, never 401. Without it, only this server's own Apple sign-in works, as before. |
| `DODDY_SESSION_SIGNING_KEY` | Stable random secret, at least 32 bytes. Signs short-lived sessions and pseudonymizes Apple subject identifiers. Rotating it invalidates sessions. |
| `UPSTASH_REDIS_REST_URL` | HTTPS URL for the durable shared session/rate-limit store. |
| `UPSTASH_REDIS_REST_TOKEN` | Secret for that store. Never log or expose it to the app. |
| `ELEVENLABS_API_KEY` | Owner-held ElevenLabs API credential. |
| `ELEVENLABS_AGENT_ID` | The DODDY agent ID configured by the owner. |
| `ELEVENLABS_TRANSLATOR_AGENT_ID` | Optional. The translator-only agent (no tools; `voice-agent/translator/`). A request with the body `{"agent":"translator"}` gets a token for it. When unset, the id in `src/handler.js` (`DEFAULT_TRANSLATOR_AGENT_ID`, public) is used, so nothing has to be set. Any other `agent` value is a 400 `unknown_agent`; no body is the main agent, as before. |
| `DODDY_TOKENS_PER_HOUR` | Optional shared per-account issuance limit; defaults to `30`. |
| `DODDY_TOKENS_PER_DAY` | Optional per-account issuance limit per UTC day, on top of the hourly one; defaults to `150` (ADR-712). |
| `DODDY_GLOBAL_TOKENS_PER_HOUR` | Optional shared global issuance limit; defaults to `100`. |
| `DODDY_SIGNINS_PER_CLIENT_HOUR` | Optional: sign-ins one caller address may complete per hour; defaults to `10` (ADR-712). |
| `DODDY_SIGNINS_PER_CLIENT_DAY` | Optional: the same per UTC day; defaults to `30`. |
| `APPLE_TEAM_ID` | Optional, with the next two: the Apple Developer team ID. Lets "Delete voice account" also revoke Sign in with Apple (ADR-524). |
| `APPLE_SIGN_IN_KEY_ID` | The key ID of a Sign in with Apple key (Apple Developer › Certificates, Identifiers & Profiles › Keys). |
| `APPLE_SIGN_IN_PRIVATE_KEY` | That key's `.p8` file contents (PEM; literal `\n` line breaks work). Secret: 1Password only. |

### Revoking Sign in with Apple for a Doddy account (decision `2026-11-09-apple-revoke-for-doddy-accounts`)

A Doddy account (a Supabase user, `SUPABASE_URL` set) made with Sign in with Apple needs the same
revoke, but it has no voice session. Two more `POST /api/voice-auth` actions take the **Doddy account's
access token** as the Bearer, checked like `/api/voice-token` checks it (a voice session's token is
refused). Both need the three `APPLE_*` key settings and `APPLE_BUNDLE_ID` below; without them they
answer 200 and do nothing.

| Action | Body | When the app sends it | Answer |
|---|---|---|---|
| `apple-link` | `identityToken`, `rawNonce`, `authorizationCode` (all from the Apple sheet just used) | right after the sign-in with Apple | `{ linked: true }` once Apple's refresh token is kept, sealed, under `account:<Supabase user id>` for 400 days; `{ linked: false }` when the code wasn't the same Apple person's or Apple refused. Counted against the per-caller sign-in limits. |
| `apple-revoke` | none | first, when "Delete my Doddy account" runs | `{ appleRevoked, apple }`, `apple` being `revoked`, `failed`, `no_token` or `not_configured`. A revoked or missing token is forgotten; a failed one is kept so asking again can work. Apple failing never stops the deletion. |

`APPLE_BUNDLE_ID` is one value: it must be the bundle ID of the build that signs in (Beta:
`com.bienos.doddy2.dev`), because Apple issues the one-time code to that app.

### Revoking Sign in with Apple when an account is deleted (ADR-524)

App Store guideline 5.1.1(v) expects an app with Sign in with Apple to revoke the user's tokens when
they delete their account. With the three `APPLE_*` key settings above:

1. At sign-in the app also sends Apple's one-time `authorizationCode`. The server swaps it at
   `https://appleid.apple.com/auth/token` (an ES256 client secret signed with the key, valid 5
   minutes) and keeps Apple's refresh token only if the `id_token` in Apple's reply names the same
   person whose identity token was just verified. It is stored sealed, never logged, and expires
   with the DODDY session (30 days, extended on refresh).
2. "Delete voice account" first posts that token to `https://appleid.apple.com/auth/revoke`, then
   deletes everything, the sealed token included. The reply is `{ deleted: true, appleRevoked }`.
   Apple failing or timing out (5 seconds) never keeps the account: `appleRevoked` is `false` and
   the log line says `failed`, `no_token` or `not_configured`.

Without the key, sign-in and deletion work as before and nothing is sent to Apple's token
endpoints. Accounts made before the key was set have no token to revoke until they sign in again.
To make the key: Apple Developer › Keys › +, tick Sign in with Apple, pick the app's primary App ID,
download the `.p8` once (Apple keeps no copy), note the key ID.

Apple Developer setup is also required: enable Sign in with Apple for each real app identifier and
provision the matching entitlement/profile. The app's active iOS entitlement includes the capability,
but this repository cannot enable it in the Apple Developer account. Configure the durable Redis
store before deploying; the service fails closed when it or the signing key is missing. Existing
provider credentials and live agents must be checked by the DODDY owner in the hosting/provider
dashboards. This code does not deploy or change those settings.

The former `DODDY_ACCESS_CODES` setting is retired. Remove it from the host after the new signed-in
build and server configuration are ready. Old app settings for editable server URLs and public
agent IDs are cleared on launch; the old tester code Keychain item is deleted.

## Security behavior

- Apple identity tokens are verified against Apple's published signing keys, issuer, audience,
  expiry, issue time, and the hashed nonce.
- Refresh tokens are opaque, stored server-side only as hashes, and rotated after each refresh;
  replay fails closed. The hash a refresh replaced is remembered for the life of the session, and if
  it is ever presented again the whole session ends (refresh token and access token), because the
  token was copied or two devices hold it (ADR-712). The caller gets the same `401 session_expired`
  as for any dead token; only the log line carries `reuse: true`. An app that loses the reply to a
  refresh and tries again with the old token is signed out the same way and has to sign in with Apple
  again. Only the latest replaced token is remembered, so one from two refreshes ago is just unknown.
- Every provider-token request checks the signed access token against the active durable session.
- Shared atomic per-account (hourly and daily) and global rate limits run before any paid provider
  request. Only a token that is actually issued is counted, so a refused request never uses up the
  global budget or the account's own allowance (ADR-671, ADR-712). A `429` log line says which limit
  it was (`user_hour`, `user_day`, `global`); the app sees the same `rate_limited` for all three.
- Sign-in is limited per caller address (`DODDY_SIGNINS_PER_CLIENT_HOUR` / `_DAY`), in the same
  Redis store and failing closed like the rest (ADR-712). It counts sign-ins that carry a token Apple
  verified, not junk, and not refresh or sign-out. The address is only believed from the header
  Vercel sets itself (`x-vercel-forwarded-for`), and only when the host is Vercel (`VERCEL` is set);
  an IPv6 address counts as its /64. Without a usable address every caller shares one "unknown"
  bucket with ten times the limit, and the log line carries `noClientAddress: true`. This is a brake
  on making many accounts from one place, not a defence against a network of addresses: add a Vercel
  Firewall rate limit on `/api/voice-auth` for that (dashboard setting).
- With the defaults a handful of accounts can still use the hourly global budget (30 per account,
  100 for everyone). Lower `DODDY_TOKENS_PER_HOUR` or raise `DODDY_GLOBAL_TOKENS_PER_HOUR` to move
  that; it is the owner's choice of cost against convenience.
- Request sizes, method, provider, upstream timeout, and provider response shape are checked.
- No content, credentials, Apple subject, or user/account identifier is written to application logs.
- The server has no in-memory session or rate-limit fallback.

## Run server tests

```sh
npm test
```

## Apple references for the iOS implementation

- [Sign in with Apple design guidance](https://developer.apple.com/design/human-interface-guidelines/sign-in-with-apple)
- [Authentication Services](https://developer.apple.com/documentation/authenticationservices)
- [ASAuthorizationAppleIDProvider](https://developer.apple.com/documentation/authenticationservices/asauthorizationappleidprovider)
