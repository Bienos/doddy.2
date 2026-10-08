# Interface system

Proposal for Pocket notebook. The supplied identity board is the visual reference. New interface roles below are explicitly proposed engineering/design tokens, not additional approved brand colors.

## Semantic colors

| Role | Light | Dark | Use |
|---|---|---|---|
| reading ink | #171715 | #FFF7E9 | Body text, headings, primary button background |
| canvas | #FFF7E9 | #171F29 | Warm paper / supplied Night |
| orange cue | #F58A24 | #F58A24 | Short underline, dot, illustration prop; pair with ink if a filled control |
| secondary text | #655F56 | #C5BCAD | Supporting copy and metadata |
| quiet surface | #F5EAD8 | #252E39 | Text input and small useful surfaces |
| separators | #DFD5C6 | #414953 | Decorative boundaries, never sole identification of an interactive control |
| accent text | #A64B00 | #FFB56B | Accessible orange-derived text role; not the bright orange master |
| confirmed | #326746 | #97CEA6 | Text/icon alongside explicit success label |
| error | #A3342E | #FFAAA1 | Clear error text/icon, draft retained |

Computed text contrast values are in `verification/contrast.json`. This does not verify every composited pixel, every illustration detail or native Liquid Glass rendering. Standard text should meet 4.5:1 and large text 3:1. Bright orange on paper is decoration, never ordinary reading text. Separators are low contrast by design; text labels and shape must establish controls independently.

## Type and spacing

Browser study: bundled Inter for reading, Caveat for brief display, both exact original font bytes. Future app: native system text with Dynamic Type for controls/body, supplied Caveat for brief display if licensing/install and scaling are verified. Do not call the browser font a native iOS rendering.

| Role | Browser reference | Native handoff |
|---|---|---|
| Display accent | Caveat 48–56, restrained to 2–3 lines | Scaled custom font; replace with system heading when legibility requires |
| Task heading | Inter 32 / 1.15 | Title style, semantic heading |
| Saved detail | Inter 25 / 1.55 | Scaled body/title; wrap without truncation |
| Body | Inter 15–16 / 1.6 | Body, no fixed maximum height |
| Supporting copy | Inter 12–14 / 1.6 | Footnote/subheadline with contrast |
| Tab label | Inter 10, large-study 13 | System tab item, native sizes |

Horizontal reference margin 25 CSS px, reduced to 20 in the 320 layout. Spacing steps: 4, 8, 12, 16, 24, 32. Primary controls minimum 54 high; tappable icons at least 44 × 44 CSS px in this study. Proposed native targets are points and require actual runtime inspection. Radius 18 for actions, 16–17 for inputs, 15 for source detail; use platform-appropriate native controls rather than reproducing CSS dimensions blindly.

## Component contracts

| Component | States and responsibility |
|---|---|
| CharacterPresence | Receives presentation state only; decorative artwork excluded from duplicate accessibility narration |
| CaptureEditor | Editable draft, validation, pending/read-only, failure preserving text, cancellation |
| SaveReceipt | Only receives committed result; explicit text and icon; one optional short motion |
| MemoryCandidateRow | Literal current text, known source/date, opens exact memory ID; no synthetic confidence score |
| SourceCard | Claim source and route to exact original record; unavailable source must be disclosed |
| MemoryDetail | Current text, immutable original, revision, correction and delete routes |
| MemoryCorrection | Draft remains on failure/conflict; native repository enforces revision precondition |
| PrivacyRow | Clear value/action; toggles expose state; cloud capability requires separate future consent |
| Navigation | Home/Memories/Settings stable; editors may use modal flows with explicit dismissal |

## Layout and accessibility

- Browser studies: 390 × 844, 320 × 750, dark Home, Polish Home, large-text Home. Gallery includes 42 states, including seven guided-setup studies. Prototype review controls combine several variants interactively.
- Large text removes Home character staging and preserves the actions in a scrollable region. The character never clips task text or forces shrinking.
- Keep VoiceOver reading order: screen title → status → editable/task content → primary action → secondary actions. SwiftUI must give headings, toggles, original-capture disclosure and result status proper semantics.
- Do not encode success/error by color alone. Each has text and/or an icon. Test contrast after native compositing.
- Focus indicators exist in the prototype. Native keyboard, Switch Control, VoiceOver and Accessibility Inspector still require testing.
- Polish sample text reflows. This is not a finished localization or proof of natural spoken Polish.
- System Reduce Motion overrides in-app preference in native implementation. The browser obeys `prefers-reduced-motion` even when the demo selector is normal.
- The browser status bar/camera cutout is an illustrative frame, not an Apple asset or a validated safe-area measurement.

## Revision 1.1 components

FirstHello introduces Doddy and gives chat, capability-preview and skip routes. IntroConversation shows one optional question with choice chips and free text. PreferenceReview keeps edits/removal in a draft until explicit approval. PersonalHome receives only approved values and actual operation/draft entries; it never manufactures a task history. PreferenceSettings supports editing and forgetting independently of saved memory deletion. New routes are mainly English; see the onboarding handoff for localization boundaries.

## Revision 1.2 components

First setup uses the unchanged approaching character; voice uses the supplied listening pose. `SetupStepCard` shows the reported page, validated next instruction and repeat/previous controls. `GuideStatus` shows session truth independent of task completion. The expanded Island illustration includes pause/resume, stop and Open steps; compact concept expands for review. Native region fitting, point sizes and accessibility must be tested separately. Written cards, non-Island Lock Screen presentation, microphone denial and unavailable Live Activities remain first-class paths. Setup completion needs a matching invocation plus explicit user confirmation of the physical gesture; an app launch alone is insufficient.
