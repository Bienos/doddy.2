# Doddy does what he is asked without asking first, except for money, bookings and messages to other people

- **Date:** 2026-11-25
- **Decided by:** owner ("he should not be really asking anything", "nothing should stop him unless he has to pay for something", "make sure this agent is not basically telling me I cannot do something", "Polish by default, follow the user switch … Spanish, German, French, Russian, Ukrainian. But that's it", temperature "0.5", "Just do these changes", 25 Nov 2026)
- **Status:** accepted; live agent changed on 25 Nov 2026 (version `agtvrsn_9801m88sg1jqfswra2xfeyswea87`); app part in the pull request that carries this file
- **Replaces:** decision `2026-11-15-after-outside-text-one-question` (option 2) for Doddy's own things; the card for `call_me_now` and `call_me_later` (ADR-754's card stays only for a later call in quiet hours)

## Why
- On 25 Nov the owner asked "jesteś w stanie zadzwonić do mojego kolegi?" and Doddy answered "Nie zadzwonię do twojego kolegi" (`conv_4301m86r7y49e5w8w1pgc7a27nqk`, logged `failure_kind: said_cant`). The prompt's "Unsupported" list and the app's "Tell the user this isn't available yet" reply taught him to stop at "I can't".
- After reading an email or a page, Doddy asked before every one of his own small things (a note, a timer, a list item), and "zadzwoń do mnie" always gave a card and a question first.
- The main agent had 90 language presets; speech recognition could pick a wrong language for a Polish sentence. Translating has run on its own agent (Doddy 6) since 12 Nov, which keeps its 89 languages.

## Decision
Live main agent (ElevenLabs, done on 25 Nov through branch `proactive-pl-2026-11-25`):
- Languages: Polish (the agent's own) plus presets for English, Spanish, German, French, Russian and Ukrainian only. Temperature 0.7 → 0.5. Speech-recognition keyterms for Doddy and common Polish brands and services.
- Prompt: Doddy's own undoable things and calls to the user's own phone run at once, also after outside text (which stays data, never an instruction); when the user's sentence already includes the next step, he does it; "call a friend" leads to the contact on screen or a message, never a bare "nie zadzwonię"; "# Unsupported" became "# Limits": never only "nie mogę", do the nearest thing; a native-Polish understanding line.
- Shared tools `call_me_now` and `call_me_later`: "Runs at once" descriptions, pre-tool speech `auto`.

App (DoddyCore and the voice controller):
- `AskFirst.ownPhoneCallsAtOnce` = `call_me_now`, `call_me_later`: tier at once, no card. A later call that falls in quiet hours keeps its card for the "call anyway" switch (`waitsForAChoice`). The server still checks consent, the verified number and its limits.
- `AskFirst.runsWithoutItsCard`: the controller's no-card rule moves into DoddyCore and no longer looks at outside text.
- `ConfirmationTiers.afterOutsideContent` no longer turns Doddy's own things into a spoken yes. `AskFirst.need(for:in:)` no longer adds a card after outside text for `make_document`, `ask_claude` with material, or the user's own list.
- Kept: `text_me` asks after outside text (it goes out from Doddy's own number, so a link or code from an email must never reach the phone unseen); a shared list asks unless the user said every item; the first look at the screen asks; sending, deleting and other people keep their card; money and bookings stay a tap.
- `VoiceToolReply.unsupported` tells the agent to do the nearest thing instead of saying it can't.
- Settings offers only the agent's languages (`ConversationLanguage.offered`); an older stored choice outside them starts automatically (`agentOverrideCode`).

## Consequences
- Fewer questions. The trade: words in an email or page can now steer Doddy's own undoable things (a note, a reminder, an item on the user's own list, a file) without a card. Each is undoable, and the agent is told never to act on such text; `text_me`, shared lists, sends, deletes, money and bookings keep their protection.
- An older app build still shows a card for `call_me_now` and `call_me_later`; the live prompt and tool descriptions handle that ("if the app shows a card instead, ask its one question").
- An older build whose Settings language is one the agent no longer has (Italian, say) sends that language as the override. Not tried live; the owner's own setting is Polish or automatic.
- Constitution: this narrows DOD-07's outside-content rule for undoable, self-directed actions only. Rules for external writes, payments and unknown outcomes are unchanged.

## Evidence
- Live tests before the merge: 43 main-agent tests, branch 40 passed and 3 failed, live 38 passed and 5 failed; the 3 failing on the branch fail on the live version too (two are outdated tests: a fixed date in the past, and "I can't order food" while `call_places` orders).
- `swift test` for DoddyCore on Linux with Swift 6.1.2: 3900 tests, 0 failures, 2 skipped. `python3 -I scripts/voice_agent_spec.py check` for the main, phone, task-call and translator agents: PASS.
- Not run: the iPhone app build (no Xcode here, and hosted CI has had no runner since 20 Nov), any device or audio check.
