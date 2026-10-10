# Connected intelligence — research baseline (reconstructed)

Date: 2026-10-09. Status: **planning baseline, not shipped behaviour.** Research is not evidence that any DODDY
feature exists, that an API still works, or that production access is available. What is actually built is in
[IMPLEMENTATION_STATUS.md](IMPLEMENTATION_STATUS.md).

## Source provenance

| Source | What it is | Availability here |
|---|---|---|
| "DODDY — Connected Intelligence Ecosystem" research | Earlier owner/assistant research on connecting DODDY to other apps | **Full report not available in this repository or session.** |
| "Composio vs Monid" decision | Earlier comparison that chose Composio for user-account connections | **Not available**; only the summary in the Composio integration prompt (2026-10-09) |
| Composio integration prompt, 2026-10-09 | The owner's instructions for this milestone, including a summary of the two items above | Read in full |
| Official documentation checked 2026-10-09 | Composio docs/SDK, Google Calendar scopes, Composio pricing, Monid OAuth guide | Cited below with check dates |

> **Reconstructed-baseline warning.** This document restates the summary supplied in the 2026-10-09 prompt. It does
> not reproduce the original reports. Missing material: the full ecosystem report (market sizing, user research,
> provider-by-provider findings, historical pricing and integration counts), the full Composio-vs-Monid comparison,
> and any legal analysis. Nothing below fills those gaps; historical prices, counts and legal conclusions are
> deliberately not repeated.

## Product decisions carried forward

1. **Memory first.** DODDY's first useful loop is user-controlled **capture → recall → follow-through**. Connections
   exist to make that loop more useful, not to turn DODDY into a universal autonomous agent in this milestone.
2. **Explicit local memories first.** Source/date metadata, honest "couldn't find it" recall, structured/lexical
   retrieval (already built: SQLite + FTS5, `Packages/DoddyCore/Sources/DoddyPersistence`). Embeddings and cloud memory
   are later and need their own approval.
3. **Wider ecosystem demand is a hypothesis.** No user research in this repository shows that users want DODDY to
   read other apps. The Google Calendar slice is a test of that hypothesis, not a validation of it.

## Roles of each integration path

| Path | Role | Notes |
|---|---|---|
| **Composio** | Connections to the user's own external accounts (Google Calendar now; Todoist/Notion candidates) | Doddy keeps its own typed capability registry and authorization between the assistant and Composio. Composio is never exposed as a generic tool catalogue. |
| **Monid** | Optional later adapter for *external information discovery/research* (data endpoints) | Monid's documented application OAuth authorises access to the user's **Monid account and workspaces** ("call the authenticated Monid API on behalf of a Monid user"; scopes `openid profile email offline_access`). It does **not** connect users' Gmail or Calendar. Endpoint-specific personal-account support must be rechecked independently. Source: [Monid OAuth quickstart](https://docs.monid.ai/guide/quickstart-oauth.html), checked 2026-10-09. |
| **Native EventKit** | Apple Calendar and Apple Reminders | Separate from Composio. Apple data is not routed through an external service to fit a unified architecture. Not built in this milestone. |
| **News sources** | Later, source-grounded briefings | Needs attribution, freshness checks and rights covering the intended processing, summarisation, storage and redistribution. RSS, API access or scraping access is not a blanket content licence. |
| **Monitoring** | Later, explicit opt-in | Frequency, expiry/cancellation, backend scheduling and APNs. DODDY must not promise continuous iPhone background execution. |

## Rules for any external action (now and later)

- Permission, appropriate confirmation and evidence-based receipts. A model proposal authorises nothing.
- Cost and rate limits are product requirements, enforced server-side before any provider call.
- Untrusted external text (event titles, emails, web pages) cannot authorise tools, widen scopes or change policy.

## Native Apple boundary (planned, not built)

