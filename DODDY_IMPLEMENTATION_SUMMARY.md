# DODDY execution audit: implementation and review record

Date: 18 November 2026. Branch: `codex/doddy-agent-execution-audit`, based on `9cbb5d31627360c8e83cf3810a61c56c977ed8be` from `Bienos/doddy.2/main`.

The supported implementation improves existing typed services and workers. It adds narrow direct-request authorization, evidence-backed call reports and durable research progress. It does not establish a newly deployed autonomous assistant. Native controller/UI wiring is **not compiled**, and no live setting, agent, migration, deployment or real call was changed.

## Requested priorities and actual result

| Priority | Before / root cause | Changed in this branch | Validation and remaining integration |
| --- | --- | --- | --- |
| 1. Autonomy | Ordinary searches/connected reads already ran immediately; substantial handoff still asked for another yes | Recent exact PL/EN research instructions authorize one bounded handoff; removed mandatory generic shopping-preference question from repository prompt/tool wording | Core policy and existing server gates exercised locally. Compatible native build/live wording and real conversations still needed. |
| 2. Direct calls | `call_places` baseline covered inquiry, booking and order under one card rule | One exact known recipient and verbatim inquiry may use the user's instruction as authorization; recheck server preview/language/principal/pause before the existing digest approval. Default result SMS false | Exact scope/expiry/replay/recipient/preview tests. Live ASR/tool argument quality and actual calls unverified. Current server call language is Polish; English grants cannot silently authorize that payload. |
| 3. Background work | Durable encrypted errands/claims/cancel/push already existed; visible stages were sparse | Add migration 042, fixed content-free stages/counters, bounded history, account/cancel/terminal fences, optional API/Core persistence and view wiring | Real disposable-Postgres progress/cancel tests. No checkpoint resume after worker crash; no iPhone suspend/relaunch or delivered push test. |
| 4. Call report quality | One quote was checked while independent summary/next-step prose was trusted | Extract typed facts in the existing writer request; verify each value/quote/speaker/line; retain uncertainty; reject unsupported prose; flag omitted numeric details; use grounded yes/no for task progression | Synthetic rejection/attribution/uncertainty tests plus server call regressions. Not a historical precision/recall or transcript-quality study. |
| 5. Sprawy/documents | Separate errands/calls/Studio records and short call card | Structured report retained with the call result; Core PL/EN Markdown document and file roundtrip; native selectable reader/export and progress history wiring | Core export is tested; SwiftUI/file-picker is not compiled. Universal task index, report versions, PDF/DOCX remain proposed. |
| 6. iOS visibility | Feature-specific widget/Activity states; no general durable task push lifecycle | Truthful in-app stage/history projection and a concrete ActivityKit contract/design | No new server-driven Live Activity implemented; no device or screenshot/HIG validation. |
| 7. Settings/workflows | Specific morning-call/watch/radar settings, no universal workflow engine | Scoped behavior reduces repeated setup questions; documented typed stored-grant/occurrence design and simpler settings structure | Generic weekly unfinished-task automation and settings regrouping are NOT IMPLEMENTED. Existing features are not relabeled as a generic builder. |
| 8. Proactivity | Specific opt-in features exist; prompt offers do not authorize arbitrary effects | Define execute/suggest/approve boundaries and standing-grant/revocation/budget requirements | No new unsolicited call, purchase, notification campaign or generalized recurring action enabled. |

## Concrete runtime changes

- `RequestedWorkSession`: user-side transcript only, exact request binding, two-minute expiry, one use per scope/turn, new-turn and conversation reset, with a connection-attempt fence on incoming transcript events. Rejects generic/ambiguous/multiple recipients and deferred or consequential-call objectives. A model/tool/web page cannot supply a grant.
- Structured `callDestinations`: optional backend/Core response data from parsed **live** place listing fields; bounded five entries. Mock/generated prose does not seed recipient authority. Explicitly spoken numbers retain typed-number provenance.
- Compiled preview check: preserves inquiry kind, destination/name/question/goal/language/principal, no extra facts, SMS, recording or changed disclosure. Existing account/phone/hours/agent/cost/pause/digest/unknown gates still own execution.
- Call evidence: normalized transcript indexes before the writer; up to 16 accepted source-bound report facts; model summaries accepted only as the actual verified answer quote. Free-form next steps become coded suggestions. Ambiguous/ungrounded decisions cannot silently finish or advance the call task.
- Progress: appended SQL migration; observed stages/counters and 24-event history in the existing row; optional API decoding/local serialization. Existing terminal state wins over stale progress. Fixed shutdown/cancellation racing with the new initial database write.
- Document: optional report on existing `CallResultCard`, translated headings/status, domain-based ordering, source quotes/line references, uncertainty/partial notice and safe Markdown export. Native reader and errand views use existing Theme/system controls; their UI remains uncompiled here.

## Required documents

