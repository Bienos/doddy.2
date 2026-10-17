# Copy/paste into Claude Code at the `Bienos/doddy.2` root — Research: how Doddy can use 1Password

You are researching, not building. The question is **how Doddy should use 1Password**: first to keep the project's own secrets (API keys, signing keys, tokens) in one place, and second whether the Doddy app should ever touch a user's 1Password. Your only output is one report file and a short summary. Change no code, config, host or account.

Read first: `CLAUDE.md`, `STATUS.md`, `BUILD_AND_TEST.md` ("Secrets and signing"), `docs/integrations/SECURITY_AND_PERMISSIONS.md` ("Secrets and tokens"), `docs/integrations/DEPLOY_RENDER.md`, `docs/trust/config/doddy_rules.yaml` (`raw_secrets_in_model_prompt_or_logs: forbidden`), `docs/trust/04_ENFORCEMENT_ARCHITECTURE.md` ("Privacy/data security"). Search `DECISIONS.md` for ADR-067, 079, 123, 149, 155, 247, 254, 265, 328 (`grep -n "| 328 |" DECISIONS.md`); don't read it whole.

## Hard rules
- **Never see, print, copy or log a secret value.** Don't open `.env`, `.env.local` or any ignored env file. Don't run `op read`, `op item get --reveal`, `vercel env pull` or anything that shows a value. Work from variable **names** only (the `.env.example` files, `render.yaml`, READMEs).
- Don't sign up, sign in, install 1Password, create vaults, change host settings or set secrets. If a dashboard or MCP tool (Render, Vercel, Supabase) can list env var **names** without values, you may use it; if it would return values, skip it and say so.
- Use 1Password's official docs (developer.1password.com / 1password.dev, the `1Password/*` GitHub repos, the 1Password blog) and each host's official docs. Your training data is older than today: check current pages. Give the URL and the date you read it for every claim. Mark beta features as beta. Keep "verified in docs" separate from "my inference".

## Part 1 — Inventory (names only)
Build a table of every secret the project uses today. Columns: variable name, service (`backend/`, `server/messaging/`, `server/voice-token/`, `gateway/`, `site/`, ElevenLabs agent tools, iOS app), where the code reads it, where it lives today (Render service or env group in `render.yaml`, Vercel project, Supabase function `voice-token` in project `doddy-gateway`, Render `doddy-voice-token`, local `.env.local`, GitHub Actions, iOS Keychain), who needs it (server at runtime, build, CI, a developer locally, a Claude agent session), and **what breaks if it is rotated** (for example `MEMORY_ENCRYPTION_KEY` makes stored memories unreadable, `DODDY_SESSION_SIGNING_KEY` signs everyone out, `PICOVOICE_ACCESS_KEY` lives on phones). Also list the non-env secrets: APNs `.p8` key, Apple signing, Picovoice keyword file, Composio and ElevenLabs dashboard logins. Say which hosts are actually live today and which you couldn't confirm.

## Part 2 — What 1Password offers, checked against current docs
For each, say what it does, which plan it needs, limits (rate limits, number of service accounts, vault access rules), cost, and whether it's GA or beta:
- 1Password CLI `op`: secret references `op://vault/item/field`, `op run --env-file`, `op inject` for templates.
- Service accounts: scoping to vaults, read-only vs write, token storage, revocation, audit trail.
- 1Password Connect server: when it's better than service accounts (probably not for a team this size, but say why).
- SDKs (JavaScript in particular, since every Doddy server is Node).
- 1Password Environments (beta): mounted local `.env` files, sharing, the documented sync destinations.
- GitHub Actions: `1password/load-secrets-action` (current major version, pin by commit SHA) and Workload Identity (OIDC, no stored token). Check which plans support it.
- Developer extras worth having or not: SSH agent, Git commit signing, shell plugins.
- AI agents: 1Password's guidance and any official MCP server for coding agents, and whether a Claude Code cloud session could use `op run` safely (would a service account token in the session's environment let an agent read the whole vault? how narrow can that vault be?).

## Part 3 — Fit for each host
For Render, Vercel, Supabase Edge Functions, GitHub Actions, a developer's Mac (Xcode + Node servers), and Claude Code cloud sessions, answer: is there a native 1Password integration (as far as the docs show)? If not, compare:
1. **Push at deploy time:** a script reads from 1Password and writes to the host's env settings through its API or CLI.
2. **Fetch at boot:** the server uses the SDK and a service account token to read secrets when it starts.
3. **Manual:** 1Password is the record; a person copies values into the dashboard.
For each, cover: where the service account token itself has to live, what happens when 1Password is down, fail-closed behaviour, rotation steps, and blast radius if the token leaks. Recommend one per host.

## Part 4 — The iPhone app and users
- Confirm the app should stay with **no secrets in the bundle** (BUILD_AND_TEST says it needs none; the Picovoice key arrives from the token server at runtime, ADR-328). Should anything about the app build use 1Password (signing, APNs key, a future xcconfig)?
- Doddy for users: is there any supported way for an iOS app to read from a user's 1Password (public API, App Intents, AutoFill/credential provider extensions, URL schemes)? Even if there is, check it against the constitution: Doddy never offers passwords or PINs as notes (ADR-247), raw secrets are forbidden in the model prompt and logs, and everything said to Doddy may reach a voice provider. Give a clear yes/no/not-now with reasons. Also say whether 1Password as a passkey/password provider affects Doddy's own sign-in.

## Part 5 — Recommendation
- Vault layout (for example one vault per environment, or per service), item naming, and who or what gets access to each.
- A phased migration plan, smallest first, each phase with its rollback.
- What a committed `op://` reference reveals (vault and item names) and whether those templates should be committed.
- Cost per month at Doddy's size, and any plan upgrade required.
- Risks and how to limit them.
- **Decisions for the owner**, each as a question with your recommended answer.
- A draft ADR paragraph in the repo's style. Put it **only in the report**, not in `DECISIONS.md`.

## Output and stop
Write `docs/research/1PASSWORD_SECRETS_2026-10.md` with the five parts, a "Sources" list (URL + date read), and "What I could not verify". Commit it on your working branch with a clear message and push. Then reply with the recommendation in five lines, the owner decisions, and the path to the report. Don't start building. The build prompt is `prompts/1PASSWORD_BUILD.md`.
