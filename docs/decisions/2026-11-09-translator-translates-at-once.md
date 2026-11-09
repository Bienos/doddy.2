# The translator translates from the first word, both ways, and never talks about itself

- **Date:** 2026-11-09
- **Decided by:** owner, in Polish: "tłumacz mi nie działa … słyszy ten [obcy] i od razu na polsku tłumaczy a tak nie jest teraz"; then, asked how it should work: "W obie strony" (their language into Polish, your Polish into their language).
- **Status:** accepted
- **Replaces:** for the Home start, ADR-215's "the app asks for the disclosure once Doddy's greeting has played"; for a start that names nothing to translate, ADR-619's "ask what to translate" (only in the `{{translator_start}}` variable, see below)

## Why
The ElevenLabs log of the owner's two translator tries on 9 Nov 2026 (`conv_8301m70vbrxjfs3s2j8jmz94pj5j`, `conv_1901m70vc5nveymb511n6a38m4g5`):
1. "Tryb tłumacza włącz" → `start_translator` → the app ended that conversation and opened a private one (review H3), as designed.
2. The new conversation opened with the normal greeting, "Jestem. Co słychać?".
3. The app then sent "(app) Translator mode is on. Do what the translator_start section says now." The agent called `start_translator` again; the app refused it ("translator mode is on, so the app doesn't run the tool"), and the agent said "Translator mode is already on. The other person hasn't spoken yet." in English.
4. The user's next words were answered with "Przetłumacz to, proszę." Nothing was translated.

## Decision
- **Opening line:** a conversation opened for translating opens with `TranslatorPrompt.openingLine`: the AI translator disclosure in their language when it is known, otherwise "Tłumaczę. Mów albo daj mówić drugiej osobie." (listen only: "Słucham i tłumaczę na polski."). No "(app)" message follows.
- **`{{translator_start}}`** (`TranslatorPrompt.render`): the mode is already on; never call `start_translator` or talk about the mode; the disclosure was the first message; don't ask what to translate; which way each line goes. With their language unknown: the first language heard that isn't yours is theirs; your words go into English (Polish for an English speaker) until then, after the English disclosure.
- **A second `start_translator`** while translating is answered `started: translator mode is already on …` with the same directions (`VoiceToolReply.translatorAlreadyOn`), never "refused". `TranslatorPolicy` allows `start_translator` and `stop_translator`; every other tool is still refused before anything runs.
- The live agent prompt (`voice-agent/instructions.md`) is **not** changed: everything above is app-side (a variable, a tool reply, the opening line).

## Consequences
- The disclosure is still said before any translation (the opening line, or once when their language is first heard).
- A voice start inside a normal conversation still restarts as a private conversation (review H3); the new conversation now begins translating at once.
- Not checked: whether ElevenLabs' speech recognition, with the agent language set to Polish (`agent.language` override), transcribes the other person's language well. If it doesn't, the next step is not sending that override in translator mode.

## Evidence
`swift test` (Linux, Swift 6.1.3): `TranslatorTests`, `ToolGateTests`. The app changes (`VoiceSessionController.swift`) are not compiled here; the hosted Mac job compiles them. Not tried on a phone or with the live agent.
