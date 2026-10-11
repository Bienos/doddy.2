# App screens in Polish status (ADR-223)
Date: 2026-10-10. Owner: "do all of them" (item 6).

## What ships
- **Polish when the iPhone is in Polish.** iOS chooses by the iPhone's language. `Config/Doddy-Info.plist` declares `CFBundleLocalizations` en and pl. English stays the source and the fallback.
- **One String Catalog,** `DoddyApp/Resources/Localizable.xcstrings`. It is generated from `l10n/pl.json`, which maps English source text, written as in the Swift code, to Polish. SwiftUI looks the keys up for literal `Text`, `Button`, `Label`, `Toggle`, `Section`, `navigationTitle`, `TextField`, `SecureField`, `Picker`, `DisclosureGroup`, `confirmationDialog`, `Link`, `ShareLink`, `DatePicker` and accessibility labels. `JourneyHeading` (the big screen titles) now looks up its eyebrow, title and subtitle as well.
- **Coverage: 562 of the 606 literal UI strings** (including the opening, ADR-225). The voice is informal ("Ty"), Doddy is "on", and terms follow iOS's own Polish ("Ustawienia", "ekran blokady", "Przypomnienia", "Mapy Apple").
- **Still in English:**
  - **The two longest privacy paragraphs** (Settings › Privacy, "What leaves this iPhone" › details) and a few long developer and setup texts. A privacy claim shouldn't be translated without review.
  - **Strings built at run time.** These include anything with a value inside (`"\(count) to go"`), messages made in Swift code (errors, receipts, the morning check-in and backup messages), the widget gallery texts, App Shortcut phrases and the system permission prompts (`INFOPLIST_KEY_…`). Each of these needs `String(localized:)` or an `InfoPlist.xcstrings`; that is the next step.
  - **Notifications** were already Polish (ADR-213), and the voice agent speaks the user's language (ADR-212).
- **CI:** `python3 -I tools/build_strings_catalog.py --check` (in `scripts/ci.sh`) fails when the catalog doesn't match the table, or when a Polish line's English text is no longer in the app.

## How to add or fix a line
Edit `l10n/pl.json`, then run `python3 -I tools/build_strings_catalog.py` and commit both files. Keys must match the Swift literal exactly, including `\n` and `\"`.

## Verified (Linux)
- The generator builds the catalog. `--check` passes. Keys were checked against the strings found in the app (none missing). Swift escapes (`\n`, `\"`, `\u{201C}`) become real characters in the catalog keys.
- `swiftc -parse` on `MemoryJourneyComponents.swift`. `plutil -lint` on the Info.plist.

## NOT RUN / UNVERIFIED
- No Xcode build. Xcode compiling the hand-made catalog, its "stale/manual" handling, and how XcodeGen lists `pl` in known regions are all not checked.
- Never seen on a Polish iPhone. Unchecked: truncation, longer Polish words in buttons, and Dynamic Type.
- The translations are one writer's. They need a native read-through before release, especially the privacy and AI-disclosure lines ("Doddy to SI, nie człowiek").

## Constitution evidence log (docs/trust/config/doddy_rules.yaml)
| Rule | What enforces it here | Tests run | Gaps / claims to limit |
|---|---|---|---|
| DOD-03 character_without_false_humanity | "Doddy to SI, nie człowiek" / "Jestem asystentem SI, nie człowiekiem" kept with the same meaning | catalog check | Native review pending |
| DOD-11 observable_privacy | Privacy paragraphs not machine-paraphrased: the longest stay English until reviewed | — | Mixed-language Privacy screen in Polish |

Don't claim "Doddy is fully in Polish": screens built at run time, long privacy texts and permission prompts are still English.

