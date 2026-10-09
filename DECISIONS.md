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

## Connections proposal (research 2026-10-09 — nothing built)

Source: `docs/research/CONNECTIONS_AND_PROACTIVE_DODDY_2026-10.md` (calendar/Google/MCP connections, iPhone actions, nudges by notification/Telegram/WhatsApp, news watch notes). All rows are **Open** until the owner answers §5 of that document.

| ADR | Proposal | Status |
|---|---|---|
| 038 | Layer order: on-phone connections (EventKit, Contacts, AlarmKit, Shortcuts) before accounts/MCP before a Watcher backend; a user who connects nothing keeps the M1 local app unchanged | Decided 2026-10-09: first slice V4a = Calendar + Reminders + Contacts, Today card, local event nudges |
| 039 | A connection shows "Connected" only after a verified read; reads auto once connected, every write/send goes through the existing proposal → confirmation card → verified receipt path | Accepted 2026-10-09 |
| 040 | Proactive nudges come only from explicit **watch notes** (a memory type with provenance) or confirmed event nudges; never from inferred interests. Every nudge carries evidence, a link and "Stop watching" | Accepted 2026-10-09 |
| 041 | Primary reach channel = push notification in Apple's message style (Doddy as sender) + in-app Nudge inbox; Telegram as first opt-in external channel; WhatsApp/calls later; iMessage cannot be sent by the app and is offered only as a user-built Shortcuts recipe | Changed 2026-10-09: notifications first, then **WhatsApp** (owner has a Meta Business account and number); Telegram not planned |
| 042 | One small gateway (the voice token server already required) also hosts APNs sending, the Watcher scheduler, delivery channels and, later, an OAuth broker and a per-user MCP server for the ElevenLabs agent (`require_approval_per_tool`, per-conversation token header) | Accepted 2026-10-09 with gateway on **Render, EU region**; the per-user MCP server part is deferred (ADR-047) |
| 043 | Google Calendar is read through EventKit when it is already synced to the iPhone; Google OAuth (sensitive scopes) only when an account feature needs it; Gmail read (restricted scope, CASA audit) is out of scope for now | Accepted 2026-10-09: Google Calendar via iPhone Calendar sync (EventKit); no Google OAuth |
| 044 | Default nudge policy: 3 per day, quiet hours 22:00–07:30 local, 90-day server retention of nudge history, urgent cadence only for notes the user marked urgent | Default applied (owner not asked separately); change any time |
| 045 | Calendar connection asks for **full access** by default (Today card + read-back verification), explained by a privacy card first | Decided 2026-10-09 |
| 046 | News Watcher: **Exa search** + provider-neutral relevance judgement against the watch-note text, hard cap **20 EUR/month** | Decided 2026-10-09 |
| 047 | "Bring your own MCP server" is **skipped for now**; revisit after V4a–V4c ship | Decided 2026-10-09 |
| 048 | Phone-call nudges (ElevenLabs outbound) out of scope | Default applied; owner may reopen |

## V4a decisions (Connections on this iPhone, built 2026-10-09)

| ADR | Decision | Status |
|---|---|---|
| 049 | Connections live in DoddyCore as pure types. `ConnectionState.status` is derived: "Connected" needs the in-app switch, a reading permission and a successful read in this refresh; it is never stored | Applied |
| 050 | EventKit, Contacts and UserNotifications only under `DoddyApp/Features/Connections/` (guard enforced). Permission strings in `Config/Doddy-Info.plist`, merged with the generated plist, because the `INFOPLIST_KEY_` names of the iOS 17 EventKit keys could not be confirmed without Xcode | Applied — **check on first Mac build** |
| 051 | The per-connection in-app switch is a UI preference in UserDefaults (`connection.<kind>.enabled`), like ADR-019; no calendar, reminder or contact data is stored by Doddy | Applied |
| 052 | Voice: `read_calendar` and `lookup_contact` run without a card once connected; `create_calendar_event` and `create_reminder` always show a card and write after the tap; one card at a time; contacts → names only to the agent | Applied |
| 053 | A write is "added" only after the item is read back by identifier; a failed read-back is `unknown` (user told to check before retrying), never retried automatically | Applied |
| 054 | Nudges are local `UNCalendarNotificationTrigger` requests, id = event + lead time (idempotent), leads 10/30/60 min for today's timed events, verified against the pending list; a moved event is flagged, not auto-rescheduled; banner shown in the foreground | Applied |
| 055 | Catalog `.v4aConnections` in the live app; privacy manifest adds Contacts (names sent to ElevenLabs during voice lookups, not linked, app functionality) | Applied — review with the privacy notice |
| 056 | UI smoke test corrected: since V1 the Settings microphone row says "Only while talking", not "Not used" | Applied |
| 057 | ElevenLabs dev agent: 4 client tools added and prompt updated (version `agtvrsn_2101m4f2ypb4ehnanva5da8pjcte`; rollback `agtvrsn_2701m4f1e2krfnysbc5w01agz5d2`) | Applied (dev agent only) |

