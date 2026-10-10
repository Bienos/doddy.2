# Provider capability matrix

Date: 2026-10-09. One row per **operation**, never per provider: a provider row does not imply its other operations
are available. Two independent columns: **capability classification** (what current official evidence says the
provider supports) and **implementation status** (what Doddy has built and how it was tested).

Capability classification: **Verified** (current official evidence supports the exactly scoped capability; says
nothing about Doddy) · **Plausible** (feasible, exact support/access unverified) · **Restricted** (documented
scope/account/verification/quota/licensing constraint — named) · **Partner-only** (needs a documented contract,
licence or partnership) · **Unknown/unsupported** (evidence missing, or evidence rules it out — says which).

Implementation status: planned · implemented · mock-tested · native-build-tested · simulator-tested · device-tested ·
live-provider-tested · blocked.

| Operation | Provider / path | User value | R/W | Permissions / scopes | Capability classification | Constraints | Evidence (checked) | Implementation status (date, evidence) | Priority | Next validation gate |
|---|---|---|---|---|---|---|---|---|---|---|
| Save an explicit note | Local SQLite (GRDB/FTS5) | Capture | W (local) | None (on-device) | Verified (own code) | Data stays on device; included in device backups (ADR-028) | Repo code | implemented, simulator-tested 2026-10-08 (M1_STATUS.md) | P0 | Device test (Data Protection, backups) |
| Recall saved notes | Local SQLite FTS5 | Recall | R (local) | None | Verified (own code) | Lexical only, no embeddings | Repo code | implemented, simulator-tested 2026-10-08 | P0 | Device test |
| Save a calendar event as a memory (explicit tap) | Local SQLite via app | Capture from calendar | W (local) | None | Verified (own code) | Only on explicit tap; text names the source | Repo code | implemented (app code, **not compiled**); core text builder unit-tested 2026-10-09 | P1 | First Mac build + simulator |
| <a id="google-calendar"></a>List events for one local day, primary calendar | Composio `GOOGLECALENDAR_EVENTS_LIST` | "Tomorrow's events" | R | `calendar.events.readonly` requested; read/identity allowlist enforced | Verified (tool schema E2; scope E8) | **Restricted:** managed OAuth app = Composio's consent screen and shared allowance (20K managed calls on Hobby); public apps may need Google verification; Google "Testing" mode limits testers | E2, E3, E7, E8 (2026-10-09) | implemented, mock-tested 2026-10-09; adapter exercised with fake SDK client; **live-provider: blocked** (no credentials/consent) | P0 | Owner's live check (`npm run live-check`) with read-only auth config |
| Connect one Google account (hosted link) | Composio `connectedAccounts.link` | Consent | — | Auth config scopes | Verified (SDK E1) | Managed vs custom auth config; `initiate()` retired for managed OAuth | E1, E4 | implemented, mock-tested; **live: blocked** | P0 | Live connect with owner's account |
| Bind completion to the signed-in user (callback verifier) | Composio `connectedAccounts.completeAuth` | Prevents link-forwarding account hijack | — | Project setting | **Plausible** (SDK declares it; production doc page 404) | Availability per plan unknown | E1, E6 | implemented (verifier mode), tested with fake; **live: blocked** | P0 | Confirm with Composio; enable in dev project |
| Verify granted scopes | Composio connected-account `state.val.scope` | Proves read-only | — | — | Plausible (field in SDK schema; live presence unverified) | If absent, live reads stay blocked | E1 | implemented; mock-tested | P0 | Live connect: inspect verdict |
| Disconnect (revoke + delete) | Composio `revoke`, `delete` | User control | — | — | Verified (SDK E1); revoke "best effort", may be unsupported per toolkit | Failed remote cleanup is reported, not hidden | E1 | implemented, mock-tested incl. failure path; **live: blocked** | P0 | Live disconnect; check Google Account › third-party access |
| Create / update / delete events | Composio Google Calendar write tools | Follow-through | W | `calendar.events` (write) | Not assessed | Requires confirmation design; out of scope | — | **planned only** — disabled in registry, no handler; confirmation foundation tested with a synthetic non-executing capability | P3 | New milestone approval |
| List all calendars / multi-account | Composio | Broader view | R | `calendar.readonly` / multiple connections | Not assessed | Out of scope | — | not planned now | P3 | Demand evidence |
| Read Apple Calendar events | Native EventKit | Calendar without Google | R | iOS full calendar access (no read-only grant) | Unknown — Apple page not fetchable 2026-10-09; prior knowledge says full access required | **Restricted:** OS full access; Doddy must enforce read-only itself | E10 | planned (card shows "Planned", no permission prompt) | P1 | Re-verify Apple docs; separate milestone |
| Create an Apple Reminder from a memory | Native EventKit | Follow-through | W | iOS full reminders access | Unknown (as above) | Preview + confirmation + native save + receipt | E10 | planned | P1 | Separate milestone (M4 in pack) |
| Read Todoist tasks | Composio Todoist toolkit | Tasks next to memories | R | Todoist OAuth scopes | Unknown — not researched this session | Least-privilege review needed | — | planned (card shows "Planned") | P2 | Evidence + scope review |
| Read Notion pages | Composio Notion toolkit | Notes next to memories | R | Notion integration capabilities | Unknown — not researched | Page-level sharing model | — | planned | P2 | Evidence + scope review |
| Read Gmail | Composio Gmail toolkit | Email context | R | Gmail read scopes | Unknown (not researched); Google treats Gmail read scopes as high sensitivity (general knowledge, unverified here) | **Restricted (expected):** Google verification/security assessment for broad Gmail scopes — verify | — | not planned now | P3 | Demand + Google policy review |
| Read Google Drive files | Composio Drive toolkit | Document context | R | Drive scopes | Unknown | Sensitive data | — | not planned now | P3 | Demand + scope review |
| External research / data endpoints | Monid | Discovery | R | Monid account OAuth (`openid profile email offline_access`) | Verified for Monid-account access (E9); **unsupported** as a way to connect users' Gmail/Calendar | Per-endpoint rights and cost | E9 | **web search built** (ADR-173: one curated endpoint, Doddy's wallet, daily caps; not live-checked) | P3 | Endpoint rights + cost check |
| News briefings | Licensed APIs / permitted RSS | Daily context | R | — | Unknown | **Restricted:** content licence must cover processing, summarising, storing, redistributing | — | not planned now | P3 | Rights review |
| Messaging import (WhatsApp, Signal) | — | — | R | — | Unknown / likely unsupported for personal chats (not researched) | Deferred | — | deferred | — | Research before any inclusion |
| Music control (Spotify) | — | — | W | — | Unknown (not researched) | Deferred | — | deferred | — | — |
| Health data (HealthKit) | — | — | R | — | Unknown (not researched) | Deferred; special-category data | — | deferred | — | — |
