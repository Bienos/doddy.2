# DODDY memory: implementation and evidence

Baseline `7a651eb27a20e04cab6663e107726a161d9dd7d1`; branch `feat/intelligent-memory-foundation`; 10 November 2026. This file distinguishes completed work from the roadmap. No deployment, live-agent edit, signing change, TestFlight upload or production write is authorized by this task. Local code and documents form the reviewable deliverable.

Final integration base: `b000ee19d83b8c345a4abf119d1b147fbefafd21`. `main` advanced during the task; the branch was rebased and reverified. The memory paths used for the synthetic before/after comparison were unchanged by that upstream commit.

## Implementation plan before code changes

The audit found existing components rather than a missing memory stack. Implement the smallest understood repair slice:

1. Apply note type and private-ID exclusions before SQLite candidate limits; retain lexical rules and explicit no-match. Add scoped recall ports with backward-compatible defaults for other adapters; recheck privacy after awaited reads. Connect voice and Siri through the same shareable recall policy as Messages.
2. Make conversation-log append commit/read-back before publishing; report decoding/write failure; keep the last good state on failure.
3. Invalidate in-process semantic vectors after corrections/deletions/restore; invalidate in-flight embedding work so it cannot restore stale vectors after an await.
4. Recheck recap remembering consent/epoch after model generation. Do not expand summary extraction, model use or automatic saving.

Baseline-driven optimization added before implementation: the synthetic 5k-note Debug median was 93–102 ms. The fallback decoded and validated every full `MemoryRecord`, including original/current text, before choosing ≤20 results. Read only row ID + folded search text for ranking, then materialize the selected records in the same read transaction. Keep the exact FTS/fuzzy ranking rules and compare the identical benchmark afterward. This is a storage projection change, not a semantic-search rollout.

No database migration or new runtime dependency is needed. Correctness/privacy repairs are unconditional; optional behavioral expansion and semantic voice retrieval stay out. Relevant constitution rules: DOD-02, DOD-06, DOD-08, DOD-11 and UX-01/UX-04. A model never gains action authority.

Tests planned: real SQLite list/private crowding, fuzzy suppression, zero/negative limits, fresh privacy state across suspension; durable file save/reopen/failure/corruption; actor invalidation across a suspended embedding; consent revocation during recap generation; existing migration/edit/delete/export tests. Run the Swift/checks CI groups and iPhone compile/unit checks when supported. Baseline local synthetic timings precede production-code edits. No speed claim without a controlled measurement.

## Roadmap with acceptance and rollback

| Phase | Changes, files and components | Dependencies / risks | Tests and acceptance | Rollback |
|---|---|---|---|---|
| 0: audit/baseline | Four files in `docs/architecture/memory-rag`; inspect active controller, repositories, app composition and server boundaries; synthetic benchmark fixture | Swift/Xcode package access; no device/provider credentials used | Pin current main; record exact commands, synthetic timings and missing end-to-end metrics | Remove test fixture/docs without touching data |
| 1a: focused reliability foundation | `Ports`, `Search`, `PrivateNotes`, `SQLiteMemoryRepository`, `MemoryStore`, voice search, Siri, `ConversationLogStore`, `MeaningSearch`, `RecapKeeper`; reuse all existing stores | Private scope must affect SQL and fuzzy ranking; actor and file semantics; controller is a shared hot file, open PRs checked | No private/list crowding, no stale result after invalidation, saved log matches file, revoked recap not saved; existing core/checks + iPhone build | Revert these code commits; no schema rollback needed. Preserve bug-fix tests as regression evidence |
| 1b: remaining reliable foundation | Owner partition in `AppEnvironment`, account lifecycle, profile/log/learning/media/settings/widget scopes; source linkage and deletion coordinator; async history journal | Legacy ownership cannot be guessed; erasure of independent copies; exact migration review | Upgrade populated DB safely; A→B account switch exposes no data; source deletion reaches summaries/indexes/caches and pending jobs; crash/retry and offline cleanup receipts | Feature flag off for expanded recall; quarantine old store; keep schema additive and reject unsupported old binaries |
| 2: intelligent retrieval | Proposed `MemoryRetrievalPlan`, query-sensitive profile/learned facts, bounded episode search, optional hybrid ranking in DoddyCore; extend Assistant wire only if needed | EN/PL quality corpus, provider integration, warm model assets; no extra classifier LLM | Recall/precision/abstention gate and supported-device latency/battery budgets; all seven requested scenarios; exact IDs and private/deleted sources never regress | Off-by-default experiment flag, lexical fallback; drop/rebuild only derived vectors |
| 3: advanced memory | Project links, explicit temporal supersession, source-preserving consolidation, document retrieval; opt-in sync only after design | Multiple owners/processors, deduplication, conflict UX and operational cost | Project continuation and historical/current facts distinguished; idempotent sync and source lineage; explicit confirmation on actions | Disable project/graph/sync reads, retain authoritative approved records/export; reconcile remote cleanup |
| 4: continuous evaluation | Content-free retrieval timing/counters; versioned fixture sets; privacy and cost reviews | No raw personal telemetry; opt-in study and sampling strategy | Track false memories, quality, resource budgets and rollback triggers by version/device/language | Disable telemetry/experiment; retain user data/control independently |

