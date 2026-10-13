# Languages: how Doddy's screens are translated

Status 2026-10-13: the app ships **English and Polish**. Nothing else is translated yet. This page says what exists, how a language gets added, and how a person switches. The translation prompt is `TRANSLATION_PROMPT.md` next to this file.

## What exists

- **No library is needed.** The app uses Apple's String Catalogs (`Localizable.xcstrings`, one per target: app, widgets, share extension, Watch, Watch widgets, Mac, Mac widgets). SwiftUI looks up every `Text("…")`, `Button("…")`, `Label`, `Toggle`, `Section` and similar literal in the catalog at run time, so the whole design is covered without touching a screen (ADR-223). Adding a language is adding a column to the catalogs, not changing views.
- **The catalogs are generated, never edited by hand.** `tools/build_strings_catalog.py` reads `l10n/pl.json` (English key → Polish), `l10n/pl_infoplist.json` (permission prompts) and `l10n/pl_shortcuts.json` (Siri phrases) and writes all the catalogs. `--check` runs in CI (`scripts/ci.sh --core-only`) and fails when a catalog is stale, a placeholder differs, or a translated line's English has left the app.
- **Coverage today:** 1,358 of 1,405 UI strings, 8 permission prompts, 26 Siri phrases. The remaining 47 are built at run time (values inside the string, error messages) and stay English in every language until they move to `String(localized:)` (`docs/implementation/POLISH_SCREENS_STATUS.md`). Text sent to the voice agent stays English on purpose.
- **Shipped languages** are listed in `CFBundleLocalizations` in `Config/Doddy-Info.plist` and `Config/DoddyMac-Info.plist` (`en`, `pl`).
- **The voice conversation has its own language setting**, separate from the screens: Settings › Voice and personality offers Automatic plus 25 European languages (`ConversationLanguage` in `Packages/DoddyCore/Sources/DoddyCore/VoiceStyle.swift`). The ElevenLabs agent is configured for 37 languages (English plus 36 presets) and detects the spoken language mid-conversation (`voice-agent/session.json`). Chinese, Japanese, Korean, Arabic and Hindi are not among them.

## How a new language gets in

1. **Translate.** Run `TRANSLATION_PROMPT.md` for the language. It writes `l10n/<code>.json`, `l10n/<code>_infoplist.json` and `l10n/<code>_shortcuts.json` in the same shape as the Polish files.
2. **Generalise the generator** (not done yet; one small change). `tools/build_strings_catalog.py` is hard-coded to Polish: the file names, the `"pl"` column it writes, the Polish-grammar rule that turns "this iPhone" into "this iPad" (`ipad_polish`), and the CI message. It should read every `l10n/<code>.json`, write one column per language, apply a plain iPhone→iPad swap for languages without a grammar rule, and add each code to `CFBundleLocalizations`. One ADR records the decision.
3. **Build the catalogs:** `python3 -I tools/build_strings_catalog.py`, then `--check`. Commit the regenerated `.xcstrings`.
4. **See it on a device** (needs a Mac): build, run with `-AppleLanguages (<code>)` or set the language in iOS Settings, and check Home, capture, Settings and the voice screen at default and AX5 Dynamic Type, light and dark, for truncation. `DoddyUITests/PolishSmokeTests.swift` is the pattern for a smoke test per language.
5. **Native review before release.** ADR-234 applies to every language: machine translation is a draft; the privacy texts and the AI disclosure are reviewed first.

Until step 2 is done, a translated file is a draft on disk, not a language the app shows.

## How a person switches language

- **Screens:** iOS does this. Once the app ships more than one language, iOS Settings › Doddy shows a **Language** row (iOS 13 and later) and the app relaunches in that language. The app can add a "Change language" row in its own Settings that opens that page (`UIApplication.openSettingsURLString`). There is no in-app picker that bypasses iOS: Apple's guidance is the Settings row, and a bypass would need every string looked up through a custom bundle.
- **Voice:** already there, Settings › Voice and personality › Language. Automatic follows the iPhone's language.

## Limits to keep in mind

- **Chinese, Japanese, Korean** screens work in SwiftUI without special handling, but the voice agent and `ConversationLanguage` do not know them; adding them means the owner changes the live ElevenLabs agent and DoddyCore gets new cases.
- **Arabic and Hebrew** run right to left. SwiftUI mirrors layouts, but the Pocket Notebook screens and the Doddy art need a design review before either ships.
- **Plurals.** The English source has no `.stringsdict` rules; counts are formatted in code. Languages with several plural forms (Polish already, then Czech, Russian, Arabic…) get the English rule's shape. Fix per string when a native reviewer flags it.
- **Length.** Translations run longer than English (German, Finnish and Polish especially). Screens must let text wrap; that is a design rule already (`BRAND_GUIDELINES.md` 3.8).
- **Don't claim** a language is supported until step 4 has been run on a device and step 5 is recorded.
