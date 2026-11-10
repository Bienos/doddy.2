# The small island draws Doddy's voice as Home's fine lines again, not seven call-style bars

- **Date:** 2026-11-10
- **Decided by:** owner (Pat, 10 Nov 2026): "chciałbym, żebyś wrócił do starszego designu tych kresek, niż teraz to są teraz, bo są gorsze … wtedy było lepiej"
- **Status:** applied in the pull request of branch `claude/fervent-turing-2cd8ae`
- **Replaces:** the "Waves" bullet of `2026-11-09-small-island-call-bars`. The rest of that decision (Action Button, Back Tap and Siri start on Home; the smiling face; island expansion off by default) stays.

## Why
The seven round bars of 9 Nov looked worse to the owner than the fine lines they replaced.

## Decision
The compact Live Activity island's right side is again ADR-683 option C: 21 fine lines in 48 × 26 pt, 1.35 pt wide, each fading out at both ends, orange → amber → rose, highest in the middle. Same envelope and beat shapes as before #284 (`IslandScene.aurora`, `IslandAuroraView`). Nothing else changes.

## Consequences
None beyond the look. The beat, its privacy (a 0–4 loudness step of Doddy's own voice) and the update rate are unchanged.

## Evidence
The two files are byte-for-byte the pre-#284 drawing code for the lines (checked with `git diff d1eec13~1`). Not compiled here: no Xcode or `swiftc` in the session; `scripts/check_island_art.sh` and `IslandScreenshotTests` run in the hosted Mac job.
