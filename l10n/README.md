# Languages: how Doddy's screens are translated

Status 2026-10-13: the catalogs carry **English, Polish and eight machine-translated drafts**: Spanish, German, French, Simplified Chinese, Japanese, Brazilian Portuguese, Italian and Croatian. The drafts have not been compiled, seen on a device or read by a native speaker; `REVIEW_NOTES.md` lists what to check first and the decisions the owner has to make. This page says what exists, how a language gets added, and how a person switches. The translation prompt is `TRANSLATION_PROMPT.md` next to this file.

## What exists

- **No library is needed.** The app uses Apple's String Catalogs (`Localizable.xcstrings`, one per target: app, widgets, share extension, Watch, Watch widgets, Mac, Mac widgets). SwiftUI looks up every `Text("…")`, `Button("…")`, `Label`, `Toggle`, `Section` and similar literal in the catalog at run time, so the whole design is covered without touching a screen (ADR-223). Adding a language is adding a column to the catalogs, not changing views.
- **The catalogs are generated, never edited by hand.** `tools/build_strings_catalog.py` reads every language table in this folder: `l10n/<code>.json` (English key → that language), `l10n/<code>_infoplist.json` (permission prompts) and `l10n/<code>_shortcuts.json` (Siri phrases), and writes all the catalogs with one column per language, plus the `CFBundleLocalizations` array in both Info.plists (ADR-458). `--check` runs in CI (`scripts/ci.sh --core-only`) and fails when a catalog or plist is stale, a placeholder differs, a prompt or phrase is missing, or a translated line's English has left the app.
- **Coverage today:** 1,358 of 1,405 UI strings, 8 permission prompts, 26 Siri phrases. The remaining 47 are built at run time (values inside the string, error messages) and stay English in every language until they move to `String(localized:)` (`docs/implementation/POLISH_SCREENS_STATUS.md`). Text sent to the voice agent stays English on purpose.
- **Shipped languages** are the `CFBundleLocalizations` array in `Config/Doddy-Info.plist` and `Config/DoddyMac-Info.plist`, which the generator writes from the tables it finds.
- **The voice speaks any language already.** OpenAI Realtime runs the voice by default (ADR-442). The session the app sends (`OpenAIRealtimeWire.sessionUpdate`) sets no language, and the transcription model detects the language it hears, so Doddy answers in whatever language the person speaks, Chinese or Japanese included; nothing in the code restricts it. The ElevenLabs switch is the exception: its agent is limited to the 37 languages it has presets for (`voice-agent/session.json`). Settings › Voice and personality › Language (Automatic plus 25 European languages, `ConversationLanguage`) is sent to ElevenLabs only; on Realtime it just picks the fallback greeting and the language a long turn is written out in on the device.

## How a new language gets in

1. **Translate.** Run `TRANSLATION_PROMPT.md` for the language. It works through `tools/l10n_batch.py`: `show` prints the next strings by number with the English and the Polish, `merge` puts the answers under the right keys (refusing empty lines and placeholder mismatches), `status` says what is left. The translator never types a key. Result: `l10n/<code>.json`, `l10n/<code>_infoplist.json`, `l10n/<code>_shortcuts.json`.
2. **Build the catalogs:** `python3 -I tools/build_strings_catalog.py`, then `--check`. The code lands in every catalog that has one of its strings and in both `CFBundleLocalizations` arrays. Commit the tables, the regenerated `.xcstrings` and the plists together.
3. **See it on a device** (needs a Mac): build, run with `-AppleLanguages (<code>)` or set the language in iOS Settings, and check Home, capture, Settings and the voice screen at default and AX5 Dynamic Type, light and dark, for truncation. `DoddyUITests/PolishSmokeTests.swift` is the pattern for a smoke test per language.
4. **Native review before release.** ADR-234 applies to every language: machine translation is a draft; the privacy texts and the AI disclosure are reviewed first.

A table that has not been through steps 3 and 4 is a draft the app can show, not a language Doddy supports.

## How a person switches language

- **Screens:** iOS does this. Once the app ships more than one language, iOS Settings › Doddy shows a **Language** row (iOS 13 and later) and the app relaunches in that language. The app can add a "Change language" row in its own Settings that opens that page (`UIApplication.openSettingsURLString`). There is no in-app picker that bypasses iOS: Apple's guidance is the Settings row, and a bypass would need every string looked up through a custom bundle.
- **Voice:** already there, Settings › Voice and personality › Language. Automatic follows the iPhone's language.

## Limits to keep in mind

- **Three wordings still assume Europe, or English and Polish.** None stops a conversation in another language; each is a one-line change: the prompt says "You speak all European languages" (`voice-agent/instructions.md`, line 8); the opening line falls back to English for a language with no `first_message` in `voice-agent/session.json` (no Chinese, Japanese, Korean, Arabic or Hindi there); the "Hey Doddy" greeting is English or Polish (`WakeGreeting`).
- **Arabic and Hebrew** run right to left. SwiftUI mirrors layouts, but the Pocket Notebook screens and the Doddy art need a design review before either ships.
- **Plurals.** The English source has no `.stringsdict` rules; counts are formatted in code. Languages with several plural forms (Polish already, then Czech, Russian, Arabic…) get the English rule's shape. Fix per string when a native reviewer flags it.
- **Length.** Translations run longer than English (German, Finnish and Polish especially). Screens must let text wrap; that is a design rule already (`BRAND_GUIDELINES.md` 3.8).
- **Don't claim** a language is supported until step 4 has been run on a device and step 5 is recorded.
