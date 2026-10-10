# Deploying the backend to Render

Status 2026-10-10: **not deployed yet.** Owner choice: Render workspace **SLIYD**, service name **`doddy`**.
Since ADR-193 the backend starts in live mode with **only a Monid key** (web search); Composio is optional.

## Web search only (fastest path)

1. Render dashboard → workspace **SLIYD** → **New → Web Service** → repo `Bienos/doddy.2`, branch
   `claude/elegant-knuth-hc1aql`. Do **not** use New → Blueprint: `render.yaml` also creates the paid
   messaging services and Postgres.
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
   | `DODDY_PUBLIC_BASE_URL` | the service's origin, e.g. `https://doddy.onrender.com` (no path) |
   | `DODDY_SESSION_SIGNING_KEY` | **secret**: Render's "Generate" button, or `openssl rand -base64 32` |
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

Blocked on a working Composio project key (the one in the cloud session was rejected with HTTP 401). Then run
`npm run setup:tools -- --create` and the Calendar setup (`ONLINE_ACCOUNTS.md`), and add `COMPOSIO_API_KEY`,
the `COMPOSIO_GOOGLECALENDAR_*` pair and any `COMPOSIO_<TOOLKIT>_*` pairs. All three Composio base values or none:
half a setup stops the server.

## Free plan caveats

* Sleeps after idle time, so the first request (and an OAuth return) can be slow.
* The SQLite file lives on the instance disk and **resets on restart and redeploy**: switches (including web search),
  connections and receipts disappear; switch web search on again. Composio still holds any accounts; users reconnect.
  A paid plan with a disk keeps them.
* Free plan is fine for one owner testing; it is not a production setup.

## Still not production

Live + production is refused by the server until real app sign-in exists; tokens are owner-minted bearer tokens.
