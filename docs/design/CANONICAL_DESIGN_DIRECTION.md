# Visual implementation decision record

## Owner-selected local memory interface — 10 October 2026

The owner requested more mockups while keeping the cream/ink/orange design, then
explicitly requested “build”. For this local native memory slice, the current visual
reference is `doddy-memory-journey-mockups.html` in the task's visualization directory.
Character art is only from `DODDY-Numbered-Video-Assets-v01.zip`: cross-legged, listening,
kneeling inspection, fist-pump and shush poses. These are new `UploadedDoddy_*` image
sets; historical assets, archives and the development app icon are preserved.

This selection supersedes the older working-reference appearance below for Home,
capture, save receipt, browse/find, provenance/edit/delete and the privacy summary.
It is not a commercial brand-rights clearance or approval for broader features. No
mockup sample notes or simulated Listening/Island images are installed as real behaviour.
Existing voice, shortcuts and native Island code remain separate, unverified-on-device
workstreams. See `docs/implementation/MEMORY_JOURNEY_REPORT.md` for executed evidence.

## Previous working candidate (preserved reference)

**Working UI master:** DODDY Interface v1.2 → **Pocket Notebook**; 42-screen browser prototype.  
**Main comparison:** `VISUAL_REVIEW/00_COMPARE_3_DESIGNS.jpg`; expanded main views in `VISUAL_REVIEW/`.

## Current assets and relative priority

1. **Owner-approved future brand guidelines** override this plan after explicit review.
2. Until then, **design/interface-v1.2/docs/DESIGN-SYSTEM.md**, **ONBOARDING-AND-PERSONAL-HOME.md**, **MOTION-AND-STATES.md**, **GUIDED-BACK-TAP-AND-VOICE-SETUP.md** and PNG previews are the *visual reference*, not production code.
3. **design/interface-v1.2/assets/** contains the matching source SVGs; **design/ios-ready-asset-catalog/** contains generated PNG export candidates for SwiftUI. Confirm right-to-use/provenance and visual fidelity.
4. `docs/design/BRAND_AND_CHARACTER.md`, `reference/character_evals/` and v1.3 original ZIPs establish character/behaviour reference, but two v1.3 asset archives disagree; final commercial asset set unresolved.
5. `assets/brand_candidate/` is historical; do **not** mix its colors with design v1.2 tokens automatically.

## Use this appearance

- Warm paper base (#FFF7E9), near-black reading ink (#171715), restrained highlight orange (#F58A24).
- Calm and editorial UI; handwritten accents for short title/wordmark only, readable native system typography for instructions and detailed data.
- Dark palette, text scale and semantic/error states per design system, not pixel-locked copies of web mockups.
- 3 primary tabs: **Home / Memories / Settings**; save/recall action available promptly. Opening a live assistant may be in the Home experience but requires a real AI milestone.
- Character is visually recognizable but reduces or disappears behind long messages, source detail, reading and accessibility.
- Use the approved captured-source/edit/delete receipt model; no invented personal facts, fake saved memory, auto profile creation or phantom progress.

## Three options and recommendation

| Option | Status | Use |
|---|---|---|
| Pocket Notebook | PROPOSED WORKING UI | Build native first-pass Home, capture, recall, settings and error states |
| Quiet Companion | REFERENCE | Lighter, expressive voice/companion mode and friendly first greeting |
| Tiny Investigation | REFERENCE | Source and provenance detail; do not turn retrieval into a mandatory investigative game |

## Sequence and version precedence

- `design/interface-v1.2` is a *newer design handoff*, not a claim it was natively implemented.
- v1.1 **First Hello → Optional Conversation → Review → Personal Home** supersedes earlier onboarding visual proposals.
- v1.2 **Guided Back Tap setup** is *optional*, skippable and deliberately deferred from M0/M1 implementation. There must always be a usable text-first route. Build after real invocation and foreground voice prerequisites, if requested.
- Text memory loop remains first buildable utility from technical M1; broad character/voice/agent features are future layers.
- For M0 use a small **static native Pocket Notebook shell**. Do not pretend a native assistant/chat or voice works.

## Design approval requests before polished production

1. Choose Pocket Notebook, Quiet Companion or a new hybrid as final master.
2. Select final v1.3 character drawings / complete brand master; approve logo/icon treatments.
3. Decide whether first beta emphasizes reliable memory, character-led general conversation or follow-through. Current engineering order implements local trust first, not a validated market decision.
4. Approve final typography acquisition/licensing, localization language priorities, and motion work.
5. Confirm precise starting Xcode/iOS target, devices and realistic Dynamic Island/Back Tap feature needs.

The agent may build **reversible, non-publishing M0 scaffolding** with the working reference; owner approval is required before freezing/selling a production visual identity.
