# How Doddy can use 1Password (research, October 2026)

Research run from `prompts/1PASSWORD_RESEARCH.md` on 17–18 October 2026. Nothing was built, installed, signed up for or changed on any host. No secret value was opened: the inventory uses variable **names** only, and the hosts were checked by listing projects and functions, never their environment variables. 1Password's developer docs have moved from developer.1password.com to www.1password.dev (old links redirect). Every claim below was checked against the current page, listed under Sources. **[inference]** marks my own reasoning rather than something a vendor states.

## The answer in five lines
1. **Use 1Password as the one record of Doddy's project secrets, and keep the hosts' environment variables as what the servers read.** A small script on the owner's Mac reads from 1Password and pushes to Vercel, Supabase and (once deployed) Render, after showing the exact plan and getting a yes.
2. **No 1Password token on any server, in CI or in Claude sessions.** No host has a native 1Password integration, fetching at boot would make every cold start depend on 1Password, and a token in an agent's environment lets the agent read every secret it can reach.
3. **Plan:** Business with one seat ($8.99/month billed yearly) if the owner wants the audit log and room for a second person; the owner's existing Individual account works for the first phases. Nothing else costs money: no Connect server, no Credential Broker.
4. **The app stays with no secrets.** Doddy can't read a user's 1Password (there is no API for that on iOS), and a "read my password aloud" feature would break Doddy's own rules. Don't build it.
5. **Go slowly with two keys:** `MEMORY_ENCRYPTION_KEY` (changing it makes stored memories unreadable) and the voice server's `DODDY_SESSION_SIGNING_KEY` (changing it signs everyone out). Record them in 1Password first, and never rotate them as part of the move.

**Built 18 Oct 2026 (ADR-493).** The manifest, `.env.op` templates, sync tool and checks are in. The owner's guide is `docs/security/SECRETS_1PASSWORD.md`. They've been tested against fakes only; the owner's first run is still to do.

## Owner answers (18 Oct 2026)
- **Plan:** Individual ($3.99/month). Move to Business later if a second person needs access or an access history is wanted.
- **Old Supabase functions:** save the code, then delete them. Code saved in `docs/archive/supabase-functions-2026-10-18/`. The `voice-token` handler there is identical to `server/voice-token/src/handler.js` at `d6ece5d`. The owner deletes both functions and their secrets in the Supabase dashboard, because Claude's tools here can't delete functions. Steps are in that folder's README.
- **Render:** deployed. Four services in the owner's one workspace, listed below.

