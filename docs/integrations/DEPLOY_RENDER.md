# Deploying the backend to Render

**Current state (2026-10-19):** the live `doddy` service runs the **ASK-01 server** (deploy of `5904c9c`, after
PR #87), not the older one. Gmail read and send were verified end to end on 19 Oct (below). The app build on the
owner's iPhone predates ASK-01 and doesn't send an approval, so the server refuses its cloud reads with 403 "Doddy
has to ask first" until a new build from the main branch is installed. Composio (Gmail) was verified after the
11 Oct note below was written; the app talking to this server is still **not verified**.

Status 2026-10-11: **deployed again on a new Render account** (owner request). Workspace **Patryk's workspace**
(`tea-db5kphqd0e5s73fqlpmg`), service **`doddy`** (`srv-db5kvu142hec739b9tu0`, https://doddy-yaci.onrender.com; the
name `doddy.onrender.com` was taken), free plan, Frankfurt, branch `claude/loving-dirac-uuxoux` (first live deploy at
commit `007de48`), auto-deploy **off**: deploy by hand after pushing. Environment set in the dashboard: Monid, the
Composio key with the Google Calendar pair and a Gmail pair, and a new session signing key (so tokens minted for the
old server do not work here: mint a new one, step 4). Verified on 2026-10-11 only that the server starts: the log shows
`"event":"listening","mode":"live","auth":"signed"` and `GET /v1/health` answered
`{"status":"ok","mode":"live","api":"v1","capabilities":["calendar.listEvents"]}`. **Not yet verified on this
server:** a web search, a Composio connection (Calendar or Gmail), and the app talking to it.
Created with the Render API, which cannot set a root directory or health check path, so the build and start commands
`cd backend` first; set the health check path to `/v1/health` in the dashboard if wanted.
Since ADR-193 the backend starts in live mode with **only a Monid key** (web search); Composio is optional.

**2026-10-18, first live Gmail attempt (owner asked the agent to do it end to end):**
* Render's logs from 2026-10-11 to 2026-10-18 show no app request to this server, only `/v1/health` and unmatched
  paths. The app has never used it. The old SLIYD service answers "This service has been suspended".
* The agent replaced `DODDY_SESSION_SIGNING_KEY` with a new key (the owner agreed the value would appear in that
  session's transcript; press **Generate** in the dashboard to replace it, then mint a new token). Deployed `754e5d6`.
* **Temporary:** `DODDY_APP_RETURN_URL` is `https://doddy-yaci.onrender.com/v1/health`, so a desktop browser lands on
  a real page with the connection ID in the address bar. **Set it back to `doddy-dev://connected-apps/return`** after
  the test, or the app's sign-in can't return.
* `GET /v1/tools`: Gmail and Google Drive set up (disconnected), Notion, Todoist and Outlook not set up, web search ready.
* `POST /v1/tools/gmail/connect` → **502 `provider_unavailable` in 583 ms**: Composio refused the link request. A
  local run of the same adapter with an invalid key gives the same answer (HTTP 401 underneath); an unknown auth
  config would give a 404 (`connection_expired`) instead. Most likely cause: `COMPOSIO_API_KEY` is not a valid
  project key (`ak_…` from platform.composio.dev; a `ck_…` key is for Composio's own apps and is refused). Unverified,
  because the server never logs Composio's answer.
* Every wake on the free plan is a new instance (a new instance ID in the logs), so the SQLite file, connections and
  switches are lost after about 15 minutes idle, not only on redeploy.
* Same day, after the owner put a new `ak_…` project key on Render and the agent set
  `COMPOSIO_GMAIL_AUTH_CONFIG_ID=ac_XUGmWDS79r-R` (deploy `dep-dba9h6nbtjjs73eaou70`), the live path worked up to
  the grant check:
  1. `POST /v1/tools/gmail/connect` → 200 with a `connect.composio.dev/link/…` link.
  2. The owner approved Google in a browser and landed on `/v1/health?attempt=…&status=success&connected_account_id=ca_…`.
  3. `POST /v1/tools/gmail/complete` (callback mode) → 200. The server re-read the connection: active, owned by this
     user, the right auth config. **Composio does report Gmail's granted scopes** (otherwise the verdict would have been
     `grant_unverifiable`). They were broader than `gmail.readonly` + `gmail.compose`: status
     `permission_insufficient`, reason `grant_too_broad`, receipt `blocked`, as designed.
  4. Switching `check_email` on → 403 `permission_insufficient`; running it → 403. No email was read.
  5. `POST /v1/tools/gmail/disconnect` → 200, revoked and deleted at Composio (`remoteCleanup: none`).
* Again after PR #87 (ASK-01, deploy of `5904c9c`; allowed Gmail grants are now `gmail.readonly`, `gmail.compose`,
  `gmail.send`, `gmail.modify` plus identity). Connect and complete worked; still `grant_too_broad`. The new
  `grant_checked` log line shows what auth config `ac_XUGmWDS79r-R` asks Google for: `https://mail.google.com/` (full
  mailbox, incl. permanent delete), `contacts.readonly`, `contacts.other.readonly`, `profile.emails.read`,
  `user.birthday.read`, `user.addresses.read`, `user.emails.read`, `user.phonenumbers.read`,
  `profile.language.read`, plus identity. Disconnected at once (revoked and deleted). No tool ran.
* A sign-in approved at 12:13 UTC was never completed (the 10-minute attempt expired, then the instance slept), so its
  Composio connection may still be live with the broad grant. Delete it in Composio (Connected Accounts, Gmail).
* Narrowing the managed config's scopes in Composio's dashboard changed nothing: two more connects granted the
  same list. Composio's managed Google app asks for its own fixed scopes.

**2026-10-19: Gmail works end to end on Render (read and send, with ASK-01).**
* The owner made Doddy's own Google OAuth client (Google Cloud project `doddy`, Web application client, redirect
  URI `https://backend.composio.dev/api/v1/auth-apps/add`, app in Testing with the owner as test user, Gmail API
  enabled in that project) and a Composio **custom** Gmail auth config, `ac_W0OsyA4HbILO`, with only the four
  Gmail scopes plus `openid email profile`. Render: `COMPOSIO_GMAIL_AUTH_CONFIG_ID=ac_W0OsyA4HbILO`,
  `DODDY_ATTEMPT_TTL_SECONDS=1800` (the 10-minute attempt expired twice while the owner was signing in; Composio's
  own `lk_…` link still expires after about 10 minutes).
