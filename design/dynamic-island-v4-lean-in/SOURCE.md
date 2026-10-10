# Dynamic Island — "Lean In" (board 01 of the owner's V4 island pack)

Source: the owner's Doddy video asset library, imported on branch `claude/friendly-sagan-6odwsl`
(commit `ab23832`, 2026-10-09), folder
`design/video-asset-library-v01/packages/Doddy-Dynamic-Island-v4/`.

Only the files the voice island uses are copied here, byte-identical. Each one's SHA-256 was
checked against the pack's own `SHA256SUMS.txt` when copied (2026-10-10). The rest of the pack
(16 boards, phone references, review sheets, generation sources) stays on that branch.

| File | Used for |
|---|---|
| `01-boards/01-voice.svg` | Lean In board: expanded, compact and minimal, listening and speaking |
| `02-states/voice-{0,1}-{expanded,compact,minimal}.svg` | Exact face, hand, arc, bar and text geometry |
| `02-states/companion-1-compact.svg` | Thinking face (brow up) and the three-dot thinking cue |
| `02-states/calm-pulse-0-minimal.svg` | Calm face (shorter eyes) for connecting, muted and lost |
| `02-states/language-bridge-1-minimal.svg` | Proud face (big smile) for "ended, note saved" |
| `Design-notes.md`, `README.txt` | The pack's own notes and scope statement |

The pack says it is static design mockups: motion, actions and native rendering are not
demonstrated. The native implementation is `DoddyWidgets/DoddyIslandMark.swift` and
`DoddyWidgets/DoddyVoiceLiveActivity.swift` (DECISIONS.md ADR-210).