1. [Agent audit](DODDY_AGENT_AUDIT.md)
2. [Autonomy design](DODDY_AUTONOMY_DESIGN.md)
3. [Background architecture](DODDY_BACKGROUND_ARCHITECTURE.md)
4. [Calling and reports](DODDY_CALLING_AND_REPORTS.md)
5. [Sprawy UX](DODDY_SPRAWY_UX.md)
6. [Workflow builder/settings](DODDY_WORKFLOW_BUILDER.md)
7. [Actual test results and twelve scenarios](DODDY_AGENT_TEST_RESULTS.md)
8. This implementation summary
9. [Research/technology evidence](DODDY_RESEARCH_AND_TECHNOLOGY_REVIEW.md)

The [source agent inventory](docs/audits/2026-11-18-agent-execution/source-agent-inventory.json) records each repository agent's tools/model/config paths. The new [decision](docs/decisions/2026-11-18-scoped-requested-work.md) and [change note](changes/scoped-agent-execution.md) leave shared historical ledgers untouched.

## Test status

Full backend: PASS, 1,100 passed / 1 skipped / 0 failed. Messaging: PASS, 1,325 passed / 0 failed / 0 skipped. Node group: PASS for executed steps, with 40 optional Redis skips and its browser step auto-skipped. Separate system-Chromium run: 16 passed / 4 skipped / 2 failures in the unchanged deck-placeholder assertion. Swift app-logic/state/store/Island checks passed; the clean full Core rerun executed 3,898 tests with 2 skipped and 0 failed, replacing the compile invalidated by a concurrent source edit. Native syntax parsing also passed; this is not a native build. Exact commands, final totals and failure analysis are in [test results](DODDY_AGENT_TEST_RESULTS.md). No production improvement percentage is claimed.

Native iOS/controller/SwiftUI/ActivityKit: **not compiled**. Linux Core and app-model checks do not replace `ios-build`, simulator/accessibility or physical-device evidence. Live agent comparison, real calls and historical report scoring: **not run**.

## Constitution evidence log

| Requirement | Enforcing code / executed evidence | Limits and claims |
| --- | --- | --- |
| DOD-01 usefulness | `RequestedWorkSession`, voice handoff/call routing; exact PL/EN policy fixtures | Narrow recognized scopes remove redundant confirmation. Live conversation quality/latency unmeasured. |
| DOD-02 truth | `taskCalls/report.ts`, `result.ts`; synthetic invented price/date/summary/commitment rejection | A verbatim statement is what the callee said, not independently verified truth or proof of completeness. |
| DOD-07, UX-03 scope/approval | Private exact turn/request grants; compiled preview; existing digest approval and server gates; payment/write/booking/SMS rejection fixtures | Direct instruction authorizes only its exact scope. ASR/speaker identity and native dispatch need device review. No global trusted switch added. |
| DOD-08, UX-02/04 evidence/status | Existing durable tasks/receipts plus `progress.ts`, report evidence and Core terminal projection; DB ownership/cancel tests | No invented percentages, provider completion, booked outcome or ActivityKit claim. Numeric coverage is conservative, not semantic completeness. |
| DOD-09 recovery | Post-write shutdown fence, late-progress/result cancellation fence, grounded chain decisions; existing unknown/timeout regressions | Worker crash still ends interrupted. No blind retry or automatic duplicate submission added. |
| DOD-11 privacy/control | Progress contains fixed metadata only, inherits row deletion/retention and account filters; Markdown disables active model links/HTML | Call transcript/report still follows existing encrypted result/acknowledgment/provider deletion lifecycle. No privacy-policy guarantee or new cloud processor. |

No memory-policy, user identity, personality, connection consent or platform permission bypass was introduced. Exact-payload call/errand approval remains server-enforced. Repository trust YAML records the conditional exception as metadata; it is not the authorization engine.

## Compatibility, risk and rollout

1. Review the native-sensitive controller diff. An open-PR collision check was attempted through GitHub API and returned `Forbidden`; it must be repeated through authorized access before integration.
2. Run required native `ios-build`, app/model tests and simulator/device scenarios. Check direct grant dispatch, fallback cards, spoken corrections/pause/lock, default no SMS, report reader/export, background re-adoption, VoiceOver/Dynamic Type and real notification delivery.
3. Apply migration **042** before the changed messaging API/worker. Deploy backend structured destination support and messaging report/progress/language echo together with compatible client expectations. No migration was applied to production here.
4. Ship a compatible phone build before changing live prompt/tool wording. Old clients safely keep their approval cards but may discard unknown report/progress fields during adoption; because acknowledgment can delete the server copy, don't promise these documents to old clients. There is no server-enforced minimum-app-version rollout gate added in this patch.
5. Read the current authorized ElevenLabs published/draft config and exact tool definitions. Compare only the changed passages/three descriptions, preserve unrelated live edits, stage/evaluate, and obtain the separate exact live-change instruction required by repository rules. Do not upload the full repository prompt over a differing live prompt.
6. Use consented test numbers/transcripts for real provider/PL/EN and recovery evaluation. Preserve unknown outcomes rather than redialing blindly. Measure actual call/task completion, extraction quality, latency and billed cost before broad rollout.

