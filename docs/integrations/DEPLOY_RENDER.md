# Deploying the backend to Render

Status 2026-10-10: **not deployed.** `render.yaml` is a draft blueprint; it has never run on Render.

Blocked on the owner: (1) a working Composio project key (the one in the cloud session was rejected with HTTP 401),
(2) `npm run setup:tools -- --create` and the Calendar setup to get auth config IDs and pinned versions,
(3) which Render workspace to use (the account has SLIYD and NAMEATLAS; "DODDY" does not exist).

## Steps (owner)

1. Run the setup scripts locally with your key (`backend/README`-style steps in `ONLINE_ACCOUNTS.md`); keep the printed IDs.
2. Render dashboard > New > Blueprint > this repo, branch `claude/blissful-thompson-72xwl1` > fill the `sync: false` values.
3. Set `DODDY_PUBLIC_BASE_URL` to the service's `https://….onrender.com` origin; redeploy.
4. Check `GET <url>/v1/health` says `"mode":"live"`.
5. Mint a phone token with the **same** signing key (Render > service > Environment > reveal `DODDY_SESSION_SIGNING_KEY`):
   `cd backend && npm run build && DODDY_SESSION_SIGNING_KEY=… npm run session:mint -- [user-uuid] [ttl-days]` (default 7 days, max 30; see `src/mintSession.ts`). The token is printed once; it is a bearer credential.
6. In the app: Settings > Connected Apps server: the https URL and the token.

## Free plan caveats

* Sleeps after idle time, so the first request (and an OAuth return) can be slow.
* The SQLite file lives on the instance disk and **resets on restart and redeploy**: connections, switches and
  receipts disappear while Composio still holds the accounts. Users reconnect; remove stale connections in the Composio
  dashboard. A paid plan with a disk (added in the dashboard) keeps them.
* Free plan is fine for one owner testing; it is not a production setup.

## Still not production

Live + production is refused by the server until real app sign-in exists; tokens are owner-minted bearer tokens.