* Connect → complete: `connected`. `grant_checked` verdict `ok`: `gmail.readonly`, `gmail.compose`, `gmail.send`,
  `gmail.modify`, `openid`, `userinfo.email`, `userinfo.profile`.
* ASK-01 live: `check_email` without an approval → 403 "Doddy has to ask first"; nothing read.
* First read failed with 502 `provider_unavailable`: the Gmail API was enabled in another Google Cloud project
  than the OAuth client's. After enabling it in `doddy`: `check_email` (owner's yes, max 5) → 200, 5 messages,
  receipt `succeeded`. Only the count and times were shown in the session.
* `send_email` (owner's yes on the exact card: to the owner's own address, subject "Doddy test") → 200,
  "sent", Gmail message id returned, receipt `succeeded`.
* Then `gmail/disconnect` → revoked and deleted, and `DODDY_APP_RETURN_URL` set back to
  `doddy-dev://connected-apps/return`.
* **Still to do:** the iPhone app talking to this server (new build from the main branch, token minted with a new
  `DODDY_SESSION_SIGNING_KEY`); leftover Composio connections from expired attempts (delete in Composio); a paid
  plan with a disk or an external database so connections survive the free plan's sleep; Google verification of
  the OAuth app before anyone but test users can connect (tokens of a Testing app expire after 7 days).

