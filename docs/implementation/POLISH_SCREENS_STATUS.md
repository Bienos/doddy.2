# App screens in Polish status (ADR-223)
Date: 2026-10-10. Owner: "do all of them" (item 6).

## What ships
- **Polish when the iPhone is in Polish.** iOS chooses by the iPhone's language. `Config/Doddy-Info.plist` declares `CFBundleLocalizations` en and pl. English stays the source and the fallback.
- **One String Catalog,** `DoddyApp/Resources/Localizable.xcstrings`. It is generated from `l10n/pl.json`, which maps English source text, written as in the Swift code, to Polish. SwiftUI looks the keys up for literal `Text`, `Button`, `Label`, `Toggle`, `Section`, `navigationTitle`, `TextField`, `SecureField`, `Picker`, `DisclosureGroup`, `confirmationDialog`, `Link`, `ShareLink`, `DatePicker` and accessibility labels. `JourneyHeading` (the big screen titles) now looks up its eyebrow, title and subtitle as well.
- **Coverage: 556 of the 598 literal UI strings.** The voice is informal ("Ty"), Doddy is "on", and terms follow iOS's own Polish ("Ustawienia", "ekran blokady", "Przypomnienia", "Mapy Apple").
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
