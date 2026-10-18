# Deploying the backend to Render

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
* **Next:** limit auth config `ac_XUGmWDS79r-R` (or a new one) to `gmail.readonly` and `gmail.compose` (identity
  scopes `openid`, `email`, `profile`, `userinfo.email`, `userinfo.profile` are also accepted), then connect again. If
  Composio's managed Gmail app won't take a narrower list, it needs Doddy's own Google OAuth client.

Earlier (2026-10-10): service `doddy` (`srv-db559odckfvc7390v2i0`, https://doddy.onrender.com) in workspace **SLIYD**,
web search verified there. That account is no longer the one in use; delete the old service there if it still runs.

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
   | `DODDY_DB_PATH` | `./data/doddy.sqlite` |
   | `DODDY_PUBLIC_BASE_URL` | the service's origin, e.g. `https://doddy-yaci.onrender.com` (no path) |
   | `DODDY_SESSION_SIGNING_KEY` | **secret**: Render's "Generate" button, or `openssl rand -base64 32`. Must decode to at least 32 bytes: a typed password or a 32-character hex string is refused |
   | `MONID_API_KEY` | **secret**: app.monid.ai → Access → API keys (`monid_live_…`) |

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

## Free plan caveats

* Sleeps after idle time, so the first request (and an OAuth return) can be slow.
* The SQLite file lives on the instance disk and **resets on restart and redeploy**: switches (including web search),
  connections and receipts disappear; switch web search on again. Composio still holds any accounts; users reconnect.
  A paid plan with a disk keeps them.
* Free plan is fine for one owner testing; it is not a production setup.

## Still not production

Live + production is refused by the server until real app sign-in exists; tokens are owner-minted bearer tokens.
