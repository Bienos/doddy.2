# SwiftUI integration handoff — no app source changes in this study

Use the NEW repository workflow from the development handoff only after a separate implementation request. Do not copy this browser prototype over the native starter. The verified starter and original repository were kept untouched.

## Proposed integration order

1. Record owner-selected direction and any amendments to Character Bible/visual rules. Keep later guidelines authoritative.
2. Define semantic color/type/spacing tokens. Add supplied approved assets with provenance and licenses. Validate native asset import; browser SVG support does not imply direct SwiftUI SVG support. Use approved raster variants/PDF vectors or a reviewed conversion workflow.
3. Replace neutral Home/Memories/Settings presentation while preserving current local-memory behavior and tests. Root state and injected services stay at the app boundary.
4. Make reusable components: `DoddyPresence`, `CaptureEditor`, `MemoryCandidateRow`, `SourceCard`, `MemoryDetail`, `OperationStatus` and `PrivacySettingsRow`. Names are proposals, not existing code.
5. Bind capture/correction success to actual repository commit. Keep failures and unknown outcomes distinct. Preserve drafts on errors, immutable originals and revision enforcement.
6. Verify light/dark, smaller layouts, Dynamic Type, contrast, VoiceOver, keyboard/Switch Control and Reduce Motion. On large text, hide decorative character staging before compromising reading space.
7. Only later connect the separately scoped gateway/voice/reminder/system phases. Do not activate those from a visual design milestone.

## Ownership and navigation

- Root owns selected tab, storage model and injected services. Preserve tab history rather than recreating models each switch.
- Feature views own field drafts and local route selection. Use immutable identifiers in detail routes.
- `MemoryModel` publishes pending/committed/error state based on actual repository operations, not timing.
- Conversation coordinator owns session/turn IDs, request/audio handles and cancellation. It passes presentation-only state to character components.
- Character view reads state. It has no database, microphone, network or action authority.
- Use native sheets for explicit editing and clear close/cancel actions. Preserve user input across transient failures. Do not dismiss on failed commit.
- Native export should invalidate prepared copies on edits/deletes and use a user-initiated share flow. The prototype JSON downloader is not a replacement.

## Review gates

Selected visuals do not prove microphone, AI, Back Tap, reminders or Live Activities. Native build, simulator tests and physical-device tests must be reported separately. Do not migrate old user data or modify Bienos/AI-AGENT-DODDY as part of this design integration.

Require an actual native layout review, physical-phone accessibility pass and observed usability sessions before making claims about ease of use. Test whether a person can save, find and correct a detail without assistance; count misunderstandings about what is remembered or sent externally, rather than measuring mascot enjoyment as task success.

## Revision 1.2 setup handoff

Insert optional guided setup before the first introduction when a native implementation is authorized. Read GUIDED-BACK-TAP-AND-VOICE-SETUP.md and use CLAUDE-GUIDED-SETUP-PROMPT.md after the safe new-repository bootstrap. They specify the foreground entry point, audio/Live Activity boundaries, device gates and staged implementation. This revision modifies only this browser design bundle, not the native starter.