The full Phase 1 is not called complete while owner isolation and source-derived deletion remain unresolved. Phase 1a is a repair of shipped semantics; its verification status is recorded below after execution.

## Performance protocol

Measure only synthetic content here. `MemoryRetrievalBenchmarkTests` is an opt-in benchmark, not a timing assertion in routine CI. Use the same fixture/Swift configuration before and after, warm each query twice, then report nearest-rank p50/p95 from 20 samples at 1k/5k/10k notes. Workload classes: exact name, no match, typo, EN→PL keyword; separate the privacy-crowding quality fixture. Include note count, database bytes, build configuration and host; exclude fixture creation from retrieval latency. The existing fallback scans only the newest 5,000 notes, so older typo-only misses at 10k are expected limitations, not a successful recall result.

No provider call is necessary for these repairs. API cost increment from the new code is zero additional extraction/embedding/router requests; additional relevant notes may change existing prompt tokens. Actual cost is `input tokens × effective input rate + output tokens × output rate + tool/hosting charges`, with cache tiers and provider billing considered. Do not infer a dollar saving from local timing. Device battery/RAM, real first token/audio and production token/cost distributions need controlled phone sessions.

## Execution record

At plan creation: Xcode 27.2 (`27B52`), Swift 6.4.2, arm64 macOS. One booted iPhone 18 Pro / iOS 27.2 simulator was discovered. Initial `make test-core` was blocked by sandbox access to the default Clang/SwiftPM cache; retry uses task-local caches and the pinned dependencies, with network access approved. Final commands/results and benchmark output are appended after execution.

## Manual and model evaluation matrix

| Case | Procedure and expected outcome | Evidence type |
|---|---|---|
| A music recall | Explicitly save “My favourite music is hypnotic techno”; ask later; source must match exact record | Storage/lexical fixture now; natural language correctness needs controlled model/device run |
| B correction | Save techno; “mostly jazz recently” is episodic until confirmed; explicit edit uses existing correction history | Existing storage tests; no automatic preference overwrite implemented |
| C restaurant | Save/discuss with approved recap; later lexical restaurant query returns source | Local note fixture; month-long raw episode search remains future |
| D unknown detail | Search returns no match; model says unknown without fabricated date | Native no-match automated; model false-memory rate not measured |
| E cross language | Polish restaurant/code note, English lookup | Existing fixed keyword rules automated; broad paraphrase and semantic quality unmeasured |
| F latency | Same device/network/provider, randomized before/after sessions; instrument end-of-turn and first audible audio | Synthetic local DB benchmark now; voice comparison not run |
| G deletion | Edit/delete, reopen DB, query again; inspect FTS/cache and pending jobs | Automated native storage/cache tests; full remote/source cleanup still a gap |
| H malicious retrieved text | Fake closing delimiters and instructions remain data; unauthorized tool never executes; forged citation rejected | Existing delimiter/citation/action gates; natural model compliance not certified |

