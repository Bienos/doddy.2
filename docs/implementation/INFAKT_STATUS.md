# inFakt invoices: draft, preview, confirm (ADR-640)

Owner, 24 Oct 2026: "inFakt" as the invoice provider (ADR-630) and, answering where the key lives, "W iPhonie, w Keychain": invoices go from the phone straight to inFakt; Doddy's server never sees them or the key. Branch `claude/infakt-inpost`, stacked on `claude/expert-modes-research` (PR #140). Research: `docs/research/2026-10-24/research_expert_modes_PL.md` section 5 and acceptance tests 8 and 9. **Status of each part is at the end; nothing here has been seen on a device and no request has ever been sent to inFakt.**

## 30 Oct 2026: invoices by voice, and getting ready for KSeF (ADR-667)

Owner, 30 Oct 2026: "Make sure invoicing works properly now by talking and how to improve it so it's ready for ksef". Research of the same day, every fact tagged and sourced: `docs/research/2026-10-30/ksef_infakt_research.md` (inFakt's field tables from the Postman collection behind docs.infakt.pl, the FA(3) brochure of August 2026 and its XSD, MF's KSeF pages and API docs).

**What the field tables settle (read, not yet seen in a real answer):** prices are integer **grosze** (`unit_net_price` "Cena netto za sztukę (grosze)", `net_price`, `gross_price`, `tax_price`); the create request takes **`invoice_date`, `sale_date` and `payment_date`** (the due date), all optional. The two [U] rows below about units and date fields are now [V] from inFakt's own docs. Still no idempotency key or field for the caller's own id. `InFaktAPI.createVerified` stays `false`: the repo's rule is one real create call in the sandbox before anything is sent, and none has been made.

**What the research says KSeF needs (each tied to a row there):**
- KSeF issuing is mandatory since 1 Apr 2026 (1 Feb for the largest firms); the ≤10,000 PLN a month exception ends **31 Dec 2026**. Penalties start 1 Jan 2027 under current law; a draft law of 20 Oct 2026 would move them to the end of 2027 (not law yet). B2C invoices in KSeF are optional. (A1–A6)
- An invoice accepted by KSeF can't be edited, cancelled or deleted, only corrected. A wrong buyer NIP sends the invoice to that other firm. (A11)
- KSeF refuses an issue date (P_1) after the day it is sent; a past one counts as offline24 and must reach KSeF by the next business day. (A13–A15)
- inFakt sends to KSeF only when asked (`send_to_ksef`, or `POST /api/v3/ksef2/documents/{uuid}/send.json`), answers `pending`, `sent`, `success` (with `ksef_number`), `error` or `rejected`, and needs the KSeF 2.0 connection set up **in the inFakt web app** (not through the API); without it every send is 422. (C6, C9, C10, C12)
- `zw` needs an exemption id from `/vat_exemptions.json`; split payment is `split_payment` + `split_payment_type`; the bank account must be verified in inFakt first; inFakt refuses `&`, `<`, `>` and double spaces in item names. (C16–C19)

