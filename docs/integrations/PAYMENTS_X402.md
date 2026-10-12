# Doddy paying for things (x402), with an optional Coinbase wallet

Date: 2026-10-12. Owner instruction: "Use Coinbase wallet connection but not as default and build it so Doddy can pay for stuff."
ADR-450. Status report and constitution evidence log: `docs/implementation/PAYMENTS_STATUS.md`.

> **State: backend built and tested on Linux against a demo seller and a demo wallet. The iPhone approval card with Face
> ID (ADR-451) is written but has never been compiled or run (no Swift toolchain was available). Nothing has run against
> the real Coinbase service, a real x402 seller, a funded wallet, or the voice agent.** The only way to start a payment
> from the app is Settings › Payments › "Pay for a page"; the voice agent cannot start one yet.

## What this is, and what it is not

- **It is** pay-per-use for *digital* things that speak [x402](https://github.com/x402-foundation/x402): a page, an API
  or a dataset answers `HTTP 402 Payment Required` with a price; Doddy pays in USDC and gets the content. Good fit:
  "research this", where Doddy buys a paid source for a few cents.
- **It is not** a shopping cart. Ordinary shops (a pair of shoes, a flight) do not speak x402. Buying those needs a
  different rail (card or checkout integrations) and is a separate decision.
- **Doddy's own web search** (Monid, `docs/integrations/ONLINE_ACCOUNTS.md`) is unchanged. It uses a different, older
  path: one fixed endpoint, paid from Doddy's Monid wallet.

## Nothing is a default

| Layer | Default | To turn on |
|---|---|---|
| Server wallet | `DODDY_PAYMENTS_WALLET=none`: every payment route answers "not set up" | The owner sets `coinbase_cdp` plus four `CDP_*` values (below) |
| Network | `base-sepolia` (test network, no real money) | Owner sets `DODDY_PAYMENTS_NETWORK=base` |
| Each person's switch | Off (`pay_x402`, same switch table as the other tools) | The person turns it on in Settings › Payments (written, not yet run) |
| Per payment | 0.25 USDC | `DODDY_PAYMENTS_MAX_PER_PAYMENT_USDC` |
| Per person per day | 1.00 USDC | `DODDY_PAYMENTS_USER_DAILY_USDC` |
| Whole server per day | 5.00 USDC | `DODDY_PAYMENTS_SERVICE_DAILY_USDC` |
| Which sites | Any public https site | `DODDY_PAYMENTS_ALLOWED_HOSTS=a.example,b.example` |

Mock mode (the default `DODDY_MODE`) uses a demo wallet and an offline demo seller. It makes no network calls and moves
no money; its receipts say `mode: "mock"`.

## How a payment happens

```
Doddy proposes a page (a URL is the only thing a model supplies)
 │
 ├─ POST /v1/payments/prepare {url}
 │    wallet set up? switch on? public https URL? ──► (no) blocked, with a receipt
 │    plain GET of the page ──► 402 + offer         (nothing is signed or paid)
 │    offer within policy? (exact, this network, the pinned USDC, a real address, ≤ cap, room today)
 │    ──► {preview, approvalId}   approval = single use, 2 minutes, bound to
 │                                 {page, recipient, amount, token, wallet}
 │
 ├─ the person sees: "Pay 0.05 USDC to shop.example (wallet 0x1234…abcd) from Coinbase wallet 0xAB12…89EF" and approves
 │
 └─ POST /v1/payments/pay {url, approvalId}
      same gates ──► read the offer AGAIN ──► must match the approval (a changed price or recipient needs a new one)
      reserve today's spend ──► use up the approval ──► write the ledger row
      sign (wallet) ──► send ONCE with PAYMENT-SIGNATURE ──► read the seller's PAYMENT-RESPONSE
      "paid" only on a valid settlement (success, tx hash, this network, this payer); otherwise see below
```

What leaves the server: the page address to the seller, and a signed EIP-3009 transfer authorization that is only
valid for the approved recipient and amount for at most two minutes. The wallet can sign one thing, that authorization;
it is never given a free-form message, a transaction or a different recipient. The account's private key is never in
this process: Coinbase signs inside its own service, and the app never holds any key. **The server does hold the
credentials that authorise signing** (the CDP API key and the Wallet Secret, in its environment). Anyone who obtains
them can ask Coinbase to sign *anything* from that account, outside Doddy's caps. That is why the account's funded
balance, not Doddy's code, is the final spending limit: keep it small, and treat those two values like a bank card.

### Outcomes (DOD-08: no "done" without a trusted confirmation)

| What the seller did after Doddy sent the payment | Receipt | Spend counted | Retried | Same page again |
|---|---|---|---|---|
| 2xx with a valid `PAYMENT-RESPONSE` (success, tx hash, network, payer) | `succeeded` + tx hash | yes | n/a | allowed |
| 402 again | `failed` (`payment_declined`) | yes (conservative) | no | allowed |
| 2xx without a valid settlement, 4xx/5xx other than 402, timeout, network error | `outcome_unknown` (`payment_unconfirmed`) | yes | **never** | refused for 15 minutes |
| (before sending) the wallet could not sign | `failed` (`wallet_unavailable`), "nothing was paid" | no (given back) | no | allowed |

An unconfirmed payment is listed in `GET /v1/payments` as `unresolved` until the person has checked the wallet's
history. The signed authorization stops being usable after `validBefore` (at most two minutes), and the message says
when. A server that stops mid-payment leaves a ledger row that shows as unresolved after five minutes; nothing is
forgotten.

## HTTP contract (`/v1/payments`, separate from `/v1/tools` on purpose)

The existing app decodes the tools catalog and receipts strictly. Payments live under their own path so they cannot
change what the shipped app sees. Request bodies are strict (a wallet, amount, recipient, network or token from a
client is a 400). Errors reuse the existing error codes; the specific reason is in `receipt.errorCode`.

| Route | Body | Result |
|---|---|---|
| `GET /v1/payments` | | `PaymentStatus`: wallet kind/short address/network/testNetwork, `enabled`, limits and used today, `unresolved` |
| `PUT /v1/payments/switch` | `{enabled}` | `{status, receipt}`; turning on needs a wallet |
| `POST /v1/payments/prepare` | `{url}` | `{mode, preview{title,lines,confirmLabel}, approvalId, expiresAt}` |
| `POST /v1/payments/pay` | `{url, approvalId}` | `{mode, text, receipt}`; `text` is for the voice agent (page content labelled as data, clipped to 4000 characters, never stored) |
| `GET /v1/payments/receipts` | | the person's last 30 payment receipts |

Schemas: `backend/src/payments/contracts.ts`. Demo scenarios (mock mode only) via the header
`x-doddy-payments-scenario`: `normal not_required version_1 wrong_network wrong_asset too_expensive price_changes declined
server_error no_proof bad_proof timeout_after_payment unreachable wallet_unavailable`.

Privacy: receipts and the ledger keep the **site name and the amount**, never the page path or query (they can say what a
person was researching). Retention matches the other receipts: 90 days. Logs carry route templates only.

## Configuration (live mode)

```
DODDY_PAYMENTS_WALLET=coinbase_cdp
DODDY_PAYMENTS_NETWORK=base-sepolia          # base = real money
CDP_API_KEY_ID=…                             # CDP portal › API keys › Secret API key (Ed25519)
CDP_API_KEY_SECRET=…                         # base64 of 64 bytes, as the portal shows it
CDP_WALLET_SECRET=…                          # CDP portal › Wallet Secret (base64 PKCS#8 P-256)
CDP_PAYMENT_ACCOUNT_ADDRESS=0x…              # a server (EVM) account created in the portal
```

Set these in the server host's secret store yourself. Never paste them into chat or the repository (the capability
guard script flags key-like values in the code and tests). The server refuses to start on a missing or malformed value and names the
variable, never the value. `production` + `live` is still refused until real app sign-in exists (existing rule).

