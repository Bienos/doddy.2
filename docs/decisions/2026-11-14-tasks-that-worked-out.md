# The owner panel's main number is tasks that worked out per account each week, with its guardrails beside it

- **Date:** 2026-11-14
- **Decided by:** owner chose option C of the research review ("C", 14 Nov 2026: verified tasks per weekly user on the admin Growth tab, extended with value in week 4 and retention from the first success)
- **Status:** proposed in this pull request
- **Replaces:** nothing; adds to `2026-11-09-usage-counts-on-by-default`

## Why
The owner's research packs of 12 Nov 2026 (Research 01 Phase V, Research 02, Research 03; not in the repository) agree on one product metric: count tasks that were finished with a result, per weekly active user, and read retention by value rather than by sessions. Research 01 calls it "verified useful tasks per weekly active user"; Research 03 adds "W4 value retention" (at least one verified success on days 22 to 28) and counting retention from the first successful task as well as from joining. They also say not to optimise message counts, session length or notification counts, and to show guardrails (not sure, failures, undone, declined) beside the number.

The panel already had accounts, cohorts by any use, and each tool's results. What Logbook can tell today is narrower than "verified": `LogbookBuilder.swift` adds `lookedUp`, `done`, `alreadyThere`, `opened` and `shown` into one `done`, so a look-up, an opened app or a BLIK card shown for the person to send counts the same as a reminder Doddy read back.

## Decision
- **Task that worked out:** per tool and day, Logbook's `done` less `undone`, never below zero (`workedOut` in `backend/src/web/owner.ts`). It is named "worked out", not "verified" or "confirmed", and the card says what it includes.
- **The weekly number:** for each of the last 8 calendar weeks (Monday to Sunday, the current week so far), tasks that worked out divided by the accounts that used Doddy that week, to one decimal. Beside it: the share of those accounts with at least one; not sure and didn't work as shares of the tries that ran (said no never ran); undone as a share of done; said no as a share of everything asked. A share with nothing to divide by is shown as a dash, never 0.
- **Value in week 4:** for each join cohort, of the accounts whose days 22 to 28 after joining (the joining day is day 1) are over, how many had a task that worked out on one of those days. An account whose window is still open is in neither number.
- **Retention from the first task that worked out:** accounts grouped by the week of their first task that worked out, looked for in every day Logbook keeps (365 days), and the share with another one in each week after. It needs Logbook only, so it shows without Supabase's account list.
- Nothing new is collected: everything comes from the counts the iPhone already sends.

## Consequences
- The owner gets one number that rises only when Doddy's tools end with a result, and sees at once when it rises together with not sure, failures or undo.
- The number overstates confirmed work by the look-ups, opened apps and cards in `done`. Counting changes confirmed by read-back separately needs a new Logbook count from the iPhone. The server's Logbook schema refuses unknown fields, so the server must accept it and be deployed before any iPhone sends it: a separate pull request, then a deploy of `doddy`, then the app change.
- The overview reads every kept Logbook day instead of the last 8 weeks, the same range `/v1/web/owner/accounts` already reads. Fine at today's number of accounts; worth a look if the panel slows.
- Privacy: no new data leaves the iPhone. The panel is owner-only, as before (`2026-11-14-owner-panel-fresh-sign-in`).

## Evidence
- Run: backend type-check and `backend/test/owner.test.ts` (21 tests, 3 new; two deliberate breaks of the week-4 window and of the range read were each caught by a test); web type-check, `web/test/adminLogic.test.ts` and `web/test/adminPage.test.tsx`; `npm run fixtures:owner` regenerated `contracts/web/owner-overview.json`. The `scripts/ci.sh` groups that were run are listed in the pull request.
- Not run: the live site, the live database, any iPhone.
