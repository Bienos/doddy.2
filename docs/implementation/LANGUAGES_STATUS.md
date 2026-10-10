# European languages and Polish notifications status (ADR-206, ADR-207)
Date: 2026-10-10. Owner: "make sure doddy can talk with all european language and change between them freerly", together with "1." (Polish wording for notification text).

## What ships
**Languages (ADR-206)**
- The live voice agent has 36 language presets plus English, 37 in total:

  pl de fr es it pt nl sv da no fi cs sk hu ro bg el hr sl lv lt uk ru tr et ca sr is ga mt mk bs be cy gl lb

  - Each preset sets only the greeting.
  - ElevenLabs refused Basque (`eu`) and Albanian (`sq`), so those are not included.
- **Switching:** the built-in `language_detection` tool was already on with `only_at_conversation_start: false`. With the presets in place it can switch to any of these languages at any point.
- **Prompt:** "Reply in the language the user is speaking. You speak all European languages: if the user switches language, even in the middle of a conversation, switch with them straight away…"
  - Wikipedia lookups use the user's language code, falling back to `en`.
  - Note search uses Polish, English and the language being spoken.
- **Wikipedia tools:** both accept the same 37 codes. Summary redirects are allowed only for the 20 largest editions, because ElevenLabs caps that list at 20.
- **Settings → "Starts in":** Automatic, or 25 languages: English and the 24 European languages the ElevenLabs Swift SDK 3.3.1 can start a conversation in. Each is labelled by its own name, e.g. "Deutsch (German)".
  - The other 12 languages are reached by speaking them.
  - Stored values from before (`english`, `polish`) still read.
- **Copy:** Settings text now says Doddy follows any European language and that all voices speak them, each with its own accent.

**Polish notification text (ADR-207)**
- When the iPhone's first language is Polish, the Lock Screen notification is Polish:
  - title "Przypomnienie", and for a repeat "Przypomnienie · w każdy poniedziałek" (also "codziennie", "w dni robocze", "co miesiąc, 12. dnia");
  - private body "Notatka, którą chcesz zobaczyć ponownie." (second person, gender-neutral);
  - buttons Otwórz notatkę, Za godzinę, Jutro 09:00, Gotowe, Gotowe tym razem.
  - The note text itself is never translated.
- **Other languages:** notifications stay English until each language has reviewed copy.
- **Language change:** when the iPhone's language changes, the next time Doddy opens it re-registers the buttons and rewrites waiting notifications.
- **In-app screens:** these stay English. The app has no localisation set up yet (no String Catalog), so translating screens is a separate step.

## Files
- **Agent:**
  - `voice-agent/session.json`: languages, greetings, and the live English greeting copied verbatim;
  - `voice-agent/instructions.md`: three lines;
  - `voice-agent/tools.json`: the Wikipedia tools;
  - `voice-agent/README.md`: sync note and the known `propose_plan` drift.
- **Core:**
  - `VoiceStyle.swift`: `ConversationLanguage` with 25 languages, plus `nativeName` and `englishName`;
  - `NoteReminders.swift`: `NotificationLanguage`, Polish copy, buttons, cadence, and the coordinator's `language` setting.
- **App:**
  - `PersonalityView.swift`: labels and copy;
  - `AppEnvironment.swift`: the coordinator uses the iPhone's language;
  - `NoteReminderNotifications.swift`: button titles;
  - `NoteReminderStore.swift`: refresh when the language changes;
  - `RootView.swift`: a comment.
- **Tests:**
  - `NicknameTests.testEveryStartingLanguageIsOnTheAgent`: every starting language has a code, both names and an agent preset;
  - `NotificationLanguageTests`: language choice, all seven Polish weekday forms, title, body, buttons, request identifiers unchanged.

## Live agent (agent_0501m4et27vyeawrwqfdxxfszfa6)
- **Version path:** `agtvrsn_2801m4knwd04fxfbj25wat868jtp` (found live) → `agtvrsn_2301m4kpwmr1fcers0b8vf7th8qr` (presets) → `agtvrsn_7101m4kpz26mf3p8yysmx0y4z6cz` (prompt).
- **Wikipedia tools:** `tool_0901m4f25swxft090rnfkczn5jhj` and `tool_1101m4f25rx2fx7ttcempcvx8s89` were updated in place.
- **Drift already present:** the live agent had `propose_plan` (ADR-204, `claude/loving-dirac-uuxoux` line), which is not on this line. Its prompt line and tool were kept unchanged. The prompt sent was that line's `instructions.md` with only the three language lines changed.

## Verified (Linux, Swift 6.2.1)
- 365 package tests pass, including the new tests above.
- The agent spec check passes (22 tools).
- ElevenLabs accepted the 36 presets; the request with `eu` and `sq` was refused as a whole, so nothing partial was applied.
- `scripts/ci.sh --core-only` and `swiftc -parse` on all app files: see the commit.

## NOT RUN / UNVERIFIED
- **Conversations:** no live conversation in any new language, and no test of switching mid-conversation.
  - Speech recognition and voice quality per language are ElevenLabs'.
  - Smaller languages (Maltese, Irish, Luxembourgish, Welsh) are likely weaker.
- **Greetings:** the 36 greetings and the Polish notification text were written without native review. Decision D6, Polish copy, stays open for review.
- **App:** not compiled, and the Settings picker hasn't been seen with 26 entries.

## Constitution evidence log (docs/trust/config/doddy_rules.yaml)
| Rule | What enforces it here | Tests run | Gaps / claims to limit |
|---|---|---|---|
| DOD-12 stable_identity | Same Doddy prompt and voice in every language; the AI disclosure line is unchanged | — | Prompt-only; not evaluated per language |
| DOD-11 observable_privacy | No new data leaves the phone. Language detection runs inside the existing ElevenLabs session. Notification text stays private by default in Polish too | `testPolishTitleBodyAndButtons` (private body) | Wikipedia lookups in more languages go to more Wikipedia editions, as before |
| DOD-08 verified_status_and_receipts | Notification identifiers and verification don't depend on language | `testPolishTitleBodyAndButtons` (identifier unchanged) | — |
| DOD-10 nonmanipulative_companionship | Copy is neutral: Polish "chcesz" avoids a gendered form | — | Native review pending |

Don't claim: "fluent in all European languages", "native quality", or "the app is translated". Only the voice agent and the notification text are multilingual.