Earlier (2026-10-10): service `doddy` (`srv-db559odckfvc7390v2i0`, https://doddy.onrender.com) in workspace **SLIYD**,
web search verified there. That account is no longer the one in use; delete the old service there if it still runs.

## Secrets come from 1Password (ADR-493)
The values for every secret below live in 1Password (`docs/security/SECRETS_1PASSWORD.md`). After the first setup, change them with the sync tool rather than by typing in the dashboard:
```
op run --env-file=secrets/deploy.env.op -- node tools/secrets/sync.mjs --target render:doddy
```
It prints the plan. Run it again with `--apply --confirm <code>` to write it, then deploy by hand, because auto-deploy is off.

Two Render facts to know:
- **Every Render API read returns values,** so the Render API key can read every secret. It lives only in the owner-only 1Password vault.
- **`sync: false` doesn't work inside an environment group:** Render ignores those keys. So `render.yaml` puts the messaging secrets on the web service and on the worker as service-level `sync: false` (ADR-495), and Render asks for them twice when the Blueprint is created.

On 18 Oct 2026 the workspace also runs copies of `doddy-voice-token` and `doddy-gateway` on a non-default branch. They aren't managed by the sync tool (owner decision pending).

## Web search only (fastest path)

1. Render dashboard → your workspace → **New → Web Service** → repo `Bienos/doddy.2`, the default branch
   (`claude/loving-dirac-uuxoux` on 2026-10-11). On a new Render account, first connect GitHub and give Render
   access to `Bienos/doddy.2` (Account Settings → Git Providers), or the repo cannot be fetched. Do **not** use
   New → Blueprint: `render.yaml` also creates the paid messaging services and Postgres.
   * Name `doddy`, region Frankfurt, plan Free, root directory `backend`
   * Build `npm ci && npm run build`, start `node dist/src/server.js`, health check path `/v1/health`
2. Environment (Render → service → Environment). Type the secrets **there**, never in chat or git:

   | Key | Value |
   |---|---|
   | `NODE_VERSION` | `22` |
   | `DODDY_MODE` | `live` |
   | `DODDY_ENV` | `development` (live + production is refused until real sign-in exists) |
   | `DODDY_HOST` | `0.0.0.0` |
   | `DODDY_PORT` | `10000` |
   | `DODDY_AUTH_MODE` | `signed` |
   | `DATABASE_URL` | **secret**: the Postgres connection string (ADR-525; see "Database" below). Without it the data is lost on every sleep |
   | `DATABASE_CA_CERT` | the database's root CA as PEM (Supabase: `prod-ca-2021.crt` from the project's Database settings) |
   | `DODDY_PUBLIC_BASE_URL` | the service's origin, e.g. `https://doddy-yaci.onrender.com` (no path) |
   | `DODDY_SESSION_SIGNING_KEY` | **secret**: Render's "Generate" button, or `openssl rand -base64 32`. Must decode to at least 32 bytes: a typed password or a 32-character hex string is refused |
   | `MONID_API_KEY` | **secret**: app.monid.ai → Access → API keys (`monid_live_…`) |
   | `STRIPE_SECRET_KEY` | optional, **secret**, **test key only** (`sk_test_…` or `rk_test_…`; a live key stops the server): Stripe Dashboard → Developers → API keys, in test mode. Payments inside Doddy (ADR-530) need it, and a persistent disk before anything beyond testing (`docs/implementation/PAYMENTS_STATUS.md`) |

   Leave every `COMPOSIO_*` variable out (all of them, or all three Calendar ones plus a toolkit pair later).
3. Deploy. `GET https://<service>/v1/health` should answer `"mode":"live"`. If the server refuses to start, the
   log names the variable (never its value).
4. Mint a phone token with the **same** signing key, on your computer:
   `cd backend && npm ci && npm run build && DODDY_SESSION_SIGNING_KEY=… npm run session:mint -- [user-uuid] [ttl-days]`
   (default 7 days, max 30). It is printed once and is a bearer credential: put it only into the app.
5. App: Settings → Connected Apps server → the https address and the token. Then Settings → Online accounts →
   Web search shows "Ready, no sign-in"; switch it on and ask Doddy something current.

