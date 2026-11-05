# Payments (x402 + optional Coinbase wallet): status

> **Read the section "Rebase onto the default branch (2026-11-05, ADR-733)" first.** The sections after it are the old branch's own records of 12 Oct 2026, kept as written; where they say something was synced to the live agent, that was undone on 19 Oct (ADR-544) and is not repeated here.

Date: 2026-10-12. Owner instruction: "Use Coinbase wallet connection but not as default and build it so Doddy can pay
for stuff." Decision record: ADR-730 (`DECISIONS.md`). Design, API and owner runbook: `docs/integrations/PAYMENTS_X402.md`.
CLAUDE.md rule 6 asks for milestone approval for cloud actions with money; this instruction is taken as that approval for
**this milestone only**. Branch `claude/fervent-hamilton-ot5z1f`. Environment: Linux, Node 22, **no Xcode**.

**Bottom line:** the backend can read an x402 offer, show exact terms, take a single-use approval bound to them, sign
through an optional Coinbase server wallet, send once, and report only what the seller confirms. It has been tested against
a demo wallet and a demo seller only. **Update (ADR-731): the iPhone approval card with Face ID is now written, but it has
never been compiled or run** (no Swift toolchain here), so treat it as untested. The voice agent cannot start a payment;
the only entry is Settings › Payments › "Pay for a page". Nothing has run against Coinbase or a real seller.

## Rebase onto the default branch (2026-11-05, ADR-733)

**What this is.** The owner approved bringing this branch up to date with the default branch `claude/loving-dirac-uuxoux` and opening a pull request **for review only** (ADR-729, option "1"). **It is not approved to be turned on.** The branch was 10 commits ahead and 854 behind; the default branch was merged in (a merge, nothing force-pushed) on `claude/rebase-usdc-pay-for-pages`, 20 files conflicted, and its ADRs 450 to 452 are now 730 to 732 (450 to 452 were already taken). The old branch's live-agent syncs of 12 Oct were undone by the owner on 19 Oct (ADR-544); **nothing here reads, syncs or calls the live ElevenLabs agent or any other live service.**

**Off by default, still.** No wallet unless `DODDY_PAYMENTS_WALLET=coinbase_cdp` with four `CDP_*` values (none are in the repository, and `secrets/manifest.json` lists them as 1Password-only, not pushed to any host); each person's switch (`pay_x402`) off; and the server now **refuses to start on any network that moves real money** (only `base-sepolia`, ADR-733). Ceilings in code: 0.25 USDC per payment, 1.00 per person per day, 5.00 for the server (`DODDY_PAYMENTS_*`, validated at startup), the typed amount from 0.10 USDC, an optional host allow-list. The voice tool is `not_synced` and is not in the live agent's prompt.