## Rollout constraints

Do not merge as part of this task: repository rules note that merges trigger production builds, and the user's request explicitly excludes deployment/build upload without approval. Existing open PRs were inspected before touching shared files; this branch does not incorporate them. A future PR should use `.github/pull_request_template.md`, describe constitution evidence and any sensitive paths, and list device/live tests still outstanding. No `STATUS.md`, shared ADR ledger or release/signing config is changed.


## Completed Phase 1a and actual verification

The focused repair slice is implemented and compiled. The whole Phase 1 remains incomplete because ownership migration and source-derived erasure are not implemented.

- `MemoryRepository.queryNotes`, scoped `RecallService`, `RepositoryRecallService`, `ShareableRecallService` and `SQLiteMemoryRepository` apply note/privacy eligibility before both the FTS and fallback limits. Matching uses lightweight row ID/search-text projections; only the selected full records are decoded in the same read transaction. Existing bilingual, inflection, typo and ordering tests remain green.
- Voice search, its newest-note fallback and Siri recheck privacy after awaited work. The fallback reuses `voiceStartupSnapshot` so 50 newer private rows cannot hide the next eligible note. Messages already uses `ShareableRecallService` and benefits from the scoped implementation.
- `MeaningIndex` invalidation advances a generation and evicts affected vectors. Suspended embedding work cannot repopulate a cleared cache. `MemoryStore` receives the real index from `DoddyApp` and invalidates it on correction, deletion, restore and delete-all.
- `ConversationLogStore` publishes an appended log only after atomic write and read-back. Failed writes retain the last committed in-process state. Corrupt archives report a problem and are preserved rather than silently overwritten. An explicit nil URL is a test-only in-memory store; production path failure is not called durable. The existing Forget button remains enabled for a storage problem so a person can reset unreadable history deliberately. Clear failure retains the error/data.
- `RecapKeeper.recapConversation` captures a consent epoch, rechecks remembering/server consent after model generation, checks cancellation, and deduplicates concurrent work for the same conversation. The writer is injectable for tests; tests invoke no provider. This fix covers voice conversation recaps. Recording/phone recap jobs, account changes, source deletion during extraction and consent changes during the storage transaction require the broader lifecycle design; this is not a claim of complete erasure or cancellation across every recap path.

No live prompt, provider settings, release/signing files, schema migration, runtime dependency or paid service was changed. Changes are in separate local commits on `feat/intelligent-memory-foundation`, rebased onto `b000ee19`; nothing was pushed or merged. Constitution decision record: `docs/decisions/2026-11-10-local-memory-foundation.md`.

### Commands and results

| Check | Actual result |
|---|---|
| Initial `make test-core` | Blocked by default cache sandbox access; no product failure inferred. Retry used task-local caches and approved dependency access. |
| Baseline `swift test --package-path Packages/DoddyCore` with task-local cache/config/security paths and `--disable-sandbox` | **2,867 passed**, zero failures, before production-code edits. |
| Final `scripts/ci.sh --only checks,swift` on the rebased branch | **26 steps passed, 1 failed**. Package suites: 2,661 core + 10 design + 207 persistence registrations, including two skipped opt-in diagnostics = **2,876 passed, 2 skipped, zero test failures**. Island art checks passed. |
| Static-check failure | Existing `scripts/studio_skills.sh:76` uses GNU `sed -i` and `0,/pattern/`. macOS BSD sed fails to create its intentionally broken SVG, so the negative renderer test fails. The script is byte-identical to upstream; it was not weakened or edited. Static-only portion: 24 pass, 1 fail. |
| Python prerequisites | Initial system Python 3.9 lacked packages and rejected the existing generator's Python 3.12+ f-string syntax. A task-local Python 3.15 environment with PyYAML, ReportLab and Matplotlib resolved those environment failures. These are QA dependencies, not app dependencies. |
| `make project` | Passed; existing XcodeGen specs and pinned packages retained. |
| `XcodeBuildMCP.test_sim`, scheme Doddy, Debug, iPhone 18 Pro/iOS 27.2, `-only-testing:DoddyTests -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO -disableAutomaticPackageResolution` | **168 passed, 1 availability-dependent test skipped, zero failures**, repeated after rebasing. Unit tests cover voice gates and the new history/recap/store integration. This is not a real voice session or a UI interaction run. |
| Final `XcodeBuildMCP.build_sim` with signing disabled for this invocation | **Passed**, including the last one-line Settings recovery-control change. No signing config was edited. |
| `git diff --check` | Passed. |
| Backend / Node / messaging suites | Not run: no server, contract, tool-spec or Node runtime code changed. |
| Physical device / real voice / full UI suite | Not run. No measurement of end-of-turn to audible response, real token cost, battery or iPhone peak RAM. iOS 17 hardware/model fallback needs device coverage; compilation against the iOS 17 minimum is not that coverage. |

