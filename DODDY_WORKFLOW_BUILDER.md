# Natural-language workflows and simpler settings

## Current capability

**VERIFIED/source:** DODDY already has bounded standing-authorized features: morning calls, scheduled personal calls, following/news/radar alerts and price/deal monitoring. They have specific schemas, switches, limits and stop behavior. The main tool spec includes `call_me_every_morning`/`stop_morning_calls`; this is not proof those current tools are attached to the live agent or exercised on a device.

**VERIFIED/source:** there is no universal workflow compiler/store for arbitrary combinations such as “every Friday summarize my unfinished tasks”. This patch does not represent a parser-only prototype as an operational scheduler. That scenario remains **NOT IMPLEMENTED**.

Detailed reports after task calls are now part of the existing post-call result pipeline; that does not require pretending a generic event-automation engine exists. Existing server jobs can continue after voice ends, and their own cancellation/retention rules remain in effect.

## Implemented friction reductions

Direct, exactly scoped research requests no longer need an additional yes on a compatible app. The repository tool/prompt wording removes the mandatory generic shopping-preference question: use supplied priorities or an empty list and state reasonable assumptions in the result. Essential missing information still requires a focused clarification. Inquiry calling uses the bounded direct-request contract in [autonomy design](DODDY_AUTONOMY_DESIGN.md).

No production prompt/tool sync or settings change was performed. A compatible phone build and reviewed live diff are prerequisites.

## A workflow is a stored grant plus a trigger

Proposed typed record:

| Field | Contract |
| --- | --- |
| ID/account/version | Immutable identity, ownership and revision; no cross-account reuse |
| User instruction | Original words as data, encrypted and retained under an explicit policy |
| Trigger | One supported schedule or trusted event; no model-generated arbitrary webhook code |
| Schedule | Local time, IANA zone, days and DST/missed-run policy |
| Allowed operation | A bounded typed action, tools, data categories and output destination |
| Authorization | Canonical payload hash, approval source, expiry and revocation state |
| Limits | Cost/time/tool caps, concurrency, maximum pending runs and provider-failure policy |
| Occurrence key | Unique `(workflow ID, version, scheduled occurrence)` identity; a restart cannot create duplicates |
| State/receipt | Due, claimed, running, awaiting user, completed/partial/failed/cancelled/unknown with evidence |
| Delivery/retention | In-app artifact and scoped notification, quiet hours, deletion/export behavior |

A model proposes this structure; typed code validates it. Only persisted active grants can schedule work. Never execute arbitrary generated tool lists, SQL, code or destination URLs.

## Minimal creation flow

1. User gives an instruction. Resolve account, time zone, known delivery preference and already supplied constraints.
2. Select a supported template. For “every Friday summarize unfinished tasks”, use internal task state only; no model inference of external commitments.
3. If the time is absent, show one sensible editable default in the preview; ask only when a missing constraint prevents responsible execution.
4. Show one plain-language preview: what, when, information used, output, budget and Stop. Authorize that exact recurring scope once.
5. Persist the grant and first occurrence transactionally. Read it back before saying “created”.
6. Each occurrence claims its unique key, rechecks grant/account/revocation and records actual results. Failure/unknown cannot become a duplicate side effect.

“Whenever a call finishes, make its report” should subscribe to a trusted settled-call/result event, not a phrase in the conversation transcript. Reports use the evidence pipeline and are linked to that call's task. Voice-session-ended is not an authoritative call-completed event.

## Initial templates worth implementing next

- Weekly unfinished-task summary: no purchases, third-party messages or private-content exports; deterministic data selection and source task links; notify only if useful.
- Weather-before-travel notice: scoped location/time input and a weather capability actually enabled for the worker; provider failure says unavailable rather than forecasting from memory.
- Changed-price watch: reuse the existing watch infrastructure rather than creating another scraper/notification loop.
- Post-call report defaults: choose language/format/retention; do not create a second copy with weaker deletion or evidence rules.

The first two need persistent workflow/occurrence tables, authenticated create/edit/revoke APIs, template execution, worker scheduling and a phone tool/preview. Current client-only provider web tools cannot simply be assumed callable by a background worker. Those integrations are not implemented in this patch.

## Settings information architecture

Proposed visible categories: Autonomy; Calls; Background tasks; Proactivity; Reports and documents; Connections; Privacy and memory. Keep provider IDs, prompts, model names and agent routing out of normal settings. Show capabilities and concrete effects, existing consent status and simple Stop/Pause controls. Expert diagnostics can retain technical configuration separately.

Existing Pause All, per-connection consent, server call settings and kill switches remain the controls for the implemented changes. A new “autonomous” switch must not quietly grant all effects. A broader standing grant is its own editable object with scope and expiry, not a global bypass.

## Required acceptance

Test creation/read-back, editing invalidating old authorization, duplicate and concurrent schedulers, DST, missed/late runs, quiet hours, revocation during a pending request, account deletion/sign-out, expired grants, cost ceilings, provider refusal, unknown external outcome, result retention and repeated events. A schedule that is not actually persisted and dispatched must never be reported as created. None of the unimplemented templates is counted as a passing live workflow evaluation.