## Finishing Polish (ADR-233, 2026-10-10, owner: "do all of them", item 2)
- **Messages made in code:** 247 on-screen messages that were plain Swift strings now go through `NSLocalizedString`. These cover errors, receipts, status words, note types, voice and personality labels, card buttons, import, backup, tidy-up, check-in and voice-memo notices. (`String(localized:)` isn't in Linux Foundation, which would break the app-logic type-check.) Two kinds were left alone on purpose:
  - **Text sent to the voice agent:** `VoiceSessionController` tool replies and `DeviceConnections` errors. These stay English for the model.
  - **The voice names.**
- **The generator** (`tools/build_strings_catalog.py`) now also finds `NSLocalizedString("…")`, App Intent titles and descriptions (`LocalizedStringResource`, `IntentDescription`) and App Shortcut short titles. Besides the app's catalog it writes four more:
  - `DoddyWidgets/Localizable.xcstrings` and `DoddyWatch/Localizable.xcstrings`: only the lines each target uses.
  - `DoddyApp/Resources/InfoPlist.xcstrings`: the 6 permission prompts, from `l10n/pl_infoplist.json`, which records the English each translation was made from. If a prompt changes in `project.yml`, `--check` fails until its Polish is reviewed.
  - `DoddyApp/Resources/AppShortcuts.xcstrings`: the 19 Siri phrases, from `l10n/pl_shortcuts.json`. Every Polish phrase must name the app once and keep `${list}` where the English has it. They use "w aplikacji ${applicationName}" so the app name needn't be declined.
- **Coverage:** 901 of 922 UI strings, 6 of 6 permission prompts and 19 of 19 Siri phrases. The privacy paragraphs are now Polish too, except the longest one (Settings › What leaves this iPhone › details), which waits for a native reviewer.
- **Still English:**
  - strings with a value inside (`"\(count) notes"`);
  - developer and test-fixture screens;
  - the watch's iPhone replies (made in DoddyCore);
  - the longest privacy paragraph.
- **Whether Siri accepts Polish phrases** depends on Siri supporting Polish on the device. That is not verified here. The short titles show in Polish in Shortcuts and Spotlight either way.
- **Verified (Linux):** `--check` passes. `scripts/ci.sh --core-only` passes. `swiftc -parse` passes on every changed Swift file.
- **Owner, 2026-10-11:** a native speaker reviews the Polish before release (ADR-234). The privacy texts and the AI disclosure go first. Until then, every Polish line counts as a draft.
- **NOT RUN:**
  - no Xcode build, so not checked whether Xcode accepts the generated InfoPlist/AppShortcuts catalogs or whether XcodeGen adds the widget and watch catalogs as resources;
  - never seen on a Polish iPhone or watch;
  - the translations need a native read-through, the privacy ones first.

## Catching up (ADR-260, 2026-10-11, owner: "build next")
- **Coverage:** 972 of 991 app strings (was 904). 68 new lines:
  - Focus and Breathing;
  - the Dynamic Island words: "Note saved", "Plan ready", "Time's up", "Open Doddy to …" (also in the widget catalog);
  - read aloud;
  - Hey Doddy settings;
  - Siri note readback ("Ask Doddy what I saved");
  - end-of-conversation save suggestions;
  - the island style screen;
  - the note history notice;
  - the Undo hint in What Doddy did;
  - the long privacy paragraph in Settings, which had fallen out of the table when its English changed.
- **The Siri phrase is quoted exactly.** The Settings help and the privacy paragraph quote the Polish phrase Siri listens for, "Zapytaj aplikację Doddy, co mam zapisane" (`l10n/pl_shortcuts.json`), so a Polish user says what actually works.
- **Birthdays added to the privacy paragraph.** The English Settings paragraph now says "contact names and birthdays (day and month)", the ADR-256 disclosure it was missing; the Polish says the same.
- **Left in English on purpose (19):**
  - punctuation;
  - example URLs;
  - the social handles;
  - "SWISH!";
  - the names "Dynamic Island" and "Hey Doddy" (the English wake word);
  - the "LIVE" island badge;
  - the developer-only Native Island test screen.
- **Still English** (built in code, not covered by the catalog):
  - the What Doddy did Undo button ("Undo" / "Undoing…", a ternary like the existing "Check in Reminders");
  - the Undo sheet's question and explanation and the birthday and calculator replies (DoddyCore).
- **Verified:** `tools/build_strings_catalog.py --check` PASS; `scripts/ci.sh --core-only` PASS (643 DoddyCore tests).
- **Not verified:** not read by a native Polish speaker, and not checked on screen for clipped text (checklist PL1).
- **Undo in Polish (ADR-261, 2026-10-11):**
  - The Undo confirmation (question, explanation, button) on the What Doddy did sheet and on the voice card follows the iPhone's language (`NotificationLanguage`, as for notifications), e.g. "Usunąć „Dentysta” z Kalendarza?" / "Usuń".
  - Dates on it are numeric (2026-10-12 18:00) in both languages. A reminder that had no due date reads "Termin zostanie usunięty, jak było przed zmianą".
  - The row buttons "Undo" / "Undoing…" now go through the catalog ("Cofnij" / "Cofanie…").
  - The rest of each What Doddy did row (app name, result, notes) is still English: it is made in DoddyCore, like before.
  - 973 of 992 strings. `ActivityUndoTests.testTheSheetIsInPolishOnAPolishIPhone`.
- **What Doddy did in Polish (ADR-262, 2026-10-11):**
  - **How:** rows are still kept in English (the activity file and old rows don't change) and are translated when shown, with the iPhone's language (`NotificationLanguage.current`).
  - **What is translated:**
    - app names ("Kalendarz", "Przypomnienia" …) and results ("Zrobione", "Nie wiadomo, czy się udało", "Cofnięte" …);
    - every row title Doddy writes ("Dodaj wydarzenie", "Odhacz na liście" …);
    - Doddy's own fixed notes (paused, not connected, interrupted, Check in Reminders, every Undo result);
    - plan headings with Polish plurals ("Plan · 3 kroki") and counts as "zrobione: 2 · niepewne: 1";
    - the plan progress on the conversation screen.
  - **What is not reworded:** the detail (the user's own words and dates), and any reason an app or server gave, which is shown as kept. For a failed Undo, the frame is Polish and the reason stays as given.
  - **Fixed on the way:** the English row title "Draft a email" is now "Draft an email"; old rows still translate.
  - **Tests:** `ActivityTextTests` builds a row for every kind of request and fails if a title has no Polish, so a new row kind can't quietly show in English. A planted missing title was caught.
  - 974 of 993 strings; `scripts/ci.sh --core-only` PASS (648 DoddyCore tests).

