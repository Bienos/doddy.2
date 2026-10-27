# InPost parcels: status check by tracking number (ADR-641)

Owner, 24 Oct 2026: "Dodaj … InPost", and (answering "how, if their API is for firms only?") "Z tokenem użytkownika". Branch `claude/infakt-inpost`, stacked on `claude/expert-modes-research` (PR #140). Research behind it: `docs/research/2026-10-24/research_expert_modes_PL.md` (section 4.2, ranking P2). **Status of each part is at the end; nothing here has been seen on a device.**

## What step 0 found (24 Oct 2026)

Tags: **[V]** read on InPost's own documentation (`dokumentacja-inpost.atlassian.net`, the "Developer Documentations" Confluence) or observed in a live request to InPost's own host, **[S]** third-party source, **[U]** not confirmed.

| Fact | Tag | Source |
|---|---|---|
| Reading a parcel's status by tracking number: `GET https://api-shipx-pl.easypack24.net/v1/tracking/{tracking_number}`; **"Resource access does not require authentication"**. | [V] | Shipment Tracking page (`.../pages/18153479`), and the "InPost Integration FAQ" (`.../pages/451903492`: "Tracking: (not authorized)") |
| Answer: `tracking_number`, `service`, `type`, `status`, `custom_attributes` (locker name `target_machine_id`, size A/B/C, `target_machine_detail` with address and opening hours), `tracking_details[]` (newest first: `status`, `origin_status`, `agency`, `location`, `datetime`), `expected_flow[]`, `created_at`, `updated_at`. | [V] | same page |
| Tracking is **not available on the sandbox** ("no statuses are returned"); it is returned for 45 days from the shipment's creation. | [V] | same page |
| `GET /v1/statuses?lang=pl_PL\|en_GB&shipment_type=inpost_locker_standard` lists status names with `title` and `description`; no token. 32 names came back on 24 Oct. InPost says its wording may be used in user interfaces. | [V] | Statusy page (`.../pages/11731056`) and a live request |
| The ShipX API proper (own shipments, labels) needs `Authorization: Bearer {token}` from Parcel Manager, with company and invoice data filled in; the organization id is in the path. | [V] | "API General Information" (`.../pages/28639247`), FAQ |
| **Live answer for an unknown number differs from the page.** The page shows `404 {"status":404,"error":"resource_not_found",...}` and `400 {"error":"uknown_tracking_number"}` for a number of unknown type. In a real request on 24 Oct, an unknown 24-digit number and a 5-digit number both gave **HTTP 404 with `{"trackingNumber":"…","message":"Tracking information about … shipment has not been found."}`**. The client therefore decides by the HTTP code (404 = not found, 400 = not a tracking number) and never by the body's shape. | [V] (live, one request each, made-up numbers, 24 Oct 2026) | InPost host, answers recorded in this table |
| Tracking number format: every example in the documentation has **24 digits** (`630000328531876219900746`, `523000015611700083038270`, `632085946340007012341234`). No page states a rule. | [U] | the examples above |
| Rate limits for the tracking endpoint are not documented. | [U] | none found |
| The new "InPost Developers Portal" (`developers.inpost-group.com/tracking`) describes a Tracking API "for merchants"; its details did not load. Not used. | [U] | the page |

## What this means for the owner's choice ("Z tokenem użytkownika")

The token is **not needed for what this slice does** (read a parcel's status by its number). InPost documents that endpoint as open. So this slice **builds no token store for InPost** and asks for no key. A user's own ShipX token would only matter for listing a business account's own shipments (`GET /v1/organizations/{id}/shipments`), which needs a Parcel Manager account with company data; that is a separate, later slice and stays the owner's call.

## What is built

- `ParcelNumber` (DoddyCore): 24 digits, nothing else accepted (spaces and dashes pasted from a message are dropped first). Flagged [U]: if InPost issues other lengths this is too strict, and a number that is refused is never sent anywhere.
- `ParcelStatus`: InPost's status names mapped to plain Polish and English sentences (the titles InPost publishes for the locker service); a name that is not in the table is "unknown", shown as such with InPost's own word, never made into a sentence.
- `ParcelTracking.parse`: reads the answer by the HTTP code; unreadable → `.unreadable`.
- `InPostTrackingClient` (DoddyApp): `GET` to the one address DoddyCore builds from a checked number; no header carries anything about the user; ephemeral session, no cookies, redirects refused, size cap, 10 s timeout, at most 20 look-ups a minute on the iPhone.
- "Przesyłki" list kept on the iPhone, only after the person turns it on.
- A parcel number that appears in an email, a message or a web page is **data**: nothing in this slice reads mail or messages, and a number is looked up only when the person adds it or taps Refresh.

## Status

As of the last commit of branch `claude/infakt-inpost` (24 Oct 2026). "Tested" means `make test-core` on Linux (Swift 6.1.2): 1,896 tests, 0 failures. Nothing below has been compiled with Xcode or seen on a device; the app has never called InPost. Two requests were made to InPost's open tracking address from this session's shell, with made-up numbers, to see the error answers.

| Part | State |
|---|---|
| `ParcelNumber` (24 digits), `ParcelLookupPolicy` (only the person's own act allows a look-up) (`Parcels/Parcels.swift`) | Real, tested (`ParcelTests`). The 24-digit rule is [U]. |
| InPost's status names as Polish and English sentences; an unknown name is shown as unknown | Real, tested. Titles are those InPost publishes for the locker service. |
| The answer read by HTTP code (`InPostTracking.parse`) | Real, tested, including InPost's live 404 body. |
| `ParcelTracker`: policy, fetch, parse; unreadable or limited answers become "unavailable" (`Parcels/ParcelTracker.swift`) | Real, tested against a scripted fetcher. |
| `ParcelBook`: off until turned on, 30 parcels, label cleaned, `apply` keeps only a parcel InPost answered for | Real, tested. |
| `ParcelsModel`: add, refresh, remove, turn off; honours "Pause all connections" | Written; compiled by `typecheck_app_logic.sh` on Linux (Swift 6 mode); not run. |
| `InPostTrackingClient` (URLSession, one address) | Written, **BLOCKED / NOT RUN** (URLSession is not type-checked on Linux; no device). The guard allows networking in this file only. |
| Settings › Parcels (InPost) (`ParcelsView.swift`) | Written, **BLOCKED / NOT RUN** (SwiftUI). |
| What leaves this iPhone row for InPost; Delete all removes the list | Real in DoddyCore (tested); the Delete all call is **BLOCKED / NOT RUN**. |
| InPost token, the person's own shipments list (`/v1/organizations/{id}/shipments`) | **Not built**, and not needed for status by number. It needs a Parcel Manager account with company data: the owner's call. |
| Reading numbers from email or messages | **Not built.** If it is ever added, a number found there stays a suggestion the person adds. |

**For the owner:** whether the token path (own shipments, for a business account) is still wanted now that tracking by number needs none; if yes, an InPost sandbox token from Parcel Manager.
