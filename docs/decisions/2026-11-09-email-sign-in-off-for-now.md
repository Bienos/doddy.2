# Email sign-in is off in the app for now; Apple and Google stay

- **Date:** 2026-11-09
- **Decided by:** owner, 9 Nov 2026, after TestFlight build 20: "a maila narazie usuńmy" ("and let's remove email for now").
- **Status:** accepted
- **Replaces:** for now, the email method of `2026-11-08-required-account` (decision 1, "Email: a 6-digit code"). Apple and Google are unchanged.

## Why
- Email sign-in can't be finished in the app today. Read on 9 Nov in the Supabase auth log of project `doddy-gateway`: the code request of 8 Nov, 19:19:55 UTC sent a `confirmation` email, and the person opened its link in Safari (`GET /auth/v1/verify?type=signup&redirect_to=http://localhost:3000`). The template sends a link to the project's Site URL, not the code the app's form asks for. OWNER_QUEUE 23 step (3) (templates that show `{{ .Token }}`) and step (4) (an email sender) aren't done.
- Supabase's built-in mailer allows only a few emails an hour, so even with the template fixed, email isn't ready for testers.

## Decision
- The welcome's sign-in sheet offers Apple and Google only (`SignInSheet.offersEmail = false`). Its words say "Apple or Google".
- Nothing else changes. `EmailCodeForm` and the email requests in DoddyCore stay, tested, so turning email back on is that one line once the template sends the code.
- An account already made by email keeps working: its session refreshes as before, and Settings shows "Signed in with email".
- Supabase's Email provider stays on. The servers accept email sessions as before.

## Consequences
- Someone without an Apple ID or a Google account can't sign in. Every iPhone has an Apple ID, so in practice this only matters for Google-only people.
- Google sign-in needs OWNER_QUEUE 25 first (Google refuses it with `redirect_uri_mismatch` today), so until then Apple is the only way in.

## Evidence
- Supabase auth and edge logs, 8 Nov 19:00 to 9 Nov 07:00 UTC, read on 9 Nov (read-only).
- Ran: `python3 -I tools/build_strings_catalog.py --check`. Not run: the iPhone build (no Xcode here).
