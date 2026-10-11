# Code review first, then optimise — with a token budget

Paste this whole prompt into Claude Code at the `Bienos/doddy.2` root. It works in two phases: **Phase 1 is read-only**, and **Phase 2 only starts after the owner approves it**.

---

## Role and limits

You are reviewing DODDY V2. `CLAUDE.md`, `AGENTS.md` and `docs/trust/` still apply. In particular:
- `Bienos/AI-AGENT-DODDY` stays read-only.
- Don't add features, providers or infrastructure.
- Never write "tested" or "passed" for a check you didn't run.

## Token rules (follow throughout)

1. **Don't open these:** `reference/`, `design/` (except `design/interface-v1.2/docs/*.md` when it's needed), `VISUAL_REVIEW/`, `site/`, `blog/`, `assets/`, `*.png|jpg|pdf|pptx|mp4`, `package-lock.json`, `Package.resolved`, `node_modules/`, `.build/`. Together they're over 70 MB and none of it is code to review.
2. **Search before you read.** Use `grep -n` / `rg` to find a symbol, then read only that line range (`sed -n 'A,Bp'` or Read with an offset and limit). Read a whole file only when it's under ~300 lines and you're reviewing all of it.
3. **Don't re-read.** If you've seen a file, rely on what you noted. Don't print a file back to check an edit.
4. **Fan out cheaply.** For a broad search, start one Explore subagent per area and ask for conclusions only (file:line + one sentence), never file dumps.
5. **Keep outputs short.** Pipe test and build output through `tail -40` or `grep -E 'error|fail|warn'`. Don't paste full logs into chat.
6. **Write findings to a file,** not chat: `docs/quality/REVIEW_<area>_<date>.md`. In chat, send only a 5-line summary and the path.
7. **One area per session.** Then `/clear` (or start a new session) and resume from the findings file.

## Phase 1 — Review (read-only, no edits)

Review **one area at a time** in this order, and stop after each one:

| # | Area | Path | How to run its checks |
|---|------|------|-----------------------|
| 1 | Swift core | `Packages/DoddyCore` | `make test-core` |
| 2 | iOS app + widgets + watch | `DoddyApp`, `DoddyWidgets`, `DoddyWatch`, `Shared` | `make ci-core` (if there's no Xcode, report the native build as **NOT RUN**) |
| 3 | Messaging server | `server/messaging` | `npm test` in that directory |
| 4 | Gateway | `gateway` | `npm test` |
| 5 | Backend | `backend` | `npm test` |
| 6 | Voice token / voice-agent | `server/voice-token`, `voice-agent` | `npm test` where it exists |

For each area, report findings ranked **critical → minor**, each one as `file:line — problem — concrete failure scenario — proposed fix (≤3 lines)`. Look for:

- **Correctness:** logic bugs, unhandled errors, race conditions, a `unknown` result treated as success, blind retries of external writes.
- **Constitution:** memory or preference claims without a verified storage operation, external writes without exact-payload approval, tool or web content treated as instructions, mocks presented as real (`docs/trust/config/doddy_rules.yaml`; cite rule IDs).
- **Security and privacy:** secrets in client code or the repo, missing auth or tenant checks, injection, SSRF (`news/safeFetch.ts`), PII in logs.
- **Duplication and dead code:** repeated helpers across `server/`, `backend/` and `gateway/`, unused exports and files, stale TODOs.
- **Efficiency:** N+1 queries, unbounded loops or fetches, missing indexes, polling where an event would do.
- **Tests:** important paths with no test, tests that assert nothing, and flaky timing.

Also record: the commands you ran, their exit codes, and what you couldn't run and why.

**End of Phase 1:** list the top 10 fixes across all areas, with effort (S/M/L) and risk. Then **STOP and wait for owner approval.**

## Phase 2 — Optimise (only the items the owner approved)

- One approved item per commit, with the smallest diff that fixes it, plus a test that would have caught it.
- Run that area's checks before and after the change, and report both results.
- No drive-by refactors, renames or formatting churn, and no new dependencies without approval.
- Update the findings file: mark each item `fixed (commit sha)`, `skipped (why)` or `needs decision`.
- End with the milestone report required by `CLAUDE.md` rule 10, including the constitution evidence log.

---

## Using fewer tokens on Doddy in general (for the owner)

- **Scope every request.** "Review `server/messaging/src/outbox.ts` for retry bugs" costs a small fraction of "review the code".
- **Start a new session per task** (`/clear`). Long chats re-send all earlier context on every turn. Use `/compact` when you must continue.
- **Block reads of large folders.** Add a deny list to `.claude/settings.json` so Claude can't wander into them:
  ```json
  { "permissions": { "deny": ["Read(./reference/**)", "Read(./VISUAL_REVIEW/**)", "Read(./design/**/*.png)", "Read(./site/**)", "Read(./**/package-lock.json)"] } }
  ```
- **Keep `CLAUDE.md` short.** It loads on every turn. Move long rules into the docs it links to, and keep only the must-follow lines.
- **Use findings files as memory.** Point a new session at `docs/quality/REVIEW_*.md` instead of re-explaining.
- **Pick cheaper models for grunt work.** Use a smaller model or lower effort for searching and listing, and save the top model for design decisions and tricky bugs.
- **Ask for diffs, not full files,** and for summaries, not logs.
- **Don't mix milestones.** One milestone, one area and one PR keep the context small.
