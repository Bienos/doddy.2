# M2 status — typed AI questions through a gateway
Date: 2026-10-10. Owner instruction: "build / finish M0 and M2"; provider **OpenAI**, host **Vercel Functions**; Gmail, Google Calendar and EventKit "maybe" (design note only). Milestone status label: **BUILT AND UNIT-TESTED, NOT EXERCISED AGAINST A REAL PROVIDER, NOT DEPLOYED, APP NOT COMPILED ON A MAC.**

## M0 and M1
Already done and Mac-verified on 2026-10-08 (`M0_REPORT.md`, `M1_STATUS.md`). Nothing to finish; this session only added to them.

## What M2 shipped (behaviour)
| Exit criterion in `MILESTONES.md` | State |
|---|---|
| Provider-neutral assistant, key gateway, limits | `AssistantClient` port → `GatewayAssistantClient` → `gateway/` (OpenAI Responses API, `store:false`, strict schema). Limits exist but are per-instance (ADR-044). |
| Memory-grounded citations | Notes selected locally (≤5, matched only), sent under aliases, citations enum-restricted, checked by gateway **and** device |
| **Real provider response confirmed, not mocked** | **NOT MET.** No OpenAI key, model id or deployment exists. Every provider response in the tests is a fake. |
| Offline / cancellation / rate-limit paths | Implemented and unit-tested (taxonomy in `ASSISTANT_GATEWAY.md`); on-device behaviour NOT RUN |
| Citation verifier blocks unknown memory IDs | Done: `CitationVerifierTests`, gateway `A-14` tests, mutation-checked |
| Measured request cost | **NOT MET** (needs a real call; the gateway returns token usage for it) |
| Logs scrubbed of personal text | Allow-list logger with shape-checked values; tests assert no question/note/answer/token/key/full id in any line. Platform (Vercel) request logs not reviewed. |

User-visible: Home → **Ask Doddy** (off until Settings → Ask Doddy is switched on after a disclosure dialog; separate "Use relevant saved notes" switch; gateway address; invite code in the Keychain). Answers show **From your saved notes** with the notes, or **Not from your notes. This is a general answer.** Failed asks keep the question in the box.

## Files changed
- New Swift core: `Packages/DoddyCore/Sources/DoddyCore/Assistant/` (`AssistantError`, `AssistantWire`, `CitationVerifier`, `GroundingSelector`, `AssistantService`, `GatewayPorts`, `GatewayAssistantClient`); edited `Ports.swift`, `Capabilities.swift` (`textAssistant`, `.m2`), `PrivacyDefaults.swift`.
- New app code: `DoddyApp/Features/Ask/`, `DoddyApp/Infrastructure/Network/` (`AppHTTPTransport`, `KeychainCredentialStore`); edited `AppEnvironment`, `HomeView`, `SettingsView`, `RootView`, `Components`, `PrivacyInfo.xcprivacy`.
- New gateway: `gateway/` (api/, src/, test/, README); shared `schemas/fixtures/`.
- Tests: 5 new Swift test files + `HonestyTests`; 7 gateway test files; `LaunchSmokeTests` (stale assertion fixed, 2 Ask tests added); `AppEnvironmentTests` adjusted.
- Scripts/docs: `check_forbidden_capabilities.sh` (HTTP only in `Infrastructure/Network`), `ci.sh` (+gateway), `BUILD_AND_TEST.md`, `DECISIONS.md` (ADR-038–050), `docs/architecture/ASSISTANT_GATEWAY.md`, `docs/architecture/CONNECTED_APPS_PROPOSAL.md`, this file.

