# Messages from Doddy while the app is closed: a proposal (not built)

Status 22 Oct 2026. A proposal for the owner's decision. Nothing here exists in code. ADR-582 and ADR-594 keep Messages on this iPhone; this page says what it would take for Doddy to write to you when Doddy is closed (a finished task, a reminder, a file).

## What exists already
`server/messaging` (ADR-139, 570, 571) already sends Apple push notifications, keeps an encrypted outbox, and runs background errands. The errand flow is the model: the server holds the result encrypted until the phone fetches it, then deletes it, and the push carries no words.

## What a server would store (smallest version)
- **Only a "something is waiting" push.** No message text in the push. The app opens, fetches, and the server deletes.
- **The waiting item, encrypted** with `MEMORY_ENCRYPTION_KEY`: a text, or a pointer to a file. Text up to a few kB; files only by link, never copied into the thread's server side.
- **Deleted** when the phone confirms it saved the message (the phone's `ChatLogFile` read-back is the confirmation), and at most 30 days after it was made if never fetched (the errand rule).
- **Never stored:** the conversation, notes, the thread itself, the user's own messages and attachments. The thread stays on the iPhone.

## What it needs
1. The messaging server always on. A free Render web service sleeps, so a push can't be sent from it on time. Options: a paid always-on instance, or a separate worker.
2. An Apple push key (APNs) from the owner's Apple Developer account, set as a secret in 1Password (ADR-493).
3. A migration for a `messages_waiting` table and two routes (list mine, confirm saved).
4. App: register for push (the messaging server already has the device token flow), fetch on push, `MessagesController.receive(_:)` for each, then confirm.

## Cost, orders of magnitude (check current prices before buying)
- Always-on server: roughly 7 to 25 USD a month on Render's paid web service tiers.
- Postgres: free on Supabase's free tier while small, or a few USD a month hosted.
- APNs: free. The Apple Developer membership is already needed for a device build.
- AI use for what Doddy writes is a separate, variable cost and unchanged by this.

## Privacy
- Words and files that wait are on the server for minutes to days, encrypted. That is new: today nothing of the thread leaves the phone except what the owner sends to the assistant gateway.
- The notification would say only "Doddy sent something" (no title), unless the owner decides the title may show (errands have the same open question).
- A "delete all messages" in the app would also ask the server to drop anything still waiting.

## Cheaper first steps already built or possible
- Messages are written to the thread as things happen while the app is open or a conversation runs (ADR-594).
- Local notifications for reminders need no server.
- A daily summary could be scheduled on the phone only; it would not be able to write new text from the cloud.

## Decisions for the owner
1. Is it worth an always-on server and the Apple push key now, or after Messages has been used for a while?
2. May a notification show a title ("Prezentacja gotowa"), or only "Doddy sent something"?
3. Fetched-and-saved items deleted at once, or kept 24 hours on the server as a safety net?
4. The Vercel account is blocked ("Account is blocked"); it must be cleared before any web deploy, though Render is separate.
