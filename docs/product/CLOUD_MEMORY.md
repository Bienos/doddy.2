# Memory on Doddy's server, and chat with it (ADR-603)

**Status: owner-approved 22 Oct 2026. The server and the web pages are built and tested. The iPhone half (23 Oct) is written: its rules and client are tested in DoddyCore on Linux, its SwiftUI screens and hooks are NOT COMPILED. Not deployed.** This is the first time the product stores a person's words on its server, so this page says exactly what is kept, how, for how long, who can read it, what is built and what is not.

## What the owner asked for

22 Oct, in the owner's words, after seeing Logbook's "never on the page" list: "I would like that data to be connected inside the app from the iPhone apps… you should have access to literally everything… I should get the context in the conversation. Everything that you said, like your notes as well, your names… it should be longer, for a year as well, not like 90 days. So it should have also the iMessage thing… where people could basically be connected to the information of Doddy and talk with it really and get access to this conversation model, connect with Haiku 5.5 or something."

Asked, the owner chose: **"All text, 1 year"** (conversation text, notes and the names in them, kept 1 year, encrypted at rest, switched on in the app, deleted when switched off, no audio) and **"Server + web chat"** as the first build.

## How this answers the open decisions in `docs/architecture/WEB_AND_SHARED_PLATFORM.md` (section F)

| # | Decision | Answer |
|---|---|---|
| 1 | Memory off the phone? | **Yes, opt-in.** "Your notes stay on this iPhone" is no longer the whole promise: when the person turns it on, a copy is kept on Doddy's server. Default stays off. |
| 2 | Server-held key or end-to-end? | **Server-held key.** The server has to read the text to search it for the web page and to answer from it. This is encryption at rest, not end-to-end: Doddy's server can read what it keeps, and so can Claude (Anthropic) for the best matches when the person asks a question. |
| 3 | Where it lives | **`backend/`'s own Postgres** (the web app's server, the account the browser already joins). Not the messaging server's older opt-in copy (ADR-153), which only phone calls read. |
| 4 | Web chat's model | **Text only, Claude through `backend/`.** `DODDY_CHAT_MODEL`, default `claude-haiku-5-5`. Ask Doddy on the phone stays on `DODDY_CLAUDE_MODEL`. |
| 5 | Retention, and do voice transcripts sync | **Conversations 1 year**; voice transcripts sync only if the person turns conversations on. |