**Built on 30 Oct 2026 (DoddyCore, tested on Linux; app screens written, not compiled):**
- **`draft_invoice`, a voice tool** (`Invoices/InvoiceVoice.swift`): the person dictates, the agent sends only what changed, and the draft on the voice screen grows call by call (one line per call). A **NIP counts as said only if its ten digits are in the person's own transcribed words** (digits or digit words, across turns); a **VAT rate only if the rate is in their words**. Anything else stays the model's suggestion: shown with a question mark, counted as missing, settled by saying it or by the person's tap on **Confirm** next to it on the card. Net from a gross price, the sums and the due date from "14 dni" are worked out by code. No issue date said means today; a future one is refused (KSeF would reject it); a past one is accepted with the offline24 warning. Nothing leaves the iPhone and the draft isn't saved: it lasts the conversation. The agent hears what is missing, the sums and that nothing was sent; never "issued".
- **Draft rules for KSeF** (`InvoiceDraft.swift`): no sale date means the issue date (art. 106e ust. 1 pkt 6; FA(3) P_6), so it is no longer "missing"; **every buyer's address is required**, a private person's too (art. 106e ust. 1 pkt 3); above **15,000 PLN gross** the draft asks whether **split payment (MPP)** applies (annex 15, P_18A); `&`, `<`, `>` in an item's name are refused; **another currency than PLN, or a buyer abroad, is marked not ready** (KSeF needs the VAT in PLN and an exchange rate; foreign buyers need an EU VAT number and 0 WDT / 0 EX / np rates, whose mapping in inFakt is undocumented).
- **KSeF status** (`Invoices/KsefStatus.swift`, `InvoiceOperation.ksef`): inFakt's answers mapped to `notSent`, `pending`, `accepted(KsefNumber)`, `rejected(reason)` and `unknown`. **Only `success` with a KSeF number in the right shape** (35 characters, the seller's NIP, the date, 12 hex, 2 check) is in KSeF; `success` without one is still pending; an unreadable answer is unknown, never success and never a reason to resend. Recorded only after inFakt's receipt; accepted is final. The card no longer says "issued in inFakt": it says "created in inFakt, not sent to KSeF yet" until a KSeF number exists.

**Next, in order (each a separate step):**
1. **Owner:** an inFakt **sandbox** account and key (`api:invoices:read` + `api:invoices:write` only), then one create call to see the real answer; only then `createVerified = true`. The sandbox is connected to KSeF's test environment, and data sent there "may be visible to others": use made-up buyers.
2. The inFakt client in the app: async create in grosze with `invoice_date` / `sale_date` / `payment_date`, the `client_*` fields, `split_payment`, reading `/async/invoices/status/{ref}.json`; the capability guard opened for exactly that one address.
3. **Send to KSeF as its own tap**, after the invoice exists, with a card that says it can't be undone (only corrected); then poll `ksef2/documents/{uuid}/status.json` and record `KsefStatus`. Never `DELETE` an invoice that has a KSeF number.
4. `zw`: replace the free-text reason with inFakt's exemption list (`/vat_exemptions.json`), picked by the person.
5. Keep a draft across conversations, with verified storage (today it is gone when the conversation ends).
6. Foreign buyers and currencies, after the sandbox shows how inFakt maps `0` and `np` to 0 WDT / 0 EX / np I / np II.
7. For a consumer or foreign buyer, a copy with KSeF's QR code (KOD I); check whether inFakt's PDF carries it before saying so.
8. From 1 Jan 2027 the KSeF number must be on B2B transfers: show it with Copy on the card.

**For the person using it:** the inFakt account needs its **KSeF 2.0 connection set up in the inFakt web app** and the bank account verified there; Doddy can't do either.

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

## What inFakt's own documentation says (27 Oct 2026)

Read from the Postman collection behind `docs.infakt.pl` (`https://docs.infakt.pl/api/collections/4951438/2s8ZDa31yd`, 203 requests). **[V] means it is written there; no call with a key has been made**, so none of this is yet seen in a real answer. Without a key, `GET` on both `api.sandbox-infakt.pl/api/v3/invoices.json` and `api.infakt.pl/api/v3/invoices.json` answers **401** `{"error":"Musisz podać klucz API."}` (observed 27 Oct 2026), and the collection's auth is the header `X-inFakt-ApiKey`.

