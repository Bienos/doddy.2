# "Show screen" is a labelled capsule over Mute and End; the transcript keeps its cards in view; files made by voice say what they are

- **Date:** 2026-11-13
- **Decided by:** owner ("Wszystko dawaj", 13 Nov 2026, to the proposals in `docs/strategy/PRZEGLAD_APLIKACJI_2026-11-12.md`, sections 2.2, 2.4 and 5)
- **Status:** accepted
- **Replaces:** the header placement in decision `2026-11-11-asked-for-runs-at-once` (the "Show screen" glyph beside •••)

## Why
The review of 12 Nov found three things in a voice conversation:
- The screen button was iOS's round record glyph with no words, beside •••. It looked like recording or a second menu, didn't show whether sharing was on, and disappeared when the conversation ended while sharing went on.
- In the transcript, cards come after the lines, and each new line scrolled to the last line (`VoiceView.swift`, `proxy.scrollTo(last.id, anchor: .bottom)`). A card that had just come up was pushed below the screen's edge while Doddy kept talking. Some cards never came up on Home at all.
- A file made by voice arrived in Messages as "Here it is: “X”" with nothing about what it was.

## Decision
1. **Screen capsule** (`ScreenShareCapsule` in `DoddyApp/Features/Voice/ScreenSharePicker.swift`, the one file the CI guard lets use iOS's picker). While Doddy talks on Home, a capsule over Mute and End says "Show screen" (eye). iOS's picker lies over the whole capsule with its glyph hidden, so a tap is still a tap on Apple's button, the only supported way to start a broadcast. While sharing is on it says "Sharing screen · Stop" with a red edge; the same tap opens iOS's sheet, where Stop Broadcast ends it.
   - Wording: the review proposed "Doddy sees the screen". The capsule says "Sharing screen" instead, because nothing leaves the iPhone until the person asks about the screen (decision `2026-11-09-doddy-looks-at-the-screen`); "sees" would claim more than happens.
   - After the conversation, a small mark (screen glyph with a red dot) stays in Home's header only while sharing is on, so it can be stopped from Home.
   - Whether sharing is on comes from the extension's state file, read every two seconds: `ScreenShareIndicator.isSharing` in DoddyCore. It counts as on while the file says live and its newest picture, or the start, is at most two minutes old. iOS sends no new picture while the screen is still, so this is longer than the 10 seconds a picture stays "the screen now". An extension iOS ended without clearing its file stops counting after two minutes; iOS's own indicator is the authority.
   - Still with Messages (`Feature.messages`), as before.
2. **Cards stay in view** (`VoiceView.swift`). An empty view after the last line and card is the end; a new line scrolls to it, so lines and the cards under them stay on screen together. A new file card scrolls to itself (before, nothing scrolled to it). On Home, the pop-up card now also comes up for the BLIK details and for list items Doddy couldn't tell apart (`HomeConversation.resultsToShow`). Reminders, Calendar changes and invoices still don't pop up: the island already says a reminder was set, and an invoice draft is kept between conversations, so it would pop up at the start of every conversation.
3. **Descriptions for files made by voice.** `ThreadDelivery.madeFileBrief(of:)` takes the `request` the agent already gives `make_document` (what it should contain, for whom, how long, in the person's language), clipped like `ThreadMessage.fileAbout` (one line, at most 280 characters, cut at a word). The file's card in the conversation shows it under the name, and Doddy's message in Messages carries it under its first line. It describes what was asked for; nothing reads the file. The live agent and `voice-agent/tools.json` are unchanged: `request` is already a required argument.

## Consequences
- The capsule depends on `RPSystemBroadcastPickerView` having one `UIButton` that can be resized. If a future iOS changes that, the capsule's words still show and the tap may miss; `ScreenSharePicker.present()` and Control Center still work.
- A Keynote file made on the iPhone (`make_presentation`) still gets no bubble in Messages; not part of this change.
- No new data is stored: the description lives in memory with the conversation's cards and in the Messages bubble's text, like the rest of that message.

## Evidence
DoddyCore tests on Linux (`make test-core`), `swiftc -parse` on each changed app file, `scripts/ci.sh --only checks`. Not compiled here: the app files; not seen on a device. To check on a phone: the capsule's tap opens iOS's sheet, VoiceOver reads it, and the red mark after the call.
