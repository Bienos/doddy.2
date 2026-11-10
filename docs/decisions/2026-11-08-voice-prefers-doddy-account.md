# Voice uses the Doddy account's token whenever someone is signed in

- **Date:** 2026-11-08
- **Decided by:** owner, 8 Nov 2026 ("tak zrób tę poprawkę"), after a build from `main` showed "your sign-in expired" at the start
- **Status:** applied in this pull request, once merged
- **Changes:** one rule of `2026-11-08-required-account` (step 4b)

## Why
`DoddyAccountServers.voiceAccountToken()` returned nil when the iPhone still had a voice session from an earlier build (`VoiceAuthSession.hasSavedSession`), so the voice token request used that older session even for a person signed in to a Doddy account. The Keychain keeps it across reinstalls. If it is dead, the request failed with "Your voice session expired. Sign in with Apple again" at the start of a conversation. The voice token server has accepted account tokens since `SUPABASE_URL` was set on 8 Nov 2026 (Vercel `doddy-voice-token`, deployment of #239).

## Decision
A signed-in Doddy account always supplies the voice token. The older voice session is used only when nobody is signed in (a build without accounts, or signed out).

## Consequences
- A voice server without `SUPABASE_URL` refuses the account token (401); the app leaves the older session alone in that case (`VoiceTokenClient`), so voice fails with the token server's answer instead of falling back. All production servers have it set now.
- Not confirmed on a device: the cause is a reading of the code, not a device log.
