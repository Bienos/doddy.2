# Doddy design-to-development handoff (v1.3)

## Asset priority

- For 24-64px: use `doddy_face_mark.svg` or app icon, not full-body illustration.
- For hero/empty states: use `doddy_master_front.svg` or relevant pose.
- For scalable imagery in iOS: convert the standalone SVG source to suitable single-scale PDF vector assets or authored SwiftUI paths, then use appropriate asset catalogs. SVG support is not equivalent to native SwiftUI Shape.
- The logo source uses Lobster Two lettering rendered as SVG text and thus depends on font availability in editing/rendering software. Convert the wordmark to verified outlines before shipping as a final trademark asset.
- UI animation: state-driven transitions; do not use looping assistant speech/listening glyphs when microphone permissions are absent.

## UIKit/SwiftUI

Use SF symbols for standard UI controls, not custom icons that reduce accessibility. Use `accessibilityLabel` and `accessibilityReduceMotion`; expose state change announcements. Do not claim always-on microphone, permanent Dynamic Island presence or automated Back Tap configuration.

## Interaction boundaries

A spoken instruction understood by Doddy is not proof a tool action completed. Render confirmed success only following a confirmed tool response. For memory save and permissions, show consent and data controls.
