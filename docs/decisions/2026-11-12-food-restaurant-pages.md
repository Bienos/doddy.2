# By voice, Doddy opens the restaurant's own page on the delivery app, not the app's front page

- **Date:** 2026-11-12
- **Decided by:** owner, 12 Nov 2026: "But I want it do do more than open app", then "Both and merge" (this is the first of the two; the second is `2026-11-12-food-by-phone`).
- **Status:** applied in the pull request that adds this file.
- **Extends:** `2026-11-12-food-by-voice`.

## Why
Opening Wolt's or Glovo's front page leaves the person to find the restaurant themselves. A search result already names the restaurant's own page on the app; opening that page lands the person on its menu.

## Decision
1. **Order pages in search results.** `backend/src/tools/foodPages.ts` recognises a restaurant's page on Uber Eats, Wolt, Glovo, Bolt Food or Pyszne.pl in web results and in a place listing's links, exactly as `bookingPages.ts` does for salons: https only, the platform's own host or a subdomain, no sign-in details or port, a path beyond the front page; the query and fragment are dropped. Doddy reads it as `order page (Wolt): <address>` with a note that nothing was ordered and no price, menu or time may be stated from it.
2. **`open_food_app` takes `page`**: only an address a result gave as an order page for that same app; never made up or changed. The iPhone checks it again (`FoodApp.page`, same rules) because it came from web content. A page on another app's host, or anything that fails the check, is **refused, not ignored**, so a card never names one app and opens another.
3. **The card says where it lands:** "Opens this page: wolt.com/pl/pol/warsaw/restaurant/sushi-kushi" before the tap; only the tap opens it. The agent is told the app opened on the restaurant's page and that nothing was ordered.

## Consequences
- Still a handoff: the person chooses, pays and orders in the app; Doddy can't see whether they did.
- It works only when a search result carries the restaurant's page on a delivery app; otherwise the app's front page opens, as before.
- Place listings' link fields aren't confirmed against Monid's live answers; web results carry the same pages. The field names read are in `listingFoodPage`.
- The backend change reaches the voice agent only after the next `doddy` deploy; the app change after the next app build; the live agent's tool needs the `page` argument added with the tool (OWNER_QUEUE 46).

## Evidence
`backend/test/food-pages.test.ts` (5: each platform, lookalike hosts and credentials refused, listing fields, web results, the tool's app list equals the platforms); `FoodHandoffTests` (3 more: page rules and cleaning, card and opening, another app's page refused); `voice_agent_spec.py check`. Not compiled: `VoiceSessionController.swift` (one changed line). Not tried by voice, and not against Monid's live results.
