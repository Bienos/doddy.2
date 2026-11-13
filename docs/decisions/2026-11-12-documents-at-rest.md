# Files Doddy makes are encrypted at rest, and their links are shorter-lived and checked on every open

- **Date:** 2026-11-12
- **Decided by:** proposal, owner approval pending
- **Status:** proposed (branch `claude/backend-documents-at-rest`)
- **Replaces:** the seven-day link of ADR-564 (the file is still kept seven days)

## Why
The backend kept every other piece of a person's content it stores (kept notes, conversations, the Messages copy) encrypted with the memory key (ADR-603), but a file Claude made (`documents.body`) and its name, which is the person's own title, were stored as plain text. The receipt for a file repeated that title. A file's signed link lasted seven days, was signed over the file's ID only, and was served without a sandbox policy.

## Decision
- **Encrypted at rest.** `documents.body` and the name are encrypted with the same key and cipher as kept memory (`DODDY_MEMORY_KEY`, AES-256-GCM, `backend/src/memory/crypto.ts`). The associated data binds each blob to its account, its row and its part (`<user>:document-name:<id>`, `<user>:document-file:<id>`), so a blob copied to another account, row or part doesn't decrypt. New columns `key_version` and `name_ciphertext` (added by the idempotent schema in `backend/src/store.ts`); `name` is left empty on an encrypted row. A row that can't be decrypted reads as missing.
- **No key, no files.** Without `DODDY_MEMORY_KEY`, `make_document` says "Making files isn't set up on this server." and nothing is written, the same as kept memory and the Messages copy. Mock mode without a hosted database keeps its throwaway demo key.
- **Older rows.** Rows written in plain text before this change are still read. The hourly housekeeping (and once at start) encrypts them one at a time (`Store.sealPlaintextDocuments`): only rows without a `key_version`, checked again in the update, so it is idempotent and safe with two servers running. A row still being made is left to its job and encrypted once it is ready or failed. Every row is deleted after seven days anyway.
- **Receipts.** The receipt for a file says its kind only ("Started a deck."), never the title.
- **Signed links.** Signed over the file's ID, **the account it was made for** and the expiry (`doddy-document:v2`). Every open reads the row again and checks the signature against the row's own account, so a deleted file or another account's doesn't open. A link lasts **24 hours** (it was seven days). A link signed the older way only ever says "This link has expired". Served with `Content-Security-Policy: sandbox; default-src 'none'`, `X-Content-Type-Options: nosniff`, and `Content-Disposition: inline` only for the kinds Doddy makes (PDF, pptx, docx, xlsx, Markdown), which the app opens in Safari for Quick Look; any other type is `attachment`.

### Why 24 hours and not 15 minutes
The iPhone keeps the signed link in its Messages thread and on the voice card and opens it in Safari when the person taps the file (`MessagesView.fileBubble`, `VoiceView`), often hours after the file-ready push. The messaging server asks the link for 15 minutes at most (`server/messaging/src/fileWatches.ts`). A day covers the same-day taps; after that the expired page tells the person to use Share on the file, which downloads it with the app's own sign-in (`GET /v1/web/documents/:id/file`) for the whole week. Going to 15 minutes needs the app to open the file through that signed-in download instead of the stored link; that is an app change, not made here.

## Consequences
- **Deploy:** `doddy` must have `DODDY_MEMORY_KEY` before this ships, or making files stops ("not set up"). On 12 Nov 2026 the live service answered `PUT /v1/web/messages` with `503 live_not_configured`, which means the key isn't set there (owner queue).
- Changing or losing the key makes the stored files unreadable (they read as missing); they are deleted within a week anyway.
- The memory key now covers files too, and file links stay signed with `DODDY_SESSION_SIGNING_KEY`. If keys are split per purpose (proposal `2026-11-12-account-and-device-tokens`), files can get their own key: each row carries its `key_version`, and a link's signature is checked on every open.
- Links made before the deploy stop opening (they say "expired"); the files stay listed and downloadable in the app and on Doddy Web.
- **Rollback** is not clean for files: the earlier code reads `name` and `body` as plain text, so it would list encrypted files with an empty name and serve their ciphertext, and it doesn't accept the new links. After a rollback, delete the encrypted rows (`DELETE FROM doddy_backend.documents WHERE key_version IS NOT NULL`, as the backend's role); they are a week's files at most. The two new columns can stay.
- The sandbox policy is new on the file itself. That Safari on an iPhone still previews a deck, a Word file, a spreadsheet and a PDF with Quick Look under it has **not been checked on a device**.

## Evidence
`backend/test/documents-at-rest.test.ts` (ciphertext in the table, binding to account and row, another key, no key, the sweep, receipts, link headers, expiry, deletion, another account's link) and the updated link tests in `backend/test/just-works.test.ts`. `npm run typecheck` and `npm test` in `backend/` (PGlite). Not run: a hosted Postgres, the iPhone app, Safari on a device.
