# Home's menu gets one "Food" button that lists the delivery apps

- **Date:** 2026-11-11
- **Decided by:** owner: "maybe other button like food as i add other ones as well there" (11 Nov 2026), in answer to an "Open in Uber Eats" button offered as a stopgap until Uber approves ordering access.
- **Status:** applied in the pull request that adds this file. Bolt Food and a voice tool added by `2026-11-12-food-by-voice`, which replaces the "No voice tool" line below.

## Why
Uber's consumer APIs (account linking, ordering) are early access and need Uber's written approval; Wolt, Glovo and Pyszne.pl have no public consumer ordering API either. Until then the owner wants one entry that holds the delivery apps, not one button per provider.

## Decision
- Home's ••• menu (the section with "Cheapest this week") gets **Food**. It opens a sheet with one row per app in `FoodApps.all` (`Packages/DoddyCore`): Uber Eats, Wolt, Glovo, Pyszne.pl. A row opens that provider's own https front page: its app when it is installed (universal link), its website otherwise.
- Adding an app is one line in `FoodApps.all` plus its host in `FoodAppsTests`.
- No search is passed in: the providers don't publish search addresses, and Uber Eats' unofficial one needs a location. Nothing is read, sent or placed by Doddy; no account, no key, no server call.
- No voice tool, and the live voice agent is unchanged (it changes only on the owner's instruction).

## Consequences
- Works today, needs nobody's approval. It can't find a dish or place an order; it only gets the person to the app.
- When Uber approves the 3PL Consumer APIs, ordering is a separate piece (server-held secret, exact order card, DOD-07 tap before anything is placed) and would live behind this same entry.
- Provider names aren't translated; the screen's own two lines are, in all nine languages (drafts, ADR-234).
- Opening a provider's page leaves Doddy; the provider's own terms and privacy apply.

## Evidence
- Ran: `swift test --filter FoodAppsTests` on Linux (4 tests: the four apps in order with their hosts, https only with no query, unique ids, a non-https address is not openable); `python3 -I tools/build_strings_catalog.py --check`.
- Not compiled: the SwiftUI screen and Home's menu (no Xcode here; `ios-build` is the first compile). Not seen on a device: that a row opens the installed app rather than Safari.
