# Deleting a Doddy account made with Apple also ends Sign in with Apple at Apple

- **Date:** 2026-11-09
- **Decided by:** owner, 8 Nov 2026: "yes start on the apple revoke" (after the review that found the gap). The earlier rule is ADR-524 (owner: "Yes", 18 Oct 2026). Proposal for this design; owner approval of the PR pending.
- **Status:** proposed, applied in the pull request that adds this file
- **Replaces:** nothing. Extends ADR-524 (voice account) to a Doddy account, `2026-11-08-required-account`.

## Why
- App Store guideline 5.1.1(v): an app with Sign in with Apple revokes the person's Apple tokens when they delete their account.
- ADR-524 does it for the voice account. A Doddy account is a Supabase user, and the app drops Apple's one-time code (`authorizationCode`) when it signs one in, so deleting a Doddy account leaves Doddy in the person's Apple ID settings (found in the review of #249).
- Supabase's id_token sign-in never receives Apple's refresh token, so Supabase can't revoke it either.

## Decision
1. **Who holds Apple's token:** the voice token server. It already has the Apple key settings, the code exchange, the sealed store and the revoke call (ADR-524), so no new service, table or migration.
2. **Two actions** on `POST /api/voice-auth`, authorised by the Doddy account's access token (a voice session's token is refused):
   - `apple-link`: right after a Doddy account signs in with Apple, the app sends the Apple identity token, its raw nonce and the one-time code. The server verifies the token, swaps the code only for the same Apple person, and keeps Apple's refresh token sealed (AES-256-GCM) under `account:<Supabase user id>` for 400 days. Best effort: the sign-in counts without it.
   - `apple-revoke`: the first thing "Delete my Doddy account" does after the messaging server confirmed its deletion, before the backend removes the sign-in at Supabase. It posts the token to Apple's `/auth/revoke`.
3. **Apple failing never keeps the account** (ADR-524). The delete result then ends with one line saying how to remove Doddy in Settings › Apple ID › Sign in with Apple. A failed revoke keeps the sealed token so a retry can work; a revoked or missing one is forgotten.
4. **Nothing says "revoked" unless Apple answered 200** (DOD-08). The app remembers a confirmed revoke per user ID until the deletion finishes, so retrying after a later step failed doesn't show a false failure.
5. **Without the Sign in with Apple key settings** on the voice server, both actions do nothing and the account works as before.

## Consequences
- An Apple user's Doddy account now has a sealed Apple refresh token on the voice server (Upstash Redis) for up to 400 days, until revoked at deletion or replaced by their next sign-in with Apple. The privacy policy draft §5.2 and the App Store privacy answers should say so (OWNER_QUEUE 24).
- Accounts made before this build have no token to revoke until the person signs in with Apple again (same limit as ADR-524).
- `APPLE_BUNDLE_ID` on the voice server is one value, so only the build with that bundle ID can link (Beta: `com.bienos.doddy2.dev`; the production ID, OWNER_QUEUE 21, needs its own value at that point).
- Apple on the web (Supabase OAuth, ADR-818) is not covered: Doddy Web never sees Apple's refresh token.
- Deleting the account takes one more network call, bounded by the server's 5-second Apple timeout.

## Evidence
- Ran: `npm test` in `server/voice-token`, 69 of 69 (12 new, Apple's endpoints faked): link then revoke, no token without a Doddy account (a voice session's token refused), a code from another Apple person keeps nothing, Apple failing keeps the token for a retry, one account's token never revoked for another, rate limit, bad bodies, 503 when the project's keys can't be read, not-configured does nothing, the Redis `DEL`.
- Not compiled: the app changes (no Xcode here): `VoiceTokenClient.swift`, `VoiceAccessGate.swift`, `DoddyAccountApp.swift`.
- Never run against Apple: the voice server has no Sign in with Apple key set (OWNER_QUEUE 24). To check on a device once it is set: sign in with Apple, delete the account, and see Doddy gone from Settings › Apple ID › Sign in with Apple.
