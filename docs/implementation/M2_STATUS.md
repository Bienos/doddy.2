# M2 status — real text AI (partial)
Date: 2026-10-08. **M2 is not complete.** The gateway is live; the Swift client is written but unbuilt.

## Built
| Piece | State |
|---|---|
| Gateway (`gateway/`, Supabase Edge Function, Frankfurt) | Deployed; real OpenAI replies verified by curl (EN, PL, recall + prompt injection). See `gateway/README.md`. |
| Swift `DoddyAssistant` module (`GatewayAssistantClient`, `HTTPTransport`, `URLSessionTransport`, `DeviceTokenStore`) | **Written, NOT compiled, tests NOT run** (no Swift toolchain in the authoring environment). |
| Unit tests (`DoddyAssistantTests`, 10 tests with a scripted transport) | Written, **NOT RUN**. |
| Guard (`scripts/check_forbidden_capabilities.sh`) | Updated to allow the network stack only in `URLSessionTransport.swift`; `scripts/verify_imported_pack.py` and the guard pass on Linux. |

## Deliberately not done
- Not linked into the app target (`project.yml` unchanged); `AppEnvironment` still uses `UnavailableAssistantClient`.
- `CapabilityCatalog` still lists `cloudAssistant` as not implemented. Flip it only after the tests run green and the app is wired.
- No Keychain `DeviceTokenStore`, no UI, no consent/disclosure screen, no privacy-policy text, no App Attest.

## Before M2 can be called done (ACCEPTANCE: see MILESTONES.md M2 exit)
1. On a Mac: `scripts/ci.sh`; fix any compile errors in `DoddyAssistant` (Swift 6 strict concurrency has not been tried).
2. Keychain token store; wire `GatewayAssistantClient` into `AppEnvironment.live`; cloud-AI consent + disclosure; update `PrivacyDefaults` and Settings copy.
3. Offline, cancellation and rate-limit paths exercised on a device; measured cost; confirm no personal text in gateway logs.
4. OpenAI project EU residency confirmed; the pasted-in-chat key rotated; spend cap set.

## Decisions required
Cloud-AI consent wording; whether to flip the capability catalog for a TestFlight build; limits (60/day/device) vs expected use.
