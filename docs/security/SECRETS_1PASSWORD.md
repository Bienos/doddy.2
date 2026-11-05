# Doddy's project secrets in 1Password

**Status (18 Oct 2026):**
- **Built and tested on Linux, against fakes only:** the manifest, the `.env.op` templates, the sync tool and its checks.
- **Not done yet:** they have never touched the real 1Password, Vercel or Render. The owner's first run (below) is still to do, and no secret has been moved.
- **Decision:** ADR-493. **Background research:** `docs/research/1PASSWORD_SECRETS_2026-10.md`.

## The rule
- **1Password is the one record of every project secret.** The hosts keep their own environment variables, and the servers read those exactly as before, so nothing at runtime depends on 1Password and tests stay offline.
- **The sync tool copies values from 1Password to the hosts.** It shows the exact plan first and writes only after you type that plan's code.
- **Where nothing goes:** no 1Password token sits on any host, in CI or in a Claude session, and the iPhone app gets no secrets and no 1Password code. The guard script checks the app and server part: `scripts/check_forbidden_capabilities.sh`.

## Files
| File | What it is |
|---|---|
| `secrets/manifest.json` | Every secret by name: its 1Password item, the services that read it, the hosts it goes to, whether the tool may write it, and what breaks when it changes. Also lists platform-managed values and settings that aren't secret |
| `backend/.env.op`, `server/messaging/.env.op`, `server/voice-token/.env.op`, `gateway/.env.op` | Generated from the manifest. `op://` references to the **development** vault only, for running things locally. The site has none, so a change here doesn't start a site build; its one secret is synced to Vercel only |
| `secrets/deploy.env.op` | References to the host API tokens the sync tool uses (owner-only vault) |
| `tools/secrets/sync.mjs` | The tool: `check`, `templates`, plan (dry run) and `--apply` |
| `secrets/.sync-state.json` | Ignored by git. What the tool last wrote to Vercel (fingerprints, Vercel's `updatedAt`), so a second run can say "same" |

A reference such as `op://doddy-prod/openai-api/credential` names a vault, an item and a field, never a value. It is useless without access to the vault, which is why the files are committed. `node tools/secrets/sync.mjs check` (in `scripts/ci.sh`) fails if any of these files holds anything but references.

## Vaults
| Vault | Holds | Who can read it |
|---|---|---|
| `doddy-prod` | Runtime secrets for the live hosts | Owner |
| `doddy-dev` | Separate values for local development: low-limit provider keys, fresh signing and encryption keys | Owner, and collaborators if any |
| `doddy-deploy` | Host API tokens: `vercel-token`, `render-api-key` | **Owner only.** A Render API key can read every Render secret |
| `doddy-accounts` | Dashboard logins with two-factor, the original APNs `.p8`, recovery codes | Owner only |

**Plan:** Individual (owner's choice, 18 Oct). Move to Business if a second person needs access or you want 1Password's access history.

**Item types:**
- Most items are **API Credential** items, and the value goes in the `credential` field.
- The APNs key is a **Secure Note**, with the `.p8` text in the note (`notesPlain`), because it spans several lines.

## What goes where
"Push" says whether the tool may write it. "Dev" says whether the local template includes it.

| Variable | Item | Hosts | Push | Dev |
|---|---|---|---|---|
| `ELEVENLABS_API_KEY` | `elevenlabs-api` | `vercel:doddy-voice-token`, `render:doddy-messaging` | yes | yes |
| `OPENAI_API_KEY` | `openai-api` | `vercel:doddy-voice-token`, `vercel:doddy-gateway`, `render:doddy-messaging` | yes | yes |
| `DODDY_SESSION_SIGNING_KEY` | `voice-token-session-signing-key` | `vercel:doddy-voice-token` | **no**: changing it signs everyone out and changes the Apple ids the server derives from it | yes |
| `UPSTASH_REDIS_REST_TOKEN` | `upstash-voice-token` | `vercel:doddy-voice-token` | yes | no |
| `UPSTASH_REDIS_REST_TOKEN` | `upstash-gateway` | `vercel:doddy-gateway` | yes | no |
| `GATEWAY_TOKEN_SECRET` | `gateway-token-secret` | `vercel:doddy-gateway` | **no**: changing it signs every device out of the typed assistant | yes |
| `GATEWAY_INVITE_CODES` | `gateway-invite-codes` | `vercel:doddy-gateway` | yes | no |
| `WAITLIST_ADMIN_PASSWORD` | `waitlist-admin-password` | `vercel:doddy` | yes | yes |
| `DODDY_SESSION_SIGNING_KEY` | `backend-session-signing-key` | `render:doddy` | **no**: changing it signs every backend session out (Render generated the live value) | yes |
| `COMPOSIO_API_KEY` | `composio-api` | `render:doddy` | yes | yes |
| `MONID_API_KEY` | `monid-api` | `render:doddy` | yes | yes |
| `APNS_PRIVATE_KEY` | `apns-auth-key` (Secure Note, `notesPlain`) | `render:doddy-messaging` | yes | no |
| `TWILIO_AUTH_TOKEN` | `twilio-auth-token` | `render:doddy-messaging` | yes | no |
| `TWILIO_TASK_AUTH_TOKEN` | `twilio-task-auth-token` | `render:doddy-messaging` | yes | no |
| `ELEVENLABS_WEBHOOK_SECRET` | `elevenlabs-webhook-secret` | `render:doddy-messaging` | **no**: ElevenLabs makes it for the post-call webhook, and the host must hold exactly that value | no |
| `MEMORY_ENCRYPTION_KEY` | `memory-encryption-key` | `render:doddy-messaging` | **no**: a different value makes stored memory copies and call notes unreadable | yes |
| `ELEVENLABS_TOOL_SECRET` | `elevenlabs-tool-secret` | `render:doddy-messaging` | **no**: it must change together with the ElevenLabs workspace secret `doddy_tool_secret` | yes |
| `ANTHROPIC_API_KEY` | `anthropic-api` | `render:doddy-messaging` | yes | yes |
| `GNEWS_API_KEY` | `gnews-api` | `render:doddy-messaging` | yes | yes |

**Managed by the platform** (never in 1Password as the record):
- `DATABASE_URL`: Render builds it from the database.
- `BLOB_READ_WRITE_TOKEN`: set by the Vercel Blob store connected to the site.
- `KV_REST_API_TOKEN` and `KV_REST_API_URL`: set by a Vercel Marketplace Redis store, if one is connected to the gateway.
- `VERCEL_ENV`: a Vercel system variable.

**Not managed here:**
- **The Render copies of `doddy-voice-token` and `doddy-gateway`.** They run a non-default branch and the app's voice address is the Vercel project. Owner decision 11 in the research report: suspend them first, then delete.
- **The old Supabase functions.** The owner is deleting them; their code is saved in `docs/archive/supabase-functions-2026-10-18/`.
- **GitHub Actions** stays secret-free (ADR-123).

## First run (owner, in this order)
Nothing here can be done from a Claude session: it needs your 1Password sign-in.

1. **Install 1Password and its CLI on your Mac.**
   - Install the 1Password app and the CLI (`brew install 1password-cli`).
   - Turn on 1Password › Settings › Developer › "Integrate with 1Password CLI". `op` then unlocks with Touch ID.
2. **Create the four vaults:** `doddy-prod`, `doddy-dev`, `doddy-deploy`, `doddy-accounts`.
3. **Fill `doddy-prod` with today's values**, one item per row of the table above, using exactly those item names.
   - **Where to get values:**
     - **Render** shows a service's values in its dashboard.
     - **Vercel** can't show a value saved as the Secret type. Take it from the provider's console, or make a new key there, which is a normal rotation.
   - **Record-only keys:** for the five "no" rows, store the value only if you can read the current one. If you can't, still create the item, and write in its notes that the live value exists only on the host. **Don't make a new one.**
4. **Fill `doddy-dev`:**
   - **Provider keys:** separate keys for local work if you can (an OpenAI project with a spending cap, for example), otherwise the same key for now.
   - **Signing and encryption keys:** fresh values (`openssl rand -base64 32`), never the production ones.
5. **Fill `doddy-deploy`:**
   - `vercel-token`: a Vercel token limited to the `doddyyyy` team.
   - `render-api-key`: a Render API key.
6. **Dry run, one host first.** Read the plan. It shows names, actions and fingerprints, never values.
   ```
   op run --env-file=secrets/deploy.env.op -- node tools/secrets/sync.mjs --target vercel:doddy-voice-token
   ```
7. **Apply that plan**, using the code it printed:
   ```
   op run --env-file=secrets/deploy.env.op -- node tools/secrets/sync.mjs --target vercel:doddy-voice-token --apply --confirm <code>
   ```
   Then redeploy `doddy-voice-token` in Vercel and talk to Doddy once.
8. **The other hosts, one at a time:** `vercel:doddy-gateway`, `vercel:doddy`, `render:doddy`, `render:doddy-messaging`. On Render, redeploy by hand after each one, because auto-deploy is off.
   - **If the Render plan says `add` for keys you know are set,** those values come from an environment group, not the service. Stop and move that target to `render-group:<name>` in the manifest, with the group's id in `hosts.render.envGroups`.
   - **If you later apply `render.yaml`:** it creates a separate worker that needs the same secrets (ADR-495). Add `doddy-messaging-worker`'s id under `hosts.render.services`, and `render:doddy-messaging-worker` to those secrets' targets.
9. **Lock 1Password when you're done.** A Touch-ID-unlocked terminal can read the whole account for up to 12 hours.

## Everyday use
- **Run a server locally with 1Password:**
  - `npm run start:op` in `backend/` or `server/messaging/`.
  - `op run --env-file=.env.op -- vercel dev` in `server/voice-token/` or `gateway/`.
  - Settings that aren't secret still come from your ignored `.env.local` (or `.env`). Values from 1Password win if a name is in both.
- **Change a secret:** update the item in `doddy-prod`, dry-run, apply with the code, redeploy that host.
- **Add a secret:**
  1. Add it to `secrets/manifest.json` and run `node tools/secrets/sync.mjs templates --write`, then `check`.
  2. Create the item, then sync.
  3. If the name is also in a `.env.example`, `check` makes sure the manifest knows it.

### What the plan says
| Action | Meaning |
|---|---|
| `add` | The host doesn't have it; it will be created (on Vercel as the Secret type, production only) |
| `change` | The host has something else. On Vercel the stored value can't be read, so without a record of the last sync it is always overwritten |
| `same` | Render's value matches, or Vercel is unchanged since this tool last wrote it |
| `remove` | A retired name, only with `--prune` |
| `CONFLICT` | A Vercel variable shared between production and preview/development. Split it in the dashboard first; the tool won't touch it |
| `missing` | No such item or field in 1Password; skipped |
| `skipped` / `ERROR` | No host token, or the host couldn't be listed; nothing is written there |

**Results after `--apply`:**
- `set` or `removed`: only when the host's answer confirms it. Vercel writes are confirmed by listing the project again.
- `failed`: the host refused it, with an HTTP status.
- `unknown`: a timeout, a dropped connection, a 5xx, or an answer that doesn't match. **Unknown is not success:** look in the dashboard before running again. The tool never retries on its own.

### What the tool never does
- Print, log, or write a value to disk. The plan, results and state file are checked by tests with a planted value.
- Put a value on a command line. Values go in the request body; the `op://` reference is the only argument to `op read`.
- Ask Vercel to decrypt anything. It reduces Render's values to fingerprints as soon as they arrive.
- Write a record-only secret, remove anything without `--prune`, use Render's replace-everything endpoint, deploy, or retry an unknown write.

## Rotation runbook
The text comes from `rotate` in the manifest.

| Secret | What to do and what breaks |
|---|---|
| `ELEVENLABS_API_KEY` (server/voice-token, server/messaging) | Make a new key in ElevenLabs, put it here, sync and redeploy both hosts, then delete the old key in ElevenLabs. A host still holding the deleted key can't start voice or phone calls. |
| `OPENAI_API_KEY` (server/voice-token, gateway, server/messaging) | Make a new key in the OpenAI project, put it here, sync and redeploy all three, then revoke the old one. Plan: one key per service at the next rotation. |
| `DODDY_SESSION_SIGNING_KEY` (server/voice-token) | Signs everyone out and changes the pseudonymous Apple subject ids. Rotate only with a written plan; never as part of a sync. |
| `UPSTASH_REDIS_REST_TOKEN` (server/voice-token) | Reset the token in Upstash, put it here, sync and redeploy. The server fails closed until it has the new token. |
| `UPSTASH_REDIS_REST_TOKEN` (gateway) | Only if the gateway uses Upstash directly; a Vercel Marketplace store sets KV_REST_API_* itself. Reset in Upstash, sync, redeploy. |
| `GATEWAY_TOKEN_SECRET` (gateway) | Signs every device out and resets the hashed counters in the store. Rotate only on purpose. |
| `GATEWAY_INVITE_CODES` (gateway) | A list, not a key: removing a code revokes that tester. Edit the list here, then sync and redeploy. |
| `WAITLIST_ADMIN_PASSWORD` (site) | Change it here, sync, redeploy the site; the owner logs into the waitlist admin with the new one. |
| `DODDY_SESSION_SIGNING_KEY` (backend) | Signs every backend session out. Must differ from the voice server's key. Rotate only on purpose. |
| `COMPOSIO_API_KEY` (backend) | Make a new project key in Composio, put it here, sync and deploy, then revoke the old one. Connected accounts stay in Composio. |
| `MONID_API_KEY` (backend) | It spends Doddy's Monid wallet: revoke fast if it leaks. New key here, sync, deploy, revoke the old one. |
| `APNS_PRIVATE_KEY` (server/messaging) | Make a new APNs key in the Apple Developer account, paste the .p8 text into this Secure Note, update APNS_KEY_ID on the host, sync, deploy, then revoke the old key. |
| `TWILIO_AUTH_TOKEN` (server/messaging) | Make a new token in Twilio, put it here, sync and deploy, then retire the old one. Texts and verify codes fail while the host has a retired token. |
| `MEMORY_ENCRYPTION_KEY` (server/messaging) | Never rotate casually: there is no re-encryption migration. 1Password's job here is the backup copy. |
| `ELEVENLABS_TOOL_SECRET` (server/messaging) | Change the ElevenLabs workspace secret and this value at the same time, or phone-call tools stop working. |
| `ANTHROPIC_API_KEY` (server/messaging) | New key in the Anthropic console, put it here, sync and deploy, revoke the old one. Without it, news digests fall back to plain headlines. |
| `GNEWS_API_KEY` (server/messaging) | New key from GNews, put it here, sync and deploy. |

**Host tokens:**
- `vercel-token`: make a new one, update the item, delete the old one in Vercel.
- `render-api-key`: make a new one, update the item, delete the old one in Render. It has no expiry that Render documents.

**If a key leaks:** revoke it at the provider first, then make a new one, store it, and sync. Downtime beats a leaked key.

## When 1Password is unavailable
- **The hosts keep running** with the values they have.
- **For an urgent change,** set it directly in the host's dashboard, then put the same value in 1Password as soon as you can.
- **Afterwards, check with a dry run:**
  - **Render:** it says `same` once the two match.
  - **Vercel:** it says `change`, since it can't compare. Applying then writes the same value again, which is harmless.
- **Keep the 1Password Emergency Kit** where you can reach it without 1Password.

## When someone leaves
- **Access:** remove them from every vault.
- **Rotate what they could read:** everything in `doddy-dev`, plus anything in `doddy-prod` they had.
- **Their own tokens:** delete any host token they created.

## AI agents
- **Claude sessions never get a 1Password token or a host API key.** With either, an agent could read every secret it reaches, and masking in `op run` is not a boundary because the agent chooses the command. Tests use fakes.
- **If you run Claude Code on your Mac,** run the sync in a different terminal from the agent. A Touch ID approval covers every process in that terminal window.

## Known limits
**Assumed from the vendors' docs, not yet seen against the real APIs:**
- **Vercel:** create with `type: "sensitive"`; update a value with `PATCH /v9/projects/{id}/env/{envId}`; the list returns `updatedAt` per variable.
- **Render:** the service variable list returns `[{envVar: {key, value}, cursor}]`; `PUT` on one key answers with that key and value.

**Other limits:**
- **First run:** the owner's first run is the real test. Run it one target at a time, as above.
- **Render storage:** whether the Render services keep their values on the service or in an environment group is unknown.
- **The voice token server has no `.env.example`**, so `check` can't cross-check its names. Its README table is the list.
- **Supabase** isn't a sync target.
