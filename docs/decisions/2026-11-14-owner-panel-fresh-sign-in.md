# The owner panel needs a recent browser sign-in and leaves a record; chats stay in the tab

- **Date:** 2026-11-14
- **Decided by:** the owner asked for this hardening of Doddy Web; the numbers below (15 minutes, 365 days, chats in the tab) are the agent's proposal inside that request, owner review pending
- **Status:** applied in the pull request that adds this file
- **Replaces:** the "either" access of `GET /v1/web/owner*` in decision `2026-11-09-usage-counts-on-by-default`; ADR-604's "chats in this browser's localStorage"

## Why
- The owner panel lists every account's email, name, sign-in method and last sign-in. Until now any session of an owner account could read it, the iPhone's own session or any browser however long ago it signed in, and nothing recorded who looked.
- The chat's list was kept in `localStorage`: the questions, Doddy's answers and the full text of the notes and conversations cited as sources. It survives closing the browser, so on a computer someone else uses next it stays on the disk until a Sign out that may never come.

## Decision
- **Panel, who:** the panel's four routes are for a browser session only (`access: "browser"`); the iPhone's session gets 401 on all of them.
- **Panel, how recently:** the three routes that show data open only if the browser signed in within `OWNER_FRESH_MS` = **15 minutes**. Same window as deleting the account or changing sign-in methods from a browser (`LINK_REAUTH_MS`), so there is one rule to explain: "a sign-in within the last 15 minutes". It counts from the sign-in, not from the last click, so a copied or forgotten session stops opening the panel soon after it was made. A later request gets 422 `refused` with a plain sentence; the page shows it, hides what was on screen and offers Sign out. Apple, Google and code sign-ins all make a new session, so any of them makes the panel open again. `GET /v1/web/owner` (is there an Admin link?) returns no data and has no time limit.
- **Panel, the record:** each use that shows data writes one row to `owner_audit` first: time, the owner's account id, the browser session id, one of `overview`, `accounts`, `account_logbook`, and for the last the account whose Logbook was opened. The table has no column for an email, name, count, word or credential. If the row can't be written, nothing is shown. A refused request writes nothing, so a stale or foreign session can't grow the table. Rows older than 365 days are pruned by the hourly sweep.
- **Chats:** the list is kept in `sessionStorage` (this tab), not `localStorage`. A reload keeps it; closing the tab or signing out forgets it. Chats an older version left in `localStorage` are moved into the tab if they belong to the signed-in session, and deleted either way, as soon as the page knows who is signed in. Nothing about a chat is written to `localStorage`.

## Consequences
- **A person will notice:** the owner, whose Admin page now needs a sign-in within 15 minutes (with the iPhone's code, Apple or Google) and shows "sign out and sign in again" afterwards; and everyone using the web chat, whose chats no longer come back after closing the tab or the browser. The page says "kept only in this tab".
- The owner reads the record in the database; there is no screen for it. A screen, an alert on odd use, and erasing rows about an account when it is deleted are separate decisions. Today account erasure doesn't touch the table: an erased account's id (an opaque id, no name or email) can stay in a row until the row is pruned after a year.
- `fixtures:owner` now signs in as a browser, because the iPhone's token no longer opens the panel.
- Only what the panel showed is recorded, not refused tries; refusals are visible in the server's request log.

## Evidence
`backend/test/owner.test.ts` (browser only, window edge at 15 minutes and one millisecond after, the record's rows and columns, no content in it, failing closed, pruning) and `web/test/chatPage.test.tsx`, `signOutChats.test.tsx`, `app.test.tsx`, `adminPage.test.tsx` (chats in the tab, nothing in `localStorage`, moving and deleting what an older version left, the sign-in-again page in English and Polish). The web end-to-end run (real backend, Chromium) was run with the browser pointed at the one installed here: 16 passed, 4 skipped, and 2 failed in "a deck made on the iPhone is downloaded", which fails the same way on an unchanged `main`. It has no test for the Admin page, so the panel's window and the sign-in-again page are tested in jsdom against stand-in replies, not in a browser. Not run: the live site, a real Apple or Google sign-in.
