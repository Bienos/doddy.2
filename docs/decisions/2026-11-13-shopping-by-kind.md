# Shopping gets five kinds of shop under its one field, each with its own page

- **Date:** 2026-11-13
- **Decided by:** owner, 13 Nov 2026 (Polish, walking through the app): "w ogóle tych wszystkich [sklepy] trzeba jakoś oddzielić: jedzeniowe osobno, ciuchowe, inne … wyszukujesz, porównujesz, zawsze wyskakuje kilka opcji, … ustawienia cen, szukanie okazji, może podłączyć jeszcze jakieś sklepy". The five kinds, the shop-to-kind mapping and the page layout are the implementation's proposal, for owner review.
- **Status:** proposed in this pull request (compiled by CI; not seen on a device).
- **Extends:** `2026-11-13-shopping-one-field` (the one routed field, #407 and #423, stays exactly as it is); `2026-11-13-feature-screens-in-doddys-colours` (the kit and the Shopify screen are #416's). It **does not** replace anything.

## Why
`main`'s Shopping screen already has one routed field and the leaflet answer as three tabs, but every shop is still one heap. The owner asked for the food shops, the clothes shops and the rest to be told apart, with more to do in each. An earlier attempt (#411) redrew the whole screen and clashed with #407; this one only adds to it.

## Decision
- **Five kinds** (`ShopCategory`, DoddyCore): groceries and household, fashion and shoes, electronics, home and garden, other. Every leaflet chain has one kind (`DealsChain.category`): supermarkets, discounters, Żabka and the drugstores are groceries; CCC and Deichmann fashion; Komfort and Action home; Maxi Zoo, zooplus and any chain this app doesn't know other. Shopify's catalogue is listed on every kind but groceries.
- **Five tiles** ("Shops by kind", `ShopKindsSection`) under the one field open a kind's page (`ShoppingCategoryView`):
  - a field for the kind. Groceries: the items go to "Cheapest this week" and the leaflets are checked at once (`DealsView(start:)`, as the one field sends them). Every other kind: "Find me this" behind the same yes card (DOD-07), with the kind added as one line under the words ("Kategoria: …" / "Category: …", `ShopCategoryRequest`), so the card shows it and the digest covers it; no new field, so the server, the digest rule and the voice path are unchanged;
  - groceries also get the way into "Cheapest this week";
  - the shops by name with what Doddy does at each (`ShopDirectory`: the leaflet chains and Shopify's catalogue; nothing Doddy can't reach), and the Shopify row for every kind but groceries.
- **Not in this change:** the Compare view for a result's picks and the watched prices by kind (they needed changes to the result and watch screens that #407 and #423 were also changing); each can follow on its own.

## Consequences
- Nothing new leaves the iPhone except the kind's line in a scoped task's words (shown on the yes card; the page's fine print says where the words go).
- **More shops, what each needs (not built; owner decision):**
  - *Any Shopify shop by its address:* the server's search schema takes only `query`; scoping to one shop needs a server change and checking whether Shop MCP filters by shop (not verified).
  - *Allegro:* the official REST API (developer account, OAuth app, the owner's acceptance of its terms). Today Allegro is a "Search further" link only.
  - *Ceneo:* a partner/affiliate feed (the owner's agreement). Today a link only.
  - *Zalando, x-kom, Media Expert, RTV Euro AGD, Empik, Castorama/Leroy Merlin:* no public product API for third parties; an affiliate-network feed after the owner joins one, or their leaflets through a new server adapter where they publish one. Until then "Find me this" reaches them through Google Shopping and their own pages.
  - No scraping is built for any of them (constitution: no getting around a shop's rules).

## Evidence
`ShopCategoryTests` (DoddyCore, 9 tests) and the two SwiftUI files are compiled and run by this pull request's CI. `tools/build_strings_catalog.py --check` passes. Nothing seen on a device.
