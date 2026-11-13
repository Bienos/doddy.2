# Shopping opens on five kinds of shop; the leaflets and "cheapest this week" are one screen; picks can be compared

- **Date:** 2026-11-13
- **Decided by:** owner: "Zakupy … trzeba trochę poprawić. 'Zakupy najtaniej w tym tygodniu' — przecież to wszystko jest połączone [z gazetkami], to trzeba złączyć albo zaproponować w jakiś ciekawszy sposób. Shopify — ten sklep Shopify trzeba zrobić redesign w środku; w ogóle tych wszystkich [sklepy] trzeba oddzielić: jedzeniowe oddzielnie, ciuchowe oddzielnie, inne oddzielnie […] wyszukujesz, porównujesz, zawsze wyskakuje kilka opcji, porównywanie dogłębsze, ustawienia cen, szukanie okazji, może podłączyć jeszcze jakieś sklepy". The five kinds, the shop-to-kind mapping and the screen layout are the implementation's proposal.
- **Status:** proposed (on a branch; not compiled)
- **Replaces:** the layout of `ShoppingHubView` (SHOPPING.md "Shopping in one place") and the top of `DealsView` (decision `2026-11-10-cheapest-this-week-simpler`); their rules don't change.

## Why
The Shopping screen was a list of cards: "Find me this", searches, "Check this", watched prices, then two rows to "Cheapest this week" and "Shopify shops". The owner read the leaflet row as a separate product from shopping, and the shops as one heap.

## Decision
- **Five kinds** (`ShopCategory`, DoddyCore): groceries and household, fashion and shoes, electronics, home and garden, other. Every leaflet chain has one kind (`DealsChain.category`): supermarkets, discounters, Żabka and the drugstores are groceries; CCC and Deichmann fashion; Komfort and Action home; Maxi Zoo, zooplus and any chain this app doesn't know other. Shopify's catalogue is listed on every kind but groceries. "Find me this" and "Check this" work in every kind.
- **A scoped "Find me this"** adds one line to the words ("Kategoria: …" / "Category: …"); no new field, so the server, the digest rule and the voice path are unchanged.
- **This week's deals** is one screen with "Cheapest" and "Leaflets"; on the Shopping screen it is the groceries page's first card.
- **Compare** shows the picks side by side; the lowest price is computed by code from the registered prices, only in one currency.

## Consequences
- Nothing new leaves the iPhone except the kind's line in a scoped task's words (shown on the yes card; the fine print on the kind's page says where the words go).
- **More shops, what each needs (not built; owner decision):**
  - *Any Shopify shop by its address:* Shop MCP's `search_catalog` searches the whole catalogue; the server's schema takes only `query`. Scoping to one shop needs a server change and checking whether Shop MCP filters by shop (not verified).
  - *Allegro:* the official REST API (developer account, OAuth app, the owner's acceptance of its terms; listing search is limited for public apps). Today Allegro is a "Search further" link only.
  - *Ceneo:* a partner/affiliate feed (Ceneo's programme, the owner's agreement). Today a "Search further" link only.
  - *Zalando, x-kom, Media Expert, RTV Euro AGD, Empik, Castorama/Leroy Merlin:* no public product API for third parties; an affiliate network feed (e.g. Awin, Convertiser, TradeDoubler, depending on the shop) after the owner joins it, or their leaflets through a new server adapter where they publish one. Until then "Find me this" reaches them through Google Shopping and their own pages.
  - No scraping is built for any of them (constitution: no getting around a shop's rules).
- **Watch:** the kind of a watch is derived on the iPhone from the task it came from; a watch made from a pasted link has no kind and shows only on the Shopping screen.

## Evidence
Written: `Packages/DoddyCore/Sources/DoddyCore/ShopCategory.swift`, `ShopCategoryTests` (15 tests). Not run: no Swift toolchain in this session, so neither DoddyCore's tests nor the app were compiled; nothing seen on a device.
