# M2 status — real text AI (partial)
Date: 2026-10-08. **M2 is not complete.** The gateway is live; the Swift client is written but unbuilt.

## Built
| Piece | State |
|---|---|
| Gateway (`gateway/`, Supabase Edge Function, Frankfurt) | Deployed; real OpenAI replies verified by curl (EN, PL, recall + prompt injection). See `gateway/README.md`. |
| Swift `DoddyAssistant` module (`GatewayAssistantClient`, `HTTPTransport`, `URLSessionTransport`, `DeviceTokenStore`) | **Written, NOT compiled, tests NOT run** (no Swift toolchain in the authoring environment). |
| Unit tests (`DoddyAssistantTests`, 10 tests with a scripted transport) | Written, **NOT RUN**. |
| Guard (`scripts/check_forbidden_capabilities.sh`) | Updated to allow the network stack only in `URLSessionTransport.swift`; `scripts/verify_imported_pack.py` and the guard pass on Linux. |

## App wiring (added, also UNBUILT and UNTESTED)
| Piece | Notes |
|---|---|
| Cloud AI notice + toggle | Settings → "Cloud AI (preview)"; off by default; consent stored as notice version (bump to re-ask). Draft wording, pending the privacy policy. |
| `KeychainDeviceTokenStore` | Gateway token in the Keychain, this-device-only. |
| `AskStore` / `AskView` | "Ask" tab appears only after consent. Sends the question + up to 3 recall matches; shows only cited notes that were actually sent; maps every `AssistantError` to plain copy; Cancel; nothing persisted. |
| `AppEnvironment.live` | Uses `GatewayAssistantClient`; no request is made until the user asks a question after consent. |
| Copy | Home, First Hello and Settings no longer claim "no networking"; Settings privacy rows follow consent. |
| `PrivacyInfo.xcprivacy` | Declares OtherUserContent, not linked, not tracking, app functionality. |
| Tests | `AskStoreTests` (3, app target) and a `PrivacyDefaults.m2` test (package): written, NOT RUN. |

## Deliberately not done
- `CapabilityCatalog` is unchanged: "AI answers" still reads "Not built yet · planned M2" until tests run green on a Mac and a device.
- No privacy-policy text (the notice says it isn't written), no "forget this device" button, no App Attest, no streaming.

## Before M2 can be called done (ACCEPTANCE: see MILESTONES.md M2 exit)
1. On a Mac: `scripts/ci.sh`; fix any compile errors in `DoddyAssistant` (Swift 6 strict concurrency has not been tried).
2. Run the new app tests and the UI smoke tests on a Mac (Settings still shows "Microphone" / "Not used"); review the consent wording with the owner.
3. Offline, cancellation and rate-limit paths exercised on a device; measured cost; confirm no personal text in gateway logs.
4. OpenAI project EU residency confirmed; the pasted-in-chat key rotated; spend cap set.

## Decisions required
Cloud-AI consent wording; whether to flip the capability catalog for a TestFlight build; limits (60/day/device) vs expected use.
