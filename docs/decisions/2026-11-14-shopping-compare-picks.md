# A shopping result's picks can be compared side by side, and only the code says which is lowest

- **Date:** 2026-11-14
- **Decided by:** owner, 13 Nov 2026 (Polish, walking through the app): "wyszukujesz, porównujesz, zawsze wyskakuje kilka opcji … porównywanie dogłębsze". Asked for by the owner on 14 Nov ("Compare view build"). The layout and the rules below are the implementation's proposal, for owner review.
- **Status:** proposed in this pull request (built by CI; not seen on a device).
- **Extends:** `2026-11-13-shopping-by-kind` (which left the Compare view out); `docs/implementation/SHOPPING.md` 3. It replaces nothing and changes no server contract.

## Why
A shopping task returns up to three picks, each on its own card. The owner wants to put them against each other: price, shop, how the price was found, delivery, why each was picked. The earlier attempt (#411, closed) did this on a result screen that has since changed; this one adds only one row and one sheet to the result as it is on `main`.

## Decision
- **Where:** a "Compare the picks side by side" row in the result's summary, shown only when two picks or more have their offers in the result (`ShoppingComparison.isOffered`). It opens `ShoppingCompareView`, a sheet.
- **What a card holds:** the pick's role, the offer's title and price, "N more than the lowest" when it isn't the lowest, "N over your budget" (the server's figure), the shop, where the price was read and when, the delivery text the source gave, Doddy's short notes, the reason and the trade-off, "Watch the price" (existing `WatchPriceButton`, only for a price read on the shop's own page) and "Buy at …" (Safari, existing `ShopPage`, partner-link line when there is one).
- **Code, not a model, compares** (`ShoppingComparison`, DoddyCore): the lowest price and the gaps are integer sums over the prices the server's code registered. A pick is marked lowest only when there are two picks or more, all in one currency, and the prices aren't all equal; two picks at the lowest price are both marked. With mixed currencies nothing is marked and the sheet says so. Prices are never converted.
- **No guessing:** a delivery the result doesn't carry reads "Not in the result". The result has no returns policy, so returns are not compared and not mentioned.
- **No new data leaves the iPhone**, nothing is stored, nothing is bought: "Buy at" opens the shop's page in Safari, as on the result card (`scripts/check_forbidden_capabilities.sh`: no web view).

## Consequences
- Easier: seeing why one pick costs more than another without scrolling three cards.
- Harder: nothing on the server; a new sheet to keep in step with the result's schema (`ShoppingOffer`, `ShoppingPick`).
- Not in this change: watched prices by kind of shop, a Compare view over leaflet baskets (`BasketTabs` already compares plans), more shops (they need partner accounts, see `2026-11-13-shopping-by-kind`).

## Evidence
`ShoppingComparisonTests` (DoddyCore, 7 tests) and the SwiftUI sheet are built and run by this pull request's CI, not by the session that wrote them (no Swift toolchain there). `tools/build_strings_catalog.py --check` passes. Nothing seen on a device.
