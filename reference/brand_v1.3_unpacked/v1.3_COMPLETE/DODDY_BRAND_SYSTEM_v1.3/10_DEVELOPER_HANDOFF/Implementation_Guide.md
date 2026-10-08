# Doddy iOS Brand Handoff

Assets: Use `03_CHARACTER` SVG masters for vector adaptation and exported PNGs for immediate SwiftUI image assets. Use app icon PNG 1024×1024, **opaque** and square; do not pre-mask rounded corners for the App Store.

Design tokens: `Design_Tokens/doddy.tokens.json`; semantic colors: `brandPrimary=#FF7A00`, `textPrimary=#0B0B0B` on paper, `background=#F7F2E9`, `surfaceDark=#151515`, `textOnDark=#F7F2E9`. Assess contrast for small orange body text against cream—it is an accent, not the default body text.

Naming: `Doddy_<category>_<variant>_<theme>_<size>`. Keep case stable. Export `@2x/@3x` bitmaps or PDF vectors as needed. No unapproved SVG runtime assumption.

SwiftUI concept: `Image("Doddy_avatar_happy")` accompanied by accessible spoken label, visual state text; `@Environment(\.accessibilityReduceMotion)` to switch to fades; `withAnimation(.easeOut(duration:0.26)) { state = ... }`. This is a styling sketch, not a production-tested Swift implementation.

Do not claim: permanent system-level presence, automatic Back Tap configuration, action completion before permission/confirmation, or background access to private screen content.

Illustration master export note: the character vectors are editable, but the deck embeds raster previews for portability; designers should update illustration at the SVG source first.
