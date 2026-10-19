# Copy/paste into Claude Code at the `Bienos/doddy.2` root — Build: Doddy's secrets in 1Password

You are the engineer moving Doddy's project secrets into 1Password, so there is one record of every key and a safe, repeatable way to get them onto each host. This is developer and deployment tooling. **The iPhone app gets no 1Password code and no secrets.** The servers keep reading plain environment variables exactly as today, so tests stay offline and nothing at runtime depends on 1Password.

## Before anything
1. Read `CLAUDE.md`, `STATUS.md` and the research report `docs/research/1PASSWORD_SECRETS_2026-10.md` (from `prompts/1PASSWORD_RESEARCH.md`). **If the report is missing, stop and say so.**
2. Find the owner's answers to the report's "Decisions for the owner": plan, vault layout, which hosts are in scope, push-at-deploy vs fetch-at-boot, whether CI gets secrets. If any answer is missing, use the report's recommended answer, list it under "Assumed", and keep that part dry-run only.
3. Inventory: branch, `git status`, Node and Swift versions, whether `op` is installed (it usually won't be in a cloud session, and you can't sign in to 1Password from one; that's expected). Run `scripts/ci.sh --core-only` once as a baseline and keep the output. (On 2026-10-17 the capability guard already failed before this work: networking and `AuthenticationServices` in `DoddyApp/Features/Voice/VoiceAuthSession.swift` and `VoiceAccessGate.swift`. Don't fix that here; just don't add new failures.)
4. Search `DECISIONS.md` for the latest ADR number (`grep -n "^| 4[0-9][0-9] |" DECISIONS.md | tail -1`); don't read it whole.

## Non-negotiables
- **You never see a secret value.** Don't run `op read`, `op item get --reveal`, `vercel env pull`, or print a resolved environment. Don't open ignored `.env*` files. Tests use made-up values only.
- Values are never committed, logged, written to disk in plain text, put in command-line arguments (where `ps` can see them) or sent to a model. Pass them over stdin or the host API body, and redact them in every error path.
- Pushing secrets to a host is an external write (constitution): show the exact plan first (target, variable name, add/change/remove, a short fingerprint of the value, never the value), require an explicit confirmation bound to that plan, report "done" only when the host API confirms, treat a timeout as `unknown` (never success, never retried blindly).
- Don't rotate or regenerate any existing secret. `MEMORY_ENCRYPTION_KEY` and `DODDY_SESSION_SIGNING_KEY` are especially dangerous: a wrong value makes stored memories unreadable or signs everyone out. Rotation is a written runbook, run by the owner.
- No 1Password SDK in the servers unless the owner chose fetch-at-boot. No changes to the live ElevenLabs agent, no deploys, no new paid plan.

## Phase A — Design (stop for review if the owner hasn't approved the report)
- `docs/security/SECRETS_1PASSWORD.md`: vault layout, item and field naming, which person, service account or CI job can read which vault, how each host gets its values, rotation runbook per secret (with what breaks), break-glass if 1Password is unavailable, and offboarding a person.
- An ADR at the next number: 1Password is the record of project secrets; hosts keep env vars; the app has none; how agents interact (never see values).

## Phase B — One manifest, templates per service
- `secrets/manifest.yaml`: every secret by name, its `op://` reference, the services that read it, and its targets (Render service or env group from `render.yaml`, Vercel project and environment, Supabase function secret), plus `rotation_impact`. Variables that are config, not secrets (limits, ports, model ids), stay out.
- Per-service templates (`backend/.env.op`, `server/messaging/.env.op`, `server/voice-token/.env.op`, `gateway/.env.op`) holding only `op://` references, for `op run --env-file=… -- npm start`. Add `npm run dev:op` (or a `make` target) per service. Keep every `.env.example` as it is; the plain `.env.local` route still works.
- Decide per the report whether templates are committed (they reveal vault and item names, not values). Update `.gitignore` so nothing `op inject` writes can be committed.

## Phase C — Sync tool (dry-run by default)
- `tools/secrets/sync.mjs` (Node 22, no new dependencies unless the report justifies one): reads the manifest, reads values through `op` with a service account or the signed-in user, reads the **names** already set on each host, and prints the plan. `--apply` asks for typed confirmation of that exact plan, then writes through each host's API or CLI. One result per target and name: `set`, `unchanged`, `failed` (with a redacted reason) or `unknown`.
- Flags: `--service`, `--target`, `--env development|production`. Never remove a host variable unless `--prune` is passed and that removal is in the confirmed plan.
- Hosts with no API access or no owner decision stay dry-run, and the tool says so.

## Phase D — CI (only if the owner approved a job that needs secrets)
Today `.github/workflows/ios.yml` uses no secrets (ADR-123); keep it that way unless approved. If approved: `1password/load-secrets-action` pinned by commit SHA, Workload Identity if the plan supports it (else `OP_SERVICE_ACCOUNT_TOKEN` as a repository secret), a read-only service account limited to one CI vault, the step only on `workflow_dispatch` or the default branch (never on pull requests from forks), and masked output.

## Phase E — Guards and tests
- Extend `scripts/check_forbidden_capabilities.sh` (or add a check under `scripts/checks/` wired into `scripts/ci.sh`): no `op://`, 1Password SDK or `op` calls in any app target (`DoddyApp`, `Shared`, widgets, Watch, Mac, `Packages/DoddyCore/Sources`); `.env.op` files and the manifest contain only `op://` references, never key-shaped strings; every name in each `.env.example` is either in the manifest or listed as not-a-secret.
- Tests for the sync tool with a fake `op` binary on `PATH` and fake host clients (no network): manifest validation (duplicates, malformed references, unknown Render service or group against `render.yaml`); a planted canary value never appears in stdout, stderr or thrown errors; dry-run makes zero writes; `--apply` without matching confirmation writes nothing; partial failure reports each target separately; a timeout is `unknown`; a second run is all `unchanged`.
- Run them, then `scripts/ci.sh --core-only`, and paste real output. Compare with the baseline.

## Phase F — Docs
Update `BUILD_AND_TEST.md` ("Secrets and signing"), `docs/integrations/SECURITY_AND_PERMISSIONS.md` (secrets table), `docs/integrations/DEPLOY_RENDER.md`, the README of each server, the comment at the top of `render.yaml`, and `STATUS.md` "Waiting on the owner" (create vaults, add the service account, run the first sync).

## Out of scope
A user-facing 1Password feature in the app (reading users' passwords, AutoFill hooks). If the report recommended one and the owner approved it, it needs its own milestone, ADR and prompt. Also out: moving hosts, changing auth, rotating keys, deploying.

## Report and stop
Small commits on your working branch, pushed. Then report: files changed; what works now versus dry-run-only versus blocked on the owner; the exact commands you ran with output; what you could not run (anything needing a 1Password sign-in or host credentials is **NOT RUN**, and the owner's first-run steps are listed in order); the constitution evidence log (rule IDs such as DOD-07 and `raw_secrets_in_model_prompt_or_logs`, the enforcing code, tests, gaps, claims to limit); security risks (where the service account token lives, blast radius); decisions still open. Never write "secrets are secure" or "migrated" for anything not run against the real vault and hosts.
