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
records, refresh-token hashes, and replay/rate-limit counters. Request logs contain action/provider,
outcome, status, and duration only.

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
