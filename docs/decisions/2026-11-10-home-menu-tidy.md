# Home's ••• menu loses "Find something", "Following" becomes "On my radar", What I can do gets tiles and points to the Privacy Policy

- **Date:** 2026-11-10
- **Decided by:** owner (Pat, 10 Nov 2026), answering on screen: Find and Notes "Usuń z menu, zostaw w pamięci"; name "Na radarze"; "Co opuszcza tego iPhone'a … powinno być w privacy policy opisane"; "co jest zbudowane, powinno być lepiej … do tych kafelek"
- **Status:** applied in the pull request of branch `claude/fervent-turing-2cd8ae`
- **Replaces:** the "rows" part of `2026-11-09-what-i-can-do`

## Why
The owner went through the menu and found "Find something" unclear, the name "Following" wrong, and What I can do too long: every scene was repeated as a long text row, and "What leaves this iPhone" sat in it.

## Decision
- Home › ••• no longer has "Find something" (`home.find`). Find stays on the notes screen (Settings › Doddy's memory › Notes, `memories.find`) and in a conversation. Notes are not removed: they are Doddy's memory.
- "Following" is called "On my radar" (Polish „Na radarze”) on the menu, the screen title, the activity log and its error line. Icon `dot.radiowaves.left.and.right`. Identifiers unchanged.
- What I can do: the "What's built" rows are two-column tiles (one column at accessibility sizes): name, status chip in words, an arrow where it opens something. VoiceOver reads the row's full text as before; identifiers `capabilities.row.<ability>` unchanged. The "What leaves this iPhone" row is gone from the sheet; the paragraph ends "What I send, and where, is in the Privacy Policy." with a Privacy Policy link under it. The screen stays in Settings › Privacy.
- Focus, timers and stopwatch stay on the menu **for now**: only the stopwatch and the AlarmKit timer can be started by voice. Focus, Wind down and the island countdown need voice tools first (a separate change to `voice-agent/tools.json`, synced to the live agent only on the owner's word); then the submenu goes.

## Consequences
One fewer menu row. Anyone looking for search goes through Doddy's memory or asks Doddy.

## Evidence
Linux, Swift 6.1.2: DoddyCore 2,867 tests, 0 failures; `scripts/ci.sh --only swift,checks` all PASS except the Studio renderer step NOT RUN (reportlab/matplotlib missing); `tools/build_strings_catalog.py --check` PASS. The SwiftUI and UI tests are not compiled here (no Xcode): the hosted Mac job is the first build. Not seen on a device.
