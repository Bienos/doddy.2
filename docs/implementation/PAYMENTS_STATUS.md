# Payments (x402 + optional Coinbase wallet): status

Date: 2026-10-12. Owner instruction: "Use Coinbase wallet connection but not as default and build it so Doddy can pay
for stuff." Decision record: ADR-450 (`DECISIONS.md`). Design, API and owner runbook: `docs/integrations/PAYMENTS_X402.md`.
CLAUDE.md rule 6 asks for milestone approval for cloud actions with money; this instruction is taken as that approval for
**this milestone only**. Branch `claude/fervent-hamilton-ot5z1f`. Environment: Linux, Node 22, **no Xcode**.

**Bottom line:** the backend can read an x402 offer, show exact terms, take a single-use approval bound to them, sign
through an optional Coinbase server wallet, send once, and report only what the seller confirms. It has been tested against
a demo wallet and a demo seller only. **Update (ADR-451): the iPhone approval card with Face ID is now written, but it has
never been compiled or run** (no Swift toolchain here), so treat it as untested. The voice agent cannot start a payment;
the only entry is Settings › Payments › "Pay for a page". Nothing has run against Coinbase or a real seller.

## Files changed
| Area | Files |
|---|---|
| New: `backend/src/payments/` | `x402.ts` (protocol, policy, typed data, settlement check), `net.ts` (URL and address safety, the only seller HTTPS client), `wallet.ts` (interface, demo wallet), `coinbase.ts` (Coinbase REST + JWTs, no SDK), `service.ts` (prepare / pay / limits / receipts / ledger), `contracts.ts` (HTTP schemas), `mockSeller.ts` (demo seller, 13 scenarios) |
| Changed | `app.ts` (wiring), `config.ts` (payment settings), `http.ts` (`/v1/payments` routes), `store.ts` (two tables, spend release, retention), `errors.ts` (receipt type) |
| Tests | New: `x402`, `paymentsNet`, `coinbase`, `payments`, `payments-config` tests and `paymentsRig.ts`. Changed: `retention.test.ts` (expected shape, plus a payments retention test) |
| Guard / config / docs | `scripts/check_forbidden_capabilities.sh` (payment rules), `backend/.env.example`, `DECISIONS.md` (ADR-450), `DEPENDENCIES_AND_LICENSES.md` (no new dependency), `docs/integrations/PAYMENTS_X402.md`, this file |
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
1. Whose money: keep the owner-funded server wallet (single owner), or move to a person-owned Coinbase wallet with a limited, revocable spend permission (recommended for more than one person; needs the native connection flow).
2. Mainnet: when, which balance and caps; confirm the Base mainnet USDC address against Circle's list first.
3. Approval UX: a card with the preview lines plus Face ID for every payment (recommended).
4. x402 v1 sellers: add support, or keep v2 only.
5. Physical goods: separate milestone and provider.

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

## Native approval card (ADR-451, 2026-10-12, owner: "build the native approval card with Face ID")
**Written without a Swift toolchain: never compiled, never run. NOT RUN.** Everything below needs a Mac (checklist 4o).

| Area | Files |
|---|---|
| DoddyCore (new, `Payments/`) | `PaymentsContracts.swift` (mirror of `payments/contracts.ts`), `PaymentsClient.swift` (typed client, `mightHaveBeenPaid`), `PaymentApprovalModel.swift` (the state machine, `PaymentAuthenticator` protocol), `PaymentsSettingsModel.swift` |
| DoddyCore tests (new) | `PaymentsTests.swift`: 37 tests (4 contract, 5 client, 23 state-machine, 5 settings), none of them run |
| App (new) | `Features/Payments/PaymentApprovalCard.swift`, `Features/Payments/PaymentsView.swift`, `Infrastructure/PaymentsClientFactory.swift` |
| App (changed) | `Features/Privacy/AppLock.swift` (`FaceIDPaymentAuthenticator`), `Features/Settings/SettingsView.swift` (Payments row; privacy paragraph) |
| Text | `DataFlow.swift` (Doddy server row), `l10n/pl.json` and the regenerated `Localizable.xcstrings` (38 new Polish lines) |
| Shared fixtures | `contracts/payments/*.json` (12 files from the real server, one per response shape) and the generator in `backend/test/fixtures.generate.ts` |
| Docs | `MAC_VERIFICATION_CHECKLIST_2026-10-10.md` section 4o, `PAYMENTS_X402.md`, `DECISIONS.md` (ADR-451), this file |

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
- *Not wired into the voice agent.* `VoiceSessionController` and `voice-agent/` were not touched: blind edits to a 2,000-line
  controller that handles live conversations were not worth the risk before the card itself has compiled.

**Constitution evidence (native part).** DOD-07: Face ID fresh per payment, single `pay` per approval, expired approval
never offered (`PaymentApprovalModelTests`, not run). DOD-08: unconfirmed never failed (`testLosingContact...`,
`testTheServersOwnDoubt...`, not run). DOD-11: the page address going to the server is stated in the Doddy server row and
the Settings paragraph. **Gap:** none of the Swift tests has run; the card's layout, Dynamic Type, VoiceOver and Polish
have never been seen.

**Decisions for the owner:** (1) Is "Pay for a page" in Settings acceptable as the only entry until the voice tool exists, or
should it be hidden outside development builds? (2) Should a payment over a set amount ask for Face ID *and* a typed
confirmation of the amount? (3) Should an unconfirmed payment keep a banner on Home, not only in Settings › Payments?