Reproduction (from the repository root; cache folders are task-local):

```sh
env CLANG_MODULE_CACHE_PATH="$PWD/../clang-cache" swift test   --package-path Packages/DoddyCore --cache-path "$PWD/../swift-cache"   --config-path "$PWD/../swift-config" --security-path "$PWD/../swift-security" --disable-sandbox

# Before and after used the same Debug timing fixture; opt in deliberately.
env CLANG_MODULE_CACHE_PATH="$PWD/../clang-cache" DODDY_MEMORY_BENCHMARK=1   DODDY_BENCHMARK_LABEL=after swift test --package-path Packages/DoddyCore   --cache-path "$PWD/../swift-cache" --config-path "$PWD/../swift-config"   --security-path "$PWD/../swift-security" --disable-sandbox --filter MemoryRetrievalBenchmarkTests

env PATH="$PWD/../qa-py315/bin:$PATH" MPLCONFIGDIR="$PWD/../matplotlib-cache"   CLANG_MODULE_CACHE_PATH="$PWD/../clang-cache" scripts/ci.sh --only checks,swift
```

The initial app build caught a non-Sendable UserDefaults capture introduced in the Siri change. It was corrected by keeping defaults access on its actor and passing the exclusion set through the scoped port; subsequent builds and tests passed. Existing unrelated actor/deprecation warnings remain in upstream app/UI-test code. Checks are not described as entirely green.

### Measured local storage performance

Host: arm64 macOS 27.0.1, Swift 6.4.2, SwiftPM **Debug**. One before run and one after run, two warmups and 20 timed samples per workload. Nearest-rank p50/p95. Fixture creation excluded. Same synthetic corpus and query set; no provider calls. No randomized trials or confidence interval, so do not generalize the percentages to phones or all stores.

| Notes | Workload | Before p50 / p95 ms | After p50 / p95 ms | Returned hits |
|---|---|---|---|---|
| 1,000 | exact | 20.07 / 21.82 | 16.26 / 21.78 | 1 |
| 1,000 | none | 18.40 / 19.62 | 17.51 / 18.00 | 0 |
| 1,000 | typo | 18.05 / 19.53 | 16.56 / 18.37 | 1 |
| 1,000 | bilingual | 18.94 / 20.61 | 17.24 / 17.83 | 1 |
| 5,000 | exact | 94.74 / 105.31 | 87.41 / 99.27 | 1 |
| 5,000 | none | 92.62 / 103.86 | 63.67 / 77.84 | 0 |
| 5,000 | typo | 96.07 / 106.48 | 61.29 / 64.80 | 1 |
| 5,000 | bilingual | 101.54 / 152.93 | 63.52 / 71.59 | 1 |
| 10,000 | exact | 116.26 / 140.38 | 61.56 / 63.08 | 1 |
| 10,000 | none | 97.94 / 114.70 | 59.59 / 63.50 | 0 |
| 10,000 | typo | 98.15 / 109.24 | 65.72 / 70.20 | 1 |
| 10,000 | bilingual | 103.01 / 112.84 | 64.88 / 69.62 | 1 |

