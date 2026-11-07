# Change notes

Each pull request adds one short note here, so nobody has to edit `STATUS.md` in a feature pull request (decision `docs/decisions/2026-11-07-agent-rules-and-records.md`).

- **File name:** `changes/<branch-or-short-slug>.md`. One file per pull request, so two pull requests never touch the same file.
- **Content:** two to five lines:
  - what changed for the user or the team;
  - the decision file or ADR, if any;
  - what was run, and what wasn't;
  - anything that needs a deploy or an owner step.
- **Folding:** whoever next updates `STATUS.md` folds the notes in and deletes them in the same pull request. That is the owner, or a session asked to do it; later the release workflow writes them into the TestFlight notes.

Example, `changes/ui-smoke-on-prs.md`:

```markdown
CI: pull requests run the UI smoke classes; every push to main runs the whole UI suite (ADR-811).
Ran: scripts/ci.sh --only checks; a dry run with fake Xcode tools. Not run: the hosted Mac job (this PR's run is the first).
```
