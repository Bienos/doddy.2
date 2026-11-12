# DODDY — JourneyPlanner + Jakdojade handoff (12 November 2026)

**Implementation status:** Code and tests on a feature branch, pending CI and iPhone QA.
This is the working **public-link handoff**, not an authenticated Jakdojade route API integration.
Do not claim a known route, bus stop, departure, real-time delay, ticket or fare.

## User story

"Jak dojadę z Woli na Mokotów komunikacją miejską?" -> existing `open_map` voice tool
with `mode: "transit"` -> user's existing confirmation card offers:
- **Start directions**: Apple Maps as before, unaffected.
- **Open in Jakdojade**: a separate choice using official Jakdojade link parameters.
- If neither endpoint names a city, a menu asks the person to choose one; never assume Warsaw.
- With an explicit start, use `/city/From/To` for the web route search.
- Without a start, use `/city?tn=Destination` to prefill destination; the person must choose their start in Jakdojade.
- For explicitly different cities, do not offer an urban Jakdojade handoff.
- Only when the person taps the Jakdojade choice do we open the URL. No location, calendars, accounts, notifications or credentials are read.

This uses the existing `VoiceSessionController` and `MapTrip`, not an extra
agent or an unsynced live ElevenLabs tool. The existing voice agent already
supports `open_map(place,from,mode)`.

## Implementation

- `Packages/DoddyCore/Sources/DoddyCore/JourneyPlanner.swift`
  - `JourneyCity`: explicit Polish city names (with common grammatical cases), never GPS inference.
  - `JourneyIntent`: origin, destination, selected city, optional depart/arrive deadline and practical preferences.
  - `JakdojadeLinkBuilder`: source-authorised fixed `https://jakdojade.pl` URLs; percent-encode all segments and query values; strict length/control validation; date/time in Europe/Warsaw.
  - `JourneyRouteProvider` typed interface for a future licensed route API.
  - `JourneyHandoff.requiresOriginSelection` distinguishes prefilled search from route search.
- `VoiceView.swift`: new secondary Jakdojade action and city selection only on transit map confirmation cards.
- `VoiceSessionController.swift`: `confirmPendingJakdojade` opens the official URL on user tap, replies truthfully, and consumes the same pending map request.
- `VoiceTools.swift`: source-correct reply; no fabricated lines or trip times.
- `JourneyPlannerTests.swift`: guards against unsafe URLs, cross-city ambiguity, unspecified origin, wrong providers, and invalid dates.

## Why no partner API calls yet?

Official public link docs:
- https://docs.jakdojade.pl/
- https://docs.jakdojade.pl/parameters/basic/
- https://docs.jakdojade.pl/parameters/advanced/
- https://docs.jakdojade.pl/examples/examples/

Official REST XML partner docs:
- https://docs.jakdojade.pl/restxml/connections/ — GET `/api/rest/v2/routes`, expects coordinates, optional arrival date, route options; XML result.
- https://docs.jakdojade.pl/restxml/locations/ — GET `/api/rest/v1/locationmatcher`.
- https://docs.jakdojade.pl/restxml/schedules/ — GET `/api/rest/v1/schedule/table`.
- https://company.jakdojade.pl/wspolpraca/ — partner and real-time commercial access.

The partner route API is not publicly usable as a live consumer integration. Do not scrape the website, reverse engineer private app endpoints, or embed keys in the app.

## Phase 2 — after partner agreement (NOT IMPLEMENTED)

1. Owner contacts `biuro@jakdojade.pl` with DODDY's commercial use case: read-only routes and stop timetables, optional real-time updates, permitted client display, city coverage, caching, throughput, billing, data licence, attribution.
2. Once a real licence exists, add a DODDY backend `JakdojadePartnerProvider`. Only server reads the partner API using server-side credentials; bound public endpoints and XML parsing; no general URL proxy.
3. Normalize to `JourneyRoute` with source, departure/arrival timestamps and actual segments. Validate coordinates, route attribution, response size, stale timestamps and upstream errors. Return **not configured** before approval — never mock results in live mode.
4. Route phone voice requests through existing approved backend and privacy/AskFirst limits. Show up to 3 verified routes with source and freshness.
5. Set leave notifications only after the person confirms a specific route, and keep `LeaveByScheduler`'s idempotency.
6. Real-time and tickets are independent integrations; only add if a partner confirms API scope and permissions. Separate purchase approval, payment receipts and ticket activation from route lookup.

## Validation and QA

- Swift package tests including `JourneyPlannerTests`.
- iOS Xcode build; voice map card accessibility checks.
- On-device Polish transit request with a named city; unnamed city; no origin; named origin; cross-city; no network; opening URL fails; user declines; repeated tap; conversation ends before opening.
- Check the generated public URLs in Jakdojade on iOS and browser for correct prefill and interpretation of options. Link behavior may change independently of our code.
- Check legacy Apple Maps route and non-transit cards still work.
- Verify `remind_when_to_leave` receives `mode: "transit"` when the person explicitly asks to use public transport; without a licensed route response this is an Apple Maps ETA, not a Jakdojade schedule.
- Do not merge or release on TestFlight before repository CI and physical-device checks.

## Licensed in-DODDY route lookup (code present, feature off until activation)

- `Packages/DoddyCore/Sources/DoddyCore/JourneyServerClient.swift`: typed transport over the existing secured `DoddyServerClient`, including authenticated status, place matcher and routes; local time normalization for Poland; no cached travel location.
- `VoiceView.swift`: on a transit map confirmation card, `GET /v1/journeys/provider` checks if the backend is actually configured. Only if `available=true`, a third explicit choice appears: **Find routes in DODDY**.
- `VoiceSessionController.swift`: after a tap, resolve the start/destination on-device using Apple Maps and, only if needed, one-time iOS location permission. Ambiguous place matches yield a clarification request, never a guessed coordinate. The iPhone then calls the secured `POST /v1/journeys/routes` endpoint. The agent receives only verified source routes, source freshness and scheduled (not real-time) times.
- There is no route fetch, GPS read or additional agent startup work until the user taps. No ticket operations or price claims.
- `JourneyServerClientTests.swift` verifies body structure and token handling, unavailable-provider failures, date normalization and missing/invalid source data.

**Integration dependency:** the backend endpoints and licence gate live in partner API PR #365. Until its deployment with a signed partner contract, `available` must remain false, so the first production feature stays the official public-link handoff.

**Known functional limit:** `open_map` currently carries only place/start/mode. Arrival deadlines and travel preferences are modeled in `JourneyIntent` and the API contract but are not yet sent from that voice call. A future protected voice-agent tool update is necessary for full arrival-time planning; do not silently infer one. Real-time disruption monitoring, Live Activities and ticket purchasing remain unimplemented pending provider scope.
