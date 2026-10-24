# Live agent edit, 24 Oct 2026: translator mode without asking (ADR-611)

Owner, 24 Oct 2026: "ogólnie to się nie pytaj nawet, od razu działaj i się przełącz i pytaj, co tłumaczyć", then "Ok" to updating the live agent.

Agent `agent_0501m4et27vyeawrwqfdxxfszfa6`. Read just before: version `agtvrsn_3501m5pk6ad9ed9v77hn049th27v` (the rollback point for the prompt). Its prompt is the dashboard DODDY persona prompt, not `voice-agent/instructions.md`, so it is edited in place, never replaced with the repo text.

## Done
- **`start_translator`** (`tool_6601m4krz5tqe0paj9jxza6vnjgp`), saved and read back: the description says to start the moment the user asks, without asking first, and to ask once what to translate if the user hasn't said; the old "The app asks the user first…" and the ASK-01 sentence are gone. `pre_tool_speech` `force` → `auto`. Parameters, timeout (90 s) and execution mode unchanged. The same description is in `voice-agent/tools.json`. Undo: the description and `pre_tool_speech: force` in `git show 12dc2d3:voice-agent/tools.json`.

## Not done yet (stopped by this session's safety check as a production change; waits for the owner's explicit go-ahead)
- **`stop_translator`** (`tool_4601m4krz73zeb1a9edtsxmn6c5s`): description to "End translator mode the moment the user asks to stop translating (for example 'Doddy, stop translating' or 'Doddy, koniec tłumaczenia'). Don't ask first: the app stops it at once (the owner's rule of 24 October 2026). The result starts with 'stopped'; then talk with the user normally again, in their language."; `pre_tool_speech` `force` → `auto`.
- **The prompt**, four edits in place (nothing else changes; 39,894 → 40,559 characters):
  1. Translator section, after "…translate nothing more.": "Right after it starts: if the user hasn't said yet what to translate, ask them once, in their language, in one short line what to translate (for example "Co mam przetłumaczyć?"). That is the only thing you say that isn't a translation, apart from the disclosure."
  2. "Always ask first (ASK-01)", after the 21 October exception: "Exception, the owner's rule of 24 October 2026: translator mode starts and stops at once. When the user asks you to translate, or to help them talk with someone in another language, call start_translator straight away, with no question first. When they ask to stop translating, call stop_translator straight away."
  3. "Approval cards": "…shows a card first, translation and lists included." → "…shows a card first, lists included." and, after the public lookups sentence, "Translator mode starts and stops at once, with no card and no question."
  4. Guardrails: "Public lookups run at once." → "Public lookups, and translator start and stop, run at once."

Until these are saved, the live prompt still tells Doddy that translation shows a card, so he may still ask out loud; the iPhone build with ADR-611 starts the mode as soon as the tool is called. Builds before ADR-611 still show their "Start translator mode?" card.
