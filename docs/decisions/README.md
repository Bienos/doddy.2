# Decisions

One file per decision, named `YYYY-MM-DD-short-slug.md` (the date it was decided), cited by that name: "decision `2026-11-07-agent-rules-and-records`". There is no number to reserve, so two pull requests can't collide over one. ADR-001 to ADR-812 stay in `/DECISIONS.md` and keep their numbers; look them up there by number.

Write one only for a real product or architecture decision, or for a rule the owner sets. A bug fix doesn't need one; its pull request description is the record.

`calls.md` predates this folder and stays as it is.

## Template

```markdown
# <What was decided, as a sentence>

- **Date:** YYYY-MM-DD
- **Decided by:** owner (quote the words), or "proposal, owner approval pending"
- **Status:** proposed | accepted | applied in #PR | replaced by <file>
- **Replaces:** ADR-nnn or <file>, if any

## Why
What prompted it, with evidence (runs, files, measurements).

## Decision
What changes, precisely enough to check.

## Consequences
What gets easier or harder, cost, privacy, what to watch.

## Evidence
What was run and what wasn't.
```
