# Agent audit: executed tests and remaining acceptance

Date: 18 November 2026. Source baseline: `9cbb5d31627360c8e83cf3810a61c56c977ed8be`. These are local mock/contract/database results, not production success rates. No real calls, paid provider requests or historical customer transcripts were used.

## Reproduction environment

Node 22.22.3; Swift 6.1.3 on Linux in the retained onboarding container; Python 3.12; system Chromium; disposable PostgreSQL on port 55432. `source /workspace/.doddy-setup/env.sh` sets the local tool paths and disposable `TEST_DATABASE_URL`. `/workspace/.doddy-setup/swift.sh` executes in the Linux Swift container. These workspace helpers and raw logs are not application dependencies or committed credentials.

Logs are retained at `/workspace/.doddy-audit/logs/`. Messaging tests destroy the schema named by `TEST_DATABASE_URL`; never point them at production. No database suites were run concurrently against that schema.

## Executed commands

| Command | Actual result / scope |
| --- | --- |
| Baseline: `swift test --package-path Packages/DoddyCore --jobs 2 -Xswiftc -DSQLITE_DISABLE_SNAPSHOT -Xlinker --allow-shlib-undefined --filter 'AskFirstTests\|CallTaskTests\|SpokenConfirmationTests'` via the wrapper | 53 passed before implementation. This is a baseline for existing gate tests, not a user-conversation benchmark. |
| `scripts/ci.sh --only backend` under the Node environment | PASS: typecheck and 1,100 passed, 1 skipped, 0 failed. Includes new structured destination tests and existing approval/unknown/payment regressions. `backend-ci.log`. |
| `scripts/ci.sh --only checks` | PASS: full static/spec/generated-file/guard group. `checks-final.log`. After final prompt consistency edits, the main agent spec was also explicitly rechecked: PASS, 127 tools. |
| `scripts/ci.sh --only messaging` under the disposable database environment | PASS: typecheck, 1,325 passed / 0 failed / 0 skipped and Studio rendered-sample checks. `messaging-final.log`. |
| `/workspace/.doddy-setup/swift.sh bash scripts/ci.sh --only swift` | The package-build step was invalidated by a source edit; every remaining step passed: app logic typecheck, call/messages/watch/open-loops/training state tests, file-store checks and Island art/scenes. `swift-ci.log`. The failed step is replaced by the clean full package command below. |
| `/workspace/.doddy-setup/swift.sh swift test --package-path Packages/DoddyCore --jobs 2 -Xswiftc -DSQLITE_DISABLE_SNAPSHOT -Xlinker --allow-shlib-undefined` | PASS: 3,898 executed, 2 skipped, 0 failed (3,896 passed). `swift-final.log`. |
| `scripts/ci.sh --only node` under the Node/Chromium environment | PASS for its executed steps: voice-token 173 passed / 40 optional Redis tests skipped; gateway 76 passed; web 190 unit tests passed plus typecheck/build; site 43 passed; secrets tooling 43 passed. Browser step auto-skipped because the group checks for bundled Chromium. `node-ci.log`. |
| `npm run build --prefix backend` then `npm run e2e --prefix web`, with `PLAYWRIGHT_CHROMIUM=/usr/bin/chromium` | Backend build PASS. Browser run: 16 passed / 4 skipped / 2 failed. Both failures are the unchanged deck-placeholder assertion described below. `browser-backend-build.log`, `browser-e2e.log`. |

Native-source syntax check: `swiftc -frontend -parse` via the Linux wrapper on the five changed native files passed, including the final transcript-connection fence. This performs no SwiftUI/SDK typecheck or native compilation. `native-parse.log`.

Focused intermediate evidence: initial requested-work/CallTask run 26 passed; Core document/gate/errand group 70 passed; destination tests 2 passed; messaging errands/report/task unit group 37 passed after fixing the shutdown race. These are development checkpoints, not additional independent trials or final-tree totals.

## Failures investigated

- New asynchronous progress storage exposed a shutdown race: an already-fired abort could be missed before provider startup. The first focused messaging run cancelled seven descendants. Added the post-write shutdown/cancel fence; the repeated focused run passed all 37 tests. No assertion or limit was weakened.
- The previous report test expected model paraphrase to become a verified summary merely because a separate quote matched. Updated the expected behavior: source excerpt plus `model_summary_unverified`; the paraphrase is no longer accepted as evidence.
- The first full messaging run had seven failing tests: three unit fixtures used placeholder `answerQuote: "x"`; a booking chain used an uncertain alternative-time reply; a clear order refusal was overblocked because general audit confidence was confused with callee uncertainty; the old writer response shape gained a literal undefined key; and a worker assertion trusted ungrounded summary prose. Fixed source quote fixtures and absent optional-field compatibility, kept uncertain chains stopped, preserved clear source-backed negative decisions and replaced unsupported prose while retaining cost accounting. Also strengthened the no-quote negative assertion: it must remain unclear. The final 1,325-test run passed.
- Separate browser checks failed twice at `web/e2e/workspace.spec.ts:95` (desktop and phone size): the unchanged assertion expects `DEMO deck: …` as UTF-8 while the unchanged mock deck generator returns a PPTX ZIP. This same issue was observed during environment onboarding before this branch. The 16 other browser cases passed; four opt-in screen cases were skipped. No deck expectation or renderer was changed to hide the failure.
- A Swift full run reported “input file … RequestedWork.swift was modified during the build”. This is an invalidated build run, not a product test failure; it is retained and followed by a clean final run.

