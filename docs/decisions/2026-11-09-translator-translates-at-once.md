# The translator stays silent until someone speaks, then translates both ways at once

- **Date:** 2026-11-09
- **Decided by:** owner, in Polish: "tłumacz mi nie działa … słyszy ten [obcy] i od razu na polsku tłumaczy a tak nie jest teraz"; then, asked how it should work: "W obie strony" (their language into Polish, your Polish into their language); then, told that Doddy would first say an AI disclosure aloud: "niech nic nie mówi, zmień zasady proszę i też to menu tłumacza zrób jakieś łatwiejsze w obsłudze i w kolorze Doddy".
- **Status:** accepted
- **Replaces:** ADR-215's spoken disclosure ("Doddy first tells them, in their language, that he's an AI translator") and its Home start ("the app asks for the disclosure once Doddy's greeting has played"); ADR-619's "ask what to translate"; the Home › Translate start screen of ADR-215 and ADR-574 (a form)

## Why
The ElevenLabs log of the owner's two translator tries on 9 Nov 2026 (`conv_8301m70vbrxjfs3s2j8jmz94pj5j`, `conv_1901m70vc5nveymb511n6a38m4g5`):
1. "Tryb tłumacza włącz" → `start_translator` → the app ended that conversation and opened a private one (review H3), as designed.
2. The new conversation opened with the normal greeting, "Jestem. Co słychać?".
3. The app then sent "(app) Translator mode is on. Do what the translator_start section says now." The agent called `start_translator` again; the app refused it ("translator mode is on, so the app doesn't run the tool"), and the agent said "Translator mode is already on. The other person hasn't spoken yet." in English.
4. The user's next words were answered with "Przetłumacz to, proszę." Nothing was translated.

## Decision
- **Silent start:** a conversation opened for translating has an empty first message (`TranslatorPrompt.openingLine` is ""), so the agent waits for someone to speak. No "(app)" message follows. Doddy says nothing of his own: no greeting, no spoken disclosure, no question.
- **The AI label stays on screen:** the other person's half always shows, in their language, "AI translation · may contain mistakes" (`TranslatorLanguage.aiLabel`). That is now the only disclosure to them.
- **`{{translator_start}}`** (`TranslatorPrompt.render`): the mode is already on; never call `start_translator` or talk about the mode; say nothing of your own (this replaces the disclosure and "ask what to translate" lines of the prompt); which way each line goes. With their language unknown: the first language heard that isn't yours is theirs; your words go into English (Polish for an English speaker) until then. The `started` reply to a voice start says the same.
- **Home › Translate** (`TranslatorStartView`): two big cards (Face to face, both ways; Listen only, into your language), "You speak" ⇄ "They speak" buttons with a swap between them, one-tap chips for English, Deutsch, Español, Français, Italiano, Українська and Polski, and one orange Start button (`Theme.orangeCue`), with Doddy waving at the top.
- **A second `start_translator`** while translating is answered `started: translator mode is already on …` with the same directions (`VoiceToolReply.translatorAlreadyOn`), never "refused". `TranslatorPolicy` allows `start_translator` and `stop_translator`; every other tool is still refused before anything runs.
- **Live agent prompt:** changed on the owner's "ok" on 9 Nov 2026 (`agtvrsn_0501m706dw6tfyj8frbt6g06m3y4` → `agtvrsn_5401m70zggkafcz88jshewy89ae8`): the disclosure and "ask what to translate" lines replaced by "Say nothing of your own…" (`voice-agent/README.md` has the exact text). The live `start_translator` description still says "ask once"; updating it was refused by this session's permission check and waits.

## Consequences
- **Disclosure is weaker:** the other person is told only in writing, on their half of the screen, that this is an AI translation; in Listen only, nobody around is told (as before). If they can't see the screen, they may not know. EU AI Act Art. 50 asks that people be told when they interact with an AI system unless it is obvious; the owner chose the silent start knowing this.
- A voice start inside a normal conversation still restarts as a private conversation (review H3); the new conversation now begins translating at once.
- Not checked: whether ElevenLabs' speech recognition, with the agent language set to Polish (`agent.language` override), transcribes the other person's language well. If it doesn't, the next step is not sending that override in translator mode.

## Evidence
`swift test` (Linux, Swift 6.1.3): `TranslatorTests`, `ToolGateTests`. The app changes (`VoiceSessionController.swift`, `TranslatorViews.swift`) are not compiled here; the hosted Mac job compiles them. Not tried on a phone or with the live agent; whether ElevenLabs accepts an empty first message from `{{opening_line}}` without speaking is to be checked in the conversation log after the first try.