When the native phases are implemented: EventKit with just-in-time consent and the deployment target's APIs. As
generally documented for iOS 17+, events offer **write-only** or **full** access and reminders offer **full** access;
there is **no read-only EventKit grant**, so reading requires full OS access and any narrower "read-only" behaviour is
enforced by Doddy, not by iOS. Apple's page could not be rendered by the automated fetch on 2026-10-09, so these
details (`requestFullAccessToEvents`, `requestWriteOnlyAccessToEvents`, `requestFullAccessToReminders`,
`NSCalendarsFullAccessUsageDescription`, `NSCalendarsWriteOnlyAccessUsageDescription`,
`NSRemindersFullAccessUsageDescription`) must be **re-verified** against
[Accessing the event store](https://developer.apple.com/documentation/eventkit/accessing-the-event-store) before
implementation. Reminder creation needs permission, a concrete preview, confirmation, a native save and an
evidence-based receipt. Planned cards in the app do not trigger permission prompts.

## Staged roadmap with gates

| Stage | Scope | Gate to start | Status |
|---|---|---|---|
| 1 | Audit/validate local capture → recall | — | Done in M1 (local SQLite memory; Mac build + simulator tests recorded 2026-10-08) |
| 2 | **This milestone:** read-only Google Calendar through Composio; mock/live adapters; Connected Apps; secure backend; tests; docs | Owner prompt 2026-10-09 | Mock milestone complete; **live unverified** |
| 3 | Native Apple Calendar read + Apple Reminders follow-through, tested separately; one explicit memory → reminder workflow | Stage 2 live check passed; owner approval; EventKit re-verification | Not started |
| 4 | Next user-requested connector (Todoist or Notion) after evidence and least-privilege review. Gmail/Drive only when demand justifies the data sensitivity and Google verification | Demand evidence; scope review | Not started |
| 5 | Source-grounded news (permitted RSS / licensed APIs); optional Monid proof of concept with endpoint rights and cost checks | Rights review | Monid web search built (ADR-173, owner request 2026-10-10; not live-checked); news not started |
| 6 | Opt-in monitors, scheduling, APNs; narrowly approved multi-tool workflows | Reliability + user value shown | Not started |

Out of scope for every stage until separately researched: WhatsApp/Signal personal-chat import, Apple Notes database
access, Spotify control, HealthKit, shopping, payments, broad scraping, partnership integrations. A catalogue listing
or an MCP wrapper cannot override provider restrictions.

## Hypotheses (unvalidated)

- H1: Seeing tomorrow's calendar next to saved memories helps users follow through. *Measure later with consenting testers.*
- H2: Users accept a hosted OAuth hand-off (Composio Connect Link → Google) inside a companion app.
- H3: Read-only access is enough for the first useful calendar experience; writes can wait.

## Licensing and access limits known so far

- Google Calendar data via a hosted OAuth app: public apps using user-data scopes may need Google verification
  (Google scopes page, 2026-10-09). Which classification `calendar.events.readonly` falls under was not stated on the
  page that was checked — **Unknown**; check the Google Cloud console before public launch.
- Composio-managed OAuth uses Composio's shared Google app (consent screen shows Composio's app, managed allowance
  limits). A custom auth config with Doddy's own Google OAuth client is the production path (consent screen name,
  quotas, verification under Doddy's name).

## Unresolved questions

1. Does Composio's managed Google Calendar auth config accept a `scopes` override of only
   `calendar.events.readonly`, and does `GOOGLECALENDAR_EVENTS_LIST` work with it? (Docs say managed configs accept
   scope overrides; not tested with a real account.)
2. Is the OAuth callback verifier (`completeAuth`) generally available on the owner's plan? (Declared in SDK 0.22.0;
   the production docs page returned 404 on 2026-10-09.)
3. Is the granted scope always exposed in `connectedAccount.state.val.scope` for Google? (Field exists in the SDK schema;
   live behaviour unverified. If it isn't exposed, Doddy keeps live reads blocked.)
4. Which Composio toolkit version should be pinned for `googlecalendar`? (Needs the owner's API key to list versions.)
5. Whether users want this at all (H1–H3).

## Dated official evidence

See the evidence table in [COMPOSIO_INTEGRATION_PLAN.md](COMPOSIO_INTEGRATION_PLAN.md#evidence) (E1–E9).
