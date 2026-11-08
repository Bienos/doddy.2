# Every Doddy user has an account, made with Apple, Google or a code sent by email

- **Date:** 2026-11-08
- **Decided by:** owner, 8 Nov 2026. Claude asked "required, or can people still skip?" and the owner answered "1 reiured". On the email sender: "2. ok we will set it up, do all whats needed reqwured". Earlier the same day: "you must have login via gogle or apple id or create account via email I think only".
- **Status:** accepted. Applied step by step, in the pull requests listed under "Order of work".
- **Replaces:**
  - the project default "no mandatory account" (`AGENTS.md`, "Project defaults");
  - the welcome's "Try Doddy without an account" and its Face ID button (ADR-598);
  - ADR-599's rule that the Apple button signs in only to the voice server;
  - ADR-526's rule that only Apple and Google may sign in (email is added).
- **Builds on:** ADR-526 (a Doddy account is a Supabase Auth user; servers check its token against the project's published keys), ADR-818 and ADR-819 (Google and Apple on Doddy Web), ADR-674 (deleting the account).

## Why
- **The owner wants it** (above).
- **Four separate identities today.** None of them shares an id with the others (engineering audit, 7 Nov 2026; `docs/architecture/WEB_AND_SHARED_PLATFORM.md` §E):
  - the backend's device session: user id = HMAC(signing key, device id), `ds1` tokens for 30 days with no refresh, `backend/src/deviceSession.ts`;
  - the messaging server's anonymous device token: a random account UUID, `server/messaging/src/auth.ts`;
  - the voice token server's Apple-only session: user id = HMAC(its own key, Apple sub), `server/voice-token/src/voice-auth.js`;
  - Doddy Web's Supabase identities, ADR-818.
- **What that costs:**
  - A reinstall loses the messaging account.
  - A leaked device id is a permanent account.
  - The signing key can't be rotated without orphaning every user.
  - Only Apple users can talk to Doddy.

## Decision
1. **Sign-in methods, and only these three.** All three go through Supabase Auth (project `doddy-gateway`), as ADR-526 already planned:
   - **Sign in with Apple:** the native sheet. Its identity token goes to Supabase, `POST /auth/v1/token?grant_type=id_token`, provider `apple`, with the raw nonce.
   - **Google:** Supabase's OAuth with PKCE in the system browser sheet (`ASWebAuthenticationSession`). It comes back to the app's link and is exchanged at `POST /auth/v1/token?grant_type=pkce`. No Google SDK is added to the app.
   - **Email:** a 6-digit code. `POST /auth/v1/otp` with `create_user: true` sends it, and `POST /auth/v1/verify`, type `email`, checks it. There are no passwords and no magic links.
2. **The app talks to Supabase Auth directly** with the project's publishable key, which is meant for clients and is not a secret. Supabase rate-limits sign-in per address; going through one of Doddy's servers would put every user behind that server's single address. The app keeps the access token and the rotating refresh token in the Keychain (this device only).
3. **One account id: the Supabase user's UUID.** Every Doddy server checks the access token itself:
   - against the project's published keys (ES256 or RS256; HS256 refused);
   - issuer, audience `authenticated`, expiry;
   - the method is Apple, Google or email (`app_metadata.provider`);
   - `amr` holds no `password` (and an `amr` that is missing passes);
   - anonymous users are refused.

   There is no shared secret between servers. The servers:
   - **backend** (`doddy`): `DODDY_AUTH_MODE=supabase`, which already exists, plus email;
   - **voice token server:** accepts the Supabase token next to its own Apple session while phones move over; the Apple-only path is removed after that;
   - **messaging server:** accepts the Supabase token and maps it to its `accounts` row (`accounts.auth_subject`).
4. **Required.** The welcome's sign-in sheet offers exactly Apple, Google and email, and the app goes no further until one succeeds. "Try Doddy without an account" and the Face ID button are removed. App Review allows a required account when the app's main features need one; Doddy's voice, server memory and connected apps do.
5. **Existing data moves to the account.** The first sign-in on a phone that already has data links that data to the account, once and with proof:
   - the backend (`POST /v1/account/link-device` with the old `ds1` token and the new Supabase token);
   - the messaging server (the old device token and the new Supabase token).

   A second account never takes over data that is already linked. Accounts are never merged (ADR-600).
6. **Deleting the account deletes the Supabase user too.** This already exists in the backend with the project's secret key, for App Store 5.1.1(v). The messaging and voice servers delete theirs as today. Signing out ends the Supabase session on this phone.

## Owner steps (OWNER_QUEUE)
- **Supabase → Authentication → Providers:**
  - Email on, with "Confirm email" on.
  - Password sign-in and sign-up off, if the dashboard allows it. The servers refuse password sessions either way.
  - Apple on, with the bundle ID `com.bienos.doddy2.dev` as a Client ID.
  - Google on, with a Google OAuth client.
- **Supabase → Authentication → URL configuration:** add the app's redirect `doddy://auth-callback`.
- **Supabase → Authentication → Email templates:** "Magic Link" and "Confirm signup" show the code (`{{ .Token }}`), in Polish and English.
- **Supabase → Authentication → SMTP:** your email sender (Resend, Postmark or similar). Supabase's built-in mailer is meant for testing and allows only a few emails an hour.
- **Supabase plan:** the free project pauses after a week with no use, and then nobody can sign in. Pro ($25 a month) removes the pause.
- **Server variables:** `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` on Render `doddy` (and `SUPABASE_SECRET_KEY` for deletion), and `SUPABASE_URL` on `doddy-messaging` and on Vercel `doddy-voice-token`.

## Order of work (one pull request each)
1. **Backend:** email sessions accepted, `amr` checked, `link-device`, tests. This decision travels with it.
2. **Voice token server:** accepts the Supabase token, tests.
3. **Messaging server:** accepts the Supabase token, migration `021`, links the old device account, tests.
4. **iPhone:**
   - the sign-in in DoddyCore (requests, PKCE, token refresh rules), tested on Linux;
   - the welcome's three methods, required;
   - every server client sends the Supabase token;
   - sign-out and deletion.

   This touches `RootView.swift`, so it waits until #221 and #232 have merged (one agent at a time on that file).
5. **After phones have moved:** retire guests, invite codes, the owner claim, `ds1` device sessions, the messaging server's anonymous `POST /v1/accounts` and the voice server's own Apple sign-in. Then run Render in production mode.

## Consequences
- Every user needs Apple, Google or an email address, and Doddy can't be tried without one.
- Sign-in depends on Supabase being up: a paused free project locks everyone out.
- Email sign-in costs the sender's price per email, and each code is a possible abuse path. Supabase's own per-address and per-email limits apply, and the sender's dashboard shows the volume.
- Privacy: Doddy now holds an email address for Google and email users, and Apple's private relay address for Apple users who choose it. The privacy policy and the App Store privacy answers have to say so (OWNER_QUEUE 7).
- The signing-key problem goes away for new accounts: Supabase signs, and the servers only verify.

## Evidence
Read on 8 Nov 2026 (three read-only maps of the code):
- `backend/src/auth.ts:184,223-225` allows only `apple` and `google` today;
- `backend/src/deviceSession.ts:136,288-294` derives the device user id;
- `server/voice-token/src/voice-auth.js:344,433-460` (Apple-sub HMAC id, HS256 sessions);
- `server/messaging/src/auth.ts:13-33` (anonymous device token);
- `DoddyApp/Features/Welcome/SignInSheet.swift:1-5,134-173` (only Apple is real; Google, email and Face ID are UI only; "Try Doddy without an account").

Nothing was run for this file.