## Tests actually executed (this environment: Linux x86_64, Swift 6.3.3, Node 22.22.0)
| Command | Result |
|---|---|
| `swift test --package-path Packages/DoddyCore -Xswiftc -DSQLITE_DISABLE_SNAPSHOT` | **73 tests, 0 failures** (30 before M2) |
| `npm test --prefix gateway` | **42 tests, 0 failures** |
| `npm run typecheck --prefix gateway` | clean |
| `scripts/check_forbidden_capabilities.sh` | PASS (and FAIL when a stray `URLSession` is planted outside `Infrastructure/Network`) |
| `scripts/ci.sh --core-only` | PASS for core scope (see final run below) |
| `swiftc -parse` on every `DoddyApp/`, `DoddyTests/`, `DoddyUITests/` file | no syntax errors (parse only, **not type-checked**: no iOS SDK here) |
Mutation checks (change the code, confirm tests fail, restore): accepting unknown citations, sending sample fixtures, letting question text into logs, limiter eviction clearing the global cap — each made tests fail.

Acceptance rows: **A-14** unit-tested (device + gateway). **A-15** unit-tested with fakes (provider fail, 429, 5xx, timeout, offline mapping, local memory untouched); not run with a real network. **A-16** field lists, id aliasing, log contents and the consent/notes switches are tested; a real network capture was **not** done.

## Independent review
A read-only security review of the gateway and Swift client found 4 real issues and several hardening items. All were fixed with tests: invite codes <16 chars refused; IPv6 /64 bucketing; per-invite assist cap; limiter eviction no longer resets the global brake; one whole-request deadline so a retry can't outlive the function limit; catch-all so errors can't leak via the platform's 500; invite tag keyed with the server secret; log values shape-checked; cached token bound to its gateway host; redirects refused; corrupt Keychain token treated as empty. Not fixed, by design: the limiter is still per instance (README, ADR-044). A review is not a penetration test.

## NOT RUN / still manual
1. **App build and tests on a Mac** (Xcode, simulator): all new SwiftUI and Keychain/URLSession code has only been parsed. Expect to fix compile errors on first build (most likely places: `AskView` `@State` of an `@Observable` class under Swift 6, `do throws(AssistantError)` in `AskController`, the typed-throws `HTTPTransport` conformance, `KeychainCredentialStore` Security calls).
2. UI smoke tests (including the corrected microphone assertion) and VoiceOver / Dynamic Type for the Ask screen.
3. A real OpenAI call: needs `OPENAI_API_KEY`, `OPENAI_MODEL`, a project spend limit, and a deploy (`gateway/README.md` checklist). Unknowns it will settle: model id validity, Structured Outputs support, `store:false` behaviour, latency, cost per question, whether answers reliably cite.
4. Real Keychain behaviour, airplane-mode and Stop/cancel on a physical iPhone.
5. Network capture proving only the approved fields leave the phone (A-16).

## Security / privacy risks (open)
- Rate limits are per serverless instance; the invite code is the only credential (**blocker before inviting anyone**: shared store + provider budget).
- OpenAI retention/training terms and `store:false` unverified; DPA, region and App Store privacy label pending legal review. Install id declared as Device ID in the privacy manifest — owner to confirm.
- Prompt injection reduced, not eliminated; the model can state uncited "facts"; the UI labels them but cannot detect them.
- Notes sent to a third party is a real change from "nothing leaves the phone": the opt-in dialog and the per-answer "N notes were sent" line exist for that, but they are product decisions the owner should read.

## Decisions required from the owner
1. Pick `OPENAI_MODEL`; approve a dedicated OpenAI project and monthly cap; authorise a Vercel deploy and the first paid call.
2. Invite-code beta gate acceptable, or require accounts/App Attest first?
3. Shared rate-limit store (Vercel KV/Upstash) — approve the extra service.
4. Legal/privacy review of the OpenAI data flow and the Device ID declaration.
5. Connected apps: answers to the four questions in `CONNECTED_APPS_PROPOSAL.md`.
6. ADR-038…050 in `DECISIONS.md` (accept / reject).

## Next recommended milestone
Run the Mac build and fix any compile errors, then deploy the gateway with a capped OpenAI project and do one real, supervised smoke test (this closes the missing M2 exit criteria). Then M3 (voice choice) or M4 (EventKit), per `MILESTONES.md`. Stopping here; no further milestone has been started.
