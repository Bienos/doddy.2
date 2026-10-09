# DODDY character & brand engineering handoff
## Identity (derived from provided v1.3 candidates and Character Bible)
**Doddy — Your mate in your pocket.** Expressive, hand-drawn stick figure with round head, vertical oval eyes, warm asymmetrical smile, black-ink line body and mitten hands, oversized trainers, orange backpack and basketball. Warm paper + ink dark environments, orange motion accents, editorial handwritten display lettering. Character serves usability, never outranks it.

## Brand version collision
Two source ZIPs have names ending in **v1.3** but are materially different. `DODDY_BRAND_SYSTEM_v1.3_COMPLETE.zip` includes 30 expression SVGs and 25 pose SVGs; `DODDY_BRAND_SYSTEM_v1.3.zip` reports 33 and 28. Both note font-based editable wordmark, not final outlined mark; illustration approval and production motion rig pending. Preserve both; sample tokens from non-COMPLETE pack currently under `assets/brand_candidate/`, not an approved master. Owner/illustrator must select one and document master asset IDs before publishing.

## Current candidate tokens (NOT approved app design spec)
`doddy-orange: #FF6A00`, `ink-black: #111115`, `warm-paper: #F8F4EB`, `night-charcoal: #16171C`, `accessible-orange: #A44200`; see JSON file. Orange can be decorative but cannot automatically serve small contrast-critical text. Check exact usage against WCAG/Apple native semantics and contrast. Fonts referenced, NOT included; third-party licenses require verification. Avoid treating GIF demos as production animation rigs.

## Behavioural invariants
Derived from Character Bible v1; not user-research-validated:
- A capable "side-quest fixer" who notices small frictions, responds usefully first and gracefully revises a mistaken theory.
- Funny about small everyday inefficiencies; serious situations get calm factual assistance.
- No sarcasm targeting user, shame, guilt, clinginess, simulated longing, exclusivity or fake human feelings.
- Do not imply access to memory not retrieved or an action not verified; never turn cartoon fiction into product capability evidence.
- User preferences: response length, humour amount, language, voice and reduced animation; user can turn jokes off.

## App implementation contract
Asset catalog: SVG not natively a production universal SwiftUI image source; prepare asset rendering via reviewed supported workflow (e.g. PDF vector assets or appropriate raster scales). Never include copyrighted/unlicensed font files. Static accessible art for M1, character state animation later; use actual runtime state events.

## Source files
Original detailed art direction and guideline PPTX/PDF in `reference/original_archives` ZIPs. Complete persona rules and 64 draft eval cases under `reference/character_evals` and Character Bible ZIP. Before claiming "approved brand", review canonical master, wordmark, exports and mobile accessibility.
