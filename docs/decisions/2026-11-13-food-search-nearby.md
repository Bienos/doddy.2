# Home › Food also lists the places near a typed address, from Apple Maps, and hands one to the delivery apps

- **Date:** 2026-11-13
- **Decided by:** owner, 13 Nov 2026 (Polish, walking through the app): "Jedzenie … kolor Dodiego musi być i … to ma być bardziej pole do zamawiania, że na przykład ja mówię, że chcę burgera i to mi pokazuje burgery z różnych tych, najbliżej mnie z tych wszystkich apek, gdzie jest najtaniej, albo … takie pole, gdzie ja sobie mogę sam zamówić i on mi to sam zamówi … potem może … będzie miał swój portfel". The honest scope below (no prices, no ordering) is the agent's, for owner review.
- **Status:** proposed in this pull request (not compiled until CI builds it).
- **Extends:** `2026-11-13-feature-screens-in-doddys-colours` (Food's hero, field, quick picks and the app rows stay as #416 made them; this adds the "Near you" section under them) and `2026-11-11-food-button`; `2026-11-12-food-by-voice` is unchanged.

## Why
The owner wants to say "a burger" and see burgers near them across the delivery apps, cheapest first, and later have Doddy order and pay. None of the five apps (Uber Eats, Wolt, Glovo, Bolt Food, Pyszne.pl) publishes a menu, price, fee or availability API for a person's own account, or a search address (`2026-11-11-food-button`, `2026-11-12-food-by-voice`). Apple Maps does answer "burger near this point" on the iPhone, with no Doddy server and no key.

## Decision
1. **A typed delivery address** under the hero, once the person has said what they feel like (the hero's field or a quick pick; the word in the app's language is what's searched). No location permission is asked for; the address is kept on the iPhone (`food.deliveryAddress`, UserDefaults) until the person taps Clear.
2. **Apple Maps only:** the address is located with the same search as a place reminder; then `MKLocalSearch` for the dish around it, points of interest only, restaurants, cafés and bakeries (`PlaceLocation.foodPlaces`, in Connections as the capability guard requires). `FoodSearch` (DoddyCore) keeps food places with a name and a real position, within 10 km, nearest first, each once, at most 15.
3. **Each place:** name, straight-line distance, kind, address; **Order in…** (a menu of the five apps: copies the place's name, this iPhone only and gone after two minutes like every Doddy copy, ADR-724, then opens the app's front page, its app if installed); **Call them** only when Apple Maps lists a plain number (`FoodSearch.callURL`; no pauses, `*`, `#` or letters; iOS asks before calling); **Maps** (Apple's place card).
4. **No search address is built for any app.** The only pattern found (Wolt's `/{country}/{city}/search?q=`) is reported by third-party scrapers, not Wolt, and needs Wolt's own city slug; it isn't used.
5. **Said on the screen:** prices and delivery fees are only in the apps, so Doddy can't say where it's cheapest; Doddy doesn't order or pay, and ordering for you needs a wallet or card that isn't built. Fine print: the dish and address go to Apple Maps only, nothing to Doddy's server. The privacy page's Apple Maps row and "stays on this iPhone" list say the same (`DataFlow`).

## Consequences
- A result is a place Apple Maps matched, not proof that it delivers, is open or is on any app. The screen never says otherwise.
- "Delete all memories" doesn't clear the address (it lives in UserDefaults, and that flow is in `SettingsScreens.swift`); the screen's Clear does.
- To make "cheapest" and "Doddy orders" real, each needs an owner decision: a partner API with prices (Uber Eats Consumer API approval; Wolt, Glovo, Bolt and Pyszne have no consumer API), ordering by phone through the order agent (`2026-11-12-food-by-phone`, pay on delivery only), or a prepaid wallet / virtual card (payments provider, legal and KYC, spending caps, and approval bound to the exact order, DOD-07).

## Evidence
`FoodSearchTests` (DoddyCore) ran in CI on an earlier branch of this work (#411, not merged) and passes there; this port runs in CI on this pull request. `scripts/check_forbidden_capabilities.sh` and `tools/build_strings_catalog.py --check`: see the pull request. Not seen on a device.
