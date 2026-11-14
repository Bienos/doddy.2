# Price alerts get a screen in Shopping, shown only while the server keeps them; an alert only tells

- **Date:** 2026-11-14
- **Decided by:** owner ("You do", 14 Nov 2026, to the agent's offer to build the app side of the price watch he asked for on 13 Nov: "leaflet results … muszą mieć też to drugie")
- **Status:** accepted
- **Replaces:** nothing. Adds the app side of decision `2026-11-13-leaflet-results-and-deal-watches` (the server's deal watches, live since 13 Nov 2026 and off until `DEAL_WATCHES_ENABLED=1`).

## Why
The server can keep "tell me when butter is under 5 zł" and check it against the leaflet catalog (decision `2026-11-13-leaflet-results-and-deal-watches`), but the app had no way to make, see or delete one, and a tapped `deal-watch` push opened nothing special. The owner asked for the price watch to be done "well, graphically and with animation, but easy to grasp".

## Decision
1. **A "Price alerts" row on Shopping** (under "Shops by kind") opens a sheet: the alerts the server keeps for this account, one card each (the words, the price or "any price", the shops, when it ends, what it found since, when it was last checked), "Add an alert", Delete (after a confirmation), and "In the leaflets now" for one alert.
2. **The row appears only once the server has answered the list** (`GET /v1/deal-watches` 200). While the server says `503 deal_watches_disabled` (today), or the app has no account yet, nothing about price alerts is on screen and nothing is stored on this iPhone. The owner turning the server switch on is what makes the row appear.
3. **Nothing is claimed that the server didn't say.** An alert is "saved" only after a 201 whose body was read; what it found is the server's count; what matches now is read from the server's catalog each time the screen opens, only the item itself, cheapest first, never a "similar" product. A make whose answer never came back (or a 201 that can't be read) says the alert may exist, reads the list again, and is not made again by itself (DOD-08). A delete that finds the alert already gone counts as deleted. Every refusal says whether anything was saved.
4. **What was there already is said to be known.** After "Save the alert" the screen lists what already matches and says the owner will be told only about new offers, because the server never pushes those.
5. **A chain read only in part is said** ("a cheaper offer may be on a page I haven't read"), on the saved card and on the matches.
6. **Words and limits live in DoddyCore** (`DealWatchesClient`, `DealWatchWords`, Polish and English, Polish plurals), where Linux tests hold them. The screens show them; the model is `PriceAlertsModel` (type-checked on Linux with the other app logic).
7. **A tapped `deal-watch` push opens Shopping on Price alerts** (`ServerPushKind.opensShopping`, `ShortcutRouter.priceAlertsOpened`, Home and Shopping take the request once). The push carries only its kind.
8. **Connections paused** (Settings): nothing is sent, the list isn't asked for, and the screen says so.
9. **Privacy:** Settings › Privacy has a new row, `dealWatches`; `docs/legal/PRIVACY_POLICY_DRAFT.md` section 5.17 has the matching row, and 9.1 the retention. The policy is still a draft and unpublished: the owner reviews it before switching alerts on (owner queue 66).
10. **Nothing is bought, nothing goes to a shop and no model is involved**: an alert only tells.

## Consequences
- Switching alerts on is the owner's: `DEAL_WATCHES_ENABLED=1` on `doddy-messaging`, after the policy line is reviewed. Until then the feature is invisible.
- **Gap, not built:** the screen doesn't check whether notifications are allowed for Doddy, and doesn't ask. With them off, matches are in the app only, and the server's push is simply not delivered. A later change can say so on the form.
- Opening Shopping asks the server for the alert list (with the device token, no words) once the account exists. With the feature off the answer is a 503 and nothing more happens.
- An alert is shown with the end date the server set (60 days by default); the app doesn't hard-code it.

## Evidence
DoddyCore tests on Linux (`make test-core`: 3,345, 0 failures; new: `DealWatchesClientTests`, `DealWatchWordsTests`, a `DataFlow` row test), `scripts/typecheck_app_logic.sh` (47 app files, including `PriceAlertsModel.swift`), `swiftc -parse` on every app file changed, `scripts/check_forbidden_capabilities.sh`, `scripts/ci.sh --only checks`. **Not compiled here:** the SwiftUI views (`PriceAlertsView`, `PriceAlertForm`, `PriceAlertMatchesView`, the Shopping, Home, Root and router changes). **Not seen on a device**, and no real alert was made: the server has them off. To check on a phone, with the server switch on: the row appears; an alert with a price saves and shows what is there now; it ends on the date shown; Delete removes it; a `deal-watch` push opens Price alerts; with Connections paused nothing is sent.
