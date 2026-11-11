# DODDY Poland Pack — v1 (11 November 2026)

**Status:** Source code in draft PR; **not merged, shipped, or validated on a device**.

## Goals and boundaries

Provide a useful Poland-first feature without waiting for Polish marketplace/identity/parcel-account commercial permissions. It is an on-demand iPhone sheet in Home > More > **Polska na co dzień / Poland Pack**. No location permission, account connection, private credentials, scheduled jobs, order placement, or payments. Users explicitly choose one of five cities; city preference is stored locally in `@AppStorage("polandPack.city")`.

Voice already has `get_weather`, `convert_currency` (ECB), and `find_deals`. This sheet **does not claim** that the live voice agent calls IMGW/GIOŚ/NBP or reads InPost tracking. Connecting these official endpoints as new voice tools is a separate architecture/release task.

## 10 actual user workflows / five source groups

| # | Workflow | What it does, not what it merely plans |
|---|---|---|
| 1 | Current Polish temperature | Reads the chosen city's IMGW SYNOP station, showing observation time. |
| 2 | Wind / rainfall / humidity | Reads separate IMGW measurement fields; omits missing values instead of showing zero. |
| 3 | Weather warnings | Reads IMGW warnings and matches county TERYT where available; uncertain locations never get a false all-clear. |
| 4 | Local air index | Reads GIOŚ station list and a station's official Polish AQI. Shows station name. |
| 5 | Confirm the air-quality source | Direct link to official GIOŚ monitoring map; no inferred citywide measurements. |
| 6 | PLN exchange-rate comparison | Reads NBP EUR/USD/GBP reference rates and publication date. |
| 7 | Convert a typed amount | Converts a user-entered amount to PLN using NBP's fetched, dated reference rate. |
| 8 | Track an InPost parcel | Validates a user-entered 24-digit number and opens official InPost tracking URL. **Does not fetch parcel status.** |
| 9 | Find a parcel locker | Opens official InPost Paczkomat/PaczkoPunkt map. |
| 10 | Compare Polish grocery promotions | Opens the **existing** DODDY DealsView/leaflet/basket flow, if the release scope enables it. No new grocery provider API. |

**Five source groups:** IMGW, GIOŚ, NBP, InPost, existing DODDY grocery leaflets. InPost is a **link handoff**, not a connected account. Group 5 reuses existing functionality. Public-data network integrations newly added in this PR: **3** (IMGW, GIOŚ, NBP).

## Sources and access

- IMGW official docs: https://dane.imgw.pl/apiinfo
  - `GET https://danepubliczne.imgw.pl/api/data/synop/station/{station}`
  - `GET https://danepubliczne.imgw.pl/api/data/warningsmeteo`
  - Warnings may be an array or `{"message":"Brak ostrzeżeń meteorologicznych"}`.
- GIOŚ official docs: https://powietrze.gios.gov.pl/pjp/content/api
  - `GET https://api.gios.gov.pl/pjp-api/v1/rest/station/findAll?page=0&size=500`
  - `GET https://api.gios.gov.pl/pjp-api/v1/rest/aqindex/getIndex/{stationId}`
  - **DO NOT** use pre-`/v1/` endpoints (retired 30 June 2025). Response is JSON-LD with Polish keys such as `Lista stacji pomiarowych`, `AqIndex`, `Wartość indeksu`. GIOŚ says live readings can be revised and requires clear source attribution. Station listing is cached in the active sheet to avoid repeated calls to restricted endpoints.
- NBP official docs: https://api.nbp.pl/
  - `GET https://api.nbp.pl/api/exchangerates/rates/a/{eur|usd|gbp}/?format=json`
  - Latest published *table A* rates; holidays/weekends may have no new rate. Values are **not** bank buying/selling rates.
- InPost tracking and lockers:
  - `https://inpost.pl/sledzenie-przesylek?number={24-digit-number}` (URL pattern documented by Shoper)
  - `https://inpost.pl/znajdz-paczkomat`
  - Tracking data is sent only when the user follows the link to InPost, not to DODDY servers.
- Grocery flow: `DoddyApp/Features/Shopping/DealsView.swift`, `docs/implementation/SHOPPING.md`. Existing feature only.

## Implementation

- `Packages/DoddyCore/Sources/DoddyCore/PolandPack.swift` — Foundation-only, testable models and endpoint allowlists, numeric input and city validation, TERYT warning matching, no hidden network calls.
- `Packages/DoddyCore/Tests/DoddyCoreTests/PolandPackTests.swift` — sample-payload tests for every source, missing data, spoofed tracking numbers, and URL checks.
- `DoddyApp/Features/Poland/PolandPackView.swift` — on-demand SwiftUI. Concurrent fetches, explicit missing-data states, choice of five cities, local city preference, checked handoff, source/time attribution. Never network-calls before the sheet opens.
- `DoddyApp/Features/Home/HomeView.swift` — More menu route; grocery link uses existing scope gate.

### Required QA before merge

1. `swift test --package-path Packages/DoddyCore --filter PolandPackTests`
2. Xcode iOS app build (all configurations) and Swift 6 concurrency checks.
3. Device + VoiceOver / Dynamic Type inspection; Polish and English languages.
4. Test five cities, GIOŚ missing index, NBP rate changes on non-business days, IMGW no-warning objects, valid and invalid parcel numbers.
5. Verify actual GIOŚ station-list paging and county/Teryt coverage. If the station for a city is not included in page 0, show *unavailable* — never substitute another city.
6. Check the returned network data sizes, GIOŚ 429 behavior, and provider terms before scaling usage.

### Not part of this PR

- InPost account login, status fetch, locker opening, or notifications (needs authorized provider access).
- Wykop API, OLX partner app, Jakdojade commercial API, Ceneo/Allegro search, payment and bookings.
- Direct tool calls from the live ElevenLabs agent; do not mark these as voice-enabled.
- Automated local recommendations or proactive background alerts.
