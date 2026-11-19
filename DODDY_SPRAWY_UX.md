# Sprawy: durable work and documents

## Evidence status

**VERIFIED/source:** `Features/Errands/ErrandsView.swift`, `ErrandsModel.swift`, `StoredErrand`, call-case list/detail/result models, generated-file sharing and message-result bridges were inspected. Backend/serialization tests exercise persistence and result delivery.

**NOT YET VERIFIED:** native screenshots, navigation on a device, VoiceOver order, Dynamic Type clipping, export picker behavior, motion and the installed production build. There is no iOS Simulator/Xcode in this Linux environment. This document is a source-grounded flow assessment and design specification; it does not claim a completed screenshot-based product audit.

## Current journey

| Step | Source-backed behavior | Status and issue |
| --- | --- | --- |
| Start work in voice | Typed request routed through permissions and feature-specific handlers | Exact research/inquiry scopes gain a direct-request path; actual native voice integration still needs a build/device test |
| Leave the conversation | Approved errands/call tasks belong to server records | Backend persistence is exercised; actual suspension/notification experience is not device-verified |
| Return to Sprawy | Errands are adopted/refreshed and saved locally; call cases have a separate workspace | Durable feature records exist, but there is no universal cross-feature task index |
| See progress | Broad states existed; this change adds persisted real stages and bounded history | No percentages or synthetic “comparing 12 products”; shopping adapters currently have coarser start/finish progress |
| Read a call outcome | A short answer/quote/confidence card existed | New structured evidence report can be opened independently as a native document |
| Save/share | Existing files have their own handling; call text was primarily a card | Added native Markdown file export; PDF/DOCX and a universal report library remain future work |
| Stop/recover | Cancel, failed/unknown states, server refresh and deletion receipts exist | A stale stage must never override failed/cancelled state; unknown work must not be silently submitted again |

## Implemented changes

- `StoredErrand.progress` retains the server's stage/history across local serialization and app restarts. The list/detail view can display it while a task is running. Terminal state overrides older active-stage text.
- `CallResultCard.report` preserves the evidence report with the call record. `CallReportReader` exposes a focused native reader and file export entry point from the existing result card.
- Reports are data-driven: only populated findings appear, with verbatim evidence and uncertainty. Unsupported details are excluded and the user is told when review is needed.

Core parsing/rendering/persistence is tested. Native screens and system file export are source changes, **not compiled** here. Do not describe the screenshots, accessibility or device behavior as verified.

## Proposed unified Sprawa

Use a durable projection over existing feature records before replacing their storage. A Sprawa needs: stable ID and account; title; user's objective; originating request/conversation reference; feature-owned task reference; state and last verified event; immutable authorization reference; generated artifact versions; provider references/receipts; open questions; suggested next action; cancellation/revocation status; retention/deletion state.

The task owns work and artifacts; Messages is one delivery surface. A report remains readable from its task without finding the original chat. Separate “a call ended”, “the question was answered” and “the user's objective was completed”. Do not collapse all three into a green Completed badge.

Suggested list: active work first, then needs-attention, then recent results. Each row shows title, meaningful state and last real update. Detail shows objective, outcome/what remains, results, activity and Stop/Cancel where supported. The existing Ink/Cream/Orange/Paper theme should remain the foundation; avoid adding a second design system.

## Content and artifact policy

- A short lookup stays a short answer/receipt. Do not generate a file for a trivial fact.
- A comparison/research task or substantive call gets a canonical structured report with source references and Markdown representation.
- Native reading is immediate. Export formats are views of the same canonical artifact, not independent model generations.
- A rerun makes a new immutable version with generated-at time, parent version and changed evidence. A user-edited copy is labeled user-edited and does not overwrite provider evidence.
- Link a report to task, relevant conversation and provider record without exposing another account's identifiers. Search is account-scoped; private/local memory remains governed by its own consent.
- Retention/export/deletion must cover the canonical artifact and every derived copy. User-selected exported files are outside server deletion control and must be described accurately.

## Accessibility and interaction acceptance

Required device checks: VoiceOver reads title/state/actions in order; state has words, not color alone; large text wraps without hiding Cancel or evidence; reduced motion suppresses decorative animation; loading/error/empty/report-partial states have recovery text; report quotations are selectable; export failure/cancellation is clear; lock/sign-out prevents sensitive content access; returning from an Activity opens the correct account's task. These are acceptance criteria, not screenshot findings.

## Live Activity design

Compact: one truthful state and the character/mark. Expanded: task title, real current stage, last update, Open and Stop when supported. Completion appears only from a stored result/provider event. No fake progress percentage, looping “success” pose while failed, or promise of unlimited background execution. Server-driven ActivityKit integration and hardware validation remain prerequisites, as detailed in [background architecture](DODDY_BACKGROUND_ARCHITECTURE.md).
