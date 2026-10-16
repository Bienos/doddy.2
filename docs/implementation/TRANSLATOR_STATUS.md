# Translator mode status (ADR-215)
Date: 2026-10-10. Owner: "build translator mode". Design: ADR-214, `docs/design/TRANSLATOR_MODE.md`, canvas "Doddy Translator". Decisions T1–T6 as the owner answered them.

## What ships
**Two ways in**
- **Ask Doddy** in a conversation ("help me talk to the taxi driver, he speaks Spanish"). The agent calls `start_translator` and the app switches immediately, without a confirmation card. If language is missing, Doddy asks one short question first. When the existing session contains personal context, it ends privately and a clean translator conversation starts without notes, profile or lists.
- **Home › Translate:** pick face to face or listen only, your language and theirs (or "Detect when they talk"), then Start translating. The conversation opens in translator mode, and the agent gets **no saved notes, recent conversations or profile**: each of those variables carries a "not shared" line instead.

**While it is on**
- **No tools:** the app answers every tool call except `stop_translator` with "refused: …" before anything is looked up, logged or changed (`TranslatorPolicy`).
- **Private:** the conversation is private and stays private (the Private switch is locked). Lines go to an in-memory `TranslatorSession`, never to the conversation log or "What Doddy did".
- **Dynamic Island (ADR-244):** Language Bridge with "Translating" and the language codes only ("EN ⇄ FR"), never a line; see `docs/implementation/V3_ISLAND_STATUS.md` check 21.
- **Face to face (T1):**
  - their half is rotated 180°;
  - the AI label is always on their half, in their language;
  - each half shows the latest line meant for it;
  - "Show what they said" reveals the original;
  - exact-fact chips on both halves;
  - Say it again, Pause, and End in the middle bar.
- **Listen only (T1):** a list of lines in your language with the original underneath; Doddy is told never to speak to the people around you.
- **Disclosure first:** for a known face-to-face language pair, the disclosure is the provider's first spoken line, skipping a generic greeting and extra prompt round-trip. The `started` result or `{{translator_start}}` supplies the exact line. If the other language is explicitly set to detect, Doddy asks the other person to speak first and discloses before translating.
- **Who is talking (T4):**
  - Each of Doddy's lines goes to a half by its own language. If that can't be read, it uses the language of what was said before it, then the hold-to-talk side being held, then takes turns.
  - With "Detect", their language is learned from the first line that is clearly not yours.
  - "Noisy place: hold to talk" mutes the microphone except while a button is held, and tells the agent whose words come next.
- **Quiet word (T5):** a line starting with "Doddy" (or "hey Doddy") is shown on your half only as "Only for you". "Say it to them" asks Doddy to say his suggested sentence to them.
- **Careful mode:** health, law/police and money words in many European languages turn on banners on both halves, and they stay on. The prompt also tells the agent to translate word for word and add no advice.
- **Exact facts:** prices with currencies, times, phone numbers, street addresses and numbers with units, copied exactly from both the original and the translation (at most 4 per line).

**At the end (T3)**
- End stops the conversation. `stop_translator` (or "stop translating") ends only the mode, and Doddy talks normally again.
- **End card:** turns · pair · minutes, and what is and isn't kept.
- **Five minutes only:** "Copy the text" and "Save the facts as a note" work for 5 minutes (until the time shown). Then the text is dropped from memory. Done drops it at once.
- **Saving facts:** this is a normal explicit save (`.explicitText`, read back from the store). The receipt shows the saved text.

**Privacy text:** Settings › Privacy and "What leaves this iPhone" now say that the other person's voice goes to ElevenLabs. They also say that listen only hears whoever is near, and that the Home start sends no notes.

## Files
- **Core:**
  - `Translator.swift`: languages and per-language lines, setup and proposal, tool parsing, policy, replies, `TranslatorPrompt`, `LanguageGuess`, `TranslatorRouter`, `ExactFacts`, `CarefulTopics`, `TranslatorSession`, `TranslatorSummary`;
  - `VoiceTools.swift`: two cases;
  - `ActivityLog.swift` and `ConnectionPause.swift`: the translator is not an app action;
  - `DataFlow.swift`: the translator row.
- **App:**
  - `Features/Translator/TranslatorViews.swift`: the screen, end card, choices, start and change sheets;
  - `VoiceSessionController.swift`: mode state, routing of lines, refusal, hold-to-talk, copy/save, five-minute drop, privacy lock, and the variables for the Home start;
  - `VoiceView.swift`: the translator screen, the proposal card and the end card;
  - `HomeView.swift`: Translate;
  - `ShortcutRouter.swift`: the translator preset;
  - `SettingsView.swift`: the privacy paragraph.
- **Agent:**
  - `voice-agent/tools.json`: two tools;
  - `voice-agent/instructions.md`: two tool lines and the "Translator mode" section with `{{translator_start}}`;
  - `voice-agent/session.json`: the variable.
- **Tests:** `TranslatorTests` (17).

## Live agent (agent_0501m4et27vyeawrwqfdxxfszfa6)
- **New client tools:**
  - `start_translator` `tool_6601m4krz5tqe0paj9jxza6vnjgp`;
  - `stop_translator` `tool_4601m4krz73zeb1a9edtsxmn6c5s`.