Reports use the existing writer request but increase its maximum output from 2,000 to 4,000 tokens; actual additional spend/latency was not measured. More output can still truncate/fail and must use the existing fallback. Verbatim grounding does not repair ASR errors, prove yes/no semantic entailment or guarantee that every spoken condition was extracted. English call execution remains an integration gap despite bilingual Core parsing/presentation.

Rollback: revert app/worker/backend behavior and repository prompt passages together as appropriate; the additive nullable progress column can remain. Do not edit old merged migrations, delete task evidence or resend effects as a rollback. No new dependency, key, cloud service or financial commitment was introduced.

## Owner decisions and next integration task

No decision is needed to review this local branch. Production rollout needs native validation and separately instructed service/live-agent changes. The next coherent implementation after this slice is a durable unified task projection with one bounded weekly-summary template, followed by server-driven ActivityKit token/push integration and device proof. Detailed acceptance contracts are in the linked design documents; none is counted as already working.

## Exact files changed

The list below is generated from this branch's tracked modifications and new source/docs, excluding workspace-only logs/toolchains.

- `BUILD_AND_TEST.md`
- `DODDY_AGENT_AUDIT.md`
- `DODDY_AGENT_TEST_RESULTS.md`
- `DODDY_AUTONOMY_DESIGN.md`
- `DODDY_BACKGROUND_ARCHITECTURE.md`
- `DODDY_CALLING_AND_REPORTS.md`
- `DODDY_IMPLEMENTATION_SUMMARY.md`
- `DODDY_RESEARCH_AND_TECHNOLOGY_REVIEW.md`
- `DODDY_SPRAWY_UX.md`
- `DODDY_WORKFLOW_BUILDER.md`
- `DoddyApp/Features/CallCases/CallCaseView.swift`
- `DoddyApp/Features/CallCases/CallCasesModel.swift`
- `DoddyApp/Features/CallCases/CallReportReader.swift`
- `DoddyApp/Features/Errands/ErrandsView.swift`
- `DoddyApp/Features/Voice/VoiceSessionController.swift`
- `Packages/DoddyCore/Sources/DoddyCore/AskFirst.swift`
- `Packages/DoddyCore/Sources/DoddyCore/CallCase.swift`
- `Packages/DoddyCore/Sources/DoddyCore/CallReport.swift`
- `Packages/DoddyCore/Sources/DoddyCore/CallTask.swift`
- `Packages/DoddyCore/Sources/DoddyCore/Errand.swift`
- `Packages/DoddyCore/Sources/DoddyCore/ErrandProgress.swift`
- `Packages/DoddyCore/Sources/DoddyCore/OnlineAccounts/OnlineAccountsContracts.swift`
- `Packages/DoddyCore/Sources/DoddyCore/RequestedWork.swift`
- `Packages/DoddyCore/Tests/DoddyCoreTests/AgentDocumentsTests.swift`
- `Packages/DoddyCore/Tests/DoddyCoreTests/CallTaskTests.swift`
- `Packages/DoddyCore/Tests/DoddyCoreTests/RequestedWorkTests.swift`
- `backend/src/tools/catalog.ts`
- `backend/src/tools/contracts.ts`
- `backend/src/tools/service.ts`
- `backend/src/tools/websearch.ts`
- `backend/test/call-destinations.test.ts`
- `changes/scoped-agent-execution.md`
- `docs/audits/2026-11-18-agent-execution/pull-request.md`
- `docs/audits/2026-11-18-agent-execution/source-agent-inventory.json`
- `docs/decisions/2026-11-18-scoped-requested-work.md`
- `docs/platforms/iphone.md`
- `docs/trust/config/doddy_rules.yaml`
- `server/messaging/README.md`
- `server/messaging/migrations/042_errand_progress.sql`
- `server/messaging/src/errands/progress.ts`
- `server/messaging/src/errands/researcher.ts`
- `server/messaging/src/errands/service.ts`
- `server/messaging/src/errands/worker.ts`
- `server/messaging/src/taskCalls/report.ts`
- `server/messaging/src/taskCalls/result.ts`
- `server/messaging/src/taskCalls/tasks.ts`
- `server/messaging/src/taskCalls/worker.ts`
- `server/messaging/src/taskCalls/writer.ts`
- `server/messaging/test/bookCalls.test.ts`
- `server/messaging/test/callReport.test.ts`
- `server/messaging/test/callTasks.test.ts`
- `server/messaging/test/errands.test.ts`
- `server/messaging/test/migrationsFrozen.test.ts`
- `server/messaging/test/orderCalls.test.ts`
- `server/messaging/test/taskCallsUnits.test.ts`
- `server/messaging/test/taskCallsWorker.test.ts`
- `voice-agent/README.md`
- `voice-agent/instructions.md`
- `voice-agent/tools.json`
