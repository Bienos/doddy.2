# Voice and chat budgets are shared fairly: a small pool for new accounts, a fair share per account, the web chat on its own

- **Date:** 2026-11-12
- **Decided by:** proposal, owner approval pending
- **Status:** proposed — waiting for the owner. No limit, default or live setting is changed by this file.
- **Replaces:** nothing. Builds on ADR-671 and ADR-712 (voice token limits), ADR-587 (Ask Doddy pools) and ADR-818 (web sign-in).

## Why
- **Shared budgets should be shared fairly.** Voice tokens are counted per account and for the whole service in one Redis script (`hitLimits`, `server/voice-token/src/voice-auth.js`; settings `DODDY_TOKENS_PER_HOUR`, `DODDY_TOKENS_PER_DAY`, `DODDY_GLOBAL_TOKENS_PER_HOUR` in `server/voice-token/src/handler.js`). The aim is that people who use Doddy every day always have room, however the rest of the budget is used.
- **New accounts should start with a smaller allowance.** An account earns the full allowance by being in use for a while. Accounts are keyed by Doddy account (`account:<id>`, `server/voice-token/src/doddy-account.js`), so the voice server can remember when it first saw each one.
- **Web sign-up should be a deliberate choice.** On the web, a Google or Apple account with no Doddy account can make one when `DODDY_WEB_SIGNUP` allows it (`backend/src/config.ts`, `backend/src/web/social.ts`; the owner asked for web sign-up on 3 Nov). The default should be the quieter one, with the owner turning it on.
- **The web chat and Ask Doddy on the iPhone should have separate pools.** Both count their questions in `backend/src/memory/chat.ts` and `backend/src/assist.ts` (`POST /v1/web/chat` is in `backend/src/memory/routes.ts`). Guests already have a pool of their own (`service:ask:guest`, ADR-587); the web chat should too.
- **App Attest is worth knowing as an option**, with its costs and limits, before deciding whether to add it to `/api/voice-token`.

## Decision (proposed)
1. **A small daily pool for new accounts.** The voice server marks the day it first issues a token to an account. For the first 7 days the account draws from a pool for all new accounts together (proposed 100 tokens a day), with 10 a day each. After that, the normal limits apply. Accounts seen in the first week after the deploy count as established, so current testers stay where they are.
2. **A fair share per account within the hourly budget.**
   - The hourly budget for everyone stays as the ceiling. Once it is half used in an hour, an account that already had 10 tokens that hour is refused (`limit: fair_share` in the log). The app sees the same `rate_limited` with `Retry-After` as for the other limits.
   - A daily ceiling for the whole service is added (`DODDY_GLOBAL_TOKENS_PER_DAY`, proposed 600) as a bound on cost.
   - All of it stays in the one script, counted only when a token is issued (ADR-671).
3. **Web sign-up off by default.** `DODDY_WEB_SIGNUP` defaults to `off`. A Google or Apple account then signs in on the web only to an account that already exists. The owner sets `open` on purpose when new accounts should be made on the web.
4. **The web chat gets its own pool.** `POST /v1/web/chat` counts against `service:web_chat` (`DODDY_LIMIT_SERVICE_DAILY_WEB_CHAT`, proposed 200 a day) instead of `service:ask`. One person's daily total stays shared between iPhone and web (`user:<id>:ask`), so using both doesn't double it.
5. **Option, not proposed for now: App Attest on `/api/voice-token`.** The app proves once per install, through Apple, that its key lives in a genuine copy of Doddy on a real Apple device (`DCAppAttestService`). After that it signs each token request with that key, and the voice server checks the signature and a counter.
   - **Costs:**
     - a new entitlement for the Beta and the production bundle ids;
     - server code that checks Apple's attestation and certificate chain, and keeps a key and a counter per install in Redis;
     - one extra request at first use;
     - a choice of what happens when Apple's service can't be reached;
     - a test path, because the Simulator can't attest: only Debug builds against a non-production server accept it.
   - **What it does not prove:** who the person is, or that a person is behind each request. It doesn't limit how much a genuine app uses (the limits above do that), and it doesn't cover the web.

## What the owner decides
1. Yes or no to each of 1 to 4, and the numbers: 100 a day for new accounts together, 10 each, 7 days; the fair-share line at half the hour and 10 per account; 600 a day for everyone; 200 a day for the web chat.
2. Web sign-up: off by default (this proposal), which changes the owner's own 3 Nov choice, or left open.
3. App Attest: later (proposed), now, or not at all.
4. The values on Vercel (`doddy-voice-token`) and Render (`doddy`), set by the owner after the merge. Nothing has to be set for the defaults to apply.

## Consequences
- A new person gets fewer voice conversations in their first week, and a heavy user is refused sooner while the service is busy. The refusal is the same "try again later" the app already shows (ADR-712).
- People already using Doddy keep their room when many new accounts arrive at once, and web chat questions and iPhone questions no longer draw from one pool.
- One more Redis key per account (the first-seen day, no content). The new-account pool and the fair-share rule need tests in `server/voice-token/test/handler.test.js` against the same fake store.

## Evidence
- Read: `server/voice-token/src/handler.js`, `server/voice-token/src/voice-auth.js`, `server/voice-token/src/doddy-account.js`, `server/voice-token/README.md`, `backend/src/config.ts`, `backend/src/web/social.ts`, `backend/src/assist.ts`, `backend/src/memory/chat.ts`, `backend/src/memory/routes.ts`, `Packages/DoddyCore/Sources/DoddyCore/Account/DoddyAccount.swift`, `DoddyApp/Features/Voice/VoiceTokenClient.swift`.
- Not run: nothing against the live services; no live setting was read.
