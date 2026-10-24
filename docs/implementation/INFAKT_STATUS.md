# inFakt invoices: draft, preview, confirm (ADR-633)

Owner, 24 Oct 2026: "inFakt" as the invoice provider (ADR-630) and, answering where the key lives, "W iPhonie, w Keychain": invoices go from the phone straight to inFakt; Doddy's server never sees them or the key. Branch `claude/infakt-inpost`, stacked on `claude/expert-modes-research` (PR #140). Research: `docs/research/2026-10-24/research_expert_modes_PL.md` section 5 and acceptance tests 8 and 9. **Status of each part is at the end; nothing here has been seen on a device and no request has ever been sent to inFakt.**

## What step 0 found (24 Oct 2026)

Tags: **[V]** read on inFakt's own documentation (`docs.infakt.pl`) or its help center (`pomoc.infakt.pl`); **[S]** third party (wrappers, plugins); **[U]** not confirmed.

| Fact | Tag | Source |
|---|---|---|
| Production base `https://api.infakt.pl/api/v3`; sandbox `https://api.sandbox-infakt.pl/api/v3`. A free sandbox account and test key: `https://konto.sandbox-infakt.pl/rejestracja`, then Settings › API. Sandbox: tests only, 2,500 invoices a month, company data anonymised. | [V] | docs.infakt.pl; help article "Środowisko testowe API Sandbox" |
| The key goes in the header `X-inFakt-ApiKey`; bodies are UTF-8 JSON with `Content-Type: application/json`. | [V] | docs.infakt.pl |
| **The key has scopes chosen when it is made:** `api:invoices:read`, `api:invoices:write` (add, change, delete invoices, clients, products; send e-mails), `api:ksef:integration:write` (set up or disconnect the KSeF integration), and others (accounting, costs, bank accounts). A key is made in Settings › API after typing the account password. | [V] | docs.infakt.pl; help article "Dodawanie nowego klucza API" |
| Limits per IP address: 300 GET and 150 other requests per 60 s; 100 records per list page; at most 3,000 invoice e-mails a day (20 a day on accounts that never paid). | [V] | docs.infakt.pl |
| Sending an invoice to KSeF through the API: `POST …/ksef2/documents/{document_uuid}/send.json`, asynchronous; status at `…/ksef2/documents/{document_uuid}/status.json` with `"sent"` (initial), `"success"` (with `ksef_number`) or `"error"` (`status_description`); the account must already be integrated with KSeF, else **422**. | [V] | help article "Wysyłka faktur przez API KSeF" (updated 12 May 2026) |
| **The same article spells the send address two ways**: `https://api.infakt.pl/v3/ksef2/…` (no `/api`) in the example and `api/v3/ksef2/…` in the text. Which one is right is not settled. | [U] | same article |
| An invoice is created with `POST …/async/invoices.json` (asynchronous) or `…/invoices.json`; body `{"invoice":{"payment_method":"cash","client_company_name":"…","services":[{"name","net_price","unit_net_price","tax_symbol","pkwiu"}]}}`. | [V] for the shape of one official example | help article "Jak wystawić przez API fakturę z danymi Podmiotu 3" (15 May 2026) |
| **Not found in any official text I could open:** whether `net_price` is in grosze or zloty (the example shows `6623` for a service named "Przykładowa Usługa"), the names of the date fields, what the asynchronous create answers with, and how to read its result. The help article "Dodawanie faktury przez API" has only readers' comments in what loaded. The field tables of docs.infakt.pl did not come through. | [U] | |
| VAT rates `23`, `8`, `5`, `0`, `np`, `zw`; payment methods `transfer`, `cash`, `card`, `paypal`, `barter`, `cod`; currencies PLN, EUR, USD, GBP; `zw` needs an exemption reason id. These are the fields of inFakt's Zapier action, which is its own help page. | [V] for the Zapier action; [U] whether the raw API takes exactly these | help article "Jak automatycznie tworzyć faktury przez Zapier" |
| A third-party wrapper uses `client_tax_code` for the buyer's NIP and `client_street`, `client_street_number`, `client_city`, `client_post_code`. | [S] | github.com/kapicaoskar/infakt |

