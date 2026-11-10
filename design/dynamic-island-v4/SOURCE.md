# Dynamic Island V4 — the owner's island pack

Source: the owner's Doddy video asset library, imported on branch `claude/friendly-sagan-6odwsl`
(commit `ab23832`, 2026-10-09), folder
`design/video-asset-library-v01/packages/Doddy-Dynamic-Island-v4/`.

Copied here byte-identical (2026-10-10), each file's SHA-256 checked against the pack's own
`SHA256SUMS.txt` (112 of 112 matched). **Trimmed on 2026-10-27 (owner: "1 yes", ADR-653):** the eight
boards the app no longer draws were deleted, so this folder is not the whole pack any more; the
files that remain are still byte-identical to it. Deleted: the seven voice looks (Lean In stays,
as the board behind Whole Doddy; Orbit, Ink Ripple, Negative Space, Editorial, Abstract Horizon and
Here With You went) and the two boards that were never used (Pocket Radio, Kinetic Ribbon). The
full pack is in git history (`git log --diff-filter=D -- design/dynamic-island-v4`). **Trimmed again
on 2026-11-09** (owner: "ok recommended", decision `docs/decisions/2026-11-09-remove-old-design-leftovers.md`):
L Calm Tide went with the breathing exercise (ADR-550).

| Folder | What |
|---|---|
| `01-boards/*.svg` | The 7 boards the app still draws (the PNG exports are Git LFS files on that branch and are not copied) |
| `02-states/*.svg` | 42 isolated states: 7 boards × 2 scenarios × expanded / compact / minimal |
| `Design-notes.md`, `README.txt` | The pack's own notes and scope statement, still describing all sixteen boards |

The phone references, review sheets and generation sources stay on that branch.

## How the app uses it

`tools/island_boards/generate_island_art.py` turns `02-states/` into
`Shared/IslandArt/IslandBoardArt.generated.swift`: shapes, colours, stroke widths and Doddy's
face, without text, buttons or the right-hand signs (those are drawn from real state).
`scripts/check_island_art.sh` fails if that file is not exactly what the generator makes, and
checks that every path parses and every state maps to the expected island.

| Board | Used for | Decision |
|---|---|---|
| 01 Lean In | Backs Whole Doddy's signs and sizes; the only voice look (the picker is gone) | ADR-238, 264, 653 |
| G Thought Pocket, J Step Stones, I Reminder Knot | A note, plan or reminder inside a conversation | ADR-240 |
| 02 Tiny Promise, K Story Spool | Focus timer and stopwatch, reading a note aloud | ADR-241, 243, 652 |
| H Language Bridge | Translator mode | ADR-244, 619 |

The pack says it is static design mockups: motion, actions and native rendering are not
demonstrated. Nothing here is proof the native island looks like this on a phone.