| Fact | Tag |
|---|---|
| Creating an invoice is asynchronous: `POST /async/invoices.json` answers **201** with `invoice_task_reference_number`, `processing_code` 100 ("Zlecenie przyjęte") and `timestamps.task_created_at`. | [V] |
| The result is read with `GET /async/invoices/status/{invoice_task_reference_number}.json` (needs `api:invoices:read`): `processing_code` **100/120/140** = accepted / waiting / being processed, **201** = created (the answer then carries `invoice_uuid`), **422** = not created (the answer carries `invoice_errors`, a map from field to messages, e.g. `payment_method`). | [V] |
| An invoice is read with `GET /invoices/{invoice_uuid}.json`. Its dates are `invoice_date`, `sale_date`, `payment_date` (the due date), `paid_date`; also `continuous_service_start_on` / `_end_on` and `invoice_date_kind`. | [V] |
| In every example `net_price` and `unit_net_price` are integers: net 6623, tax 1523, gross 8146 at 23%. That fits **grosze** (6623 × 1.23 = 8146.29), but no sentence says the unit. | [U], inferred |
| Services take `name`, `quantity` (decimals such as 0.5 are in an example), `unit_net_price` / `net_price` or `gross_price` (not both), `tax_symbol` (a number in requests, a string in answers), `pkwiu`. The buyer is `client_company_name` (a saved client) or `client_*` fields with `client_tax_code` for the NIP. | [V] |
| The create body also takes `status` (`draft` by default, `paid`, `printed`) and, next to `invoice`, `send_to_ksef` (boolean). There is also `POST /invoices/{invoice_uuid}/send_to_ksef.json`, and the older `ksef2/documents/{uuid}/send.json` still appears. | [V] |
| **No idempotency key and no field for the caller's own id** appears anywhere in the create request. If the answer to a create is lost, the invoice cannot be found again by Doddy's operation id; the rule stays: an unknown outcome is not a success and is not resent, and the person checks inFakt. | [V] that none is documented |
| Not in any example: the name of the **due-date field in a create request** (the read answer says `payment_date`), and the names of `invoice_date` / `sale_date` in a create. | [U] |

So the **units** (grosze, inferred) and the **due-date field name in a create** are still settled only by one real create call in the sandbox. `InFaktAPI.createVerified` stays `false` until then.

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
| Settings › Invoices (inFakt): save, replace, remove the key; the example card (`InFaktSettingsView.swift`, `InvoiceCardView.swift`) | Written, **BLOCKED / NOT RUN** (SwiftUI). The example is labelled as one and has gaps on purpose. From 27 Oct 2026 a "Paste the key from the clipboard" button fills the secure field from the clipboard (UIPasteboard, so iOS may ask to allow the paste); the key is checked and kept only on Save. **How to make the key** (`InFaktKeyGuideView.swift`, 27 Oct 2026): four steps (open inFakt, Settings › API, tick only `api:invoices:read` and `api:invoices:write`, copy), a paste button that appears when the clipboard holds text (`hasStrings`, which does not show iOS's paste prompt), and a note that the write right also lets a key change and delete invoices. "Open inFakt" opens `https://www.infakt.pl`: the signed-in panel's address could not be checked (inFakt's firewall answers bots with a 403), so it is not guessed. It sends nothing; a **key check against inFakt is not built** because the capability guard allows no inFakt networking until the real client exists. Written, **BLOCKED / NOT RUN** (SwiftUI). |
| What leaves this iPhone row for inFakt | Real, tested. Not active while `createVerified` is false; says so. |
| `UnverifiedInFaktProvider` and the create/find calls | Stub. Refuses to run. |
| inFakt client in the app, the real create call, reading its answer, finding an invoice by operation id after an unknown outcome | **Not built.** Needs a sandbox call (see above). |
| Drafting by voice (`draft_invoice`, `Invoices/InvoiceVoice.swift`; 30 Oct 2026, ADR-667) | Real, tested on Linux (`InvoiceVoiceTests`). The voice screen's card and the controller's handler are written, **NOT COMPILED** (no Xcode). In `voice-agent/tools.json` as `not_synced`: **not on the live ElevenLabs agent**. Messages: not built. |
| Send to KSeF | **Not built.** The status rules are (`KsefStatus`, tested); the call is a separate confirmed operation after the invoice exists (step 3 above). |

**For the owner:** (1) a free inFakt sandbox account and an API key with `api:invoices:read` and `api:invoices:write` only, to settle the [U] rows with one create call; (2) whether drafts may come from a voice tool once that is settled; (3) whether KSeF send follows.
