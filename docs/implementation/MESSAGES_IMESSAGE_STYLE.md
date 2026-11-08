# Messages looks like the iPhone's Messages (ADR-605)

Owner, 24 Oct 2026: the typed conversation with Doddy should look like iMessage exactly and have the same functions; it should say which model it is connected to; "we will write with Doddy there and he will send me all the things".

## Which model

Messages asks **Claude Haiku 5.5** (`claude-haiku-5-5`, effort medium, text only) through Doddy's messaging server (`POST /v1/assistant/ask`; `ASSISTANT_MODEL` in `server/messaging/src/config.ts`, ADR-586). The web chat on Doddy's server also uses a Haiku model (ADR-603). Voice is a different system (ElevenLabs agent). The app does not show the model's name anywhere; the line under the thread says the question goes to Doddy's server and on to Anthropic.

## Done in this change (view only)

| iMessage trait | In Doddy |
|---|---|
| Orange bubbles for you on the right, quiet surface for Doddy on the left | yes, in the app's own colours: `Theme.orangeCue` with dark ink for you (cream on orange does not read), `Theme.quietSurface` for Doddy, the cream canvas; dark mode uses the app's dark palette |
| Tail on the last bubble of a run, runs of one sender close together | yes (`BubbleTail`, `messageBlock`) |
| Time heading after a pause | kept (`ThreadRules.showsHeading`) |
| Typing bubble while the answer is on its way | yes (`TypingBubble`; still under Reduce Motion) |
| Capsule composer, round orange send arrow inside it, grey while empty, stop button while sending | yes |
| "+" button left of the composer | yes, holds the one real choice: use saved notes or not. Photos, files and voice notes are not offered because they are not built |
| Press and hold a bubble: Copy | yes |
| Links tappable | yes, http and https only, opened only when tapped |
| Drag the thread down to dismiss the keyboard | yes (`scrollDismissesKeyboard(.interactively)`) |

**Different on purpose.** No "Delivered" and no "Read": nothing here can know either (`ThreadRules.deliveryLine`, constitution: no claim without a confirmed status). Under a message you only ever see "Sending…" or "No answer yet. Tap to try again." Doddy keeps saying he is an AI (line under the thread) and where an answer came from (caption under the bubble).

Not copied: Apple's name, logo or blue and grey. The ids the UI tests use are unchanged.

## Not done, and what each needs ("he will send me all the things")

| Function | What it takes | Decision needed |
|---|---|---|
| **Doddy writes first**: a finished errand, a reminder, a morning brief, a scheduled task | The thread lives only on this iPhone. A message from the server needs a delivery path: a push notification (APNs, needs the paid Apple team) that carries or fetches the text, and a rule for writing it into the saved thread with the same read-back checks. Errands already have a "Done" card (ADR-571) to start from | Which things may arrive on their own, and quiet hours (the constitution forbids pressure and guilt) |
| **Files and pictures from Doddy** (a deck, a Word file, a PDF, a photo) | **Built first increment (ADR-606, not compiled until Mac CI):** the server model may offer a file (`proposal`), the thread shows a card with the exact words, and only the tap runs `make_document` (single-use approval); the result is a file bubble with name, kind and link, kept in the thread as a link only. No preview image yet; pictures need a store on this iPhone and a delete path | Whether documents should be kept in the thread or only linked (now: only linked) |
| **Cards in the thread** (a reminder to confirm, a BLIK draft, a map pin, a contact) | The voice conversation has these cards; Messages has no tools yet, text only (ADR-586). Needs a tool-using assistant on the server with the same approval rules (ASK-01: exact payload, tap to approve) | Whether typed Doddy gets the same tools as spoken Doddy |
| Reactions (tapbacks), reply to one message, delete one message | New columns and a read-back delete in `thread_messages`; reactions to Doddy's answers would be a signal for the learning loop | Do you want reactions to teach Doddy? |
| Photos and voice notes from you | Photo notes and voice memos exist elsewhere in the app; sending them to the model needs consent text and a model that takes images | Which of the two first |
| Typing the model's name in the UI | One line in the header | Show it or not |

## Checked

Not compiled and not seen on a device: `MessagesView.swift` was written on Linux. Hosted Mac CI on this branch is the first compile; UI tests that open Messages (`LaunchSmokeTests`, `MotionRideTests`, `MotionSurfaceTests`) use the same ids. The tail's curve is drawn from coordinates, not from a design file: look at it on a device before calling it exact.
