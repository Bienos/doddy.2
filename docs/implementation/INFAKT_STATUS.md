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
- **Stub, off by default, refuses to run:** the transport that creates an invoice and the one that sends it to KSeF. The units of the price fields, the date fields, the create answer and the KSeF address are [U]; a wrong guess here would issue a wrong invoice on someone's books. `InFaktTransport.isVerified` is `false` and the client throws `notVerified` before any request is made.
- **What unblocks it:** a sandbox key (free, from `konto.sandbox-infakt.pl`) so one real create call in the sandbox can settle the units, the date fields and the async answer, or the field tables of docs.infakt.pl read by a person.

## Status

Filled in at the end of the build (see the commits).
