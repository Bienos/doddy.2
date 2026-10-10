# Doddy / Little instruments — complete V4 redesign

Sixteen new compositions, using the original Doddy identity and the V3 mockups as references. The previous packs and synced project files remain unchanged.

## What changed

V3 used a repeated corner-avatar composition with small graphics below the information. The new direction integrates character and action: a dial, pocket, paired dialogue shapes, cream ink silhouette, reminder knot, stepping stones, paper spool and breathing tide. This is a new illustration and layout system rather than another spacing pass.

Doddy keeps his circular cream face, vertical oval eyes, slightly raised right eye, one curved eyebrow and asymmetric mouth. His hands act on the object when useful. Faces in the main action compositions are 30–36pt in diameter; there are no tiny full-body figures. Compact uses a simplified face and state cue. Minimal prioritises the essential number, language, breathing phase or state symbol.

Every expanded view separates activity, primary status, context and next action. Redundant footer copy and repeated reminder times were removed. Paused timers and playback hold the same progress. Processing a task does not pretend that its first step is already ready.

## Three strongest choices

- **Orbit:** strongest base system. The three tick marks and elliptical dial are recognisable at small scale; the countdown remains the primary information.
- **Thought Pocket:** strongest character moment. The little hand and orange thought token make saving feel distinctly Doddy. A completion check emerges inside the pocket.
- **Language Bridge:** clearest action identity. The dialogue forms, language labels and completed crossing explain translation; “Hear it” makes the next move obvious.

Use one action instrument at a time. The cream, black and orange palette, type hierarchy, face construction and shared geometry keep the designs related.

## Rationale for all sixteen

| Direction | Rationale |
| --- | --- |
| 01 / Lean In | The cupped hand and short voice bars show attentive capture; the mouth changes when Doddy speaks. |
| 02 / Tiny Promise | A measured dial holds Doddy close to the countdown. The paused state keeps the same time and progress. |
| 03 / Pocket Radio | Vinyl-like rings and a restrained orange needle make playback identifiable without an album cover. |
| 04 / Here With You | Two small hands and a held conversation loop convey presence. Thinking replaces the active voice cue. |
| A / Orbit | Three quiet ticks give the elliptical dial precision; one orange segment carries focus progress or voice activity. |
| B / Ink Ripple | An organic cream silhouette and an orange energy contour form one speech instrument, rather than a decorative waveform. |
| C / Negative Space | A cream crescent cut from the island supports Doddy’s face and an offered hand. The black surface completes the gesture. |
| D / Kinetic Ribbon | The ribbon wraps the identity and changes from a controlled speech fold to a measured focus loop. |
| E / Editorial | Large tabular numerals and a small character signature let the information do the work. A caret marks active capture. |
| F / Abstract Horizon | Two cream contours form a horizon beneath Doddy. An orange marker indicates the active phase or timer progress. |
| G / Thought Pocket | An orange thought token drops into a cream pocket. The proud face and offered hand turn completion into a Doddy moment. |
| H / Language Bridge | Two dialogue shapes carry EN and FR. The crossing turns orange when the phrase is ready to hear. |
| I / Reminder Knot | A cream reminder tag and a small orange knot connect setup to confirmation. The scheduled time stays primary metadata. |
| J / Step Stones | Three stepping stones encode the plan. The orange first stone identifies the next step; the app contains the full breakdown. |
| K / Story Spool | An open paper spool and an orange word marker give read-aloud its own identity. Pause holds the marker in place. |
| L / Calm Tide | A tide line and phase arc support the literal In/Out labels. The face remains calm as the breathing phase changes. |

## Shared visual system

