# Help me clear my own Doddy to-do list (19 Oct)

Repo `Bienos/doddy.2`, default branch `claude/loving-dirac-uuxoux`. Read `STATUS.md` and `CLAUDE.md` first.

These are tasks only I (the owner) can finish, because they need my accounts, my ID, my phone or my decision. Your job is to do every part an agent can, and walk me through the rest one click at a time. I'm in this chat, so ask me directly.

## Rules
- **One task at a time,** in the order below. Tell me what you need from me in one short message, then wait.
- **Secrets:** never ask me to paste a secret (keys, tokens, passwords, ID numbers) into this chat. When a secret is needed, tell me exactly where to paste it myself.
- **Changes to live services** (Render, Twilio, ElevenLabs, Vercel, Composio, Apple):
  - Before each one, show me the exact change and wait for my "yes" in this chat.
  - Never retry a write whose result is unclear. Read the state back first.
  - Call it done only when the provider confirms it.
- **Merge sessions:** don't push to or merge PRs another session is driving. The merge session `session_01RGYbtpY4KDQunpJzkXaWhh` owns #84, #88 and #90.
- **When a task finishes,** record it in `STATUS.md` ("Waiting on the owner") through a small docs PR on your own branch. Merge it once `core` is green.

## The tasks
1. **Apple sign-in. Voice can't work without it.**
   - Check `project.yml` and the entitlements for the bundle ID (`com.bienos.doddy2.dev`) and the Sign in with Apple capability.
   - Walk me through:
     - confirming my paid Apple Developer Program membership (developer.apple.com → Account → Membership);
     - turning on Sign in with Apple for that App ID (Certificates, Identifiers & Profiles);
     - in Xcode: `make project`, open `Doddy.xcodeproj`, choose my paid team, build to my iPhone with Developer Mode on;
     - first talk: Talk to Doddy → Sign in with Apple → allow the microphone → say hello.
   - Give me the `MAC_VERIFICATION_CHECKLIST` rows (V0a to V0f) as a checklist to tick.
   - Before the build, check that the merge session has merged #88. Without it the app calls a dead voice address.
2. **Render, deadline 10 Nov: the free database is deleted then.**
   - Use the Render tools read-only to list my services and databases, their plans and the expiry date.
   - Tell me the exact upgrades (messaging server to Starter, database to a paid plan) and the monthly cost Render shows.
   - Make each change only after my yes, or tell me where to click.
   - Then check that `doddy-messaging` deploys from the branch the phone-number session's runbook says, and that its health check is `/healthz`. Report it; don't change it without my yes.
3. **Twilio (the review takes 2–3 business days, so start early).**
   - Walk me through: upgrading from trial, allowing Poland for SMS and voice, and submitting the Polish regulatory bundle with my ID. I submit the ID myself; you never see it.
   - Then making the Verify service and the Messaging service, and a subaccount limited to Poland for calls (#90).
   - Their IDs (starting `VA`, `MG` or `AC`) aren't secret: I'll paste them here. Pass the VA and MG IDs to the phone-number session (`session_01TWmNMWhbDNzDVVkN5AfFhs`) with `send_message`.
   - Auth tokens are secret: tell me where to paste each one in Render myself.
4. **Composio Gmail.**
   - Read the Composio session's last message (`session_01VkU5sPUikrKpXEJvVA2SCJ`) and walk me through the steps left: Google OAuth client redirect URIs, Gmail scopes, test user, and the Composio auth config.
   - When I have the `ac_…` ID, I'll paste it here (not secret). Send it to that session with `send_message`.
5. **Calls in Polish (#90).**
   - Write a one-page draft for me and a lawyer on the legal basis for the call recording notice in Poland (GDPR and Polish telecom law), marked as a draft, not legal advice. Save it under `docs/legal/` on your branch.
   - Draft the Polish calling agent's spec from `docs/implementation/CALL_CASES_STATUS.md`. Create it in ElevenLabs only after my yes on the exact config.
6. **Decisions.** Ask me each one in a single message, with your recommendation and one line of why:
   - translator mode: ask first, or start straight away;
   - BLIK limit per transfer: keep 10,000 zł, or a new number;
   - #90's secrets split (which new variables are secrets);
   - repository visibility: GitHub says public, ADR-497 says private. Which is intended? If it should be private, tell me where to change it, and list what changes (for example, Actions minutes).

   Record each answer as a new numbered ADR row in `DECISIONS.md` on your branch. Search for the highest number first, and don't reuse 483, 490 to 495 or 530.
7. **Native review of translations.** From `l10n/REVIEW_NOTES.md`, make me a short list per language of what a native speaker must check first. Then draft a message I can send to a reviewer.
8. **Double voice session bug.** Write me exact steps to capture a device log on my iPhone (Console.app on the Mac, filter on the Doddy process), including the locked-phone "Hey Doddy" case. Say where to save the log so the next session can read it.

## Report at the end
Give a table with each task: done (with proof, such as a provider confirmation or a link), waiting on me (the exact next click), or waiting on someone else (Twilio review, a lawyer, a reviewer). Then list what was not run or verified.
