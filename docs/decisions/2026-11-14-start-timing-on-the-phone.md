# The Action Button's timing lines are kept on the iPhone and shown in Settings, so they can be read without a Mac

- **Date:** 2026-11-14
- **Decided by:** owner (Pat, 14 Nov 2026). Asked to paste the timing lines from Console.app, they answered "Nie mam maca" to "Masz Maca, czy robić wersję z wyświetlaniem w aplikacji?"; the session read that as asking for the in-app version.
- **Status:** applied in the pull request of branch `claude/optimistic-keller-4r9elt`. Not verified on a device.
- **Replaces:** nothing. Follows `2026-11-13-island-first` (its follow-up, the launch line) and `2026-11-14-first-audible-sound`, which both end with "reading the log needs Console.app on a Mac".

## Why
The three timing lines that say where the seconds of an Action Button press go (`talk start launch`, `talk start timing`, `voice first audible sound after start`) were written only to the device log. That log is read in Console.app, on a Mac with the phone connected. The owner has no Mac, so the numbers the next step depends on could not be read at all.

## Decision
- `StartTimingJournal` (DoddyCore, tested on Linux) keeps the last 18 lines with their time of day. It keeps a line **only** if it starts with one of the three fixed openings, holds nothing but letters, digits, spaces and `. : · ( ) - ,`, and is at most 300 characters. So no address, name, quote or text can be written into it, whoever calls it. A stored value is checked again when it is read.
- `StartTimingStore` (app) holds it as one value in the app's preferences (`PreferenceKey.startTimingJournal`), read and written under a lock because the first-sound line arrives on a background queue. It is listed in `DevicePreferences.erasedKeys`, so "Erase everything on this iPhone" removes it; no code sends it anywhere.
- `TalkInIsland` records the launch and timing lines when the start has ended or handed back, which is after the island is up; the work is a few small preference writes. `AgentVoiceMeter` records the first-sound line where it logs it. The log lines are unchanged.
- Settings › About › Advanced › **Start timing** (`StartTimingView`) lists the lines, pull down to refresh, **Copy** and **Clear**. Copy uses the clipboard the way every copy from Doddy is made (this iPhone only, gone after two minutes, `NoteClipboard`, ADR-724). Clear removes the lines and the page reads them back before it shows empty.
- Polish and English texts; the other languages show English until translated.

## Consequences
- The owner can press the Action Button, open Start timing, copy the lines and paste them to whoever reads them, with no Mac. Only seconds and fixed words are on the page.
- A Home tap writes only the first-sound line (it has no launch or timing line).
- One more preference key, erased with everything else. About 18 short lines, replaced oldest first, so it can't grow.
- This is a measuring aid, not a feature for everyone: it sits under Advanced. It does not change how a start works.
- The privacy policy and the App Store answers are not changed: nothing leaves the phone and nothing about the person is in the lines. This is not a claim that anything is "privacy guaranteed".

## Evidence
- `make test-core` (Linux, Swift 6.1.2): see the pull request for the counts, including the new `StartTimingJournalTests` (an accepted-lines test built from the real `VoiceStartTimeline`, `TalkLaunchTiming` and `VoiceAudibleOnset` outputs, refusal of anything else, the cap, storage round trips, damaged storage, and the erase rule).
- `scripts/ci.sh --only checks`: PASS except "Studio skills: renderers on samples" (NOT RUN: no reportlab or matplotlib here).
- `python3 -I tools/build_strings_catalog.py`: the app catalog regenerated for the new texts, with Polish lines in `l10n/pl.json`.
- Not run: **the app is not compiled** (no Xcode): `StartTimingStore`, `StartTimingView`, the Settings row, `TalkInIsland` and `AgentVoiceMeter` are checked by `swiftc -parse` only; the hosted `ios-build` job is their first compile. Nothing was seen on a device.

## How to read it on a phone
Press the Action Button (once after force-quitting Doddy, once with Doddy in the background). Open Doddy › Settings › About › Advanced › Start timing, pull down to refresh, tap Copy, and paste. The lines read as in `docs/implementation/VOICE_SESSION_STARTS.md`.
