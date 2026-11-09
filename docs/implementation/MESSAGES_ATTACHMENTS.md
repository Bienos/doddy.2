# Messages: files as cards under the thread

Owner, 28 Oct 2026: "go ahead with attachments next" (item 3: documents, slides and photos as tappable cards in the thread).

## What it does
- Files Doddy made on his server that are **not already a bubble in the thread** (a deck or document from a voice conversation or a background task) show as cards under the newest message, headed "Files Doddy made for you". Newest six at most, oldest first.
- Only a **ready** file the server still keeps is offered (`ThreadAttachments.shown`). Working, failed and stopped files stay on the Files tab, which says why.
- A tap downloads the file with the iPhone's own session (same path as the Files tab, `MadeDocumentsModel`) and opens it in Quick Look; Share there saves or sends it.
- A file made from the chat's "Make it" card is already a bubble; it is matched by the id inside its server link and not shown twice.
- The cards are read from the server each time Messages opens. Nothing is added to the saved thread, so a file the server deleted (after a week) just stops showing. *(Changed 9 Nov 2026, see below: no longer only while Ask Doddy is on.)*

## Every kind of file, as soon as it is asked for (9 Nov 2026)
Owner, 9 Nov 2026: "decks, docs, excels, he should do all of them." `make_document` already makes a deck, Word document, spreadsheet, PDF or text on the server; they only showed in Messages when finished **and** the screen had been opened after that **and** Ask Doddy was on.
- A file Doddy is **still making** (`ThreadAttachments.inProgress`: working, not past 15 minutes, not deleted) now shows at once as a card that says he is still making it; it is not tappable until ready.
- Messages keeps looking while it is open: every 6 seconds while a file is being made, every 30 seconds otherwise (`keepFilesFresh`), so a file finishing in a minute or two appears by itself. The quiet refresh doesn't delete a file open in Quick Look (`refresh(clearingDownloads: false)`).
- The list no longer waits for **Ask Doddy**. It is the person's own list of their files, read with their own session, as the Files sheet reads it; it sends no question or note. Owner: say if you want the old gate back.
- Decks made on the iPhone (`make_presentation`) stay in the section below. Not covered: Studio briefs, Google Drive and Notion files, and a push or badge when a file is ready.
- **Not compiled, not run** (no Swift toolchain here): `ThreadAttachmentsTests` (3 new), the view, the polling on a device.

## Files Doddy made on the iPhone (9 Nov 2026)
Owner, 9 Nov 2026: "i want Doddy to send me files he creates in Messages inside the app."
- The deck from `make_presentation` (ADR-567) was written to a temporary folder cleared within a day and offered only on the voice screen's share sheet. Now, once it is written and read back, a copy is kept for a week (`LocalMadeFilesStore`: Application Support/MadeFiles/<id>/, an index, readable after first unlock only) and shows in the same "Files Doddy made for you" section, **first**, before the server's files. A tap opens it in Quick Look (Share saves or sends it); a long press offers Delete, which changes the list only after the index was rewritten.
- A copy counts as kept only when it reads back byte for byte. When it can't be kept, the deck is still on the share sheet as before and Doddy is not told it is in Messages (`VoiceToolReply.presentationMade(_, inMessages:)`).
- On the iPhone only: no server, no Ask Doddy consent needed, nothing added to the saved thread or its web copy. Rules in DoddyCore `ThreadLocalFiles.swift` (`ThreadLocalFilesTests`).
- Not covered: Studio briefs and infographics (they stay in Home ••• › Studio; Studio is off by default), invoice drafts, and a real chat bubble among the messages (a saved bubble needs a thread-table and web-sync change, so the file is a card under the newest message, like the server's files). Google Drive and Notion pages Doddy creates are in those apps, not here.

## Files
- `Packages/DoddyCore/.../Messages/ThreadAttachments.swift` (+ `ThreadAttachmentsTests`); `MadeDocument.isID` made public.
- `DoddyApp/Features/Messages/MessagesView.swift`: the `attachments` section; `MadeDocumentRow` in `FilesView.swift` is now shared.

## Not done
- **Photos are not done.** Sending a photo to Doddy would send an image to Anthropic through the server; today the route is text only (ADR-586) and the consent says so. It needs the owner's yes to a new data flow, a server change and new consent wording. Shown photos on screen from `find_photos` stay as they are.
- Cards sit under the thread, not placed by time among the bubbles, and are not stored (so web sync will not carry them yet).
- **Not compiled, not run** (no Swift or Xcode in this session): `ThreadAttachmentsTests`, the view, Quick Look from this screen. Not seen on a device; layout of the cards unseen.
- New string "Files Doddy made for you" is not in `Localizable.xcstrings` or translated.