## What this means: what is real and what is a stub

- **Real (DoddyCore, tested on Linux):** the invoice draft, the NIP check, the VAT math in integer grosze, the missing-data report, the payload digest, the confirmation state machine, the "unknown outcome → check status, never resend" rule, a provider protocol and a fake provider.
- **Stub, off by default, refuses to run:** the transport that creates an invoice and the one that sends it to KSeF. The units of the price fields, the date fields, the create answer and the KSeF address are [U]; a wrong guess here would issue a wrong invoice on someone's books. `InFaktAPI.createVerified` is `false`, `UnverifiedInFaktProvider` throws `notVerified` before any request is made, and the app has no inFakt client at all (the capability guard fails if the app names inFakt's address or key header without one).
- **What unblocks it:** a sandbox key (free, from `konto.sandbox-infakt.pl`) so one real create call in the sandbox can settle the units, the date fields and the async answer, or the field tables of docs.infakt.pl read by a person.

## Status

As of the last commit of branch `claude/infakt-inpost` (24 Oct 2026). "Tested" means `make test-core` on Linux (Swift 6.1.2): 1,896 tests, 0 failures. Nothing below has been compiled with Xcode or seen on a device, and no request has ever been sent to inFakt.

| Part | State |
|---|---|
| Invoice draft, `Sourced` fields, NIP check, dates, VAT rates, currencies, payment methods (`Invoices/InvoiceBasics.swift`, `InvoiceDraft.swift`) | Real, tested (`InvoiceTests`). A NIP, address, buyer kind or VAT rate the model only proposed counts as missing. |
| Sums in integer grosze, VAT per rate on the sum of nets (`InvoiceTotals.swift`) | Real, tested, with overflow refused. |
| Confirmation bound to the SHA-256 of the exact invoice; `pendingExternalWrite` saved before the call; receipt must name the operation; `unknownOutcome` never resent; none-found needs a new yes (`InvoiceOperation.swift`, `InvoiceSender`) | Real, tested against a scripted fake provider (succeed, reject, answer lost after create, timeout before create, answer for another operation). |
| Invoice card wording, sums and problems in Polish and English (`InvoiceCard.swift`) | Real, tested. The Confirm button is not offered while `InFaktAPI.createVerified` is false. |
| inFakt key: format check, masked display, save/remove confirmed by reading back (`AccountKey.swift`) | Real, tested against a fake store that refuses, forgets, stores something else or cannot be read. |
| Keychain store, wipe on Delete all, clear on a fresh install (`AccountKeyStore.swift`) | Written, **BLOCKED / NOT RUN** (Keychain, no Xcode). The guard allows `SecItem` only in the files that already hold a token or key. |
| Settings › Invoices (inFakt): save, replace, remove the key; the example card (`InFaktSettingsView.swift`, `InvoiceCardView.swift`) | Written, **BLOCKED / NOT RUN** (SwiftUI). The example is labelled as one and has gaps on purpose. |
| What leaves this iPhone row for inFakt | Real, tested. Not active while `createVerified` is false; says so. |
| `UnverifiedInFaktProvider` and the create/find calls | Stub. Refuses to run. |
| inFakt client in the app, the real create call, reading its answer, finding an invoice by operation id after an unknown outcome | **Not built.** Needs a sandbox call (see above). |
| Drafting by voice or Messages (a tool that proposes an invoice) | **Not built.** A new tool needs its own approval and the ElevenLabs agent is not touched. |
| Send to KSeF | **Not built.** A separate confirmed operation after the invoice exists. |

**For the owner:** (1) a free inFakt sandbox account and an API key with `api:invoices:read` and `api:invoices:write` only, to settle the [U] rows with one create call; (2) whether drafts may come from a voice tool once that is settled; (3) whether KSeF send follows.