## Twelve requested scenarios

| Scenario | Executable evidence | What remains unverified |
| --- | --- | --- |
| 1. Competitor research without repeated permission | `RequestedWorkTests`: exact PL/EN research instruction, one-use scope, changed brief/expiry blocked. Existing research runner tests bound tools/time and verify source-backed cards. | No live main-agent conversation or actual 10-competitor quality/completion score. |
| 2. Work continues after voice ends | PostgreSQL errand claim/status/cancel/result tests; Core persistence/adoption contracts. Independent API reader sees stored progress. | Actual iPhone suspension/relaunch and delivered push not tested. Worker crash resumes no checkpoint: it ends interrupted. |
| 3. Explicit inquiry call | PL/EN instruction parser, exact number/live-listing contract, compiled preview gate; server call/task mock regressions. | Actual native route, live tool arguments, Twilio/ElevenLabs call/audio not tested. Current configured call payload is Polish. |
| 4. Missing/ambiguous contact | No grant for missing listing, duplicate-name/different-number, generic recipient, multiple recipients, changed number or unspecified objective. | Conversational clarification quality on a device not tested. |
| 5. Detailed report | Synthetic transcript extraction/rejection, uncertain dates/prices, assistant versus callee attribution, typed Core decoding, real UTF-8 file write/read and Markdown escaping. | No historical-call accuracy study, native file-picker/export or PDF/DOCX test. |
| 6. Dynamic Island visibility | Existing repository art/state checks only. Proposed task Activity states are documented. | New server-driven ActivityKit updates are NOT IMPLEMENTED; no simulator/device screenshots or HIG review. |
| 7. Weekly unfinished-task workflow | Source audit establishes absence of a general workflow scheduler; typed design and acceptance cases provided. | NOT IMPLEMENTED. Existing morning-call/watch features are not counted as this scenario. |
| 8. External-service failure | Existing researcher/provider timeout, refusal, limits, unknown-outcome and call failure mock tests; terminal progress projection. | Production failure frequency, retry cost and recovery latency not measured. |
| 9. Payment approval | New requested-work gate cannot grant cloud/payment writes; existing backend payment exact-approval/unknown tests run in the full backend group. | No real payment was initiated. |
| 10. Multiple simultaneous tasks | Existing maximum-three worker/claim tests; single-use direct scope, account-scoped progress and cancellation-fenced terminal writes. | Multi-device/native presentation and production throughput not measured. |
| 11. User interruption/correction | Grant changes on new turn, rejects expired/mutated requests; existing shutdown/cancel tests and conversation resets. | Actual ASR/interruptions and stopping a real in-flight third-party call need a controlled device experiment. |
| 12. Hallucinated report facts | Fabricated dates/prices, false commitments, wrong speaker/line, arbitrary summary/next step, cropped uncertainty and unsupported negative/positive decisions are rejected in synthetic tests. | Verbatim grounding cannot prove transcript correctness, semantic completeness or a real external booking. |

## Measurement boundaries

The baseline gate tests establish existing behavior; source inspection establishes why redundant confirmation and ungrounded prose occurred. No before/after production dataset exists in this session. Task completion rate, unnecessary-confirmation/clarification rate, autonomous tool success, crash/relaunch reliability, latency to useful answer/completion, real call initiation rate, historical extraction precision/recall, report completeness, user intervention and cost per useful task are **NOT YET MEASURED**.

Synthetic assertions are release-gate examples, not calibrated population accuracy percentages. Numeric-coverage flags only detect omitted numeric tokens; they cannot certify every important verbal condition was extracted. Do not advertise “zero hallucinations” from these fixtures.

A future authorized evaluation should pin app/server/agent versions, use consented transcripts/test numbers, retain exact task/provider receipts and de-identified outcomes, score PL/EN cases separately, distinguish objective success from call answered, and compare the same task set before/after. Sample size, exclusions, confidence intervals, failed/unknown attempts and actual billed usage must accompany results.

## Not run

Xcode/native iOS compilation, simulator/UI/accessibility tests, physical-device voice/ActivityKit/push, live agent compare/run-tests, real Twilio calls, historical transcript analysis and production migrations/deployments were not run. ElevenLabs/GitHub connector read tools were not exposed; direct GitHub API and official Apple/ElevenLabs docs requests were denied by the proxy. Pinned official ElevenLabs SDK source was inspected instead. These are integration gaps, not passing tests.
