# Dynamic Island V4 — the owner's island pack

Source: the owner's Doddy video asset library, imported on branch `claude/friendly-sagan-6odwsl`
(commit `ab23832`, 2026-10-09), folder
`design/video-asset-library-v01/packages/Doddy-Dynamic-Island-v4/`.

Copied here byte-identical (2026-10-10), each file's SHA-256 checked against the pack's own
`SHA256SUMS.txt` (112 of 112 matched):

| Folder | What |
|---|---|
| `01-boards/*.svg` | The 16 boards (the PNG exports are Git LFS files on that branch and are not copied) |
| `02-states/*.svg` | 96 isolated states: 16 boards × 2 scenarios × expanded / compact / minimal |
| `Design-notes.md`, `README.txt` | The pack's own notes and scope statement |

The phone references, review sheets and generation sources stay on that branch.

## How the app uses it

`tools/island_boards/generate_island_art.py` turns `02-states/` into
`Shared/IslandArt/IslandBoardArt.generated.swift`: shapes, colours, stroke widths and Doddy's
face, without text, buttons or the right-hand signs (those are drawn from real state).
`scripts/check_island_art.sh` fails if that file is not exactly what the generator makes, and
checks that every path parses and every state maps to the expected island.

| Board | Used for | Decision |
|---|---|---|
| 01 Lean In, A Orbit, B Ink Ripple, C Negative Space, E Editorial, F Abstract Horizon, 04 Here With You | Voice conversation, chosen in Settings → Voice → Dynamic Island style | ADR-211, ADR-212 |
| G Thought Pocket, J Step Stones, I Reminder Knot | A note, plan or reminder inside a conversation | ADR-213 |
| 02 Tiny Promise, L Calm Tide, K Story Spool | Focus timer, breathing, reading a note aloud | ADR-214, ADR-215, ADR-216 |
| H Language Bridge | Translator mode, once it reaches the default branch | Waiting |
| 03 Pocket Radio, D Kinetic Ribbon, and the focus states of A–F | Music (owner: later); Kinetic Ribbon has no voice state of its own | Not used |

The pack says it is static design mockups: motion, actions and native rendering are not
demonstrated. Nothing here is proof the native island looks like this on a phone.
