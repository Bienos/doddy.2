# M6 — Learning loop: status
Status: **Phase B built and Linux-tested; Phase C not started.** ADR-324. Owner on 2026-10-11: "use your proposed defaults and start Phase B" — the six decisions in the design doc §12 are accepted as proposed. `docs/implementation/MILESTONES.md` is an imported pack file (byte-locked by `scripts/verify_imported_pack.py`), so this milestone lives here, like M4a, S1 and N1.

**Place in the sequence:** after M2 (real text model), M4 (real actions) and the M5 beta decision, so learning does not confound the beta's retention measurement. Owner may instead run it inside M5 with a control group (design doc §12, decision 5).

**Goal:** Doddy gets better for one person as **data, never code**: verified facts confirmed word for word, procedures as saved plan templates over the existing ADR-204 allowlist with every step still approved on the plan card, outcome events without user text, capability gaps as local categories. Design: `docs/architecture/LEARNING_LOOP.md`.

**Phases**
- A — design review: `LEARNING_LOOP.md`, ADR-324, schema proposal, policy map. Done 2026-10-11; defaults accepted by the owner the same day.
- B — typed core (`Packages/DoddyCore/Sources/DoddyCore/Learning/`), migrations `v11`–`v13` and three SQLite repositories with read-back (`Packages/DoddyCore/Sources/DoddyPersistence/SQLite{LearnedFact,Procedure,OutcomeEvent}Repository.swift`), Linux tests. **Built 2026-10-11.** The defaults live in `LearningLimits.standard` (3 proposals a day, 1 per conversation, 7-day proposal expiry, 90-day procedure retirement, 90-day outcome retention), `LearnedFactKind.expiryDays` (preference 365, routine 180, fact/person/place none with review after 365) and `SensitiveContentFilter`.
- C — proposal cards, "What I've learned" screen (list, edit, delete, export, "That's wrong"), procedure runs through the plan card, gap counts, `note_capability_gap` agent tool if approved. Not started. Model proposer only if the gateway path is confirmed live; otherwise `Unavailable*`.

**Metric:** user corrections per week, computed locally from `outcome_events` of kinds `corrected`, `redone` and `cancelled`. **Baseline needed:** two weeks with learning off (owner's own use or the beta) before any "gets better" claim.

**Exit:** save → restart → read back for facts and procedures; delete reaches the FTS tables and the next request; a hand-edited procedure row cannot skip an approval card or use an off connection; a sensitive sentence is never proposed; the same evidence is never proposed twice; corrections per week on a device compared with the baseline. No cloud, sync, embeddings, telemetry or new providers.

**Evidence (Phase B, 2026-10-11, Linux x86_64, Swift 6.1 release toolchain downloaded into the session, same version as CI's `swift:6.1-noble`):**
```
$ swift test --package-path Packages/DoddyCore -Xswiftc -DSQLITE_DISABLE_SNAPSHOT -Xlinker --allow-shlib-undefined --filter "LearningTests|SQLiteLearningRepositoryTests"
Executed 19 tests, with 0 failures (0 unexpected)   # LearningTests
Executed 12 tests, with 0 failures (0 unexpected)   # SQLiteLearningRepositoryTests
Executed 31 tests, with 0 failures (0 unexpected)
```
Full package and guards, same session:
```
$ swift test --package-path Packages/DoddyCore -Xswiftc -DSQLITE_DISABLE_SNAPSHOT -Xlinker --allow-shlib-undefined
Executed 801 tests, with 0 failures (0 unexpected) in 14.391 seconds
$ scripts/typecheck_app_logic.sh        PASS: 18 app files type-check
$ python3 -I scripts/verify_imported_pack.py   PASS: 259 imported pack files match
$ scripts/check_forbidden_capabilities.sh      PASS
``` What the tests cover: v10 → v13 upgrade of an existing file keeps its notes; propose → confirm (exact text only, once) → reopen → read back; preference/routine expiry, "still true?" reconfirm, revise with history, retire; delete and delete-all reach the FTS tables and the revisions; Polish diacritics found with and without accents; conflicting facts both returned; same evidence refused twice, "never this" sticks, unanswered proposals pruned; procedure confirm/use/edit (version 2)/retire-unused/revive/delete; a hand-edited row claiming `"approval":"none"` still shows the card and a row naming `open_map` is reported corrupt; outcome events record, count, prune, export with no text; parser refuses keys outside the contract; policy caps, pause, sensitive mode, sensitive text (EN/PL), tool allowlist and off-tools; assembler budget, scope, pause and status.

**NOT RUN:** the iOS app (no Xcode here); nothing in Phase B is shown on a screen yet. **Not claimed:** that Doddy learns anything on a device. No proposer runs, no card exists, and nothing calls these repositories from the app.