Checks after a search: Render logs show `POST /v1/tools/run` with status 200; app.monid.ai shows the run and its cost.

## Adding the accounts later (Composio)

2026-10-11: on the new service the owner entered a Composio key, the Google Calendar pair and a Gmail pair, and the
server accepted them at startup (`COMPOSIO_COMPLETION_MODE=callback`, single-owner development). That checks only the
configuration's shape: no account has been connected or used through this server yet. For more toolkits (Drive,
Notion, Todoist), run `npm run setup:tools -- --create` (`ONLINE_ACCOUNTS.md`; it does not cover Calendar) and add
the printed `COMPOSIO_<TOOLKIT>_*` pairs, both values of a pair or neither. The three base values (`COMPOSIO_API_KEY`
and the `COMPOSIO_GOOGLECALENDAR_*` pair) are all or none: half a setup stops the server.

## Database (ADR-525)

Since 19 Oct 2026 the server keeps its data in Postgres, so a sleep, restart or deploy no longer loses connections,
switches, approvals or receipts. For testing it is the free Supabase project `doddy-gateway` (ref
`sliondswemhneuzehpoq`, Frankfurt):

* Schema `doddy_backend`, created by the migration `doddy_backend_schema`. The server creates its tables there at
  startup. The public API roles (`anon`, `authenticated`) have no access and the schema is not exposed by the Data API.
* Login role `doddy_backend` (no other rights, 10 connections at most), through the **session pooler**:
  `postgresql://doddy_backend.sliondswemhneuzehpoq:<password>@aws-1-eu-central-1.pooler.supabase.com:5432/postgres`.
  The direct host `db.<ref>.supabase.co` is IPv6 only on the free plan, which Render can't reach.
* `DATABASE_CA_CERT` is Supabase's root CA (Dashboard → Database → Settings → SSL certificate, `prod-ca-2021.crt`).
* **New password:** Supabase → SQL editor: `alter role doddy_backend password '<new>';`, then change
  `DATABASE_URL` on Render. The 19 Oct password was generated in a Claude session and appears in its log: change it
  before real users arrive.
* **Free plan limits:** 500 MB, and the project pauses after a week without any use (Dashboard → Restore). Supabase
  Pro ($25 a month) removes the pause. Moving to another Postgres (Render Postgres, Neon) needs only a new
  `DATABASE_URL`.
* Checked on Render on 19 Oct: the log line `"store":"postgres"`, and all nine tables present in `doddy_backend`.

## Sign-in with Apple or Google (Supabase Auth, ADR-526)

The server can accept Doddy accounts from Supabase Auth: `DODDY_AUTH_MODE=supabase` and
`SUPABASE_URL=https://sliondswemhneuzehpoq.supabase.co`. It checks each access token against the project's public
keys; no Supabase secret is needed. In development, when `DODDY_SESSION_SIGNING_KEY` is also set, the owner's minted
token keeps working next to it; production accepts Supabase sign-ins only.

Before people can sign in (owner):
1. Supabase → Authentication → Sign In / Providers → **Apple**: on; Client IDs: the app's bundle ID. Needs the paid
   Apple Developer team and the Sign in with Apple capability on the App ID (go-live checklist A5).
2. Google Cloud → APIs & Services → Credentials → Create OAuth client ID → **iOS**, with the app's bundle ID. Then
   Supabase → Providers → **Google**: on; Client IDs: that iOS client ID.
3. The app's sign-in screens (not built yet, see ADR-526).

## Free plan caveats

* Sleeps after idle time, so the first request (and an OAuth return) can be slow.
* Without `DATABASE_URL` the server falls back to PGlite on the instance disk, which **resets on restart and
  redeploy**. With it (ADR-525), nothing is lost.
* Free plan is fine for one owner testing; it is not a production setup.

## Still not production

Live + production needs `DODDY_AUTH_MODE=supabase` (ADR-526) and `DATABASE_URL`, and the server refuses to start
without them. Until the app has its sign-in screens, the owner uses a minted bearer token in development.
