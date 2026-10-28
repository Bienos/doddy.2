# Messages: files as cards under the thread

Owner, 28 Oct 2026: "go ahead with attachments next" (item 3: documents, slides and photos as tappable cards in the thread).

## What it does
- Files Doddy made on his server that are **not already a bubble in the thread** (a deck or document from a voice conversation or a background task) show as cards under the newest message, headed "Files Doddy made for you". Newest six at most, oldest first.
- Only a **ready** file the server still keeps is offered (`ThreadAttachments.shown`). Working, failed and stopped files stay on the Files tab, which says why.
- A tap downloads the file with the iPhone's own session (same path as the Files tab, `MadeDocumentsModel`) and opens it in Quick Look; Share there saves or sends it.
- A file made from the chat's "Make it" card is already a bubble; it is matched by the id inside its server link and not shown twice.
- The cards are read from the server each time Messages opens and **only while Ask Doddy is on**. Nothing is added to the saved thread, so a file the server deleted (after a week) just stops showing.

## Files
- `Packages/DoddyCore/.../Messages/ThreadAttachments.swift` (+ `ThreadAttachmentsTests`); `MadeDocument.isID` made public.
- `DoddyApp/Features/Messages/MessagesView.swift`: the `attachments` section; `MadeDocumentRow` in `FilesView.swift` is now shared.

## Not done
- **Photos are not done.** Sending a photo to Doddy would send an image to Anthropic through the server; today the route is text only (ADR-586) and the consent says so. It needs the owner's yes to a new data flow, a server change and new consent wording. Shown photos on screen from `find_photos` stay as they are.
- Cards sit under the thread, not placed by time among the bubbles, and are not stored (so web sync will not carry them yet).
- **Not compiled, not run** (no Swift or Xcode in this session): `ThreadAttachmentsTests`, the view, Quick Look from this screen. Not seen on a device; layout of the cards unseen.
- New string "Files Doddy made for you" is not in `Localizable.xcstrings` or translated.
