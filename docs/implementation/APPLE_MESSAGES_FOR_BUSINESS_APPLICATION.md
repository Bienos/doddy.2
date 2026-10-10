# Apple Messages for Business — application checklist (owner action)
Status: **owner decided to apply (2026-10-10). Not submitted.** Only the owner can register; an agent cannot.

## What it gives Doddy
A real blue-bubble Doddy conversation inside Messages. **The user must message Doddy first**; Doddy cannot start a conversation.

## Read before applying: Apple's requirements
1. **Apple-approved Messaging Service Provider (MSP).** A business cannot connect to the channel directly.
2. **Live human agents during business hours.** Apple's documentation requires an asynchronous messaging platform staffed by live agents during business hours. Bots must be able to hand off to agents. An AI-only Doddy does not meet this as described.
3. Becoming our own MSP ("custom platform") is a separate, strictly reviewed application. It needs:
   - intent-based routing;
   - a channel connector to Apple;
   - a live-agent console;
   - bot-to-agent handoff.
   That is weeks of work. **Not recommended for now.**
4. Commercial accounts with no activity for about 3 months may be deactivated (third-party report).

Requirements above were taken from Apple Business Register documentation and MSP guides, searched 2026-10-10. Re-check them at register.apple.com before submitting.

## Steps (owner)
1. Decide who answers as the **live agent**: you or a support person, with set hours. Without this the application is likely to be rejected.
2. Pick an approved MSP that supports bot-to-agent handoff and has an API Doddy's server can reach. Ask each MSP about:
   - EU data residency;
   - price per conversation;
   - whether an AI-first assistant is acceptable to Apple.
3. Sign in at **register.apple.com** (Apple Business Register) with a 2FA Apple Account and do these in order:
   1. Create the organisation profile.
   2. Create a Messages for Business account.
   3. Select the MSP (or "Advanced" if the MSP gives a custom configuration).
   4. Add test Apple Accounts.
   5. Wait for the MSP to confirm the connection.
4. Prepare brand assets:
   - logo, colours, display name "Doddy";
   - the use-case description: "personal memory assistant; replies to the user's own questions; human support during listed hours".
5. After approval, add a "Message Doddy" button in the app and on the website linking to the business chat URL Apple issues.

## Engineering after approval (not started)
- MSP webhook → Doddy server → same answer path as voice and text. Memory stays on the phone, so answers need the app's consent model decided first.
- Agent handoff: route to the human console when Doddy is unsure or the user asks.