### Owner setup, test network first (not yet done; steps not run)

1. In the Coinbase Developer Platform portal: create a project, a Secret API key (choose Ed25519) and a Wallet Secret,
   and create one **EVM server account**. Doddy never creates accounts.
2. Fund that account with **Base Sepolia test USDC** (not real money). Keep the balance small: the account balance is
   the real, final spending limit, whatever Doddy's caps say.
3. Put the four `CDP_*` values and `DODDY_PAYMENTS_WALLET=coinbase_cdp` on the server. Leave the network on
   `base-sepolia`.
4. Pay a seller you control or a public x402 demo endpoint on Base Sepolia (none has been verified from here) with
   `prepare` then `pay`, and confirm: a `succeeded` receipt with a real transaction hash that you can see on a Base
   Sepolia block explorer.
5. Also try: a wrong price, a refused host, an expired approval, and unplugging the wallet (expect `wallet_unavailable`).

**Before any mainnet use** (`DODDY_PAYMENTS_NETWORK=base`): confirm the USDC address in `x402.ts` against Circle's
official contract list (the Base *Sepolia* address was confirmed against Circle's page; the Base *mainnet* address was
only seen on a third-party page), fund a minimal balance, keep the caps small, and read "Open decisions" below.

## The iPhone side (ADR-451; written, never compiled)

