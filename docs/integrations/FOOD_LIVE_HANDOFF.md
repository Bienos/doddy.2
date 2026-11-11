# Food delivery — first real integrations (provider handoff + Apple Maps)

**Built 2026-11-11, review branch only; not deployed. NO DEMO.**

## Exactly what works after merge/build

On iPhone/iPad, Home → ••• → **Order food / Zamów jedzenie** opens a native sheet. It offers five **real, official consumer websites**; tapping opens the provider in iOS using an HTTPS Universal Link/browser. The user signs in and places/pays for the order **in that provider**, not Doddy.

- Uber Eats → https://www.ubereats.com/pl/near-me (real provider location picker).
- Glovo → https://glovoapp.com/pl/pl/warszawa/categories/jedzenie_1 (real Warsaw restaurants).
- Wolt → https://wolt.com/pl/pol/warsaw (real Warsaw listings).
- Pyszne.pl → https://www.pyszne.pl/ (real address picker).
- Bolt Food → https://food.bolt.eu/ (real ordering website, JavaScript required).

**Verified official web destinations as of 2026-11-11**. iOS Universal Link behavior, provider sign-in and actual order checkout must still be checked on a real iPhone. Any URL change requires fresh source verification.

The sheet also supports **real Apple Maps restaurant lookup** via `MKLocalSearch`, using user-entered dish and city (defaults to Warszawa, editable). Results show real places from Apple's service and open in Maps. They do **not** assert the venue is available for delivery, listed at any of the food providers, currently open, or offering a particular menu or price. Queries are sent only when Search is tapped and capped at 80 characters per field. Doddy requests no iOS precise-location permission for this feature; Apple's Maps service may process contextual device/network signals under Apple's policies.

## What it does NOT do (do not claim otherwise)

- No Uber Eats/Glovo/Wolt/Pyszne/Bolt account linkage to Doddy.
- No partner OAuth scopes, direct consumer ordering API, real-time provider menu, specific in-provider restaurant match, final quote, cart management or order placement.
- No payment, order receipt, tracking, reordering, price or ETA comparison, consumer loyalty/affiliate attribution.
- Doddy cannot detect a completed external order. An opened link means **opened link** only.
- This is **not** a substitute for Uber Consumer Delivery API approval or an independently contracted merchant checkout + courier provider.

## Architecture & implementation

- `Packages/DoddyCore/Sources/DoddyCore/FoodDeliveryProvider.swift`: five source-controlled official HTTPS destinations, explicit Warsaw-specific scope, explicit `canOrderInsideDoddy == false`.
- `DoddyApp/Features/Food/FoodDeliveryView.swift`: provider handoff & Apple Maps query. No backend or secrets.
- `DoddyApp/Features/Home/HomeView.swift`: Home menu entry and sheet.
- `Packages/DoddyCore/Tests/DoddyCoreTests/FoodDeliveryProviderTests.swift`: fixed hosts/schemes/no credentials/no invented order capabilities.
- `DoddyUITests/LaunchSmokeTests.swift`: smoke check for menu and provider rows (no external taps).

Providers require the user's own address/login/payment inside their official site. No order data is transferred from Doddy to a provider; no user account is stored by this code. No user content is sent to Doddy backend by this feature. The MapKit request is handled by Apple.

## Release checks

1. Run `make test-core`, `scripts/ci.sh --only checks` and iOS Xcode build/simulator tests.
2. Verify menu and actual link destinations on physical iPhone with and without provider apps installed.
3. Verify Apple Maps restaurant results for a Warsaw search and an unknown city, plus offline/timeout paths.
4. Validate VoiceOver, keyboard and Dynamic Type.
5. Confirm Polish/English wording; run the repository localization generation/checks as required.
6. Confirm no provider states/quotes/payment receipts are logged, stored or inferred.
7. Do not merge/deploy until CI and on-device checks are reviewed.

## Upgrade to in-Doddy ordering

See [FOOD_ORDERING_RESEARCH_2026-11-11.md](FOOD_ORDERING_RESEARCH_2026-11-11.md) on the research branch / PR #328. The complete consumer ordering workflow requires official production credentials and scopes (Uber Consumer Delivery early access) or a contracted merchant that will accept orders plus optional delivery logistics API. Replace this **external handoff** with an authorized adapter on a separate PR, reusing `CheckoutDraft` and `ConfirmationPolicy`.

## Primary source links

- https://www.ubereats.com/pl/near-me
- https://glovoapp.com/pl/pl/warszawa/categories/jedzenie_1
- https://wolt.com/pl/pol/warsaw
- https://www.pyszne.pl/
- https://bolt.eu/pl-pl/food/ (links to https://food.bolt.eu/)
- https://developer.apple.com/documentation/mapkit/mklocalsearch

## Evidence

- Core unit tests added but not executed locally; CI results must be read after PR.
- UI smoke test added but not executed on a physical iPhone.
- No app deployed. No provider API has been called; these are genuine official links, **not** consumer ordering API integrations.