**What was ported, beyond resolving text conflicts**
- The store: the old branch's SQLite calls became Postgres ones (async): tables `payments` and `payment_receipts` in `SCHEMA_SQL`, added to `ERASED_TABLES` (deleting an account erases them; the default branch's schema test fails without that), `prune` (90 days) and `releaseUsage`. `PaymentsService` is async throughout.
- ASK-01: approvals for a payment are issued and used through `AskGate` (`backend/src/tools/askFirst.ts`), the one place the guard allows; the old direct `consumeApproval` calls were removed.
- `pay_for_page` was added to `ToolCatalog` (DoddyCore) and to the Logbook's tool list, because the default branch has tests that pin both to `voice-agent/tools.json`.
- App: the Payments row is under Settings › Connections (the default branch's Settings was rebuilt in ADR-633), the Home notice is in Home's `notices`, the payments client uses `DeviceSession.serverURL()` (ADR-720).

**Files with real conflicts and how each was resolved**
| File | Resolution |
|---|---|
| `DECISIONS.md` | Default branch's table kept; the three ADRs appended as 730 to 732 with an ADR-733 for this work |
| `DEPENDENCIES_AND_LICENSES.md` | Default branch's Postgres text kept; the "payments added no dependency" paragraph kept |
| `backend/src/app.ts` | Both sets of imports and overrides kept; payments built before `createHandler` and passed to it; `payments` kept in the returned object |
| `backend/src/config.ts` | Both settings kept; new refusal of a real-money network |
| `backend/src/store.ts` | Default branch's Postgres store kept; the payment tables and methods rewritten for it (see above) |
| `backend/test/fixtures.generate.ts`, `retention.test.ts` | Both kept; the payment tests converted to the async store (`Store.memory()`); `account.test.ts` and `revocation.test.ts` extended for the two new tables |
| `scripts/check_forbidden_capabilities.sh` | Default branch's guard kept (ASK-01, Health, camera, no wake word); the payment rules and the Coinbase secret pattern added back |
| `secrets/manifest.json` (not a conflict, but its check failed) | The CDP variables listed as 1Password-only, not pushed; the other payment variables as not secrets |
| `voice-agent/tools.json`, `instructions.md`, `README.md` | Default branch's kept; only `pay_for_page` added (ASK-01 fields, `not_synced`); no prompt line; a note in the README; `add_to_diary` and `upcoming_renewals` not restored |
| `DoddyApp/Resources/Localizable.xcstrings`, `l10n/pl.json` | Default branch's `pl.json` kept plus the old branch's 44 payment lines; the catalog regenerated with `tools/build_strings_catalog.py`, not merged by hand |
| `DoddyApp/App/RootView.swift` | Three preference keys kept next to the default branch's |
| `DoddyApp/Features/Home/HomeView.swift` | Default branch's Home kept; the banner added to its `notices` |
| `DoddyApp/Features/Settings/SettingsView.swift` | Default branch's version kept (the old paragraph is gone); the row moved to `SettingsHubs.swift` |
| `DoddyApp/Features/Voice/VoiceSessionController.swift`, `VoiceView.swift` | Default branch's kept; `paymentApproval`, `handlePayForPage` and the sheet added |
| `Packages/DoddyCore/.../DataFlow.swift` | Default branch's row text kept; the payment sentence added |
| `docs/implementation/MAC_VERIFICATION_CHECKLIST_2026-10-10.md` | Default branch's kept; the payments section added as 4za |

**Checks run on Linux (this rebase)**
| Command (from the repository root unless noted) | Result |
|---|---|
| `npm ci` then `npm test` in `backend/` (PGlite, the in-process Postgres the default branch's tests use; no `DATABASE_URL`) | First run 585 tests, 582 pass, **3 fail**: the account-erasure seed lacked the two new tables, the Logbook's tool list lacked `pay_for_page`, and a test pinned `prune`'s keys. Fixed. Second run: **585 tests, 585 pass, 0 fail, 0 skipped** (831 s). Includes the ported payment tests (`payments`, `payments-config`, `x402`, `coinbase`, `paymentsNet`) and the fixtures schema test |
| `npm run typecheck` in `backend/` | clean |
| `scripts/check_forbidden_capabilities.sh` | PASS (ASK-01, approvals only in `askFirst.ts`, Coinbase only in `payments/coinbase.ts`, seller HTTPS only in `payments/net.ts`, signing only from the payments service, no payment or key code in the app, secret pattern incl. `CDP_*`) |
| `python3 -I scripts/voice_agent_spec.py check` (app, `--agent phone`, `--agent task-call`) | PASS: 101 tools including `pay_for_page`; phone 3; task-call matches |
| `python3 -I tools/build_strings_catalog.py --check` | PASS (catalogs regenerated by the tool, 44 payment lines in Polish) |
| `tools/build_blog.py --check`, `build_site_i18n.py --check`, `build_day.py --check`, `gen_web_assets.py --check`, `scripts/verify_imported_pack.py` | PASS |
| `node tools/secrets/sync.mjs check` and `node --test "tools/secrets/test/*.test.mjs"` | OK (24 secrets, 14 synced, 10 1Password-only); 43/43 pass |
| `scripts/test_ci_needs_mac.sh`, `test_copy_binary_dsyms.sh`, `test_xcode_cloud_post_clone.sh`, `test_ci_groups.sh`, `scripts/check_platform_specs.py` | PASS |
| gitleaks | **not installed here, not run**; a grep of the diff for private keys, `sk-` keys and 64-hex values found only demo transaction hashes in fixtures |
| `swift test`, `scripts/typecheck_app_logic.sh`, xcodebuild | **Swift NOT COMPILED, NOT RUN** (no Swift toolchain) |

`scripts/ci.sh --core-only` was not run as a whole; the steps above that touch this change were run one by one. The other servers (`server/*`, `gateway/`, `web/`, `site/`) were not touched and not re-run.

**Hosted CI (added after the first push).** On head `c9e783a0` (run 42006957025) the app compiled and every job passed: DoddyCore 2,436 tests, app unit tests 134, UI tests 64 (1 skipped), backend, messaging, node, checks. The first hosted run found one test that did not compile and, once it did, two payment tests that failed (page words kept on several lines in the reply; the typed amount kept untrimmed); both are fixed in code, no test was changed. **Still not run:** no UI test drives the payment screens, so the card, Face ID, the voice path and the Home notice have never been used on a simulator or a device; also not Coinbase, a real seller, or the live voice agent. Before that run this section said "Swift NOT COMPILED, NOT RUN", which was true when written.

**Gaps found while porting (not closed here)**
- The voice controller's `AskLedger` is not consulted for `pay_for_page`: the payment card (tap, typed amount, Face ID) and the server's single-use approval are its gate. A test for that path would need the Swift toolchain.
- If the person closes the voice transcript while the payment card is up, the card goes with it, the approval expires after two minutes and nothing is paid; the agent's call waits for its timeout.
- Payments rows in Settings need a Doddy server session; the screen does not sign the phone in by itself (it says "not set up" until another online feature has).
- `PaymentsClient` error text still says "Check the session token in Settings", from before the device sign-in; the Polish line for the not-set-up text was rewritten by hand (machine-quality).
- `ASK_FIRST.md` has a row for the tool; the default branch's Swift ASK-01 tests were not run on it.
- gitleaks is not installed here; a grep of the diff for key material found only the demo transaction hash in fixtures.

**Constitution evidence log (this rebase)**
| Rule | Requirement | Enforcing code | Tests run | Gap / claim to limit |
|---|---|---|---|---|
| DOD-07 / ASK-01 | No money moves without explicit approval of the exact action | `PaymentsService.prepare/pay` through `AskGate` (single-use, 2 minutes, bound to page, recipient, amount, token and wallet), re-checked against a fresh read of the offer; typed amount from 0.10 USDC; the app's card plus Face ID | `backend/test/payments.test.ts` (reuse, expiry, other user, other page, price change, switch off, races), the default branch's ASK-01 backend tests | The card, Face ID and the voice path are Swift: **NOT RUN**. "A person approves every payment" is true only once the card has run on a device. |
| DOD-08 | "Done" only on a trusted confirmation; `unknown` is never success and never blindly retried | `confirmSettlement`, the `unknown()` path, one send per approval, 15-minute block, `mightHaveBeenPaid` in the app | `x402.test.ts`, `payments.test.ts` (four unknown scenarios, declined, wallet failure) | Settlement header format follows the spec text, not a live seller (a mismatch is `unknown`, never success). |
| Ceilings | An amount ceiling and a daily cap | `loadPayments` (validated), `spendChecks`, `reserveUsage` (per person and per server) | `payments-config.test.ts`, `payments.test.ts` daily-limit and race tests | The numbers are defaults the owner has not re-confirmed since the rebase. |
| Off by default | The feature is behind a switch, testnet only, no key in the repository | `DODDY_PAYMENTS_WALLET=none`, per-person switch, `loadPayments` refuses real-money networks, secrets manifest, guard's secret pattern | `payments-config.test.ts`, `payments.test.ts` switch tests, the guard | Mainnet is undecided; nothing was run against Coinbase. |
| DOD-11 / DC-027 | Privacy; web content is data, not instructions | Receipts keep host and amount only; page content labelled and clipped; erased with the account | `payments.test.ts` privacy test, `account.test.ts` (both tables erased) | The page address goes to the seller and the server's IP is visible to it. |
| Repo rule 1 | Model proposes, typed code validates, scoped tools execute | One argument (`url`) accepted; limits and policy in code; the guard keeps Coinbase and signing in their files | strict-input test, guard | The voice prompt has no payment line (nothing depends on a prompt). |

**Claims to limit:** do not write that payments are "implemented", "enabled", "secure" or "tested with Coinbase" for users. Accurate: "the backend payment path, ported to the default branch's database and approval gate, passes its Linux tests against a demo wallet and demo seller; the app side is written and has never been compiled; nothing has run against Coinbase, a seller or a device; it is off by default and test-network only."

**Decisions needed from the owner:** (1) mainnet (and the Circle-confirmed address, a funded balance and caps) stays open; (2) are 0.25 per payment, 1.00 a day, 5.00 for the server and the 0.10 typed-amount threshold still right; (3) does `pay_for_page` ever return to the live agent (ADR-544 removed it), with what exact text; (4) a wallet that belongs to the person, instead of the owner's server wallet.

## Files changed
| Area | Files |
|---|---|
| New: `backend/src/payments/` | `x402.ts` (protocol, policy, typed data, settlement check), `net.ts` (URL and address safety, the only seller HTTPS client), `wallet.ts` (interface, demo wallet), `coinbase.ts` (Coinbase REST + JWTs, no SDK), `service.ts` (prepare / pay / limits / receipts / ledger), `contracts.ts` (HTTP schemas), `mockSeller.ts` (demo seller, 13 scenarios) |
| Changed | `app.ts` (wiring), `config.ts` (payment settings), `http.ts` (`/v1/payments` routes), `store.ts` (two tables, spend release, retention), `errors.ts` (receipt type) |
| Tests | New: `x402`, `paymentsNet`, `coinbase`, `payments`, `payments-config` tests and `paymentsRig.ts`. Changed: `retention.test.ts` (expected shape, plus a payments retention test) |
| Guard / config / docs | `scripts/check_forbidden_capabilities.sh` (payment rules), `backend/.env.example`, `DECISIONS.md` (ADR-730), `DEPENDENCIES_AND_LICENSES.md` (no new dependency), `docs/integrations/PAYMENTS_X402.md`, this file |
| **Not touched** | The widgets, watch app, `voice-agent/`, the existing fixtures in `contracts/connected-apps` and `contracts/online-accounts`, and the existing `/v1/tools` and `/v1/connected-apps` behaviour. (The iPhone files added later are listed under "Native approval card" below.) |

## Shipped behaviour (backend, mock mode and tests)
- `GET /v1/payments`, `PUT /v1/payments/switch`, `POST /v1/payments/prepare`, `POST /v1/payments/pay`, `GET /v1/payments/receipts`.
- Off by default at three layers: no wallet (`DODDY_PAYMENTS_WALLET=none`), per-person switch off, test network. Small caps by default.
- A model can supply only a page address. Price, recipient and token come from the seller's offer and are checked by code.
- Approval: single use, 2 minutes, per person, per page, bound to {page, recipient, amount, token, wallet}; re-checked against a fresh read of the offer at pay time.
- Honest outcomes: `succeeded` only on a valid settlement; `outcome_unknown` otherwise after sending; never retried; duplicate payment to the same page blocked for 15 minutes.
- Receipts and ledger keep the site and amount only; retention 90 days.

## Tests actually run
Environment: Linux, Node 22 (`npm ci` then `npm test` in `backend/`; `node --test`, spec reporter).

| Command | Result |
|---|---|
| `npm test` before any change (baseline) | 188 tests, 188 pass |
| `npm test` after the backend work | 257 tests, 257 pass (69 new). After the fixtures test was added for the native card: **258 tests, 258 pass, 0 fail, 0 skipped** |
| `npm run typecheck` | clean |
| `bash scripts/check_forbidden_capabilities.sh` | PASS, including the new payment rules |
| Guard probe: a temporary Swift file naming `PAYMENT-SIGNATURE` and a backend file calling `api.cdp.coinbase.com` | guard failed on both (exit 1); probes deleted afterwards |
| Mutation check: removed the amount from the approval digest | the price-change test failed (as intended); original restored and byte-compared |
| Second mutation (approval never consumed) | **not run**: the auto-mode classifier blocked it as a security weakening. Not retried. The reuse test exists and passes on the real code, but it has not been shown to fail when the check is removed |

New tests cover: x402 parsing and policy; EIP-3009 typed data and the header; settlement rules; URL and IPv4/IPv6 address
rules; Coinbase JWT structure and signatures (fresh keys per run) and the wallet request against a fake server; the full
flow over HTTP including every failure the demo seller and demo wallet can produce; approvals; daily limits; races; privacy; configuration.

## Manual verification still pending (nobody has done these)
1. **Real Coinbase:** fund a Base Sepolia test account and make one signing request. Expect any problem to be in the
   JWT claims or the typed-data body format (written from docs and SDK source, never sent).
2. **Real seller:** one `prepare` then `pay` against an x402 v2 seller on Base Sepolia; check the `succeeded` receipt's
   transaction on a block explorer. Confirms the `PAYMENT-SIGNATURE` encoding and the `PAYMENT-RESPONSE` header name.
3. **Real HTTPS client** (`PublicHttps`): a live TLS connection, a blocked address, an oversize body.
4. The unconfirmed-payment path with a real seller that times out after payment.
5. Everything on the phone: build it, run `PaymentsTests`, and walk checklist 4o (P1 to P15). None of it has run. The voice tool still does not exist.

## Security and privacy risks
| Risk | State |
|---|---|
| Server holds the CDP API key and Wallet Secret; a leak lets someone request any signature from that account, beyond Doddy's caps | **Open by design.** Mitigation: small funded balance (the real limit), secrets only in the host's secret store, guard flags key-like values. Add CDP-side policies (allowed recipients, per-transaction cap) in the portal if available; not verified from here |
| Prompt injection steers the model to a hostile page | Contained: the model supplies only an address; terms are shown to the person; caps; optional allow-list; page content returns as labelled data |
| SSRF through the URL | Address checked inside the socket's own DNS lookup, https only, no redirects, no IP literals, size cap. Unit-tested; **not run against a live host** |
| A seller changes price between prepare and pay | Blocked: the offer is re-read and must match the approval |
| Double payment (retry, race, replay) | One send per approval; approval consumed once; busy-slot; 15-minute block after an unconfirmed payment. Tested, including a race with two slots |
| A seller keeps an authorization and settles later | The authorization expires within 2 minutes (`validBefore`) |
| Declined or unconfirmed payments still count against the cap | Intentional (conservative); a person can lose headroom for a day after seller errors |
| Custody if several people use it | Not addressed; single-owner only (see decisions) |
| Daily caps and the 15-minute guard are per server process state in SQLite | Fine for the single instance this backend is designed for (as the other limits) |

## Decisions required (owner)
**Answered 2026-10-12 (owner: "approve everything").** Recorded as approvals of what is built or recommended, nothing wider:
1. Whose money: **approved as built**, the owner-funded server wallet, single owner. A person-owned Coinbase wallet with a revocable spend permission is still the way for more than one person; that is a new milestone, not covered by this approval.
2. Mainnet: **not approved, still open.** It needs the owner's balance and caps, and the Base mainnet USDC address confirmed against Circle's list (it has only been seen on a third-party page). Nothing on mainnet is switched on.
3. Approval UX: **approved**, a card with the preview lines plus Face ID for every payment, and the typed amount from 0.10 USDC (the threshold in the last section is confirmed too).
4. x402 v1 sellers: **v2 only**, as built.
5. Physical goods: **separate milestone and provider**, not started.
Approving a decision is not verification: checklist 4o (P1 to P24) is still unwalked, and the Swift and the agent-to-card path have never run.

## Next recommended milestone
1. **Compile and run what was written** (checklist 4o P1 to P11, mock server): expect compile fixes, since no Swift
   toolchain was available. 2. The live Coinbase and seller checks above on the test network (P12). 3. Only then a
   voice-agent tool that can call `prepare` and hands the card to the person (the agent must never reach `pay`; that stays
   behind the card and Face ID), with the agent spec and `VoiceSessionController` changes that needs.

## Constitution evidence log
| Rule | Requirement | Enforcing code | Tests | Gap / claim to limit |
|---|---|---|---|---|
| DOD-07 | No purchase without explicit approval of the exact action | `PaymentsService.pay`: `consumeApproval` bound to `offerDigest` (page, recipient, amount, token, wallet), checked against a fresh offer, consumed before signing | `payments.test.ts`: reuse, expiry, other user, other page, price change, switch off, races | The approval card and a fresh Face ID per payment are **written but never compiled or run**. The server enforces that an approval exists; it cannot tell whether a person saw the card, so "a person approves every payment" is true only once the card has been run on a device (checklist P4 to P8, P13). Do not claim it before then |
| DOD-08 | Never assert success without a trusted confirmation; unknown is not success, never blindly retried | `confirmSettlement` (success + tx hash + network + payer); `unknown()` path; single `http.get` after signing; 15-minute duplicate block | `x402.test.ts` settlement table; `payments.test.ts` four unknown scenarios, declined, wallet failure | Settlement header name and encoding follow the spec text, not a live seller (a mismatch yields `unknown`, never a false success) |
| DOD-09 | Admit errors; plain recovery | Plain messages naming what happened and what is safe ("Nothing was paid" only when proven, else "may or may not"); unresolved count in status | message assertions in `payments.test.ts` | Wording not yet reviewed by the owner or shown in a UI |
| DOD-11 | Privacy as an observable right; untrusted web content is not instructions (DC-027) | Receipts/ledger store host and amount only; page content labelled data, clipped, control characters removed, never stored; `url_hash` not the URL; logs are route templates | privacy test (no path or query anywhere); paid-content tests | Page content does reach the voice agent (by design, labelled). The seller learns the page address and the server's IP |
| Repo rule 1 (REPO_ALIGNMENT) | Model proposes, typed code validates, scoped tools execute; prompts never enforce spending | Strict zod request schemas; only a URL accepted; limits and policy in code | strict-input test; policy tests | No voice-agent prompt or tool was added, so nothing yet depends on a prompt |
| T27 / R29 (risk register) | "Purchase the cheaper option right now" shows item, price, merchant and needs approval; no unintended purchase | `prepare` preview lines; caps; allow-list | flow tests | Shows merchant (site), price, recipient wallet; **there is no "item" for x402** beyond the page address. Not yet evaluated end to end with the agent |

**Claims to limit:** do not write that payments are "implemented" for users, "secure" or "tested with Coinbase". Accurate: "backend
payment path built and tested against a demo wallet and demo seller; Coinbase adapter written to Coinbase's published auth scheme and not
yet run; no app screen or voice tool yet."

## Native approval card (ADR-731, 2026-10-12, owner: "build the native approval card with Face ID")
**Written without a Swift toolchain: never compiled, never run. NOT RUN.** Everything below needs a Mac (checklist 4o).

| Area | Files |
|---|---|
| DoddyCore (new, `Payments/`) | `PaymentsContracts.swift` (mirror of `payments/contracts.ts`), `PaymentsClient.swift` (typed client, `mightHaveBeenPaid`), `PaymentApprovalModel.swift` (the state machine, `PaymentAuthenticator` protocol), `PaymentsSettingsModel.swift` |
| DoddyCore tests (new) | `PaymentsTests.swift`: 37 tests (4 contract, 5 client, 23 state-machine, 5 settings), none of them run |
| App (new) | `Features/Payments/PaymentApprovalCard.swift`, `Features/Payments/PaymentsView.swift`, `Infrastructure/PaymentsClientFactory.swift` |
| App (changed) | `Features/Privacy/AppLock.swift` (`FaceIDPaymentAuthenticator`), `Features/Settings/SettingsView.swift` (Payments row; privacy paragraph) |
| Text | `DataFlow.swift` (Doddy server row), `l10n/pl.json` and the regenerated `Localizable.xcstrings` (38 new Polish lines) |
| Shared fixtures | `contracts/payments/*.json` (12 files from the real server, one per response shape) and the generator in `backend/test/fixtures.generate.ts` |
| Docs | `MAC_VERIFICATION_CHECKLIST_2026-10-10.md` section 4o, `PAYMENTS_X402.md`, `DECISIONS.md` (ADR-731), this file |

**What was actually run for this part:** `npm test` in `backend/` (258 pass; includes a test that every
`contracts/payments` fixture matches the server's strict schemas); `bash scripts/check_forbidden_capabilities.sh` (PASS, so no
wallet, signing or payment-protocol names are in the Swift, and LocalAuthentication is still only in `AppLock.swift`);
`python3 -I tools/build_strings_catalog.py --check` (PASS); a bracket-balance check of the new Swift files; a search for
name clashes with existing declarations. **Not run:** the Swift compiler, `swift test`, `scripts/ci.sh`, Xcode, a device.

**Design choices worth knowing**
- *Unconfirmed, never failed.* The app's request times out at 20 s, but a payment can take longer on the server. If the app
  loses the answer it cannot know, so it shows "Not confirmed", never a retry; **Check again** reads the server's receipts.
- *Face ID is its own check.* It never touches `AppLock.unlockedAt`, so paying can't unlock private notes and an earlier
  unlock can't count as a payment's yes. No biometrics or passcode on the iPhone means the payment is refused.
- *The app composes nothing financial.* It shows the server's lines and label verbatim; the client has no field for an
  amount, recipient or wallet.
- *Voice agent:* not wired in this round (see "Voice agent, typed amount and Home banner" below, which supersedes this).

**Constitution evidence (native part).** DOD-07: Face ID fresh per payment, single `pay` per approval, expired approval
never offered (`PaymentApprovalModelTests`, not run). DOD-08: unconfirmed never failed (`testLosingContact...`,
`testTheServersOwnDoubt...`, not run). DOD-11: the page address going to the server is stated in the Doddy server row and
the Settings paragraph. **Gap:** none of the Swift tests has run; the card's layout, Dynamic Type, VoiceOver and Polish
have never been seen.

**Decisions for the owner, answered 2026-10-12:** (1) "Pay for a page" stays in Settings as an entry point: **ok**. (2) Larger
payments also need the amount typed: **yes** (built below). (3) An unconfirmed payment gets a banner on Home: **yes** (built below).

## Voice agent, typed amount and Home banner (ADR-732, 2026-10-12)
Owner: "wire the voice agent to prepare payments", then answers "ok / yes / yes" to the three open decisions above.
**Backend part run and tested on Linux. Swift and the voice tool: written, never compiled or run, NOT RUN.**

| Area | What |
|---|---|
| Backend (tested) | `DODDY_PAYMENTS_CONFIRM_AMOUNT_USDC` (default 0.10); `prepare` returns `amount` and `confirmAmountRequired`; `pay` takes `confirmAmount` and refuses with `amount_confirmation_required` before reserving or signing, keeping the approval; 14 fixtures in `contracts/payments/` (2 new) |
| Voice spec | `voice-agent/tools.json` `pay_for_page(url)` (phone tool, on-screen confirm, 120 s, `not_synced`); a rule in `voice-agent/instructions.md`. The spec checker passes for both agents; the phone-call agent has no payment tool |
| DoddyCore (new) | `Payments/VoicePayments.swift` (tool name, the one-argument rule, replies), `Payments/PaymentsBannerModel.swift`; `PaymentAmount` and `outcome()` in `PaymentApprovalModel.swift` |
| DoddyCore (changed) | `VoiceCloudTools.swift` (routes the tool), `OnlineAccountsContracts.swift` (`CloudToolCall.isWrite`), `CarProfile.swift` (refused while driving), `ActivityLog.swift` ("Paid for a page", no address), `VoiceTools.swift` (`paid:` is a done word), `PaymentsClient.swift`/`PaymentsContracts.swift` (`confirmAmount`, `amount`) |
| App (new) | `Features/Payments/UnconfirmedPaymentsBanner.swift`, `Infrastructure/PaymentsBannerStorage.swift` |
| App (changed) | `VoiceSessionController.swift` (`handlePayForPage`), `VoiceView.swift` (the sheet), `PaymentApprovalCard.swift` (typed amount field), `PaymentsView.swift` ("I've checked my wallet"), `HomeView.swift`, `RootView.swift` (three preference keys) |
| Tests (Swift, not run) | `PaymentsTests.swift` 50 tests (5 contract, 5 client, 30 state machine, 5 settings, 5 banner); `PaymentsVoiceTests.swift` 11 tests |
| Text | 7 more Polish lines (45 for the feature in all); the Doddy server data-flow row and Settings paragraph already mention payments |

**Run for this part:** `npm test` in `backend/` (**263 pass**, 5 new typed-amount tests and a 14-fixture schema test), `tsc` typecheck, `scripts/check_forbidden_capabilities.sh`
(PASS), `voice_agent_spec.py check` for the app and phone agents (PASS), `build_strings_catalog.py --check` (PASS), `build_blog.py --check` (PASS), a bracket-balance
check of all 20 changed Swift files, a name-clash search. **Not run:** the Swift compiler, `swift test`, `scripts/ci.sh`, Xcode, a device, a live ElevenLabs agent.

**How the agent is kept from paying**
- It supplies one string, `url`; the app refuses any other argument (`PaymentToolName.address`), and the server refuses an amount or recipient from any client.
- The tool call returns only after the person has decided: it waits on `PaymentApprovalModel.outcome()`. Nothing in the agent's reach calls `pay`.
- The person's confirmation is a tap (plus the typed amount from 0.10 USDC up) and Face ID, not speech. The agent is told that saying yes does not approve.
- It rides the cloud-tool route, so the existing gates apply and were tested: refused while driving, refused when connections are paused, never a plan step.
- Replies: `paid:` only for a confirmed payment; `declined:`, `unknown:` (never retry), `failed:`. Page content and failure reasons follow as marked data.
- A new tool name in `CloudToolName.all` was avoided on purpose: a test pins that list to the server's online-account catalog.

**Known limits**
- If the person takes longer than the tool's 120 s timeout (the approval itself lasts 2 minutes), ElevenLabs gives up waiting. The card still works and the receipt is recorded, but the agent never hears the outcome.
- ~~`pay_for_page` is `not_synced`~~ **(History: it was synced 2026-10-12 and detached again by the owner on 19 Oct, ADR-544; on this branch it is `not_synced` again.)** Synced 2026-10-12 at the owner's request (tool `tool_1401m4rmxkm5eg3v87sphf87c45p`, agent version `agtvrsn_8101m4rmy839eks9hgq6hd4pps70`, 60 tool ids, read back). Done before the app was built or checklist 4o was walked, against my earlier advice; the exposure is small because an app without ADR-732 answers the tool as unsupported. The `pay_for_page` prompt line was merged into the live prompt afterwards (version `agtvrsn_9601m4rnnbnxesh9sm34aad15p04`; one added line, verified by diff), so both the prompt and the tool's description carry the rules.
- A page address spoken aloud is hard to get right; the agent is told to ask for the full address and never to guess. Web search results carry only site names, so they cannot supply one.
- The banner depends on the server's count, which only clears when a record is pruned (90 days); "I've checked" hides it locally. No server-side "resolved" call exists.

**Constitution evidence (this part).** DOD-07: typed amount from the threshold, enforced by the server (`payments.test.ts`, run) and the state machine (`PaymentApprovalModelTests`, not run); the agent can only propose (`PaymentsVoiceTests`, not run). DOD-08: `unknown:` never reads as done (`testOnlyAConfirmedPaymentIsDone`, not run). DOD-11: page content and reasons are marked data; the address is not logged in "What Doddy did". **Gap:** the whole agent-to-card path has never run; the ElevenLabs agent has not been tested with the tool; the typed-amount threshold (0.10) is an assumption for the owner to confirm.

**Decisions for the owner:** (1) Is 0.10 USDC the right threshold for typing the amount? (2) Should the agent's wait be longer than 120 s, or should the outcome be delivered later as a spoken follow-up? **Answered 2026-10-12 ("approve everything"): 0.10 USDC stays; the 120 s wait stays, and a later spoken follow-up is not built.** (3) ~~Sync after checklist 4o~~ done early; the first real conversation with the tool should be on the test network with the mock or Base Sepolia wallet (checklist P18 to P22).
