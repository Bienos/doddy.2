# DODDY × Jakdojade — licensed route adapter (12 November 2026)

**Status:** server-side implementation and offline contract tests only.
No registered partner licence exists in this branch. The adapter is not connected to
a live endpoint, an iPhone transport client, an ElevenLabs tool, or ticket purchasing.
It is intentionally impossible to produce "live routes" without an injected licence.

## Official documented endpoints

- Route search: `GET https://jakdojade.pl/api/rest/v2/routes`.
- Location matching: `GET https://jakdojade.pl/api/rest/v1/locationmatcher`.
- Stop schedules (future): `GET https://jakdojade.pl/api/rest/v1/schedule/table`.
- Authentication: HTTPS + HTTP Basic using a **public partner licence key and private secret**.
- The docs note that requests without authentication return **sample/test data**;
  DODDY must never treat these as actual trip suggestions.
- Contract: https://docs.jakdojade.pl/restxml/rest/ and
  https://docs.jakdojade.pl/restxml/connections/.
- Partner request: https://company.jakdojade.pl/wspolpraca/, `biuro@jakdojade.pl`.

## Implemented

`server/messaging/src/integrations/jakdojade.ts`:
- A credential-injected, fixed-host, **read-only** HTTP adapter. No credentials
  in source, mobile client, logs or tests. No public route exposed yet.
- `locations(agg, search)`: returns up to 10 station/street/POI candidates
  with source coordinates; caller must pick any ambiguous place.
- `routes({from,to,day,hour,arriving,mode,avoidBuses,avoidTransfers})`:
  1–3 source routes using the official partner API's required coordinate params.
- `output=xml`, bounded 256 KiB response, 8-second deadline, no redirects,
  XML validation with external entities/DOCTYPE disallowed.
- Source route dates, vehicle types, lines and stop departure/arrival fields.
  No invented timetable, ticket availability, disruption data or cash prices.
- Distinct `not_configured`, `unauthorized`, `forbidden`, `rate_limited`,
  `unavailable` and `invalid_response` errors; provider failures cannot
  pretend successful results.

`server/messaging/test/jakdojade.test.ts` exercises offline simulated provider
responses and error cases. No production secrets, remote provider calls or purchases.

## What it takes to become a full in-app integration

1. Owner obtains Jakdojade's written permission for a consumer voice assistant
   to display routes and stops commercially, and receives licensed key + secret.
2. Put key/secret into the existing server secret-manager mechanism, add a
   configuration gate and inject a non-null `CredentialSource` into the adapter.
   No anonymous request, `test=true` or fake result in live mode.
3. Wire a strictly typed authenticated backend route to DODDY, with rate limits,
   per-request user approval for location, geographic validation, and provider
   costs measured. Never expose partner credentials to Swift or ElevenLabs.
4. Bind this typed result to the `JourneyRouteProvider` and journey card created
   in the separate official-link handoff PR. Check true route freshness and
   timezone, reconcile ambiguous place names with the person, and test in Poland.
5. Add stop timetable and real-time updates only under explicit partner API
   permissions; don't poll continuously without need.
6. Ticket purchase/validation, account access and payments require separate
   partner contracts and user confirmation.

The browser link handoff is independent of this adapter and works without API credentials.
This PR is not ready for use in TestFlight until it is fully integrated and validated.
