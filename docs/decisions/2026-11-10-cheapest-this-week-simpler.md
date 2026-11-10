# "Cheapest this week" asks one question and answers with one card: item → price → shop

- **Date:** 2026-11-10
- **Decided by:** owner (Pat, 10 Nov 2026): "to musi być takie bardziej prostsze, że na przykład ja mówię, potrzebuję mleko to i to, znajdź mi, ile to kosztuje i wtedy dostaję informację, na przykład właśnie w jakim sklepie co kosztuje … w brandingu Dodiego"; then "zrób nowy ekran też"
- **Status:** applied in the pull request of branch `claude/fervent-turing-2cd8ae`
- **Replaces:** the layout of `DealsView` (SHOPPING.md 2, ADR-661 to 668). The rules behind it don't change.

## Why
The first screen opened with a text field, about twenty shop switches and a loyalty-app list; the answer was a long Form of sections. The owner couldn't tell how to use it.

## Decision
- **Ask:** Doddy (`WholeDoddy_kneeling_inspect`, from the owner's pack) and "What do you need?"; the items are chips (comma or Return adds one, × removes it); examples to tap while it's empty; "From my list"; a line saying the same works by voice. One button, "Check prices".
- **Shops:** a line under the button ("14 shops' leaflets · Change") opens a sheet with My shops, the leaflets to check and My loyalty apps. Same preferences and identifiers (`deals.myShops`, `deals.program.*`).
- **Answer:** "Where it's cheapest", one card: for each item its best-value pick (`BasketSolver.bestValue`, unchanged), the product, the shop, the price, the price per unit, "+N other shops", the condition or "Check the leaflet" when Doddy couldn't confirm it. A tap opens the item's page with everything the old section had (pick and its conditions, why this one, the others, similar, promotions, the kind picker, reminders, the leaflet page link, partner-link notice). The basket button follows the card. What wasn't checked (items left out, leaflets read in part, chains not read) is one collapsed group; "Search further" is a card.
- **Not changed:** the server, the request, the matching and picking rules, what is sent, the partner-link wording (ADR-612/668), the honesty lines.

## Consequences
- The screen still only works where it is switched on: it is hidden in Release builds (`ReleaseScope.shipping`, `.deals`) and the messaging server has `DEALS_ENABLED=0` (render.yaml). Turning it on is a separate owner step.
- The voice tool `find_deals` is on the live agent (read 10 Nov 2026), so "Doddy, how much is milk?" is the same search.

## Evidence
`swiftc -parse` on the file: OK. String catalogs: PASS. Not compiled (no Xcode here): the hosted Mac job builds it and runs `ScreenFixtureTests` (deals, basket). Not seen on a device.
