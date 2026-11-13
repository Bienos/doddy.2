# Shopping has one field that code routes to the leaflets, to online shops or to both, and the leaflet answer has three tabs

- **Date:** 2026-11-13
- **Decided by:** owner, 12–13 Nov 2026: the review `docs/strategy/PRZEGLAD_APLIKACJI_2026-11-12.md` (sections 1.5 and 1.6, item 3 "Aplikacja: jedno pole w Zakupach, trzy zakładki odpowiedzi, „Szukaj w sklepach internetowych” przy pustym wyniku"), then "Wszystko dawaj"
- **Status:** applied in the pull request of branch `claude/shopping-one-field-three-tabs`
- **Replaces:** the "Find me this" card at the top of `ShoppingHubView` (SHOPPING.md, "Shopping in one place"), the "Where it's cheapest" card and the separate "Basket" screen of `DealsView` (decision `2026-11-10-cheapest-this-week-simpler`, section "Answer"). The rules behind them don't change.

## Why
Shopping had two ways in with different words: "Find me this" (online shops, a background task) and "Cheapest this week" (the leaflets, at once). A person who typed "słuchawki Apple" into the leaflets got a true "nothing matches" and links only (review 1.4); groceries typed into "Find me this" became a slow errand. The basket, which the owner wants as "where do I go", was a screen behind a button.

## Decision
- **One field** at the top of Home › ••• › Shopping: "What do you need?" with "From my list". `ShoppingRoute` (DoddyCore, pure, tested on Linux) decides where the words go, and the card says it before the tap, with "Change" to pick the other place:
  - everyday things (food, drinks, household and drugstore goods, nappies, pet food): "Cheapest this week" opens with them and checks the leaflets at once (`DealsView(start:)`, the same request and model as before);
  - a thing to compare online (electronics, appliances, furniture, bikes, prams): "Find me this", with "What matters most?" and the **same yes card** (`TypedHandOverSheet`, constitution DOD-07); several such things are offered one tap each, each behind its own card;
  - things in between (shoes, small appliances, clothes, kitchen and home goods, tools, toys): the leaflets now, and "Search online shops for …" under the answer;
  - a product link: the "Check this" card, which still asks for its own tap.
  The word lists follow the server's `specialty.ts` and `categories.ts` and are written by hand; the longest known phrase decides ("tabletki do zmywarki" is everyday, "zmywarka" online, "ekspres do kawy" online). An item no list knows goes to the leaflets first; a budget ("do 2000 zł"), a size to compare ("55 cali"), a model ("XM5") or an electronics brand makes it online. A part after a comma that only qualifies the item ("z ANC", "do 400 zł", "rozmiar 4") stays with it; a budget isn't sent to the leaflets.
- **The leaflet answer is three tabs** (`BasketTabs` in DoddyCore, every amount from `BasketSolver` in grosze):
  - **One shop**: the solver's best single chain, its total, "Missing: X", "Before you go" and the list to share;
  - **Two shops**: only when the solver offers a pair (more items, or a saving of at least the person's own minimum, ADR-664). Otherwise the one-shop tab says why ("wouldn't save anything", or "would save X, less than your minimum of Y"), and the minimum can be changed under every tab;
  - **Each item separately**: per item its cheapest line for the quantity asked and the other shops' lines in one line under it (`BasketSolver.options`, whose first lines are exactly "everything at its cheapest"), and the total of everything at its cheapest. One item shows only its row.
  The kind picked on an item's card ("kawa" → "mielona") now narrows the tabs too (`DealsResult.narrowed`).
- **The row and the card:** the row is the basket's cheapest line (the price for the quantity); the item's card keeps the best value per kg, "Why this one", similar products and promotions, and now lists **every other offer in full** (conditions, "Until …", reminders, leaflet page) where it showed three in one line.
- **"Search online shops"** after a leaflet answer (`ShoppingRoute.onlineNext`): for things in between, things for online shops, and an unknown item with no offer and no promotion. Never for groceries. A button prepares the same typed shopping task and opens the same yes card; nothing is sent before "Yes, go"; a start the server didn't confirm keeps its button off.
- **Not changed:** the server, the leaflet request and its limits, matching and picking on the server, the errand request, digest and approval, the partner-link wording, "Check this", watches, Shopify, the voice tool `find_deals` and its description.

## Consequences
- The routing is a guess by word lists, said on screen before anything happens; a wrong guess costs one tap on "Change". A missed word means the leaflets are asked first, which is free and quick. Leaflet checks still count against the day's limit.
- "Each item separately" ranks by the price for the quantity asked, like the other two tabs, so the three tabs add up; the best value per kg stays on the item's card. An item can show a smaller pack in the row than the card's best-value pick.
- No new data leaves the iPhone: the leaflet request and the errand are the same requests as before, sent at the same taps.
- Voice (owner, 13 Nov 2026: "Find me this"): `find_deals`'s reply, which the app writes, ends its data with "Online shops next" for the same things the screen offers (`ShoppingRoute.onlineNext`, at most three; never everyday groceries), asking Doddy to offer once, in one short line, to look in online shops in the background, and to use `hand_over_errand` with kind `shopping` if the person wants it. Its own card still starts it only on their tap (ASK-01). The live agent's prompt and `voice-agent/tools.json` are unchanged (`DealsResultText.onlineNextLine`).

## Evidence
`make test-core` on Linux (Swift 6.1.2) with the new `ShoppingRouteTests` and `BasketTabsTests`; `swiftc -parse` on every changed app file; string catalogs `--check`; `scripts/ci.sh --only checks`; `scripts/typecheck_app_logic.sh`. **Not compiled:** the SwiftUI views (no Xcode here); nothing was seen on a device; the UI test that opens the basket was updated but not run.