Not decided here (still the owner's): whether notes should also expire at a year. Built so far: notes mirror the iPhone (a note deleted there is gone here at the next send) and an iPhone that stops sending for a year loses its notes (see "Retention").

## What is kept, and what never is

- **Notes:** text, how it was saved (voice, typed, shared, imported), its type, when. Private notes (ADR-310) must never be sent: the phone leaves them out, and the server can't tell. (The existing sync, `MemoryCopySync.swift`, already does this for the call copy.)
- **Conversations:** language, how it ended, and every turn as text (`user` or `doddy`). Up to 400 turns of 4,000 characters, 1,500 conversations and 24 MiB per person.
- **Never:** audio, photos, contacts, the address book, anything from connected apps. Logbook (ADR-602) stays counts only and says so; this is a separate page, switched on separately.
- **Two switches**, set only by the iPhone: notes, conversations. Off deletes that kind in the same transaction. Both off by default.

## How it is kept

- **Tables** (`backend/src/store.ts`): `memory_state` (the two switches), `memory_notes`, `memory_conversations`. The text of a note or conversation is one encrypted blob; the server also holds what it needs to list and sweep (id, times, turn count, key version) in the clear.
- **Encryption:** AES-256-GCM (`backend/src/memory/crypto.ts`), key `DODDY_MEMORY_KEY` (base64 of 32 random bytes, held in the host's environment, never in the repository or the app). Each blob is bound to its user, kind and row (`userId:note:id`), so a row copied to another user or row fails to decrypt (tested). A key version is stored with each row.
- **Without the key** the server says "not set up" (503) for everything that needs it and keeps nothing. In mock mode with no hosted database and outside production, a published demo key is used so the demo and the tests work; it is refused anywhere a real database is set.
- **Logs:** counts and tokens only, never a note, a turn, a question or an answer (tested with planted strings). A refusal names the section that failed, never what was sent.
- **Cache:** every signed-in web reply is `private, no-store`.

## The routes (`backend/src/memory/routes.ts`)

| Route | Who | What |
|---|---|---|
| `PUT /v1/web/memory/state` `{notes, conversations}` | the iPhone only | Sets the two switches. Off deletes that kind. |
| `PUT /v1/web/memory/notes` `{items}` | the iPhone only, 8 MiB | The whole list of notes the phone holds now; the server replaces its copy (a deleted note goes). Up to 5,000. 403 while notes are off. |
| `PUT /v1/web/memory/conversations/:id` | the iPhone only, 768 KiB | One conversation (replaces the same id). Started within the last year, ended no later than tomorrow. 403 while off, 413 past the caps. |
| `GET /v1/web/memory` | browser or iPhone | Switches, counts, when the iPhone last sent. |
| `GET /v1/web/memory/notes`, `…/conversations`, `…/conversations/:id` | browser or iPhone | Pages of what is kept, newest first; one conversation in full. Rows that no longer decrypt are left out and counted (`unreadable`). |
| `POST /v1/web/memory/notes/search` `{q}` | browser or iPhone | Search. The words are in the body, never in an address a proxy could log. Rate limited: 20 a minute per person (it decrypts every note). |
| `DELETE /v1/web/memory/conversations/:id` | browser or iPhone | Deletes one conversation from the server (the iPhone keeps its own). |
| `DELETE /v1/web/memory` | browser or iPhone | Deletes everything and switches both off, so the iPhone's next send is refused and it stops. |
| `GET /v1/web/memory/export` | browser or iPhone | Everything, decrypted, as a JSON file. Same rate limit. |
| `POST /v1/web/chat` | browser or iPhone | Ask a question; see "Chat". |

A browser can read, search, download, delete and ask, and can **never put anything on the server or switch keeping on**: its cookie is refused on the three `PUT`s (tested). A cookie request that changes something needs the web app's own request (same-origin check). A guest iPhone (Ask Doddy only, ADR-587) has no memory. Every query is keyed by the user id from the session; tests read, delete and ask as B while A has data.

## Chat (`backend/src/memory/chat.ts`)

A question goes in; Claude answers from the best-matching notes (up to 6) and conversation excerpts (up to 3) of that person, and cites only what it was given.

- **Retrieval** is lexical and loose (`search.ts`): case and diacritics don't matter, a term matches the start of a word minus its last letter, so inflected names match (Anna finds Anny, Łukasz finds Łukasza). A wider net than the app's own search on purpose: a miss costs more than an extra note. Only the 150 newest conversations are searched per question, which bounds the work.
- **Data, not instructions:** notes and excerpts go to the model as JSON under short aliases (`n1`, `c1`), the answer's schema lets it cite only those aliases, there are no tools, and nothing is stored (the page sends the last six turns). A note that says "ignore previous instructions" stays inside a JSON string (tested). The page renders the answer as plain text, never markup or links (tested).
- **Cost control:** the same per-person and per-service daily caps as Ask Doddy (50 and 500), taken before anything is decrypted, and not spent when nothing is kept or no key is set.
- **One Doddy, many doors:** `MemoryChat.answer(userId, …)` knows nothing about the web. A text-message channel would call the same function for the same person.

## iMessage and other text channels: not built (designed in `docs/architecture/TEXT_CHANNELS.md`)

- **iMessage** can only be a business chat through **Apple Messages for Business**, whose application is pending (`docs/architecture/INTEGRATIONS_AND_CHANNELS.md`; it requires a way to reach a human). Apple's terms forbid relaying iMessage from a Mac, so that route is rejected.
- **SMS or WhatsApp** (Twilio, already used by `server/messaging`) could reach the same `MemoryChat`. Either channel needs a **link between the sender's number and the person's account**, with a proof from the phone and an internal call from `server/messaging` to `backend/`: that is the identity work of the architecture plan, phase 2. Not built.

## Retention

- **Conversations:** 365 days from when they started. Reads ignore older ones at once; an hourly sweep (its own step, so another step failing can't skip it, and a failure of its own is logged) deletes them.
- **Notes:** mirror the iPhone. Each list the phone sends rewrites every note's time, so only a phone that stopped sending for 365 days loses its notes to the sweep.
- **Switching a kind off, or "Delete everything here"**, deletes it at once. Deleting on the web removes the server's copy only; the iPhone keeps its own, and says so.

## The iPhone half (23 Oct): written, partly verified

| Piece | Where | Verified how |
|---|---|---|
| HTTP client for the five calls and the shapes it sends (an allow-list: id, text, source, type, time; turns as text) | `Packages/DoddyCore/Sources/DoddyCore/OnlineAccounts/WebMemoryClient.swift` | `WebMemoryClientTests` (DoddyCore, Linux) |
| Rules: the switch follows the server's answer; notes sent as the whole list (so a deleted note goes); one send for a burst of edits; retry only after a successful read; conversations one at a time with a 50-entry retry list; private notes and private conversations never sent; a 403 switches that kind off | `OnlineAccounts/WebMemoryModel.swift` | `WebMemoryModelTests` (DoddyCore, Linux) |
| "What leaves this iPhone" rows, switches and entries | `DataFlow.swift` | `DataFlowTests` (DoddyCore, Linux) |
| Strings in Polish and the generated catalogs | `l10n/pl.json`, `DoddyApp/Resources/Localizable.xcstrings` | `tools/build_strings_catalog.py --check` |
| **Settings › Doddy on the web › Keep on Doddy's server** (two switches, consent screen, delete button, status), the launch and foreground hooks, the call from `VoiceSessionController.keepLog`, `MemoryDetailView` changes, `WebMemoryClientFactory` | `DoddyApp/Features/Web/WebMemory*.swift`, `DoddyApp/Infrastructure/WebMemoryClientFactory.swift`, `RootView.swift`, `VoiceSessionController.swift`, `MemoryDetailView.swift`, `DataFlowView.swift` | **NOT COMPILED. NOT RUN.** `scripts/typecheck_app_logic.sh` does not cover `WebMemory.swift` or `WebMemoryClientFactory.swift`; the SwiftUI files need the hosted Mac build (`scripts/ci.sh`) and a run on a device |

Still open: the Logbook day counter and summary builder (`IPHONE_SENDS_LOGBOOK`), a device test of the whole path (switch on, note appears on the web, delete on the web, the phone's next send is refused and the switch goes off), the answer to a person who keeps "Remember recent conversations" off but conversations-on-the-server on (the server then holds conversations the phone does not), and flipping `IPHONE_SYNCS_MEMORY` in `web/src/memory/config.ts` **only after** the device test.

## Before anyone but the owner uses it

- `DODDY_MEMORY_KEY` must be set on the server (`openssl rand -base64 32`), kept somewhere safe, and **never changed**: there is no key rotation yet, so a different key makes existing rows unreadable (the page then says how many are left out; nothing is deleted). A rotation needs a key list chosen by each row's stored key version.
- `docs/legal/PRIVACY_POLICY_DRAFT.md` section 5.13 (23 Oct) now describes this, and Appendix B items 17 to 21 list what disagrees. The site's Privacy Policy, the in-app Settings paragraph, the website privacy panel and the App Store privacy answers still say the app keeps notes on the phone; they must be changed to match and get the legal review `doddy_rules.yaml` requires. Confirm the database region first.
- **The key was generated in a working session and is in that session's transcript.** Copy it from the host's environment into a password manager. Decide whether to replace it with one generated by the owner before real notes are stored (rotation is not built, so replace it before the first note is kept).
- Run the cross-user isolation checks again before a second account can exist (`DODDY_DEVICE_SIGNUP=first-device` means one account today).
- The plaintext columns (times, turn count) are outside the encryption's authentication; someone who can write to the database could change a conversation's age or order. Binding them in is a later hardening.
- The key is shared by all people and each note list is re-encrypted with fresh random nonces; fine at this scale, to be revisited with rotation.

## Independent review (22 Oct) and what it changed

A read-only security review of the new server code found no cross-user read or delete and no way for a browser to write. It found one blocking problem (one account could exhaust the server's memory or time with huge uploads and repeated searches, downloads or questions) and several smaller ones. Fixed, each with a test: per-person caps (1,500 conversations, 24 MiB) and a bounded download that is complete; rate limits on search and download; decryption in batches that give the server a turn; the published demo key refused wherever a real database is set; unreadable rows counted for the page and logged as a number; the memory sweep as its own step with a failure log, an index for it, and notes swept by the time they were last sent; no quota spent when the key is missing; search words moved from the address to the body; the matching turn always kept in an excerpt; a source named twice kept once. **Not changed:** a wrong or rotated key still makes data unreadable (no rotation; see above); the shared `service:ask` cap is global, as it already was for Ask Doddy; concurrency (a send racing a switch-off) is protected by serializable transactions and retries but the tests run on PGlite, which is single-threaded, so it is untested.

## Constitution evidence log

| Rule | Evidence today | Gap |
|---|---|---|
| DOD-11 observable privacy, "never call it fully private" | The Memory page states what is kept, that it is text only, that the server can read it and that Claude reads the best matches; the chat page says answers can be wrong and aren't saved. Switches default off and are the iPhone's alone (tested). | The app's consent screen, switches and "What leaves this iPhone" are not built. Privacy policy and store answers not updated. |
| DOD-06 deletion | Switching a kind off deletes it in the same transaction; delete-everything switches both off; one conversation can be deleted; "Deleted" is said only after the server answers (tested, including a refused delete). | The phone's own deletion doesn't yet reach the server for conversations (the app half). Backups of the database are the host's. |
| DOD-08 / "never claim saved without a verified operation" | `stored: true` and counts come from the database operation; the page says Deleted/Saved only after the server's reply. | None for this page. |
| Content-free logs | Counts and tokens only (tested with planted strings, including a refusal and a chat). | None known. |
| Cross-user isolation | Every query keyed by the session's user id; tests for lists, conversations, delete, export, chat retrieval and a copied ciphertext (fails to decrypt). | Concurrency not exercised (PGlite). Re-run before a second account exists. |
| Prompt injection / data is not instructions | Aliases, JSON data, answer schema limited to given aliases, no tools; planted "ignore all previous instructions" stays data (tested); a citation of something not given discards the answer (tested). | Indirect injection through shared or imported notes can still change the wording of an answer; there are no tools and the CSP blocks image loads, so nothing can be sent anywhere. |
| ASK-01 | Chat can only answer; it starts nothing. | None. |

## Tests run (22 Oct 2026, Node 22, PGlite, jsdom, headless Chromium 1194)

See the result lines in `STATUS.md`. **Not run:** anything on an iPhone (nothing exists), the real Anthropic API (the demo provider answers in tests), real Postgres, the deployed server, a screen reader.
