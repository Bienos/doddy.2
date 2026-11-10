# Tasks ("Sprawy") in Doddy's style, with a way to hand a task over by typing

- **Date:** 2026-11-10
- **Decided by:** owner: "Sprawy są spoko, ale potrzebuję lepszego designu, żeby to było bardziej w stylu Doddy'ego, w jego kolorach, w jego brandingu, żeby to było łatwiejsze do zrozumienia, co można tutaj zrobić, jak z tego korzystać, jak można takie sprawy ustawić dla Doddy'ego", then "No wygląda właśnie tak, to zrób."
- **Status:** applied in the pull request from `claude/tasks-redesign`
- **Replaces:** nothing; ADR-570 (errands) stands. The Tasks screen's layout only.

## Why
The Tasks screen (`DoddyApp/Features/Errands/ErrandsView.swift`) was a plain `Form`: one footnote on handing a task over by voice, the list rows, "No tasks yet." and the price watches. A task could only be handed over in a conversation, and the empty screen gave no example and no button, so it didn't say what Tasks are or how to start one.

What the background worker can do was read from the code, so the screen promises nothing more: `server/messaging/src/errands/researcher.ts` researches with web search and web fetch only (result sections `options`, `brief`, `checklist`, `places`), nothing it reads can book, buy or send; a shopping task (`kind: "shopping"`) needs the user's priorities, which only the conversation asks for.

## Decision
1. **The look of "Cheapest this week"** (branch `claude/fervent-turing-2cd8ae`, `DealsView.swift`): Doddy (the owner's pack pose `WholeDoddy_reaching_high`, the island's "waiting for your yes" pose) with one line in his voice, "Hand me something to sort out"; cards on `Theme.quietSurface` with 20-pt corners and a separator edge; one primary button; details behind a tap. Colours and type only from `Theme` and the system text styles.
2. **The list as cards.** Each task shows its state as a chip with a word and an icon (never colour alone), the title, the user's words, the date, and "New result" for a finished one not yet opened. Tasks come first when there are any; with none, the screen leads with how to hand one over and says "No tasks yet." under it (a failed read still shows the error, never "no tasks").
3. **Hand a task over by typing.** A box, three examples of what the worker does (compare flights under a budget, find places, the steps for an ID card; a tap fills the box, nothing is sent) and "Hand it to Doddy". The server already takes a task without voice (`POST /v1/errands`, then `/approve`); no server change.
   - It is the same request as the voice tool's: the same digest over the words, Doddy's note and the title, the same preview check, one approval, never two (`ErrandsModel.submit`, shared by `handOver` and `handOverTyped`).
   - With no conversation there is no note from Doddy. The note is a fixed sentence that says so ("Typed by the user on the Tasks screen, not said in a conversation, so Doddy added no note of its own. Do what the words ask.", Polish for `pl`), and the title is the start of the words, cut after a whole word at 60 characters (`ErrandDraft.typed`, DoddyCore `ErrandTyped.swift`).
   - A card shows all three texts in full, what one tap allows, that nothing is booked, bought or sent, and where the texts go (Doddy's server; the words and note also to Anthropic). Only "Yes, go" sends anything (ADR-716). A link, words over 1,000 characters, or "Pause all connections" stop it before the card, with the reason in words.
   - The 30-day log ("What Doddy did") records "Hand over a task" with no title or words, as the voice tool does: done when the server said queued, not sure when the answer never came, not done when refused.
   - Typed tasks are research tasks. Shopping stays in the conversation, which asks what matters most; the screen says so.
4. **"How it works" in three steps:** say what you need; tap yes once; get the answer here and in Messages, with the pages Doddy read.
5. **One task** keeps a `Form`, so a shopping task's sections (`ShoppingResultSections`) stay as they are, drawn on the canvas with the quiet surface: a header with Doddy in the pose for the state (working, fist pump when done, facepalm when it failed, shrug when not confirmed), the state chip, the title and the date; then every status text as before, the result, "You said" and "Doddy's note", Stop and Delete.
6. **Watched prices** (`WatchesSection`, used only here) are drawn as cards too, with the same texts, buttons and identifiers.
7. **No "Talk to Doddy" button.** The Tasks screen is a sheet over Home; starting a conversation from it needs Home to close the sheet first and then start (`HomeConversation.talk`), which means a change in `HomeView.swift`, where other work is going on. The screen tells the user what to say instead. A follow-up can add the button with a small Home change.

## Consequences
- People can see what Tasks do and start one without a conversation. It sends the same data as the voice path, plus the fixed note; nothing new leaves the iPhone.
- The accessibility identifiers the UI tests use are kept (`home.tasks`, `errands.row`, `errand.state`, `errand.cancel`, `errand.delete`, `errands.openLoops`, `watch.*`). New ones: `errands.newTask`, `errands.example`, `errands.handOver`, `errands.handOverNote`, `errands.howItWorks`, `errands.empty`, `errands.ask.words`, `errands.ask.yes`, `errands.ask.no`.
- Polish lines for every new string; the one footnote that left the app is dropped from `l10n/pl.json`.
- Errands are still hidden in the beta's release scope (`ReleaseScope.shipping`), so Release builds don't show the screen; Debug builds do.

## Evidence
See the pull request. The SwiftUI views were not compiled here (no Xcode); the new DoddyCore rules have Linux tests, and `ErrandsModel.swift` was type-checked on Linux against DoddyCore with stand-ins for the push and server-config types. Nothing was seen on a device.
