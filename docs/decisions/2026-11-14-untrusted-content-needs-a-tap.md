# Once text from outside has reached a conversation, the tools that run at once and could carry it out of the phone ask for a tap

- **Date:** 2026-11-14
- **Decided by:** the owner approved this work and its edits to the voice controller, `AskFirst.swift` and `NoteQuestion.swift` (agent brief, 14 Nov 2026). The product choices marked "Owner decision" below are proposals until the owner says otherwise.
- **Status:** applied in the pull request from `claude/untrusted-content-needs-a-tap`
- **Replaces:** nothing. It adds to `2026-11-11-asked-for-runs-at-once`: that decision's baseline is unchanged.

## Why
- Since 11 Nov a handful of voice tools run with no card because the user asked for them. Most are harmless whatever the agent was told. A few can send text, spend money or change something other people see, and text from an email, a web page or the screen can be written to look like the user's own request.
- The constitution says a model proposes and typed code validates (DOD-07), and that tool, web, email and document content is data, never instructions (`untrusted_tool_outputs_are_instructions: false`). A line in the prompt says the second part to the agent; this change makes the app enforce the part that matters for the tools below.

## Decision
The app keeps one fact per conversation, "text someone else wrote has reached it" (`OutsideContentSession`, DoddyCore `OutsideContent.swift`), and a pure rule on top of the baseline `AskFirst.need(for:)`, `AskFirst.need(for:in:listIsShared:)`. It only ever adds a card; a call that already asks keeps its ask. A card is answered by a tap through the existing `AskLedger` (one tap, one run, exactly this request; a spoken yes, a no, a timeout or a replaced card runs nothing).

1. **What sets the fact.** The app is about to run: an online-account tool (reads and writes, except `ask_claude` and `make_document`), `web_search`, `news_search`, `find_places`, flights, `check_errands`, `find_deals`, `pay_for_page`. A look at the screen sets it separately (see 4). ElevenLabs runs the weather and Wikipedia tools itself; the app sees only that they were called, and counts the call.
2. **`text_me`, and `ask_claude` with material:** a card once the fact is set. The text card shows the exact text and that it goes to the user's own verified number only. The Claude card shows the request, the start of the material and its full length. Without outside text, or without material, they run at once as before.
3. **`make_document`:** a card once the fact is set, with the kind, title, request and the start of any material. Without outside text a file is made at once: the owner decided on 13 Nov 2026 (`2026-11-13-file-being-made-island-note`) that Doddy never asks the person to tap for a file being made, and this keeps that. If you want a card on every file, it is one condition in `AskFirst.need(for:in:)` (drop the `outsideContentSeen` guard on `make_document`).
4. **`look_at_screen`:** a tap for the first look in a conversation (the existing card, `ScreenLookSpeech.askCard`), and again for a look after text from somewhere other than the screen. Later looks run at once while nothing else has come in. What Claude reads off the screen reaches the agent between the data markers (`ToolData.block`, one clean line each).
5. **`add_to_list` and `check_off` on a shared list:** a card with the exact items, unless every item is made of words the user said in their last line (folded whole words; a number said as a word does not match a digit, so it asks). The app resolves the list first and asks `SharedListsController` whether other people are on it. Shared lists are off in builds with no iCloud container, so today this changes nothing for anyone.
6. **"Ask me about it":** the saved note goes to the agent between the data markers, on one clean line (`NoteQuestion.appMessage`).
7. **Per conversation.** The session value is replaced where a conversation starts and where it ends; nothing carries over. The user's last line is kept for the shared-list match and replaced by the next.

**Not changed, on purpose:** `voice-agent/tools.json` (it waits for the live-agent sync) and the python spec checks. The tools above are still `runs_now` there: that is the baseline, and `ToolCatalogTests` and `AskFirstTests` still pin it. The wording the live descriptions need is `docs/OWNER_QUEUE.md` 97, including the `follow_news` sentence that promises a card that does not exist.

## Consequences
- More taps in the cases above, and none otherwise. After an email read, "text me that code" shows a card.
- The agent is not told a card may appear until the descriptions are synced (OWNER_QUEUE 97). A card waits up to 60 s for a tap on those tools until `timeout_secs` is raised there.
- The Wikipedia and weather results are still not marked as data: they would have to run on the phone (`runs_on: phone`), which is a `tools.json` change and its own pull request.
- **Gaps, recorded so nobody reads this as complete:** notes, the device calendar and the items of a shared list are the user's own data and do not set the fact (a calendar invitation or a shared item can still carry someone else's words). The match for shared-list items is a conservative word match; a false "ask" costs a tap, a false "run" would need every word to be the user's. Plan cards (`propose_plan`) are approved as a whole and are not changed.

## Evidence
- DoddyCore on Linux, Swift 6.1.3: `OutsideContentTests` (28 tests: the flag per source, per session and for the screen; each guarded tool with and without the fact; shared-list word matching; a declined, ignored, late or spoken answer never runs the tool; Polish cards), `NoteQuestionTests` and `ScreenLookTests` (the data markers, and a text that tries to close the block). The exact commands and results are in the pull request.
- Constitution rules covered: DOD-07 (tap bound to the exact payload; no model-only approval), DOD-08 (nothing reported done without the tool's own result; a declined card says "did nothing"), the tool-content-is-data rule (`untrusted_tool_outputs_are_instructions: false`), ASK-01 (`AskLedger`). Gaps: the controller wiring is not compiled here (no Xcode) and not seen on a device.
