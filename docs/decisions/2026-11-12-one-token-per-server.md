# The account's Supabase token is exchanged once per server for that server's own token; signed taps are a separate option

- **Date:** 2026-11-12
- **Decided by:** proposal, owner approval pending
- **Status:** proposed — waiting for the owner. Nothing in the app or the servers is changed by this file.
- **Replaces:** nothing. Builds on `2026-11-08-required-account` and on how the messaging server already signs in (`POST /v1/accounts/sign-in`).

## Why
- **Each server should hold a token scoped to itself.** The Doddy account signs in once, at Supabase. The account's token should then be exchanged once per server for a token that only that server accepts, with its own expiry, and that it can revoke on its own (sign-out, a revoked iPhone, account deletion). The messaging server already works this way: one exchange at `POST /v1/accounts/sign-in`, then its own device token (`server/messaging/src/routes/account.ts`). This proposal gives the backend and the voice server the same shape.
- **A tap can carry its own proof.** Approvals (a text, a call, a delivery) are bound to their exact payload by a hash both sides compute (`approvalHash`, `server/messaging/src/approval.ts`; shared vectors in `contracts/phone/approval-vectors.json`; DOD-07). A signature made on the iPhone at the moment of the tap would add evidence that a person approved that payload just then.

**Where the changes go:**

| Server | What changes | Code |
|---|---|---|
| Backend `doddy` | a new exchange route; the backend clients use the backend's own session | `DoddyAccountServers.linkBackend` and `backendToken` (`DoddyApp/Features/Account/DoddyAccountApp.swift`); `DeviceSession.ensure` and `renew` (`DoddyApp/Infrastructure/DeviceSession.swift`); `DoddyAccountLink` (`Packages/DoddyCore/Sources/DoddyCore/Account/DoddyAccount.swift`); `backend/src/auth.ts` |
| Voice server (Vercel) | a new exchange action; token requests use the voice server's own session | `VoiceTokenClient` (`DoddyApp/Features/Voice/VoiceTokenClient.swift`); `voiceAccountToken` (`DoddyAccountApp.swift`); `server/voice-token/src/voice-auth.js`, `server/voice-token/src/handler.js`, `server/voice-token/src/doddy-account.js` |
| Messaging server | nothing: it already exchanges once | `DoddyAccountLink.signInMessaging`; `server/messaging/src/routes/account.ts` |
| Supabase Auth | nothing: sign-out still ends the Supabase session | `DoddyAccountClient.signOut` |

Doddy Web is not affected: the backend runs its sign-in and keeps only its own cookie (`backend/src/web/social.ts`).

## Decision (proposed)
1. **One exchange per server.** Each server gets an exchange route that takes the Supabase token once and answers with a token of its own, scoped to that server (its own audience and key id, from the per-purpose keys in `2026-11-12-account-and-device-tokens`, (b)), with an expiry and a way to revoke it:
   - **Backend:** `POST /v1/session/account` returns a backend session for this iPhone, checked by the existing `RevocableSessionVerifier` and token floors (ADR-709). It appears in the device list of `2026-11-12-account-and-device-tokens`, (c).
   - **Voice server:** a `POST /api/voice-auth` action, `account-session`, returns the voice server's own access and refresh tokens, the kind it already issues for Apple voice accounts (10-minute access, rotating 30-day refresh, `server/voice-token/src/voice-auth.js`), bound to the Doddy account. `/api/voice-token` then accepts those. The `apple-link` and `apple-revoke` actions keep taking the account's token, since they run right after sign-in and right before deletion.
   - **Messaging server:** unchanged.
2. **The app keeps one token per server.** `DoddyAccountServers` asks each server for its token when it has none or it was refused, with a fresh Supabase token. Signing out ends each server's token (as #279 does for the messaging server) and then the Supabase session.
3. **Moving over without breaking older builds.** For one release each server accepts both the Supabase token and its own. A later pull request accepts the Supabase token only at the exchange route, once the owner confirms the installed builds are new enough (owner queue 50 lists what is checked on a device).

**Separate option: signed taps.** At the moment of a tap on an approval card, the app signs the approval hash, together with a challenge from the server and the time, using a key kept in the iPhone's Secure Enclave. The key's public half is registered with each server during the exchange above. The server stores the approval only with a valid signature from a key registered to that account.
- **What it proves:** that the iPhone holding that key approved this exact payload just now. With an access rule that asks for Face ID or the passcode, it also proves that someone passed it at that moment.
- **What it does not prove:** that the person read the card; that the app is unmodified (App Attest is the tool for that, `2026-11-12-voice-token-fair-share`); anything on the web, which would need passkeys.
- **Costs:** a Face ID prompt per approval if presence is required (the owner picks which actions: texts, calls, deliveries, payments); key registration and loss handling (a restored iPhone registers a new key); software keys in tests, since the Simulator has no Secure Enclave.

## What the owner decides
1. Yes or no to the exchange per server (1 to 3), and its order relative to `2026-11-12-account-and-device-tokens`. It needs that proposal's per-purpose keys first.
2. How long the backend's own session lasts (proposed: 30 days, renewed while used, like Doddy Web's sessions in `backend/src/web/sessions.ts`).
3. Signed taps: not now, now for some actions (which), or never; and whether they need Face ID or the passcode.

## Consequences
- Each server accepts only its own tokens for everyday requests, and can end them itself (sign-out, revoke, account deletion) without waiting for Supabase's expiry.
- One more request per server after sign-in, and one more token per server in the Keychain. The voice server already has the code for its own sessions; the backend reuses its signed sessions.
- With signed taps, the server stores an approval only with a fresh signature from the person's iPhone. The cost is a prompt per approval when presence is required.

## Evidence
- Searched the app and DoddyCore for where the account token is used (`accessToken()`, `.authorization`, `voiceAccountToken`, `accountToken`); the table above lists where the changes go.
- Read: `Packages/DoddyCore/Sources/DoddyCore/Account/DoddyAccount.swift`, `DoddyApp/Features/Account/DoddyAccountApp.swift`, `DoddyApp/Infrastructure/DeviceSession.swift`, `DoddyApp/Features/Voice/VoiceTokenClient.swift`, `backend/src/auth.ts`, `backend/src/web/social.ts`, `backend/src/web/sessions.ts`, `server/voice-token/src/doddy-account.js`, `server/voice-token/src/voice-auth.js`, `server/messaging/src/doddyAccount.ts`, `server/messaging/src/routes/account.ts`, `server/messaging/src/approval.ts`.
- Not run: the app (no Xcode here), any server, any device.
