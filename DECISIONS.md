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

## Trust and behaviour decisions

| ADR | Decision | Status |
|---|---|---|
| 038 | **DODDY AI Constitution V1** (2026-10-10) adopted as the governing behaviour, memory, action, privacy and character spec: `docs/trust/`, `config/doddy_rules.yaml`; mapping and gaps in `docs/trust/REPO_ALIGNMENT.md`. Repo milestones stay the build order; the constitution's "M1–M5" are mapped, not renamed. Its rules are appended to `AGENTS.md` and `CLAUDE.md`; `scripts/verify_imported_pack.py` treats those two files as append-only (imported bytes must remain an exact prefix) | Applied (owner approved option A) — constitution text itself still marked "owner approval pending" in its header |
| 039 | Action statuses follow the constitution (`proposed, drafted, needs_approval, executing, confirmed, failed, unknown, cancelled`); they supersede the reminder state names in `docs/architecture/TOOLS_AND_ACTIONS.md` (pinned pack doc, left unedited) | Applied |
| 040 | Approval is bound by **equality with the full canonical payload** (type, target, every field, exact whitespace) instead of a digest: equivalent in memory, no crypto dependency. Add a digest when approvals are persisted or sent to a server | Applied |
| 041 | Approval lasts **5 minutes** and is **single use**; any edit clears it. `failed` is final; a retry must be a new draft with a new approval | Applied — owner may adjust lifetime |
| 042 | An adapter error or an OK without a provider reference is recorded as **`unknown`**, never success; `unknown` can only be reconciled (status check by idempotency key), never re-executed or cancelled | Applied |
| 043 | `ActionLedger` is **in memory** for the simulation. Durable pending state before the external call is a prerequisite for any real adapter | Superseded by ADR-045 |
| 044 | Approval demo lives in Settings → Actions, runs only on `SimulatedActionAdapter`, labelled as simulation on every state; capability `actionSimulation` in `CapabilityCatalog.v1Trust`. Old `ToolProposal`/`ToolConfirmation`/`ToolExecutor`/`ActionReceipt` ports replaced by `ActionAdapter` + `UnavailableActionAdapter` | Applied |
| 045 | Actions persist in a **separate SQLite file** (`Application Support/Actions/actions.sqlite`, same protection and `secure_delete` as memories, included in backups). The ledger calls `ActionStore` **synchronously inside the actor**, so writes are ordered and nothing interleaves; `executing` is stored before the provider call | Applied |
| 046 | **Approvals are never stored**; after a restart every action needs a new approval tap. `executing` found at launch becomes `unknown` and is only reconciled | Applied |
| 047 | Provider answered but the result couldn't be stored → receipt shows the result, error `resultNotSaved`; the stored `executing` turns into `unknown` after restart and is re-checked | Applied |
| 048 | **Retention:** finished actions (confirmed, failed, cancelled) are deleted 30 days after their last change; unfinished/unknown kept until resolved or deleted. User can delete all history (refused while a send is in flight) | Applied — **owner to confirm 30 days** |
| 049 | Lifecycle rules are repeated as SQLite CHECK constraints and re-checked by `ActionRecord.restore` on load; a damaged store switches actions off, never resets the file | Applied |
| 050 | **Apple Reminders is the first real action** (M4), via `RemindersActionAdapter` in the same ledger. EventKit is behind a `RemindersClient` protocol; the only EventKit code is `DoddyApp/Features/Reminders/EventKitRemindersClient.swift` | Applied (owner instruction) — **device verification pending** |
| 051 | **Second permission:** `NSRemindersFullAccessUsageDescription` (iOS 17 offers no write-only access to reminders). Asked only after an in-app explanation, the first time the user adds a reminder. Guard (supersedes ADR-037 on this point): EventKit only in `Features/Reminders`, no calendar events, permissions = microphone + Reminders full access | Applied |
| 052 | **Verified write:** each reminder carries the idempotency key in its URL and notes; "confirmed" only after finding it again; a failed save is looked up before being called failed; a lookup before writing prevents duplicates; reconcile = lookup only | Applied |
| 053 | Adapters expose `readiness`; the ledger checks it before `executing` and **re-validates the record after the await**. `notReady` leaves the action and its approval untouched (draft kept when access is off) | Applied |
| 054 | Reminder payload = title, due time as ISO 8601 with UTC offset, time-zone ID, list ID; target = list name. Default suggestion tomorrow 09:00 device time, shown and editable; seconds dropped; no past dates | Applied — owner may prefer another default |
| 055 | Entry point is a memory's detail screen only. Not built: voice `create_reminder` tool (changes the live ElevenLabs agent), non-default lists, editing/deleting reminders from Doddy | Applied — **owner to decide on voice tool** |

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
