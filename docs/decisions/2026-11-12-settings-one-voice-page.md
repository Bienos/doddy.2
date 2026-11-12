# Settings: one Voice and personality page, Phone calls on the first page, both accounts on About

- **Date:** 2026-11-12
- **Decided by:** owner: "ustawienia wyglądają tak średnio, myślę, że powinieneś ten design trochę zmienić i polepszyć i zrobić to trochę lepiej wszystkim", then "zrób teraz Ustawienia" (12 Nov 2026). The layout below is the implementation's, following the review (`docs/strategy/PRZEGLAD_APLIKACJI_2026-11-12.md`, sections 3 and 4).
- **Status:** accepted; built on branch `claude/settings-one-page`, on top of `claude/peaceful-allen-1mh9uq` (#352, which removed the choice of voice)
- **Replaces:** the layout part of ADR-633 and ADR-727 for the pages named here; keeps `2026-11-11` first-page tiles.

## Why
The review found, in the code:
- Settings › Voice opened a second page for the personality, and both were called "Voice".
- The voice account was a section at the bottom of Voice, and "Your Doddy account" showed twice (About, and the Voice connection row).
- Phone calls was the last row of Notifications, with number verification one more page down.
- The first page's header was a sentence about memory.
- Only the first page had the orange symbol tiles; the pages behind it were plain text rows.

## Decision
- **One page, "Voice and personality" (`settings.voice`).** Its sections, in this order:
  - Auto-start voice, first because it is the one switch most people look for;
  - Speed, Expressiveness and "Starts in";
  - what Doddy calls you;
  - "Opening Doddy": the island, Siri and Back Tap;
  - how he comes across: quick picks, Fine-tune and "Always the same".

  The first-page row shows the personality's summary. Every control keeps its accessibility identifier and preference key; only the row `settings.personality` is gone, because the page it opened is gone.
- **Phone calls is a first-page row** (`settings.calls`), between Connections and Notifications, shown when the build shows phone calls. It left Notifications. Home's ••• › Phone calls is unchanged.
- **Both accounts are in one place, still one page down, on About.** The owner asked on 11 Nov to hide the account more ("schowaj bardziej to usunięcie konta i to, że jesteś zalogowany"), so there is no first-page Account row, which the review had proposed. "Your Doddy account" has the voice account and the connection as its "Voice" section; a build without Doddy accounts shows that section on About itself.
- **Header:** "Set how Doddy sounds, what he remembers and what he can use." The sentence it had ("You choose each saved memory. See the original, edit it or remove it.") is now the footer of Doddy's memory, with its translations.
- **Tiles:** the Notifications and Doddy's memory pages use the first page's `SettingsRow`. Connections, the long pages and the forms are unchanged.
- **One more text fixed:** the voice error that told people to choose "Use Doddy's own voice" (a button `2026-11-12-one-voice` removed) now says to set Speed to Normal, Expressiveness to Natural and Starts in to Automatic, which are the three things still sent. One line in `VoiceSessionController.swift`, far from the hunks open pull requests change. "Settings › Notifications › Phone calls" in the What-leaves-this-iPhone text is now "Settings › Phone calls".

## Consequences
- Fewer levels: Voice and personality is one tap from the first page. The page is longer (about 12 rows plus footers) and is read top to bottom.
- Anyone who knew Phone calls under Notifications finds it on the first page.
- "Starts in" (the conversation's language) and the app language (Settings › Language) are still two settings in two places. They are different things, but the names don't say so; not changed here.
- Nine language tables lost 3 to 4 lines that left the app; Polish got the new ones. The eight drafts show the new header in English.

## Not done
- Connections and the pages behind it are unchanged (their tiles, the long footers, "Connection" jargon).
- No new Settings search and no reordering of rows by use.
- Nothing was compiled or seen on a device: the SwiftUI changes are checked by `swiftc -parse` and by the hosted Mac job.

## Evidence
`make test-core` (Swift 6.1.2, Linux), `scripts/typecheck_app_logic.sh`, `python3 -I tools/build_strings_catalog.py --check`; numbers in the pull request. UI tests that walk Settings (`settings.voice`, `settings.listenOnOpen`, `settings.ways`, `settings.about`, the memory and connection pages) use identifiers that did not change; the screen atlas's two paths that did were updated.
