# DODDY voice service

This service verifies Sign in with Apple once, keeps a revocable DODDY voice session, and exchanges
that session for a provider-scoped credential. Apple and provider credentials stay on the server;
the app never asks for a provider API key, tester code, or server URL. Voice transcripts, audio,
notes, profile data, and conversation prompts are not sent to this service for credential requests.

The app calls two routes:

- `POST /api/voice-auth`: Apple identity-token verification, refresh-token rotation, sign-out, and
  DODDY voice-session deletion. The selected provider must be configured before a voice account
  session can be created.
- `POST /api/voice-token`: validates an active DODDY session and returns an ElevenLabs conversation
  token, OpenAI Realtime client secret, or the configured Picovoice key.

Access tokens last 10 minutes and stay in app memory. Opaque refresh tokens rotate on use and last
30 days; the app stores the current refresh token and Apple user identifier in the iOS Keychain with
device-only accessibility. A revoked Apple credential, DODDY sign-out, or invalid refresh token
requires a new Apple sign-in. The server stores only a keyed pseudonymous Apple subject, session
records, refresh-token hashes, and replay/rate-limit counters, plus, when the Apple key below is set,
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
| `DODDY_SESSION_SIGNING_KEY` | Stable random secret, at least 32 bytes. Signs short-lived sessions and pseudonymizes Apple subject identifiers. Rotating it invalidates sessions. |
| `UPSTASH_REDIS_REST_URL` | HTTPS URL for the durable shared session/rate-limit store. |
| `UPSTASH_REDIS_REST_TOKEN` | Secret for that store. Never log or expose it to the app. |
| `ELEVENLABS_API_KEY` | Owner-held ElevenLabs API credential. |
| `ELEVENLABS_AGENT_ID` | The DODDY agent ID configured by the owner. |
| `OPENAI_API_KEY` | Owner-held OpenAI API credential, if OpenAI voice is enabled. |
| `OPENAI_REALTIME_MODEL` | Optional server default; the app's model is restricted to the allowlist in `src/handler.js`. |
| `OPENAI_REALTIME_VOICE` | Optional server default voice. |
| `PICOVOICE_ACCESS_KEY` | Optional owner-held key for one-tap Hey Doddy setup. |
| `DODDY_TOKENS_PER_HOUR` | Optional shared per-account issuance limit; defaults to `30`. |
| `DODDY_GLOBAL_TOKENS_PER_HOUR` | Optional shared global issuance limit; defaults to `100`. |
| `APPLE_TEAM_ID` | Optional, with the next two: the Apple Developer team ID. Lets "Delete voice account" also revoke Sign in with Apple (ADR-524). |
| `APPLE_SIGN_IN_KEY_ID` | The key ID of a Sign in with Apple key (Apple Developer › Certificates, Identifiers & Profiles › Keys). |
| `APPLE_SIGN_IN_PRIVATE_KEY` | That key's `.p8` file contents (PEM; literal `\n` line breaks work). Secret: 1Password only. |

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
  replay fails closed.
- Every provider-token request checks the signed access token against the active durable session.
- Shared atomic per-account and global rate limits run before any paid provider request.
- Request sizes, method, provider, model, upstream timeout, and provider response shape are checked.
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
