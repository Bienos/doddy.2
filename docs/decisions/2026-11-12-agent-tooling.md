# Coding agents: remove (or pin) the Composio skill, and give routine sessions read-only access to the consoles

- **Date:** 2026-11-12
- **Decided by:** proposal, owner approval pending. Agent configuration is the owner's decision.
- **Status:** proposed — waiting for the owner. No file under `.claude/` or `.agents/` and no connector is changed by this file.
- **Replaces:** nothing. Applies the rule in `CLAUDE.md` ("Prompts describe rules; code enforces them") to the agents that work on this repository.

## Why
- **The Composio skill should be removed, or pinned.**
  - `.claude/skills/composio` links to `.agents/skills/composio/`. It was added on 10 Oct 2026 with `npx skills` (commit `55fc412c`), and `skills-lock.json` records its source (`ComposioHQ/composio`) and a hash.
  - Its references include install lines for the Composio CLI that fetch and run an installer script (`.agents/skills/composio/references/for-you.md` and `references/platform.md`, the "install" blocks). Installing tools is the owner's step, from a pinned release, not something a skill in the repository should tell an agent to do.
  - Its description matches any task that mentions Gmail, Calendar, Notion and similar apps, which Doddy's own code does often (`backend/src/tools/`).
  - Doddy's product doesn't need it: the backend uses Composio through the pinned `@composio/core` package (`backend/src/providers/composio.ts`).
- **Routine coding sessions should have read-only access to the consoles.** `AGENTS.md` ("Live systems and data") lets agents read Render, Vercel, Supabase and ElevenLabs and leaves every change there to the owner's instruction. Read-only access makes that rule hold by construction, as Doddy's own code does for its rules.

## Decision (proposed)
1. **The Composio skill: remove it (proposed), or pin it.**
   - **Remove:** delete `.claude/skills/composio`, `.agents/skills/composio/` and its entry in `skills-lock.json`. Someone who needs it for Composio work installs it in their own session, not in the repository.
   - **Pin, if the owner wants to keep it:** keep the checked-in copy as the only one (no `npx skills` update without a pull request). Replace the two install blocks with "the owner installs the Composio CLI from a pinned release after checking its checksum; agents don't install it". Narrow the description to Composio work only.
   - **Either way:** a check in `scripts/ci.sh --only checks` fails on any line that pipes a download into a shell, in `.agents/`, `.claude/`, `scripts/` and `docs/`.
2. **Routine coding sessions get read-only console access.** Render, Vercel, Supabase and ElevenLabs are reachable for reading (logs, deploy state, settings' names, agent versions), and their writing tools are not available.
   - Where a console offers it, use a read-only credential or mode. Supabase's MCP server documents a read-only mode; ElevenLabs keys can be restricted per feature. To be checked in each console.
   - Where none exists on the current plans, the writing tools are denied by name in the agent's settings. Two ways: `permissions.deny` in `.claude/settings.json` for Claude Code, with the matching setting for Codex, or the owner's own per-session connector choice.
   - Example names, to be checked against the session's tool list before use: `mcp__Render__update_environment_variables`, `mcp__Render__trigger_deploy`, `mcp__Vercel__create_project_env`, `mcp__Vercel__edit_project_env`, `mcp__Supabase__apply_migration`, `mcp__Supabase__execute_sql`, `mcp__ElevenLabs__agents_update`.
3. **Console work the owner asks for** (a deploy, a setting, an agent sync) runs in a session the owner opens for that purpose, with write access, and records what it did as today (`voice-agent/README.md`, `docs/OWNER_QUEUE.md`).

## What the owner decides
1. The Composio skill: remove (proposed) or pin.
2. Yes or no to read-only console access for routine sessions, and for which consoles.
3. How it is enforced: read-only credentials in the consoles, deny rules checked into `.claude/settings.json` (they apply to every session opened in this repository, the owner's included), or the owner's connector settings per session.
4. Yes or no to the CI check against pipe-to-shell lines.

## Consequences
- Routine work can't change a live service by mistake. Console changes take one deliberate step more.
- Deny rules in the repository are visible and reviewed like code. A read-only credential holds even outside this repository. Whether a deny rule in project settings can be lifted by a person's own settings must be checked in Claude Code's documentation before relying on it.
- Without the skill, an agent working on Composio reads Composio's documentation directly. The product's integration is unchanged.

## Evidence
- Read: `.claude/settings.json`, `.agents/skills/composio/SKILL.md` and its three references, `skills-lock.json`, `git show --stat 55fc412c`, `backend/src/providers/composio.ts`, `scripts/ci_groups.sh`, `AGENTS.md`.
- Searched the repository for install lines that pipe a download into a shell: only the two above.
- Not checked: which read-only options each console offers on the owner's plans; no connector or setting was changed.
