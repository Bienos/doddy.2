# Agents work from one current rule set, and shared ledgers stop being the coordination layer

- **Date:** 2026-11-07
- **Decided by:** owner, 7 Nov 2026: "do all", for the plan in the engineering audit of the same day (the second of its first five pull requests)
- **Status:** applied in this pull request once merged
- **Replaces:** the practice, from ADR-457 onwards, of adding a row to `DECISIONS.md` and a paragraph to `STATUS.md` in every pull request; the reservation of ADR numbers in `STATUS.md`

## Why
- **Constant conflicts.** In one month `DECISIONS.md` (778 KB) changed in 462 commits and `STATUS.md` (138 KB, meant to be one page) in 180. Across branches, 97 commits exist only to renumber ADRs and 195 merge the default branch back into a feature branch. Two pull requests almost always conflicted on those two files even when their code didn't touch.
- **Expensive sessions.** Every session was told to read `STATUS.md` first. With `CLAUDE.md`, `AGENTS.md` and a platform page, that came to about 175 KB (about 45k tokens) before any code.
- **Stale rules.** `CLAUDE.md` and `AGENTS.md` are append-only (ADR-178), so they still open with superseded rules (the Pocket Notebook design, "implement M0 only"). Later sections overrule those, but a reader has to reconcile them.
- **Hand-merged generated files.** The 3 MB string catalog changed in 186 commits.

## Decision
1. `AGENTS.md` gets a final section, "Current working rules — read this section first", which wins over older lines. `CLAUDE.md` imports it (`@AGENTS.md`). Both files stay append-only; the imported pack check still passes.
2. `STATUS.md` is one page of current facts. Its log up to 7 Nov 2026 moves, unchanged, to `docs/archive/STATUS-log-2026-10-08-to-2026-11-07.md`.
3. New decisions are files in `docs/decisions/` named by date and slug. `DECISIONS.md` keeps ADR-001 to ADR-812 for lookup and takes no new rows.
4. Each pull request describes its change in a note in `changes/`. Whoever next updates `STATUS.md` folds the notes in and deletes them.
5. `scripts/regen.sh` regenerates every generated file. It is used instead of hand-merging them.

## Consequences
- Parallel pull requests stop conflicting on bookkeeping.
- Sessions start with about a tenth of the reading.
- Someone has to fold `changes/` notes into `STATUS.md` now and then (the owner, or a session asked to). Until the release workflow does it, status can lag by a few merges.
- Old links into `STATUS.md` sections ("Known problems", "Not merged yet") now point at the archive file. Those sections are history there.

## Evidence
`python3 -I scripts/verify_imported_pack.py` passes (70 files; `AGENTS.md` and `CLAUDE.md` keep their imported prefix). `scripts/regen.sh` on a clean checkout of `main` changed no file. `scripts/ci.sh --only checks` passes.