| Piece | Where | What it guarantees |
|---|---|---|
| Contracts and client | `Packages/DoddyCore/.../Payments/PaymentsContracts.swift`, `PaymentsClient.swift` | Decode the shared fixtures in `contracts/payments/`. The client can send only a page address and an approval: there is no call that takes an amount, a recipient or a wallet |
| State machine | `PaymentApprovalModel.swift` | `idle → preparing → awaitingApproval → authenticating → paying → paid / failed / unconfirmed`. Pays at most once per approval; Face ID every time (no remembered yes); an expired approval never reaches Face ID or the server; no cancel or dismiss while paying; after the server was asked to pay, any doubt (lost connection, unreadable answer, 5xx without a receipt) is **unconfirmed, never failed**, and nothing offers "pay again" |
| Face ID | `FaceIDPaymentAuthenticator` in `DoddyApp/Features/Privacy/AppLock.swift` (the only file allowed LocalAuthentication) | A fresh check per payment; separate from the app lock (never reads or sets `unlockedAt`, so it can't unlock private notes); no Face ID, Touch ID or passcode means refused, never skipped |
| Card | `DoddyApp/Features/Payments/PaymentApprovalCard.swift` | Shows the server's own lines (the app never composes an amount or recipient); the confirm button carries the server's label; Close is disabled and the sheet can't be swiped away while paying |
| Settings | `PaymentsView.swift`, a row in `SettingsView.swift` | Switch moves only when the server accepts it; wallet, limits, an unconfirmed-payments warning, recent receipts, and "Pay for a page" |
| Privacy text | `DataFlow.swift` (Doddy server row) and the Settings paragraph, with Polish | The page address going to the server for a payment is stated |

A request that outlives the app's 20-second timeout (the server may spend longer reading the offer, signing and paying)
is exactly the case the unconfirmed state exists for: the app shows "Not confirmed", offers **Check again** (which reads
the server's receipts and resolves the payment from them) and never a retry.

## What was verified, and what was not

Verified (Linux, Node 22, `npm test` in `backend/`, 258 tests, all pass; baseline before this work 188):
x402 v2 parsing and policy; EIP-3009 typed data and header encoding; settlement confirmation rules; SSRF rules for URLs
and addresses (IPv4/IPv6/mapped forms); the JWT construction for Coinbase (structure and signatures, checked against
freshly generated keys) and the request the wallet sends (checked against a fake server); the whole prepare/pay flow
over HTTP with every failure scenario; approvals (single use, expiry, per user, per page, price change); daily limits;
the unknown-outcome rules; privacy (no path or query stored); configuration; the capability guard (probe-tested).

**Not verified** (each is a real gap):
- Any request to the real Coinbase service. The JWT scheme follows Coinbase's published docs and SDK source, but a
  wrong claim or body format would only show up live. Expect a first-run fix at most there.
- Any real x402 seller. Two details come from the spec's prose, not an example: the base64 encoding of the
  `PAYMENT-SIGNATURE` value, and the `PAYMENT-RESPONSE` header name (`X-PAYMENT-RESPONSE` is also read). A seller that
  differs would lead to `payment_unconfirmed`, never to a false "paid".
- The real HTTPS client (`PublicHttps`) against a live host. Its address rules are unit-tested and it refuses blocked
  addresses without connecting, but a TLS connection to a real seller has not been made.
- The iPhone: the approval card, Face ID step and Settings › Payments screen are written (see "The iPhone side"
  below) but were **never compiled or run**: this environment has no Swift toolchain. No voice-agent tool exists.

## Limits of this version (each refused with a plain message, never guessed)

x402 **v2 only** (v1 sellers are refused as "older payment version"); scheme `exact` only; USDC via EIP-3009 only;
Base (or Base Sepolia) only; recipient must be a real 0x address; no redirects are followed; response bodies are cut at
256 KB; content other than text/JSON is paid for but not read out; no refunds, disputes or receipts from the seller.

## Open decisions (owner)

1. **Whose money.** Today the wallet is a server-side account the owner funds: a single-owner arrangement, like the
   Monid wallet. For several people, holding their funds is custody and may be regulated. The alternative is a wallet the
   person owns (Coinbase's Base Account) that grants Doddy a limited, revocable *spend permission*; that needs the
   native wallet connection flow and is the recommended next step, not built.
2. **Mainnet.** When, with what balance and caps, after the checks above.
3. **Where the approval happens.** Decided and built (not yet run): a card that shows the server's preview lines and
   asks Face ID for every payment, right before `POST /v1/payments/pay`.
4. **Physical goods.** Separate milestone and provider choice (virtual cards or checkout APIs).
