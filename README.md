# Doddy

**Your mate in your pocket.** A voice-first AI companion for iPhone and iPad, with explicit, source-grounded memory. Doddy is an AI character, not a person.

This repository is the working product repo (`Bienos/doddy.2`). `Bienos/AI-AGENT-DODDY` is the old repo and is read-only.

## Start here
- **[STATUS.md](STATUS.md):** one page on what is live, what is open and what waits on the owner. It is the source for "what is true now".
- **[BUILD_AND_TEST.md](BUILD_AND_TEST.md):** commands and CI.
- **Agents (Claude Code, Codex):** [AGENTS.md](AGENTS.md) (`CLAUDE.md` imports it). Read its last section, "Current working rules", first. It wins over older lines.

## Build and test
- Any OS: `make test-core` (Swift package tests), or `scripts/ci.sh --only checks|swift|backend|node|messaging`.
- Mac with Xcode: `make project`, then scheme `Doddy` (specs `project.yml` and `project-iphone.yml`), or `scripts/ci.sh`.
- Generated files (string catalogs, site pages, blog, web assets, tokens): never merge by hand. Run `scripts/regen.sh`, then `scripts/ci.sh --only checks`.
- Apple Watch (`project-watch.yml`) and Mac (`project-mac.yml`) are **paused** (ADR-572). Do not build or change them unless the owner re-enables them.

## What is where
| Folder | Contents |
|---|---|
| `DoddyApp/`, `Shared/`, `Packages/` | iPhone app and shared Swift code |
| `DoddyTests/`, `DoddyUITests/` | App unit and UI tests |
| `backend/`, `web/` | Phone backend and Doddy Web |
| `server/`, `gateway/` | Messaging and other servers |
| `voice-agent/` | Voice agent spec and token server |
| `site/`, `blog/` | Website and blog |
| `design/` | Current design (ADR-548) and brand V2.2 (ADR-556) |
| `docs/` | Product, architecture, platform pages, trust rules, decisions |
| `changes/` | One short note per pull request |
| `reference/`, `docs/archive/`, `prompts/` | History and evidence. Not instructions. |

## Rules that always apply
- **Constitution:** `docs/trust/` and `docs/trust/config/doddy_rules.yaml` govern behaviour, memory, actions, privacy and character. A model proposes, typed code validates, scoped tools execute. Start at `docs/trust/REPO_ALIGNMENT.md`.
- **No fake completion.** Memory, preferences, actions and audio are "saved" or "done" only after a verified storage operation or trusted provider confirmation. Mock, design or unbuilt work is never called implemented or tested.
- **No secrets** in files, logs or pull requests. No font binaries.
- **Live systems** (Render, Vercel, Supabase, ElevenLabs, Twilio, App Store Connect): read only. Write the change you need into the pull request or `docs/OWNER_QUEUE.md`.

## Decisions and records
- Decisions: `DECISIONS.md` holds ADR-001 onward. Search it by number, never read it whole. New decisions go in `docs/decisions/` (see its README).
- Feature pull requests do not edit `STATUS.md` or `DECISIONS.md`. Add `changes/<slug>.md` instead (see `changes/README.md`).
- `main` is the only permanent branch. One topic per branch and pull request. The owner merges.

`READ_ME_FIRST.md` is the original consolidated design and engineering brief. Parts of it are history; where it conflicts with `AGENTS.md`, `AGENTS.md` wins.