## Found along the way (fix these whatever happens with 1Password)
- **`render.yaml`'s environment group won't ask for its secrets.** All 18 keys in `doddy-messaging-secrets` are `sync: false`. Render's Blueprint spec says: "You can't apply `sync: false` to environment variables defined in an environment group", and Render then ignores them. It also prompts for `sync: false` values "only during the initial Blueprint creation". The file's header comment ("Render then asks for every variable marked `sync: false`") is therefore wrong for the messaging server. Its secrets would have to be added by hand or by API after the Blueprint is created. (Verified on render.com/docs/blueprint-spec, 18 Oct.)
- **Render's API always returns secret values.** Listing a service's variables or an environment group returns `{key, value}`, and even a write to one group variable returns the whole group with values. So a Render API key can read every Render secret in every workspace the owner belongs to. It must live only in 1Password, and any tool that calls Render must throw the values away without logging them.
- **Render doesn't redeploy after an env change here:** all three services have `autoDeploy: false`, and env-group changes only redeploy services with autodeploy on. Each sync to Render needs an explicit deploy.
- **Render was set up by hand, not from `render.yaml`.**
  - Four free web services, all with auto-deploy off, none suspended:
    - `doddy` (backend, branch `claude/loving-dirac-uuxoux`)
    - `doddy-messaging` (branch `claude/loving-dirac-uuxoux`, no separate worker)
    - `doddy-voice-token` and `doddy-gateway` (both branch `claude/affectionate-tesla-nqu0nj`, started with `node server.js`, a file that isn't on the default branch)
  - So the env-group problem hasn't caused harm yet, but a Blueprint deploy would hit it.
  - **The voice token server and the gateway each exist in three places:** Vercel, Render and Supabase. For voice, the app calls the Vercel copy; the gateway address is whatever is typed into the app's Settings. Each copy probably holds its own provider keys **[inference]**.
  - Health and recent traffic of the Render services weren't checked.
- **Two old Supabase functions are live** (`assistant` v4 and `voice-token` v1 in project `doddy-gateway`), and their source isn't in this repo. Nothing in the app calls them. Each one probably holds its own copy of provider keys **[inference]**: more places a key can leak, and more places to update on rotation.

## Part 1: Inventory (names only)

Built from `render.yaml`, every `.env.example`, the server READMEs and a search of each service's source for the environment variables it reads. No value was opened. Host state was checked on 2026-10-17 by listing projects and functions only (no environment variables were listed).

### Where things run today

| Host | What is there | Live? | How checked |
|---|---|---|---|
| Vercel team `doddyyyy` | Projects `doddy` (site, www.doddy.lol), `doddy-gateway` (`gateway/`), `doddy-voice-token` (`server/voice-token/`), plus an unrelated `name-atlas` | Yes: all three Doddy projects exist (created 12 Oct 2026). The app's voice endpoint is `https://doddy-voice-token.vercel.app/api/voice-token` (`DoddyApp/Features/Voice/VoiceConfig.swift`) | Vercel project list |
| Supabase project `doddy-gateway` (eu-central-1) | Edge Functions `assistant` (v4) and `voice-token` (v1). The organisation was created through the Vercel Marketplace integration | Active, but the source for these functions isn't in this repository. They look like the older Supabase variants of the gateway and token server (`docs/implementation/BRANCH_TRIAGE_2026-10-11.md`). Nothing in the app points at them | Supabase project and function list |
| Render workspace (owner's, one team workspace) | Web services `doddy` (backend), `doddy-messaging`, `doddy-voice-token`, `doddy-gateway`, all on the free plan, auto-deploy off. Not created from `render.yaml`: there's no worker, and the messaging server is a free web service | **Yes**, all four running (not suspended), checked 18 Oct. Health and traffic not checked. Postgres for the messaging server not checked | Render service list |
| GitHub Actions | `.github/workflows/ios.yml` | Runs, and uses **no secrets** (ADR-123). The Postgres password in it is a throwaway for the test container | Read the file |
| ElevenLabs | Voice agent and phone agent; a workspace secret `doddy_tool_secret` that the phone agent's webhook tools send | Live (STATUS.md) | `voice-agent/phone/tools.json` |
| A developer's Mac | `.env.local` files per service, Xcode signing in the login Keychain | Owner's machine | Docs |
| iPhone | Per-device Keychain: Doddy session and refresh tokens, the Picovoice key | Live | ADR-079, 149, 328 |

### Secrets each service reads

"Rotate" says what breaks if the value changes. Config that isn't secret (ports, limits, model ids, agent ids, toolkit versions, bundle ids, public URLs) is left out; it stays in the repo or the host as it is today.

| Name | Service | Lives today | Needed by | Rotate |
|---|---|---|---|---|
| `DODDY_SESSION_SIGNING_KEY` | `server/voice-token` | Vercel `doddy-voice-token`, probably also Render `doddy-voice-token` (which runs a different branch) | Server at runtime | **Dangerous.** Signs everyone out **and** changes the pseudonymous Apple subject ids the server derives from it (README). My inference: server-side records keyed by those ids would no longer match |
| `DODDY_SESSION_SIGNING_KEY` | `backend/` | Render `doddy` (`generateValue: true`, so Render made it) | Server at runtime; `mintSession.ts` locally | Signs every backend session out. Same name as above but must be a **different value** |
| `UPSTASH_REDIS_REST_TOKEN` | `server/voice-token`, `gateway/` | Vercel | Runtime | Update both services together; short outage otherwise (both fail closed) |
| `KV_REST_API_TOKEN` | `gateway/` (alternative to Upstash) | Set by a Vercel Marketplace store, if one is connected | Runtime | Managed by Vercel; don't copy it into 1Password as the record |
| `ELEVENLABS_API_KEY` | `server/voice-token`, `server/messaging` | Vercel; Render env group | Runtime; `setup-phone-agent.mjs` locally | Update every host that has it, then revoke the old key in ElevenLabs |
| `OPENAI_API_KEY` | `server/voice-token`, `gateway/`, `server/messaging` | Vercel; Render env group | Runtime | As above. Three services, ideally three separate keys (one per OpenAI project) so a leak is contained |
| `PICOVOICE_ACCESS_KEY` | `server/voice-token` | Vercel | Runtime; **handed to phones by design** (ADR-328) | Phones keep the old key in the Keychain. After rotation "Hey Doddy" fails on each phone until it fetches the new one. Whether the app refetches after a key failure is not verified |
| `GATEWAY_TOKEN_SECRET` | `gateway/` | Vercel `doddy-gateway`, probably also Render `doddy-gateway` | Runtime | Signs every device out of the typed assistant; also re-keys the HMAC'd store keys (counters reset) |
| `GATEWAY_INVITE_CODES` | `gateway/` | Vercel | Runtime; the owner hands codes to testers | Removing a code revokes that tester; this is a list that changes, not a key |
| `WAITLIST_ADMIN_PASSWORD` | `site/api` | Vercel `doddy` | Runtime; the owner logs into the waitlist admin | Owner logs in with the new one |
| `BLOB_READ_WRITE_TOKEN` | `site/api` (`@vercel/blob`) | Set by Vercel when the Blob store is connected | Runtime | Managed by Vercel |
| `COMPOSIO_API_KEY` | `backend/` | Render `doddy` (not confirmed deployed); `.env.local` | Runtime; `setup:tools` locally | Update host, revoke old key in Composio. Connected Google/Notion accounts stay in Composio |
| `MONID_API_KEY` | `backend/` | Render `doddy` | Runtime | Update host; it spends Doddy's Monid wallet, so revoke fast on leak |
| `APNS_PRIVATE_KEY` (+ `APNS_KEY_ID`, `APNS_TEAM_ID`) | `server/messaging` | Render env group (multi-line `.p8` contents) | Runtime | Make a new key in the Apple Developer account, update host, then revoke the old key |
| `TWILIO_AUTH_TOKEN` (+ SIDs) | `server/messaging` | Render env group | Runtime | Update host, then retire the old token in Twilio |
| `MEMORY_ENCRYPTION_KEY` | `server/messaging` | Render env group | Runtime | **Never rotate casually.** Losing or changing it makes stored memory copies and call notes unreadable (`.env.example`). There is no re-encryption migration. 1Password's main job here is being the backup |
| `ELEVENLABS_TOOL_SECRET` | `server/messaging` | Render env group, **and** the ElevenLabs workspace secret `doddy_tool_secret` | Runtime on both sides | Must change in both places together, or phone-call tools fail |
| `ANTHROPIC_API_KEY` | `server/messaging` | Render env group | Runtime | Update host, revoke old |
| `GNEWS_API_KEY` | `server/messaging` | Render env group | Runtime | Update host |
| `DATABASE_URL` | `server/messaging` | Made by Render from `doddy-db` (`fromDatabase`) | Runtime | Managed by Render; leave it there |

### Secrets that aren't environment variables
- **Apple:** the APNs `.p8` file (a 1Password document item), the Apple Developer account and its two-factor login, and Xcode signing certificates (in the Mac's Keychain today; Xcode's automatic signing doesn't need them anywhere else). No App Store Connect API key is in use.
- **Picovoice:** the Console login; the `hey-doddy.ppn` keyword file, which isn't in the repo yet. It's a licensed file rather than a secret, but 1Password is a fine place to keep the original.
- **Dashboard logins:** Vercel, Supabase, Render, GitHub, ElevenLabs, OpenAI, Anthropic, Composio, Monid, Twilio, GNews, Upstash, Google Analytics, the `doddy.lol` registrar. Each of these can create or reveal every key above, so they matter more than any single key.
- **Per-user credentials on phones** (session and refresh tokens, a user's own Picovoice key) are not project secrets. They stay in the iPhone Keychain, this device only, as ADR-079/149/328 decided.

## Part 2: What 1Password offers (checked 17 Oct 2026)

| Feature | What it does | Plan | Limits and status | Use for Doddy |
|---|---|---|---|---|
| **CLI `op`** (2.41.0, 12 Oct 2026) | Secret references `op://vault/item/[section/]field`. `op run --env-file=… -- cmd` puts secrets into one process's environment. `op inject` fills a template (writes a plaintext file, mode 0600) | All plans | Masks secrets printed to stdout/stderr by default, but "best effort", and `--no-masking` turns it off. Names with characters other than letters, digits, `- _ .` and spaces must be referenced by ID. A file attachment (the APNs `.p8`) is `op://vault/item/<file name>` | **Yes:** local dev and the sync script |
| **Desktop app sign-in** | Touch ID unlocks `op` for one terminal window | All plans | A 10-minute session that refreshes on use, 12-hour cap. Covers the **whole account** and every sub-shell in that window | **Yes:** the owner runs the sync from their Mac |
| **Service accounts** | A token (`ops_…`) for machines, scoped to chosen vaults | All plans (the rate-limit tables list Individual, Families, Teams, Business) | Up to 100. Per-vault read/write. **Permissions can't be changed later**; make a new one instead. Can't reach Personal, Private, Employee or the default Shared vault. Token rotation with a grace period; revocation is instant. Per token: 1,000 reads/hour (10,000 on Business). Per account: 1,000 requests/day on Individual and Families, 5,000 on Teams, 50,000 on Business. A read by name costs 3 requests, by ID 1 | **Not needed at first.** Later, maybe a read-only one for the sync script |
| **Connect server** | A self-hosted REST cache in Docker | "Included" on one page, "add-on" on another | No rate limits after the first fetch. Doesn't support Environments | **No:** another server to run and patch, for volume Doddy doesn't have |
| **JavaScript SDK** `@1password/sdk` 0.5.0 | Resolve references, manage items, read Environments | All plans | "Version 0" but declared production-ready; minor versions may break. **Node only**: a 14 MB WebAssembly core loaded from disk, so not Vercel Edge, not Deno or Supabase Edge (open issue #184) | **No:** only needed for fetch-at-boot, which isn't recommended |
| **Environments** | Named sets of variables kept apart from vault items. Mounted `.env` files are served through a named pipe, never stored on disk | No plan restriction stated; sharing needs a team or business account | Mac and Linux. Once unlocked, **any process can read the mounted file** until 1Password locks. Up to 10 mounts per device. `op run --environment` is GA (CLI 2.41.0); the rest is beta or unclear. Sync destinations: AWS Secrets Manager (beta), GitHub via Credential Broker. **None for Vercel, Render or Supabase** | **Maybe later** for local dev. Vault items plus `op://` references are simpler today and fully GA |
| **GitHub Actions** `1password/load-secrets-action` v5.0.1 | Loads secrets into a job and masks them | All plans (service account) | Pin to commit `70062d7a876d3eb6334754fa26efd2fbd90c32f2`. The `configure` step exposes the token to every later step | **No:** CI stays secret-free (ADR-123) |
| **Credential Broker** (workload identity) | GitHub OIDC instead of a stored token | **Business only.** Also needs a GitHub organisation, and not for private repos on GitHub Free | Public preview since 28 Jul 2026; GA "late 2026" | **No** |
| **SSH agent, Git signing, shell plugins** | SSH keys and commit signing from 1Password; CLI sign-in for Vercel and `gh` | All plans | The Vercel shell plugin passes the token as a command-line argument (visible in `ps`) | SSH and signing are worth having. Skip the Vercel plugin; set `VERCEL_TOKEN` through `op run` instead |
| **Environments MCP server** and **Claude Code plugin** | Lets a local agent create Environments and list variable **names**. "The server cannot return secret values" | Desktop app setting | Beta. Local only (stdio); Mac and Linux; doesn't work for cloud sessions | Optional for the owner's local Claude Code. Not needed |
| **Rotation** | 1Password doesn't rotate third-party keys | — | Manual: rotate at the provider, update the item, push | Write runbooks (Part 5) |

**Pricing** (1password.com/pricing, 17 Oct 2026; the page data is labelled as a test variant, so confirm at checkout):

| Plan | Yearly billing | Monthly billing |
|---|---|---|
| Individual | $3.99/mo | $4.99/mo |
| Families (5 people) | $5.99/mo | $7.99/mo |
| Teams Starter Pack (up to 10 users) | $24.95/mo flat | about $29.90/mo (my arithmetic) |
| Business (1 user minimum) | $8.99/user/mo | $10.99/user/mo |

Audit log, item usage reports and the Events API are **Business only**. Business is cheaper than Teams Starter Pack up to two users.

## Part 3: Fit for each host

Three ways to get a value from 1Password onto a host:
- **(a) Push at deploy time:** a script reads 1Password and writes to the host's API.
- **(b) Fetch at boot:** the server reads 1Password with the SDK each time it starts.
- **(c) Manual:** a person copies values from 1Password into the dashboard.

| Host | 1Password integration | How to write | List names without values? | Recommended |
|---|---|---|---|---|
| **Vercel** (3 live projects) | None (the old marketplace link is a dead page) | `vercel env add NAME production --type secret` reading the value from **stdin**, or REST `POST /v10/projects/{id}/env?upsert=true` with `"type":"sensitive"`. Never `--value` or `--token` (argv). Needs a redeploy | **Yes:** `GET /v10/projects/{id}/env` without `decrypt=true`. Secret-type values are write-only, so a value can't be compared, only overwritten | **(a)** with a project-scoped Vercel token kept in 1Password |
| **Supabase** (2 old functions) | None | Management API `POST /v1/projects/{ref}/secrets` with `[{name, value}]`, or `supabase secrets set --env-file` (never `NAME=VALUE` in argv). Functions see new secrets straight away | **Yes:** the list returns name plus a digest (format unverified; test with a dummy secret) | **(a)** with a scoped access token (GA since 6 Oct 2026). Or retire the functions (decision 2) |
| **Render** (not confirmed deployed) | None | REST `PUT /v1/services/{id}/env-vars/{key}` and `PUT /v1/env-groups/{id}/env-vars/{key}`, one key at a time. **Never** the bulk `PUT …/env-vars`, which replaces everything and would regenerate the backend's `generateValue` signing key. Then `POST /v1/services/{id}/deploys` | **No:** values come back on every read and write | **(c)** for the first setup (the dashboard's "Add from .env"), then **(a)** |
| **GitHub Actions** | Yes (`load-secrets-action`; Credential Broker in preview) | `gh secret set NAME` reading stdin | Yes | **Keep no secrets** |
| **Claude Code cloud sessions** | None. 1Password's plugin and MCP server are local only | Environment variables in the environment settings: visible to every command the agent runs. **Network secrets:** the proxy adds a header for listed hosts, and the key "doesn't appear in the session's environment variables or in any file" | n/a | **No 1Password token.** Tests stay on fakes. If an agent ever needs a live test key, use a low-limit provider key as a network secret, never a host API key |
| **Owner's Mac** | Yes (desktop app and CLI) | n/a | n/a | `op run --env-file=… -- npm start` for servers. It also runs the sync script |
| **Xcode / the app** | n/a | n/a | n/a | Nothing. The app ships no secrets; signing uses the Mac's Keychain and Apple account |

**Why not fetch at boot (b), anywhere:**
- The service account token would sit on the host, where anyone with dashboard access can read it, and it unlocks whole vaults.
- Render's free plan sleeps after 15 minutes and can restart at any time, so every wake-up would need 1Password to be up.
- Vercel cold-starts per instance, so three projects could hit the 1,000 or 5,000 requests/day account limit. A 429 would lock them out for up to a day.
- The SDK doesn't run on Supabase Edge (Deno) or Vercel Edge.

**Pushing (a)** costs about 20–60 requests per full sync (about 20 secrets; a read by name counts as 3). That is well inside even the Individual plan's 1,000 a day. If 1Password is down, running services keep their last values.

**Agents and `op`:** masking is not a boundary, because the agent picks the command and can pass `--no-masking`. A terminal the owner unlocked with Touch ID lets anything in it, a local agent included, read the whole account for up to 12 hours. A mounted Environments `.env` is readable by any process once unlocked. In 1Password's own words: "A local coding agent should never hold credentials for production systems." So:
- Run the sync in a terminal with no agent in it.
- Never give a Claude session a 1Password token, or a Render, Vercel or Supabase API key.

## Part 4: The iPhone app and users

**The app keeps no secrets.** Nothing in this research changes `BUILD_AND_TEST.md`'s "the app needs none":
- The Picovoice key arriving from the token server is a deliberate exception, already recorded (ADR-328).
- Per-user tokens stay in the iPhone Keychain, this device only (ADR-079, 149).
- The only Apple-side secrets are the APNs `.p8` file and the developer account login. Both belong in 1Password as an owner-only document and login. Xcode needs nothing from 1Password.

**Doddy reading a user's 1Password: no.**
- There is no supported way:
  - 1Password "has never exposed raw credentials via public APIs" and won't through MCP.
  - The SDKs are Go, JavaScript and Python only.
  - Environments isn't on iOS.
  - The old 1Password App Extension was archived in Feb 2025.
  - No App Intents or Shortcuts actions appear in the iOS release notes up to 8.12.40.
- What iOS does allow:
  - AutoFill fills a field only after the user taps a suggestion, and only for the app's own associated domain, or with the iOS 18+ "AutoFill > Passwords" menu that the user picks by hand.
  - `ASCredentialProviderViewController` is for the password manager, not the app asking.
  - Wi-Fi APIs can't read a password.
- Even through a user-made service account on a Doddy server, the value would then sit in the voice provider's transcript, the model's context and Doddy's logs. That breaks `raw_secrets_in_model_prompt_or_logs: forbidden` and ADR-247 (passwords and PINs are never offered as notes), and it would be spoken aloud.
- The safe version is Doddy saying where to look ("open 1Password, Home Wi-Fi, and show the QR code"), without touching the value. A supported deep link for that was not found.

**Doddy's own sign-in:**
- Sign in with Apple is a separate system and 1Password doesn't affect it.
- If Doddy ever adds passkeys, the standard Apple passkey code works with 1Password as the passkey provider with no 1Password-specific work.

## Part 5: Recommendation

### Vault layout and naming
Four vaults, short names without spaces (references then need no quoting):

| Vault | Holds | Who can read |
|---|---|---|
| `doddy-prod` | Every runtime secret for live hosts, one item per secret per service (`voice-token-session-signing-key` and `backend-session-signing-key` are separate items) | Owner. Later, at most a read-only service account for the sync script |
| `doddy-dev` | Separate low-limit keys for local development (an OpenAI project with a spending cap, a dev ElevenLabs key) | Owner and collaborators |
| `doddy-deploy` | Host API tokens: project-scoped Vercel tokens, the Render API key, the Supabase scoped token | **Owner only.** The Render key reads every Render secret |
| `doddy-accounts` | Dashboard logins with two-factor, the APNs `.p8` original, the Picovoice keyword file, recovery codes | Owner only |

Item fields: `credential` for the value, plus `notes` holding the provider console link, what breaks on rotation, and the date last rotated. Example reference: `op://doddy-prod/elevenlabs-api/credential`.

Values the platform owns stay with the platform, and the manifest records them as managed: `DATABASE_URL` (Render), `BLOB_READ_WRITE_TOKEN` and `KV_REST_API_*` (Vercel stores). Config that isn't secret stays where it is.

### Committing references
An `op://` reference reveals vault and item names, never a value, and can't be used without access to the vault. **Commit them:** the manifest and the `.env.op` templates make the setup reproducible, and they are what the build prompt needs. Keep item names plain (`openai-api`, not something that describes a weakness), and keep secret values out of comments.

### Phased plan (smallest first; each phase can be undone)

| Phase | Who | What | Undo |
|---|---|---|---|
| 0. Record | Owner, no code | Pick the plan, create the four vaults, and put every current value in. **Catch:** a value saved on Vercel as the Secret type can't be read back. For each one, find the original at the provider, or make a new key at the provider (a rotation). **Never** do this for `DODDY_SESSION_SIGNING_KEY` or `MEMORY_ENCRYPTION_KEY`. If those can't be read back, mark them "host-only" in the manifest until a planned rotation | Nothing changes on any host |
| 1. Local dev | Build prompt | `secrets/manifest.yaml`, `.env.op` templates, `npm run dev:op`, guard checks, docs | Delete the files; `.env.local` still works |
| 2. Sync, dry-run | Build prompt, then the owner | The sync tool lists names on Vercel and Supabase and prints the plan: no writes | Nothing to undo |
| 3. Sync, Vercel | Owner runs `--apply` and confirms | Push to `doddy-voice-token` first (the one the app uses), redeploy, and talk to Doddy once. Then gateway and site | Re-push the old value from 1Password's item history and redeploy. Env changes only apply to new deployments, so an earlier deployment can also be promoted back **[inference]** |
| 4. Supabase | Owner decides | Either delete the two old functions and their secrets (recommended if unused), or add them to the manifest | Functions can be redeployed from their source, which isn't in the repo, so **copy the source out before deleting** |
| 5. Render | Owner and build prompt | It's deployed (4 services). First decide which of the duplicate `doddy-voice-token` / `doddy-gateway` copies to keep (decision 11). Copy current values into 1Password from the Render dashboard (Render can show them), then sync by API one key at a time, with an explicit deploy | Re-push the old value from 1Password's item history and deploy again |
| 6. Runbooks | Build prompt | A rotation runbook per secret in `docs/security/SECRETS_1PASSWORD.md`, and separate provider keys per service at each key's next rotation | Docs only |

CI, Claude sessions and the app are deliberately left out of every phase.

### Cost
- **Business with one seat:** $8.99/month billed yearly ($107.88/year), or $10.99 monthly.
- **The owner's Individual plan:** $3.99/month yearly; enough for phases 0 to 3 if the owner already has it.
- Nothing else: no Connect, no Credential Broker, no AWS.

### Risks and limits

| Risk | Limit |
|---|---|
| The Render API key reads every Render secret | Owner-only vault, never on a host or in an agent's environment, revoke if exposed (no expiry is documented) |
| A Touch-ID-unlocked terminal exposes the whole account for up to 12 hours to anything running in it | Run the sync in its own terminal with no agent; lock 1Password afterwards. Later, a read-only service account limited to `doddy-prod` and `doddy-deploy` for the script |
| `op run` masking is best effort | The sync tool never prints values at all; tests plant a fake value and check it never appears |
| Vercel Secret values can't be read back, so a wrong push can't be detected by comparing | Push from 1Password only; record `updatedAt`; one talk-to-Doddy check after each Vercel push |
| 1Password becomes the place everything depends on | The owner keeps the Emergency Kit and account recovery set up. Hosts keep running with their last values if 1Password is down |
| `MEMORY_ENCRYPTION_KEY` lost or changed | Record it first (phase 0), never rotate it as part of this work, and write a re-encryption plan before any rotation |
| Agents reading secrets through tokens or transcripts | No 1Password or host tokens in any Claude session; tests use fakes |

### Decisions for the owner (each with a recommended answer)
1. **Which 1Password plan?** **Answered: Individual.**
2. **Are the Supabase functions `assistant` and `voice-token` still used?** **Answered: no. Code saved; the owner deletes them in the dashboard.**
3. **Is Render deployed, and in which workspace?** **Answered: yes, the owner's one workspace, 4 services.**
4. **Vault layout as above?** Recommended: yes, four vaults.
5. **Who runs the sync?** Recommended: you, from your Mac with Touch ID. No service account until it's needed.
6. **Commit the `op://` manifest and templates?** Recommended: yes.
7. **Any 1Password or host token for Claude sessions?** Recommended: no.
8. **A user-facing 1Password feature?** Recommended: no.
9. **Separate provider keys per service** (OpenAI and ElevenLabs are each used by two or three servers)? Recommended: yes, at each key's next rotation, not as part of the move.
10. **Install 1Password's Claude Code plugin on your Mac?** Recommended: optional and not needed. It's beta, and it can only manage Environments, never read values.
11. **Keep the Render copies of `doddy-voice-token` and `doddy-gateway`?** Both run a non-default branch. The app's voice address is fixed to the Vercel `doddy-voice-token` (`VoiceConfig.swift`), so it never calls the Render one. The gateway address is typed into the app's Settings, so first check which gateway address your phone has. Recommended: suspend the copies you don't use, and delete them a week later if nothing breaks. That leaves fewer copies of each key to sync and rotate.

### Draft ADR (for `DECISIONS.md` only after the owner approves)
> | NNN | **Project secrets are recorded in 1Password; hosts keep environment variables** (owner: "search how we can use 1password"; research `docs/research/1PASSWORD_SECRETS_2026-10.md`). 1Password holds every project secret in four owner-controlled vaults (`doddy-prod`, `doddy-dev`, `doddy-deploy`, `doddy-accounts`). The servers keep reading plain environment variables, so nothing at runtime depends on 1Password and tests stay offline. A committed manifest maps each variable to its `op://` reference and its hosts. A sync tool run by the owner from their Mac shows the exact plan (host, name, add/change/remove, never the value), asks for a confirmation bound to that plan, writes through each host's API from stdin or the request body (never argv), and reports `set`, `unchanged`, `failed` or `unknown` per name. No 1Password token is stored on any host, in CI or in a Claude session, and the iPhone app gets no secrets and no 1Password code. Platform-managed values (`DATABASE_URL`, Vercel store tokens) stay with the platform. `MEMORY_ENCRYPTION_KEY` and `DODDY_SESSION_SIGNING_KEY` are recorded but never rotated by this work. Reading users' 1Password from the app is rejected: iOS offers no API for it, and it would put secrets into the voice provider's context and Doddy's logs. | Proposed — owner approval pending |

## Constitution fit
- **External writes (DOD-07):** the sync tool's plan and confirmation is the "exact payload, explicit approval" rule applied to hosts. "Done" comes only from the host API's answer, and a timeout is `unknown`.
- **`raw_secrets_in_model_prompt_or_logs: forbidden`:** no agent holds a token, the tool never prints values, and the user-facing feature is rejected.
- **"Use secure storage for credentials; separate from model context"** (04_ENFORCEMENT_ARCHITECTURE): 1Password for project secrets, the Keychain for per-user tokens.
- **Claims to limit:** this is research. Nothing is migrated, built or tested yet.

## Sources (read 17 Oct 2026 unless marked)

**1Password: CLI, service accounts, SDK, Environments**
- https://www.1password.dev/cli/secret-reference-syntax/
- https://www.1password.dev/cli/reference/commands/run/
- https://www.1password.dev/cli/reference/commands/inject.md
- https://www.1password.dev/cli/app-integration-security/
- https://releases.1password.com/developers/cli/
- https://www.1password.dev/service-accounts/get-started/
- https://www.1password.dev/service-accounts/rate-limits/
- https://www.1password.dev/service-accounts/security/
- https://www.1password.dev/service-accounts/manage-service-accounts/
- https://www.1password.dev/connect/overview.md
- https://www.1password.dev/sdks/concepts.md
- https://github.com/1Password/onepassword-sdk-js and issue #184
- https://registry.npmjs.org/@1password/sdk
- https://www.1password.dev/environments/overview.md
- https://www.1password.dev/environments/local-env-file.md
- https://www.1password.dev/environments/mcp-server
- https://www.1password.dev/environments/claude-plugin
- https://www.1password.dev/environments/aws-secrets-manager.md

**1Password: CI, Credential Broker, extras, pricing**
- https://www.1password.dev/ci-cd/github-actions
- https://github.com/1Password/load-secrets-action (README, releases, tags)
- https://www.1password.dev/brokered-access/github-actions.md
- https://1password.com/blog/1password-credential-broker-public-preview
- https://www.1password.dev/cli/shell-plugins/vercel.md
- https://www.1password.dev/ssh/git-commit-signing.md
- https://1password.com/pricing, https://1password.com/pricing/business
- https://support.1password.com/reports/, https://support.1password.com/activity-log/

**1Password: AI agents and users**
- https://1password.com/blog/where-mcp-fits-and-where-it-doesnt
- https://1password.com/blog/ai-agent-identity-architectures
- https://www.1password.dev/get-started/secure-ai-access
- https://www.1password.dev/security-for-ai
- https://www.1password.dev/sdks/ai-agent
- https://github.com/agilebits/onepassword-app-extension (archived)
- https://releases.1password.com/ios/stable/
- https://support.1password.com/ios-autofill/

**Apple**
- https://developer.apple.com/documentation/security/password-autofill
- https://developer.apple.com/documentation/authenticationservices/ascredentialproviderviewcontroller
- https://developer.apple.com/documentation/authenticationservices/asauthorizationpasswordprovider
- https://developer.apple.com/documentation/authenticationservices/supporting-passkeys
- https://developer.apple.com/documentation/networkextension/nehotspotnetwork

**Hosts**
- https://render.com/docs/blueprint-spec (re-read 18 Oct)
- https://render.com/docs/configure-environment-variables
- https://render.com/docs/free
- https://api-docs.render.com/openapi/render-public-api-1.json
- https://vercel.com/docs/cli/env
- https://vercel.com/docs/environment-variables/sensitive-environment-variables
- https://vercel.com/docs/rest-api/reference/endpoints/projects/retrieve-the-environment-variables-of-a-project-by-id-or-name
- https://vercel.com/kb/bulletin/vercel-april-2026-security-incident (read 18 Oct)
- https://supabase.com/docs/guides/functions/secrets
- https://supabase.com/docs/guides/functions/limits
- https://api.supabase.com/api/v1-json
- https://supabase.com/changelog/scoped-personal-access-tokens-ga
- https://docs.github.com/en/rest/actions/secrets
- https://cli.github.com/manual/gh_secret_set
- https://code.claude.com/docs/en/claude-code-on-the-web
- https://code.claude.com/docs/en/cloud-environments

## What I could not verify
- **Hosts:**
  - Whether Render is deployed, in which workspace, and what the old Render `doddy-voice-token` service named in `HEY_DODDY_STATUS.md` is. The Render tool asks the owner to choose a workspace first.
  - Which Vercel variables are Secret type and which are Config. Listing them wasn't done, on purpose. Vercel's April 2026 incident exposed Config-type ("non-sensitive") values, but Doddy's projects were created on 12 Oct 2026, after it. Store every secret as Secret type anyway.
  - The format of Supabase's secret digest, and whether Render's per-key write starts a deploy by itself.
  - What the old Supabase functions read: their source isn't in the repo.
- **1Password plans and limits:**
  - A direct statement that service accounts work on Individual (it's inferred from the rate-limit tables).
  - The exact Teams Starter Pack limits.
  - Whether a batch resolve counts as one request.
- **Feature status:**
  - The current status of Environments (no beta badge on the pages, last explicit word "public beta").
  - Whether the Environments MCP approval lasts per action or until 1Password locks (two official pages disagree).
  - The status of Secure Agentic Autofill.
- **App:**
  - Whether the app fetches a new Picovoice key after the old one stops working.
  - A supported `onepassword://` deep link to a specific item.
