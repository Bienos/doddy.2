# Messages on the web

Owner, 28 Oct 2026: item 4 "yes", then for the switch: **"No, sync always on"** (asked whether it should be an opt-in switch, off by default; recommended yes; owner chose always on). This reverses the 22 Oct line in `MESSAGES_STATUS.md` that the conversation is not stored on a server.

## What it does
- **iPhone:** after every change to the thread (a message saved, an answer, a file bubble, a delete) and each time Messages opens, `MessagesModel` sends the newest 200 messages to `PUT /v1/web/messages` on Doddy's server (`doddy`, the Doddy Web backend), with the iPhone's own session (`ServerThreadSync`, same server and session as Files). Only the latest send matters (400 ms debounce; an earlier one is cancelled). A failed send is retried at the next change or the next open; the thread on the iPhone is unaffected.
- **No session, nothing sent:** an iPhone that has never signed in to that server sends nothing and no sign-in is started for it (there is no web account to show it to).
- **What is sent:** id, who, text (cut at 10,000 characters), time, delivery for your messages, `hasPhoto` (never the photo), and a file's name and kind (never its link).
- **Server:** keeps one encrypted snapshot per user in `message_threads` (AES-256-GCM with `DODDY_MEMORY_KEY`, the same key and cipher as kept memory, ADR-603; encryption at rest, not end-to-end: the server can read it). A new snapshot replaces the old, so a message deleted on the iPhone is gone at the next send. A copy not refreshed for 365 days is swept. Logs carry counts only.
- **Web:** Doddy Web › Messages shows it read only, bubbles like the app's. The menu says **Soon** (`IPHONE_SENDS_MESSAGES = false` in `web/src/messages/config.ts`) until an iPhone build with this ships; set it to true then.
- **Delete everywhere:** Delete conversation removes it from the iPhone (read back), then calls `DELETE /v1/web/messages`; the app says the web copy is deleted only when the server confirms, and otherwise offers Try again. A browser cannot write or delete the copy (it would come back at the iPhone's next send).
- **Disclosure** under the thread and the delete dialog now say a copy is kept on Doddy's server for Doddy Web (all ten languages; nine machine-written).

## Checked here
- `backend`: `npm test`, 435 of 435 pass, including 7 new in `test/messages.test.ts` (encrypted at rest, replace and delete, browser refused, per-user, shape, no key).
- `web`: `npm run typecheck` clean; `vitest` 101 of 101 pass, including `test/messagesPage.test.tsx` and the menu test updated for "Messages Soon".
- String catalogs `--check` and the capability guard pass.

## Not checked
- Swift not compiled or run (no Swift or Xcode here): `ThreadSyncTests` (5), the new `MessagesModelTests` (2), `ServerThreadSync.swift`, the alert.
- Not deployed: `doddy` needs a deploy (the table is created at start) and `DODDY_MEMORY_KEY` set, or the routes answer "not set up".
- The privacy pages (`site/privacy/`), Settings' "What leaves this iPhone" and the Ask Doddy consent dialog do not mention the web copy yet. The consent dialog wording was the owner's "c" on 22 Oct; it should be revisited now that the thread leaves the iPhone.
- Account deletion: `message_threads` follows the same path as the memory tables; not separately tested.