- **Versions:** `agtvrsn_7101m4kpz26mf3p8yysmx0y4z6cz` (found live, unchanged since the language update) → `agtvrsn_2301m4krzkz7e52tvq4wj55fpx86` (placeholder `translator_start: none`, so builds that don't send it still start) → `agtvrsn_6601m4ks1cwmfqfs30v2cpsgg6c0` (prompt and 25 tool ids).
- **Kept as found:** the `propose_plan` tool and its prompt line (ADR-204, other line). The live prompt is `instructions.md` plus that one line.
- **Not changed:**
  - The `first_message` override stays off. The Home start gets the greeting first, then the app asks for the disclosure.
  - `max_duration_seconds` stays 600, so a translation, like any conversation, ends after 10 minutes.

## Verified (Linux, Swift 6.2.1)
- 382 package tests pass (365 before): 17 new in `TranslatorTests`, the rest unchanged.
  - The new tests cover the languages, including a check that all 37 agent languages have every line and a distinct disclosure.
  - They cover parsing, the policy and refusals, the started reply, the language guess and routing, the quiet word, listen only, detect, exact facts, careful topics, the session and the 5-minute summary, the prompt variable and the privacy row.
- The agent spec check passes (24 tools). `RealtimeVoiceTests` confirms every phone tool in the spec is routed.
- `swiftc -parse` passes on every changed app file.

## NOT RUN / UNVERIFIED
- **App:** not compiled or type-checked against the iOS SDK (no Xcode here). No screen has been seen, including the rotated half, hold-to-talk and the end card.
- **Live conversation:** none run. Unchecked:
  - whether the agent reliably translates instead of answering;
  - whether it says the disclosure first;
  - whether it keeps notes to itself when started mid-conversation (a prompt rule only, T2 risk);
  - whether it stays quiet in listen only;
  - latency;
  - whether `sendMessage` / `updateContext` messages behave as expected;
  - whether ElevenLabs echoes app messages as user transcripts (the app filters the "(app)" prefix either way).
- **Language lines:** the disclosure, AI label, hold-to-talk and careful lines in 37 languages were written without native review. The review sheet is `docs/implementation/TRANSLATOR_LANGUAGE_REVIEW.md`. It is generated from the code, and a test keeps it in step.
- **Routing:** the language guess is a small word-and-letter heuristic. It is wrong for very short lines, mixed languages and two people speaking the same language.
- **Careful mode:** word lists miss topics and may over-trigger.
- **Listen only:**
  - "Read aloud" (follow-up, ADR-221) can now be turned off. It sets the agent's audio track to volume 0 on this iPhone (LiveKit `RemoteAudioTrack.volume`, read back). ElevenLabs still makes the audio. This has not been heard on a device.
  - Turn-taking with a continuous speaker is untested.
- **T6:** native voices per language are not built. Doddy's own voice is used for both sides. There is a shortlist for a listening pass, and the one-voice-per-conversation constraint, in `docs/implementation/TRANSLATOR_VOICE_SHORTLIST.md`.

## Constitution evidence log (docs/trust/config/doddy_rules.yaml)
| Rule | What enforces it here | Tests run | Gaps / claims to limit |
|---|---|---|---|
| DOD-03 character_without_false_humanity / DOD-12 stable_identity | Disclosure line "an AI translator on this phone" in 37 languages, given to the agent verbatim. "AI translation · may contain mistakes" is always on their half | `testEveryAgentLanguageHasTheTranslatorLines`, `testStartedReplyCarriesTheDisclosureInTheirLanguage` | Saying it first is a prompt rule; no live run. Lines unreviewed |
| DOD-07 scoped_action_approval | `start_translator` is an immediate mode switch on the user's explicit request; while on, `TranslatorPolicy` refuses every tool before it runs or is logged | `testOnlyStopIsAllowedWhileTranslating` | Controller path not compiled |
| DOD-11 observable_privacy | Home start and the fresh voice-start conversation send no notes, conversations or profile. The prior conversation ends privately. Translator lines stay in memory only, dropped after 5 minutes. Privacy screens list the other person's voice | `testWhatLeavesThisIPhoneListsTheTranslator`, `testTranslatorStartVariable` | The prior provider session already received its approved context before the switch; the app cannot retract that prior processing. ElevenLabs keeps its own recording |
| DOD-06 user_controlled_relevant_memory | Nothing saved unless the user taps "Save the facts as a note"; that save is read back | `testSessionKeepsTurnsCarefulModeAndTheFiveMinuteSummary` (note text) | Save path not compiled |
| DOD-08 verified_status_and_receipts | "Saved as a note" shows the stored text; Copy says "Copied" only after the pasteboard write | — | UI not run |
| DOD-02 honesty_over_agreeableness / DOD-10 | Prompt: translate, never answer; add or soften nothing; "not sure:" instead of guessing; careful mode, no advice; emergencies → 112 | `testCarefulTopics`, `testExactFacts` | Translation accuracy is the model's and cannot be guaranteed |

Don't claim: "real-time interpreter", "accurate translation", "works in all 37 languages", "private" without "ElevenLabs keeps a recording", or that the app is tested on a device.