- Boards: 2560 × 1440 pixels, 88px horizontal margins, identical phone position and two scenario columns.
- One 393 × 852pt screen reference per board at 0.90×, inside the same illustrative frame. All 96 phone SVGs are also provided separately. The wallpaper supplies quiet presentation context; it is not a working app interface.
- Expanded details: 2.25×. Compact/minimal details: 1.80×. These scales are identical across every board. The gallery offers 1× and 2× inspection, where one logical point maps to one CSS pixel. Monitor zoom affects physical size.
- Expanded island: 371 × 156pt, 44pt corner radius, one continuous opaque black surface. Hardware reservation: x122.83, y8, width125.34, height29. No content crosses it; one subdued camera dot is shown.
- Compact: 230 × 36.67pt, with 52.33pt leading/trailing regions and a clear centre. Minimal: 45 × 36.67pt. Minimal phone references show the separate activity bubble beside the hardware pill.
- Character/action instrument sits below the hardware, beside status and context. Editorial intentionally uses a typography-led composition. Main text uses 21pt, timer 32pt, Editorial timer 48pt; context 12.5pt. Arial/Helvetica text and tabular numerals remain editable.
- Buttons have a 34pt visual pill within a proposed 44pt target. Transparent SVG target guides are included. This is a visual specification, not proven native hit testing.
- Palette: cream #F5EFE2, black #080808, orange #EC803F. Secondary island text #BDB7AA; board text #756F63.

Dimensions and camera-clearance decisions were checked against [Apple’s current Live Activities guidance](https://developer.apple.com/design/human-interface-guidelines/live-activities). Device/font/localisation/accessibility behaviour must still be checked after native implementation.

The six A–F core concept boards retain both voice-session and focus-timer examples. The other ten use two lifecycle states. 12:48 represents 51.2% remaining in a 25-minute focus session. All scenario text and timings are representative mock data.

## Motion proposals — not demonstrated

- **Lean In:** Replace the capture bars and mouth only with voice-state updates.
- **Tiny Promise:** Countdown and dial follow actual remaining time. Pause holds both.
- **Pocket Radio:** The orange record segment follows playback progress and holds when paused.
- **Here With You:** Replace the conversation loop with thought points while processing.
- **Orbit:** Dial segment follows progress; voice uses a bounded activity segment.
- **Ink Ripple:** Speech updates change the energy contour. Focus settles it into a quiet curve.
- **Negative Space:** The gesture stays still; the orange state point changes with useful updates.
- **Kinetic Ribbon:** A bounded fold change follows voice-state updates. Focus has a stable measured loop.
- **Editorial:** Numeric content changes stay on a fixed baseline; a caret indicates active capture.
- **Abstract Horizon:** The horizon stays still; only the state/progress marker changes.
- **Thought Pocket:** A short transition tucks the thought token into the pocket and reveals the saved check.
- **Language Bridge:** The crossing completes when the translation becomes ready. Hear it starts narration.
- **Reminder Knot:** The knot settles once when setup completes; the later reminder is a notification.
- **Step Stones:** The active stone changes when a task step is completed.
- **Story Spool:** The orange word marker advances with narration; pause holds its position.
- **Calm Tide:** The tide and phase arc change with the breathing phase; keep explicit In/Out text with reduced motion.

Use bounded transitions following real state changes. Live Activity update animations are limited to two seconds. Avoid decorative continuous loops. Reduced motion retains explicit status, time and phase text. Speech graphics describe a design mapping, not a proven native refresh rate.

Thought capture, translation, reminder setup, task planning and reply drafting are bounded tasks. Their completion should end promptly or open the related app view. The future scheduled reminder should be a notification, not a setup confirmation left running all day.

## Files and proof scope

- `01-boards`: 16 final PNG boards and 16 editable SVG boards.
- `02-states`: 96 isolated editable SVGs: 16 boards × 2 scenarios × 3 presentations.
- `03-phone-reference`: 96 matching editable phone SVGs.
- `04-review`: comparison sheet, all-16 overview, before/after audit, browser preview and the separate raster art-direction exploration.
- `05-source`: original identity copied unchanged, generation sources, the exact image-generation prompt and the V3 scenario source used for the redesign.
- `Gallery.html`: board review plus scenario, presentation and scale selection.
- `Validation.json`: actual static checks. `Packing-check.json` and `SHA256SUMS.txt`: delivery integrity.

The art-direction exploration used the built-in image_gen tool, with the original identity and V3 comparison as references. The exact prompt is in [Image-generation-prompt.md](05-source/Image-generation-prompt.md). That raster explores style; its hardware spacing and focus hierarchy are not the final specification. The final boards are directly editable vector compositions with deterministic PNG exports.

Demonstrated: switching static boards/scenarios/presentations/scales in the local gallery. Proposed: motion, navigation and actions. Not demonstrated: native iOS, actual Dynamic Island rendering, microphone, speech, timers, reminders, translation, music playback or accessibility behaviour. The package contains design mockups, not native app implementation.
