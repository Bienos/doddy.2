# Sign in with Apple asks for the email, so one person can reach one Doddy account by Apple, Google or email

- **Date:** 2026-11-09
- **Decided by:** owner, 8 Nov 2026: "people should be able to connect account via apple sign in google and email to web ipad etc" and "the email scope change so accounts can link". Proposal for the exact wording; owner approval of the PR pending.
- **Status:** proposed, applied in this pull request
- **Replaces:** nothing. Refines `2026-11-08-required-account`, decision 1 (Apple).

## Why
- The iPhone's Apple button asked Apple for no scopes (`VoiceAccessGate.swift`, `AppleAccountSignInButton`). Apple then leaves the email out of the identity token, so a Doddy account made with Apple has no address and nothing ties it to a Google or email account of the same person.
- Supabase joins sign-ins that share a verified email into one user by default (to confirm in the project's Authentication settings; not checked from this environment).

## Decision
1. With Doddy accounts set up in the build, the Apple request asks for the `.email` scope only (not the name).
2. Apple's token then holds the person's real address, or Apple's private relay address when they choose "Hide My Email".
3. Supabase's automatic linking by verified email does the joining. No Doddy server merges anything (ADR-600 still holds).
4. The Supabase Apple setting "Allow users without an email" stays on, as a fallback.
5. The voice-only sign-in (a build without Doddy accounts) is unchanged.

## Consequences
- A person who uses the same address with Google or email and Apple (sharing the real address) gets one account. One who hides their email with Apple gets the relay address, which matches nothing, so that sign-in stays a separate account.
- Apple only shows the email choice the first time a person authorises the app. An Apple account made before this change keeps having no email in its token; it is not joined retroactively.
- Privacy: Doddy now holds the email or relay address of Apple users, as it already does for Google and email users (`2026-11-08-required-account`, Consequences). The privacy policy and App Store privacy answers already say so (OWNER_QUEUE 7).

## Evidence
- Not compiled: no Xcode here. The change is one line, `request.requestedScopes = [.email]`, inside the existing request closure.
- Not run: no sign-in on a device. To check: sign in with Google using an address, sign out, then sign in with Apple sharing that same address; Settings › Your Doddy account should show the same user.
