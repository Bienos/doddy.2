# Doddy — a little less to carry

Interface design review · 8 October 2026 · v1.2

Open **index.html** in a modern browser. No install, account or internet connection is needed. The four studio tabs show the design directions, 42-screen gallery, clickable journey and design system. All character artwork is bundled locally. Font binaries are intentionally omitted in this consolidated package; browser falls back to system fonts; the original PNG screenshots preserve the reviewed typesetting.

**Recommended direction: Pocket notebook.** Warm paper, readable ink, restrained orange, and a character who makes room for the user's task. Quiet companion and Tiny investigation remain alternative visual proposals. None is marked owner-approved or audience-validated.

## Try the new first-use journey

1. Open “Try the journey.” Start with optional Double Back Tap setup. Choose the voice preview or step cards; prepare a personal Open Doddy shortcut, follow the reported Settings steps, then simulate a shortcut receipt and confirm how you triggered it. Pause, stop, collapse or open the illustrated Island. Use the review controls to test microphone denial, unavailable Live Activities and non-Island fallback.
2. Finish or defer setup to reach “Hey. Let’s talk.”
3. Choose the short introduction or ask what Doddy can do. Skip any question; “Review & finish” is always available.
4. Review the drafted preferences. Edit or remove values, then explicitly save them—or continue without saving.
5. Enter the personal Home. It uses only approved information and starts without invented task activity.
6. Prepare a small next step, or save a detail. A draft appears as “Ready for your review”; a confirmed fictional memory write appears as “Saved in demo.”
7. Open Settings → What I know about you to change or forget personalization.
8. Save/find/correct/delete the spare-key example to try the original memory journey.

The side controls still offer dark appearance, larger text, smaller layout and mock write outcomes. Profile edits and the conversation are temporary drafts until approval. Browser reload/reset clears all demo data and returns to first setup. Full native persistence, AI interpretation, voice and automatic personalization are future implementation work.

Read `docs/ONBOARDING-AND-PERSONAL-HOME.md` for the complete flow, fields, activity rules and native handoff proposal. The original three directions and earlier capture-first Home remain reference concepts; the latest first-use/personal Home is the revision 1.2 recommendation.

## Review materials

- `previews/01-pocket-notebook.png`, `02-quiet-companion.png`, `03-tiny-investigation.png`: three comparable concept sheets.
- `previews/04-core-gallery.png`: extended core journey.
- `previews/11-guided-back-tap-setup.png`: first setup, guided Settings and tap-test design.
- `docs/GUIDED-BACK-TAP-AND-VOICE-SETUP.md`: precise steps, platform requirements, sources and device acceptance gates.
- `docs/CLAUDE-GUIDED-SETUP-PROMPT.md`: phased native implementation prompt.
- `previews/10-first-hello-personal-home.png`: new first hello, conversational preferences and personal Home.
- `previews/profile-review.png`: explicit review before saving.
- Other previews: failure, voice, appearance/accessibility, motion storyboard and individual key screens.
- `docs/DESIGN-DECISIONS.md`: rationale, evidence boundaries, sources and tradeoffs.
- `docs/DESIGN-SYSTEM.md`: semantic tokens, component and accessibility requirements.
- `docs/MOTION-AND-STATES.md`: storyboard, authoritative triggers and reduced-motion alternatives.
- `docs/IMPLEMENTATION-NOTES.md`: SwiftUI handoff without app source changes.
- `docs/ASSET-MAP.md` and `docs/asset-provenance.json`: exact original files, hashes, use and gaps.
- `verification/`: actual local browser checks and remaining review items.

## Package integrity

`MANIFEST.json` records every other package file’s size and SHA-256. After extracting the ZIP, run `python3 verification/verify-bundle.py` from this folder to verify completeness and bytes. Browser review scripts require a local static server, Playwright and Chrome; they verify only the scripted design.

## What this proves

This is a **standalone HTML design prototype**, with original supplied character SVGs and licensed fonts. It is not a native SwiftUI redesign. The interactions are fictional: memory writes use temporary page memory; AI replies and voice states are staged; no microphone, AI provider, Apple Reminders, Live Activity, account or cloud service is connected. Export downloads fictional JSON only.

The previously verified app foundation and handoff ZIP were not modified. Bienos/AI-AGENT-DODDY and synced `sources/` were not modified. No repository was created and nothing was deployed.

The character direction is derived from the supplied v1.1 Character Bible, which is a proposal. The visual refinement pack is an overlay/subset of v1.3, not the full brand pack. Later user brand specifications override these proposals. See the asset map for missing base assets and the verification report for native/device/accessibility work still required.

## Optional local preview

If file links are restricted by a browser, serve this folder with a local-only static file server and open its localhost URL. A currently running local preview may be available at http://127.0.0.1:8768/ while this session remains active. This is not an online deployment.

## Setup voice boundary

The Island is a system presentation for a Live Activity, not the audio engine. A native implementation needs an explicitly started audio session, supported background behavior, App Intents and device verification. The guide follows the user’s reported location; it does not silently inspect Settings. Its “listening” indicator here is only a labeled simulation. There is no actual microphone recording, speech reply, Settings navigation or Back Tap detection in this package. See the guided setup document for Apple sources and exact acceptance gates.
