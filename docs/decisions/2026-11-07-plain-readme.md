# The root README describes the repository as it is, in plain language; the pack's original moves to the archive

- **Date:** 2026-11-07
- **Decided by:** owner, 7 Nov 2026: "readme should be done better i think better describe etc but written in easy to understand language", in a request to bring the Markdown files up to date
- **Status:** applied in this pull request once merged
- **Replaces:** ADR-072 for `README.md` and `READ_ME_FIRST.md` (pack files stay unmodified at the root). ADR-024 still holds: the imported bytes are still checked, at their new path.

## Why
- `README.md` and `READ_ME_FIRST.md` were the first pages of the documentation pack imported on 8 Oct 2026. They still said the repository was "a documentation package, not compiled code", pointed at folders deleted on 20 Oct (`VISUAL_REVIEW/`, `design/interface-v1.2/`, ADR-548) and told readers to "implement M0 only".
- `scripts/verify_imported_pack.py` checks both files byte for byte against `PACKAGE_MANIFEST.json` (ADR-024), so nobody could correct them. ADR-072 kept them that way and named the alternative: the owner can ask for in-place edits.
- GitHub shows `README.md` on the repository's front page, so it is the first thing any person or agent reads.

## Decision
1. The original `README.md` and `READ_ME_FIRST.md` move, unchanged, to `docs/archive/imported-pack/`.
2. `scripts/verify_imported_pack.py` gets a `MOVED` map and checks those two files at the new path against the same manifest entries. `PACKAGE_MANIFEST.json` and `MANIFEST.json` are not changed.
3. A new `README.md`, written for this repository, says in plain language what Doddy is, what works today, how the parts fit together, how to build and test, and where to read more. Like `STATUS.md`, it is kept to facts that are true now; its "Where things stand" section points at `STATUS.md` instead of repeating it.
4. `READ_ME_FIRST.md` stays at the root as a short pointer, because the opening lines of `AGENTS.md` and `CLAUDE.md` (append-only, ADR-178) still name it.

## Consequences
- The front page matches the code. Old links to `README.md` sections from the pack land on the new page; the pack's text is one click away in the archive.
- Whoever changes what the app or the servers do should check the README's "What Doddy can do today" list in the same pull request, as for the platform pages.
- The other pack files (`docs/00_START_HERE/`, `docs/product/`, `docs/implementation/MILESTONES.md`, `prompts/` and so on) stay where they are, byte for byte, as the October plan.

## Evidence
`python3 -I scripts/verify_imported_pack.py` passes with the files moved (70 files). With one byte appended to `docs/archive/imported-pack/README.md` it fails with `hash/size mismatch: README.md`, so the original is still protected. `scripts/ci.sh --only checks` results are in the pull request.