At 5,000 notes, measured median changes range from 7.7% to 37.4% lower in this run. Database file sizes were unchanged: 729,088 bytes at 1k, 2,240,512 at 5k and 4,149,248 at 10k, including the existing unrelated schema tables. The 5k p95 values remain about 65–99 ms in Mac Debug; the proposed 50-ms **phone** budget has not been validated. The fallback still scans up to 5,000 eligible rows and has not become a general semantic index. Raw observations: [retrieval-benchmark.json](retrieval-benchmark.json).

### Retrieval quality diagnostic

Thirteen hand-authored synthetic queries: nine with one gold relevant note and four expected-empty cases (unknown detail, unknown school, private note and edited-away word). **Recall@5: 7/9 = 77.8%**. **Macro Precision@5 on the nine answerable queries: 15.6%**, using the literal denominator 5 even when fewer than five records are returned; precision among actually returned records was 7/7 = 100%. All four expected-empty queries returned no records. The restaurant paraphrase and cross-language jazz paraphrase were missed. These small figures are transparent diagnostics, not a production quality claim or proof that semantic retrieval is ready.

No model answer was generated, so answer correctness, hallucinated-memory rate, natural-language abstention and prompt-injection resistance of the remote LLM are **not measured**. Existing native delimiter, citation and action-gate tests are useful code-boundary evidence but cannot establish those model metrics. Results and case IDs: [retrieval-evaluation.json](retrieval-evaluation.json). Test counters/statuses: [verification.json](verification.json).

### Constitution evidence log

| Rule | Enforcing code and executed evidence | Remaining gap |
|---|---|---|
| DOD-02 / UX-04: truthful recall | Existing source records/no-match/citation checks; new `ScopedMemoryRecallTests`; 13-case diagnostic | No universal entailment/abstention guarantee for model prose; semantic paraphrases missed |
| DOD-06: controlled memory | SQL eligibility before ranking; fresh `ShareableRecallService`; recap consent epoch; suspended `MeaningIndex` tests; correction/delete/reopen tests | Account isolation, source-linked recap deletion and independent server erasure not complete |
| DOD-08: verified success | Log append/save/read-back and failed-write preservation; existing SQLite read-back; recap ledger written after save | File I/O is synchronous on main actor; no durable background extraction outbox |
| DOD-11: minimize and respect sharing | No new network processing; private-ID scope/recheck; voice fallback before limits; test-injected recap writer | Startup personal context already sent cannot be withdrawn; provider retention/remote copies unverified |
| UX-01: inspect/edit/delete | Existing note/history/settings; corrupted log reports failure and deliberate reset remains possible | Unified memory wallet across all stores/sources is proposed, not built |

### Prioritized remaining work

| Priority | Improvement | User benefit | Complexity estimate | Actual status |
|---|---|---|---|---|
| P0 | Owner-scoped local stores and legacy-data quarantine | Another account cannot inherit personal memory | High; migration/product review | Designed, not implemented |
| P0 | Source links, pending-job cancellation and verified derived/remote erasure | Forget removes active derived context accurately | High | Designed, not implemented |
| P1 | Scoped recall + lightweight row materialization | Valid notes survive privacy filters; less local retrieval work | Medium | Implemented, SQLite tests and local timings verified |
| P1 | Verified history, vector invalidation and voice recap consent | Less lost/stale/revoked memory | Medium | Implemented, package/app unit tests and final compile verified |
| P1 | Queryable consented episodic sources and personal-question abstention | Reliable “last month” recall and explicit unknowns | Medium/high | Design only |
| P2 | Calibrated EN/PL hybrid ranking and query-sensitive learned facts | Paraphrase/personalization beyond fixed keyword mappings | Medium/high | Evaluation gate defined; voice rollout not implemented |
| P2 | Projects, temporal consolidation and optional synchronization | Continuity over long activities/devices | High | Deferred |

Next engineering task: implement owner partitioning and legacy-data quarantine as its own reviewed migration, with A→B sign-in, logout, media/settings/index and pending-work tests, before widening automatic personal retrieval. Then add source-linked erasure and a queryable episode slice. Do not deploy the advanced roadmap just because the documents describe it.
