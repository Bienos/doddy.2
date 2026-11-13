# A file Doddy is still making drops a small note out of the island, not the pop-up card, and Doddy never asks for a tap

- **Date:** 2026-11-13
- **Decided by:** owner, 13 Nov 2026, with a screenshot of the "Deck from Claude" pop-up after asking for a report by voice: "wyskoczyło coś takiego, co jest w ogóle niepotrzebne … to powinno być bardziej taki … mały pop-up z Dynamic Island albo coś, że z pokazaniem, co ogólnie on będzie robił"; "on też jak mówi, to każe mi to tapnąć, a to nie będzie tapnięcia, bez sensu … Popraw to, to tak nie powinno być."
- **Status:** applied in the pull request from `claude/keen-gates-zu8o7b`
- **Replaces:** for a file still being made only, item 1 of `2026-11-10-cards-pop-up-and-results-in-messages` ("something Doddy just made … opens the conversation's sheet as a card"). Ready files and every other card keep popping up.

## Why
- `make_document` always answers `status: working` (`backend/src/tools/service.ts`). The file isn't there yet, so the pop-up card ("Deck from Claude", Open, Share) had nothing to open. Open showed a "still making" page, and the card covered half of Home while the person was talking.
- The server's reply told the agent "A card to open it is on the user's screen now … Tell the user that in one sentence", and the tool's description said "a card with Open and Share is on the user's screen at once". So Doddy said to tap the card in the middle of a voice conversation.
- The real island's subtitle for this moment was "Its button is in Doddy".

## Decision
1. **No pop-up for a file being made.** `HomeConversation.resultsToShow` counts only files `MadeFileStart.popsUpCard` allows, which means ready ones. When the card is up for something else, it leaves a file being made out.
2. **A small note drops out of the island on Home** (`MadeFileIslandNote`, over Home's island strip). It is black like the island, with the kind's icon, "Making your deck" (or document, spreadsheet, PDF, text), the file's name without its extension, "It lands in Messages in a minute or two." and a spinner. It stays 6 s (`MadeFileStart.noteSeconds`), has no buttons, and a tap puts it away sooner. Reduce Motion: it fades instead of growing out of the island. It is drawn on every iPhone and iPad, not only on those with a Dynamic Island.
3. **The transcript shows a quiet row** for a file being made: an icon, the same title, the name, what was asked for, and "It lands in Messages when it's ready." There is no spinner, because the conversation doesn't hear when the file is done, and no button. A ready file keeps its card with Open and Share. Its line now reads "It's in Messages and in Files too."
4. **Private conversations.** Nothing from them reaches Messages (`keepMadeDocument` skips `ThreadInbox`). There, the row keeps Open, which is the only way to the file, the note says "Open it from the transcript when it's ready.", and the agent is told the same. Doddy never promises Messages there.
5. **What the agent hears.** For a `make_document` result that is still working, the phone answers with its own words (`MadeFileStart.voiceReply`, called from `VoiceToolReply.cloudResult` and from the controller with the private flag). They start with `started:` and say Claude is making the deck now, in one to three minutes. They say it will be in Messages (or opens from the transcript, if private), that nothing waits on the screen, and to say it in one short sentence without asking the person to tap, open or look at anything. The file's name follows between the data markers. None of the server's line is passed on. Demo servers still say "DEMO DATA".
6. **The real island** (outside the app) says "Making your document · Takes a minute or two" instead of "… · Its button is in Doddy".
7. **Repo only, not live:** the server's line (`service.ts`) no longer mentions a card, for app builds without this change. The `make_document` description in `voice-agent/tools.json` and its line in `instructions.md` no longer say a card is on the screen. The live agent is changed only on the owner's instruction (`voice-agent/README.md`), and `doddy` needs a deploy for the server line.

## Consequences
- Doddy's own words reach the agent from the first build with this change, without a deploy or an agent change. The live tool description still says "a card with Open and Share is on the user's screen", so the agent sees one contradiction until it is synced. The tool's own result is newer and says otherwise. Whether the model follows it can only be heard on a device.
- The note shows only on Home, where the conversation runs. On another tab, or under the full transcript, it isn't seen. The transcript row and Messages still have the file.
- The note has the file's name, which the agent chose, on the screen for 6 seconds. That is the same name the card showed, and nothing new is stored or sent.
- The file-ready push still says the result waits in Messages, even for a private conversation. This was true before this change and is not fixed here.
- New Polish strings in `l10n/pl.json`. The eight draft languages show English for them. Native review applies (ADR-234).

## Evidence
- DoddyCore on Linux, Swift 6.1.2: `make test-core`, with the new `MadeFileStartTests`. Backend: `scripts/ci.sh --only backend`, with `just-works.test.ts` checking that no card is promised. `scripts/ci.sh --only checks`. The exact counts are in the pull request.
- Not compiled here: the app files (no Xcode). Not seen on a device: the note under the island, its timing, VoiceOver, and what the live agent says.
