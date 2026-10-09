# DECISIONS.md — DODDY V2 decision log with status

Companion to the pack's proposal table `docs/architecture/DECISIONS.md` (left unmodified).
Status values: **Applied in M0 — owner approval pending**, **Not exercised in M0**, **Open**. Nothing here is
owner-approved; the owner marks each `accepted / rejected / needs investigation`. Dates are 2026-10-08.

## Pack ADRs (001–012)

| ADR | Status after M0 | Evidence / notes |
|---|---|---|
| 001 Greenfield repo, old repo read-only | Applied in M0 — approval pending | Work only in `Bienos/doddy.2`; old repo not touched or cloned. |
| 002 iOS 17+, SwiftUI, Swift Concurrency | Applied — approval pending | `project.yml` iOS 17.0, iPhone only, Swift 6 mode. Built and tested on Xcode 27.0 / iOS simulator on 2026-10-08. |
| 003 GRDB/SQLite local-first | Applied in M1 — approval pending | `DoddyPersistence/SQLiteMemoryRepository` (GRDB 7.9.0, migration `v1_memories`, FTS5). Exercised against real SQLite on Linux. |
| 004 Exact original text + immutable provenance | Applied in domain model, unit-tested | `MemoryRecord.rawText` immutable, `correcting(to:at:)` keeps raw text and capture date; 13 tests. |
| 005 Lexical/FTS retrieval first | Applied in M1 | FTS5 prefix-OR query ranked by bm25 then matched-term count; no embeddings. |
| 006 Provider-neutral AI, server-side key proxy | Not exercised in M0 | `AssistantClient` port + `UnavailableAssistantClient`; no provider, no key, no network code (guarded by script). |
| 007 Typed tool schema, confirmation, receipts | Port only | `ToolProposal` → `ToolConfirmation` → `ToolExecutor.execute` → `ActionReceipt`; no executor exists. |
| 008 No account/sync/Postgres | Applied in M0 | None exist; `PrivacyDefaults.m0` all off. |
| 009 Persona separate from safety/data/action policy | Not exercised in M0 | No persona or model in M0. |
| 010 Choose ONE brand ZIP after art QA | **Open — blocks any "final brand" claim** | UI shows only Pocket Notebook candidate tokens and 2 candidate PNGs, labelled "Candidate art — not final". Both v1.3 ZIPs are preserved untouched. |
| 011 Content-free telemetry, separate control | Applied in M0 (no telemetry at all) | Settings states analytics/telemetry "Off (not built)". |
| 012 `reference/` never overrides canonical docs | Applied | `reference/` is outside every build target. |

## Architecture changes and decisions made while implementing M0

| ADR | Decision | Why | Status |
|---|---|---|---|
| 013 | The Xcode project is generated from `project.yml` (XcodeGen); `Doddy.xcodeproj` is **not committed**. | No Xcode here to open/validate a project; hand-writing a pbxproj would be unverifiable. Spec was validated by generating with XcodeGen 2.44.1 on Linux only. | Applied — approval pending; revisit after first Mac build |
| 014 | Domain code lives in a local Swift package `Packages/DoddyCore` (targets `DoddyCore`, `DoddyDesignTokens`) rather than only app folders. **Deviation** from `IOS_ARCHITECTURE.md`'s "folders/modules, no multi-package". | The doc allows splitting "where tests/build benefit": it is the only part that can compile and be tested without a Mac. App code stays in `DoddyApp/`. One package, two targets — not a monorepo. | Applied — approval pending |
| 015 | Swift language mode 6, tools-version 6.0; typed throws in domain validation. | Strict concurrency from the start; package verified on Swift 6.3.3 (Linux) and 6.4 (macOS); app target built in Swift 6 mode on Xcode 27.0. | Applied — approval pending |
| 016 | Text limit counted in **Unicode scalars** (matches JSON Schema `maxLength`); whitespace-only = empty; accepted text stored **exactly** (no trim, no normalisation). | Pack says "5,000 Unicode characters" — ambiguous between scalars and grapheme clusters; schema counts code points. A test pins the difference (family emoji = 7 scalars). | Applied — **owner to confirm** |
| 017 | `MemoryRecord` does not model `deletedAtMs` tombstones; deletion is a purge. Schema keeps the field; a test asserts this is the only difference. | `MEMORY_AND_DATA.md` leaves tombstone policy undefined ("define purge policy"); safest default for erasure. | Applied — **owner to decide before M1** |
| 018 | Design tokens come from the **Pocket Notebook** table in `design/interface-v1.2/docs/DESIGN-SYSTEM.md`, not `assets/brand_candidate/`. Tokens live in pure-Swift `DoddyDesignTokens`, WCAG contrast unit-tested (text roles ≥ 4.5:1 in light and dark; figures match `contrast.json`). | `CANONICAL_DESIGN_DIRECTION.md` precedence rule #5. Bright orange is decoration only. | Applied as **candidate** — approval pending |
| 019 | `@AppStorage`/`UserDefaults` is used **only** for three UI preferences (appearance, hide character artwork, has-seen-First-Hello); never for memories. `PrivacyInfo.xcprivacy` declares reason CA92.1. | Old prototype's `UserDefaults` memory store is the thing to avoid; UI prefs are a different class. | Applied — approval pending |
| 020 | Honesty by construction: `CapabilityCatalog.m0` (every capability "not built"), `Unavailable*` adapters that throw, UI copy derived from the catalog, and `scripts/check_forbidden_capabilities.sh` (no networking/audio/speech/EventKit/account code, no secrets, no permission keys). | Makes "no fake capability" testable instead of a promise. | Applied — approval pending |
| 021 | "Accessibility toggle" is **Hide character artwork** (real effect), not a reduce-motion switch. | M0 has no animation, so a motion toggle would do nothing (a fake). System Reduce Motion stays authoritative later. | Applied — approval pending |
| 022 | No GitHub Actions workflow; checks run via `scripts/ci.sh`. | Hosted macOS runners are billable; M0 forbids paid services without approval. | Open — owner to decide |
| 023 | Dev bundle id `com.bienos.doddy2.dev`, version 0.0.1, no signing team, no app icon. | Production identifier/team/icon are owner decisions; placeholders are clearly development-only. | Open |
| 024 | Imported pack files unmodified; a second checker `scripts/verify_imported_pack.py` was added because `tools/verify_pack.py` rejects any file the V2 repo adds (it also hashes itself, so it was not edited). | Keep provenance intact. | Applied |

