# File-ready push: "tell me when the file is done"

Owner, 9 Nov 2026: "when I tell Doddy to do it he starts in the background, and if he created a doc or did the job I get a notification."

## What it does
When Doddy starts making a file by voice (`make_document`: deck, Word, Excel, PDF or text, ADR-564), the user gets **one notification when the file is ready or failed**, with fixed words and nothing from the file: "Gotowe. Twój plik czeka w aplikacji." / "Ready. Your file is waiting in the app." (or "Nie udało się przygotować pliku." / "Doddy couldn't finish a file."). The file is then in Messages under "Files Doddy made for you" and in Files (`MESSAGES_ATTACHMENTS.md`). Tapping the notification opens Doddy (it carries no routing hint yet).

## How
1. **iPhone** (`FileReadyPush.watch`, called where the voice screen gets a `working` document): sends the file's signed link and the language ("pl" or "en") to the messaging server, `POST /v1/file-watches`. Best effort and silent.
2. **Messaging server** (`server/messaging/src/fileWatches.ts`, route `routes/fileWatches.ts`, table `file_watches`, migration `023`): accepts only a link on `DOCUMENTS_ORIGIN` shaped `/v1/documents/<24 chars>?exp=…&sig=…` (rebuilt from its parts; no other host, scheme, credentials or fragment), keeps it **encrypted**, at most 10 open per account. A worker pass asks the link every ~12 s, and queues one push through the normal outbox when it answers `ready` or `failed`. A link still `working` after 15 minutes, or `gone`, ends silently.
3. **Backend** (`backend/src/documents.ts`): the same signed link with `?status=1` answers `{"status":"working"|"ready"|"failed"|"gone"}` as JSON and no file bytes (404 for a bad or expired link). No new permission: whoever holds the link could already open the file.

## Off by default
- Messaging server: needs `DOCUMENTS_ORIGIN` (the `doddy` backend's public address, https, no path) **and** `MEMORY_ENCRYPTION_KEY`; without either, the route answers 503 `file_watch_disabled` and the app does nothing.
- A push also needs notifications on and a device token (`canPush`). Without one the watch ends quietly.

## Privacy
Row `fileReady` in "What leaves this iPhone" (`DataFlow.swift`): the private link and the language leave the iPhone to the messaging server, never the file, its words or its name. The notification has fixed words.

## Tests that ran (9 Nov 2026, this session)
- Backend `test/just-works.test.ts` (20 of 20): status JSON, no bytes, 404 for bad or expired.
- Messaging `test/fileWatches.test.ts` against Postgres 16 (8 database tests and the link-validation units) and `migrationsFrozen.test.ts`; the **whole messaging suite passed: 855 of 855**.

## Not run
- **Nothing was deployed.** Both `doddy` (backend) and `doddy-messaging` need a deploy, and `DOCUMENTS_ORIGIN` must be set on `doddy-messaging` (`docs/OWNER_QUEUE.md` item 28).
- **Swift not compiled, not run** (no toolchain here): `FileWatchClient.swift` and `FileWatchClientTests` in DoddyCore, `DataFlow.swift` row, `DoddyApp/Infrastructure/Server/FileReadyPush.swift`, the call in `VoiceSessionController.swift`. Not seen on a device; no real push was sent through Apple.
- Files made from the Messages "Make it" card are not watched (the person is in the app then).
- A tapped notification does not open Messages by itself.
