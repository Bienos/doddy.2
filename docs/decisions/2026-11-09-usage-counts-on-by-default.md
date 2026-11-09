# Logbook counts are on by default, and the owner sees every account's counts

- **Date:** 2026-11-09
- **Decided by:** owner, 9 Nov 2026. Asked "what should the owner panel show?", the answer was "sumy + historia kazdego konta ale narazie nie przejmuj sie. ppolityka etc usun to z tego na koinec zrobimy nowa" (totals and each account's history; don't worry for now; the privacy policy etc. comes at the end, we'll write a new one). Asked "who is counted?", the answer was "Włączone domyślnie" (on by default). Earlier the same day: "I użytkownicy też będą mogli dostać dane tej analityki… czy ja mogę mieć… na bazie wszystkich użytkowników" (users get their own analytics, and the owner gets it across all users).
- **Status:** accepted. The iPhone half ships with the pull request that adds this file; the admin dashboard follows in its own pull request.
- **Replaces:**
  - Logbook rule 2 (`docs/product/WEB_LOGBOOK.md`, ADR-602): "Off until the person turns it on in the app" becomes **on unless the person turns it off**. Turning it off still deletes what the server holds.
  - Logbook rule 7: "There is no admin view of anyone's Logbook" becomes **the owner sees every account's counts and their totals**. One person still sees only their own Logbook.
  - The "Not part of this: any owner dashboard across all users" line of `WEB_LOGBOOK.md`.
  - ADR-011's "separately controlled" stays (there is a switch); its "off by default" reading does not.

## Why
- The owner wants usage numbers for every account: what people use, what works and what fails.
- Logbook already had the server and the web page (22 Oct). Only the iPhone half was missing, so no real person had numbers.

## Decision
1. **Counts only, as before.** The day summary's allow-list (`backend/src/web/logbook.ts`) is unchanged: tool ids, note types, language codes and whole numbers. No words, note text, names, places, emails or audio. Private notes and private conversations are not counted.
2. **On by default.** The iPhone counts and sends unless the person turns it off in Settings › Doddy on the web › Logbook. Turning it off:
   - stops counting at once;
   - asks the server to delete the days it holds, and says "deleted" only after the server confirmed (DOD-08);
   - if the server can't be reached, asks again at the next sync.
3. **What the person is told.** The switch's footer and the web page say that Doddy's team can see the counts with the account. A switch that shared data without saying so would be a hidden transfer.
4. **The admin dashboard** (own pull request): a separate page at `/admin`, outside the workspace menu, in its own code chunk. It shows totals across all accounts, what works and what doesn't, who is active, retention, and each account with its sign-in method, email, dates and own days. It is owner-only, with an allow-list of account ids set on the server (`DODDY_OWNER_ACCOUNTS`), never in the repository; everyone else is told "not found". Only one person sees their own Logbook page. Owner's words, 9 Nov: "osobny dashboard jako admin... tylko ja mam dostęp", "weź te analityki ładniej pokaż... powymyślaj co jeszcze się przyda".
5. **The privacy policy is rewritten at the end** (owner). Until then:
   - the published draft says "The app has no analytics", which is no longer true;
   - App Store and outside testers must wait for the new policy and the matching App Store privacy answers ("Usage Data, linked to you, analytics");
   - this is OWNER_QUEUE 26.

## Consequences
- Every signed-in iPhone on a build with this change sends counts: up to 8 days the first time (the last week and today), then today at most once an hour and each day once more after it ends.
- The owner can see who uses what. This is personal data under the GDPR even without words, and the hour-by-hour pattern shows when someone is awake. The legal basis and the wording are the owner's to settle with the new policy (`legal_review_required_before_launch` in `doddy_rules.yaml`).
- `cross_user_isolation` still holds between users. The owner allow-list is the one exception, and it is the owner's own access.

## Evidence
- `Packages/DoddyCore/Sources/DoddyCore/Logbook/`:
  - Linux tests: `LogbookTests`, 10, and `LogbookModelTests`, 7.
  - A day built by the Swift code was checked against the server's own `DaySummarySchema` and `parseDaySummary` (Node 22, the backend's built `dist/src/web/logbook.js`): accepted.
- `web/`: `npm run typecheck`, `vitest run` (143 pass).
- Not run: the iPhone app build (no Xcode here; the pull request's `ios-build` job is the first build), a device.