## M1 decisions (local memory loop)

| ADR | Decision | Status |
|---|---|---|
| 025 | Owner instruction 2026-10-08: build M1 now, **no unnecessary tests**. M1 adds 2 storage tests only; UI flows are untested beyond the existing smoke tests. | Applied |
| 026 | `MemoryRepository` gains `list(limit:)` and `deleteAll()`; new `MemoryStoreError`. Every write is one transaction plus read-back before success. | Applied |
| 027 | Search indexes a folded copy of `current_text` (`search_text`: case + diacritics folded, plus ł→l, ß→ss, etc.). Query = non-stopword terms as FTS5 prefix terms joined with OR. No typo tolerance beyond prefixes. | Applied — owner may want fuzzier search later |
| 028 | `PRAGMA secure_delete = ON`; delete-all also rebuilds the FTS index. DB in Application Support/Memories with `completeUntilFirstUserAuthentication`; **included in device backups** (disclosed in Settings). | Applied — **owner to confirm backup inclusion** |
| 029 | If the store cannot open, the app switches saving off and shows the error; it never resets or deletes the file. | Applied |
| 030 | Export: JSON (`formatVersion` 1 envelope of schema records) and plain text, both via the share sheet. | Applied |
| 031 | On Linux, package tests need `-Xswiftc -DSQLITE_DISABLE_SNAPSHOT` (Ubuntu SQLite lacks the snapshot API); `ci.sh`/`Makefile` add it automatically. Apple builds unaffected. | Applied |
| 032 | Not built in M1: private/no-history session mode (PRD item 6), content-free telemetry (item 8), conflict highlighting beyond listing all matches. | Open — owner to schedule |

## V1 voice decisions

| ADR | Decision | Status |
|---|---|---|
| 033 | Voice runs on **ElevenLabs Agents** (owner has Creator plan), behind app-side tool handling; provider bake-off vs OpenAI Realtime still recommended | Applied (owner instruction) |
| 034 | Dev agent is **public**; its ID is in `VoiceConfig.swift`. Token server + authenticated agent required before any other user | Applied for dev — **must change before TestFlight** |
| 035 | Agent tools are proposals: search runs locally; save needs an on-screen tap; agent is told saved, declined or failed | Applied |
| 036 | Voice is foreground-only in V1; background listening + Dynamic Island are V3 | Applied |
| 037 | Guard script: no networking of our own, audio and ElevenLabs code only in `Features/Voice`, microphone is the only permission | Applied |
| 058 | Personality settings (humour, reply length, tone, mood) from the persona draft's fixed options, stored as UI preferences in `UserDefaults`, sent to the agent as the fixed-text dynamic variable `doddy_personality`; safety rules are not adjustable. See `docs/product/PERSONALITY_SETTINGS.md` | App applied; **agent prompt change pending owner approval** |

## Decisions the owner must approve before M1 (written at M0; items 6–7 since applied as defaults in M1)

1. **Narrow MVP job** — confirm capture → later retrieval (text) as the first utility, and whether first beta needs real text AI (M2) or can wait.
2. **Visual master** — Pocket Notebook vs Quiet Companion vs hybrid, and which of the two v1.3 brand ZIPs (COMPLETE vs non-COMPLETE) is the character master; human illustrator review of the art.
3. **Artwork rights/provenance** — confirm you may ship the candidate PNGs/SVGs (provenance file says AI-assisted task output, no trademark review), and approve app icon work.
4. **Typography** — system fonts only for now, or license Caveat/other display font (file binaries are deliberately excluded).
5. **Targets** — minimum iOS (17.0 proposed), device matrix (iPhone only proposed), and the Xcode version to standardise on.
6. **Text-length semantics** (ADR-016) and **tombstone vs purge** (ADR-017).
7. **Persistence choice for M1** — approve GRDB/SQLite + FTS5 (ADR-003) and which GRDB release; export formats (JSON + plain text proposed).
8. **Identity & signing** — bundle identifier, Apple developer team, and whether to commit the generated `Doddy.xcodeproj` after a first good Mac build (ADR-013).
9. **CI** — accept local-script CI only, or approve a hosted macOS runner and its cost (ADR-022).
10. **Run the Mac verification** listed in `docs/implementation/M0_REPORT.md` and record results; **M1 should not start until M0's iOS build/tests are confirmed on a Mac** (M0 exit criteria are not met without it).
