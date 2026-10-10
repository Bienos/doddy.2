# Go live: the daily news message (owner steps)

Date: 2026-10-10. Turns on **one** messaging-server feature: a short daily news digest at your
chosen time. Two ways (ADR-174):
- **In the app only** (cheapest): the digest waits in Settings → Messages from Doddy → Daily news.
  No Apple Developer account needed; skip section 1 and the APNs rows.
- **As a notification**: the same digest also arrives as a notification. Needs section 1.

Nothing here has been done yet; every step needs your accounts. Status of the code: `N1_NEWS_STATUS.md` (server tested on Linux; the app has not been
compiled in Xcode yet; no real Claude, GNews or Apple push call has been made).

## What you need

| Account | Why | Cost |
|---|---|---|
| Apple Developer Program (notification path only) | Notifications need an APNs key, and the app must be signed by a team with Push Notifications | 99 USD a year |
| **Render** | Runs the messaging server, its worker and Postgres | Paid plans: check the prices Render shows before you confirm |
| **Anthropic API** | Claude Haiku writes one line per story. Without a key, the message is the plain top-3 headlines | About one small call per user per day; set a spend limit |
| GNews (optional) | Only for your **own keyword** topics. The curated topics use RSS feeds and need no account. Free plan: 12-hour delay, not for commercial use | Paid plan if used |

Not needed for this: Twilio, ElevenLabs, `PUBLIC_BASE_URL`, the Composio backend.

## 1. Apple (notification path only, about 15 minutes)
1. developer.apple.com → Certificates, Identifiers & Profiles → **Identifiers** → the app's ID.
   The project's default is `com.bienos.doddy2.dev` (`DODDY_APP_BUNDLE_IDENTIFIER` in
   `project.yml`); create it if it doesn't exist. Tick **Push Notifications** and save.
2. **Keys** → **+** → name it "Doddy APNs", tick **Apple Push Notifications service (APNs)** →
   Continue → Register → **Download** the `.p8` file (you can download it only once).
3. Write down the **Key ID** (on the key page) and your **Team ID** (top right, or Membership).
4. Keep the `.p8` file private. Never paste it into a chat, a commit or an issue.

## 2. Anthropic (5 minutes)
1. console.anthropic.com → **API Keys** → Create key, name it "doddy-messaging".
2. **Limits** → set a monthly spend limit (for example 5 USD while testing).

## 3. Render (about 20 minutes)
Created by hand rather than with `render.yaml`: the blueprint would also create
`doddy` (the backend; since ADR-193 it starts with a Monid key alone, but it is a separate decision).

1. **New → Postgres**: name `doddy-db`, region **Frankfurt**, PostgreSQL **16**, the smallest
   paid plan. When it is ready, copy its **Internal Database URL**.
2. **New → Environment Group** `doddy-messaging-secrets` with:

   | Key | Value |
   |---|---|
   | `DATABASE_URL` | the Internal Database URL from step 1 |
   | `NODE_VERSION` | `22` |
   | `TRUST_PROXY_HOPS` | `1` (Render's proxy; used for per-IP rate limits) |
   | `APNS_TEAM_ID` | your Team ID (notification path only, like the next three) |
   | `APNS_KEY_ID` | the Key ID |
   | `APNS_PRIVATE_KEY` | the whole `.p8` file, including the `BEGIN`/`END` lines |
   | `APNS_BUNDLE_ID` | `com.bienos.doddy2.dev` (or the identifier you build with) |
   | `ANTHROPIC_API_KEY` | the key from step 2 |
   | `GNEWS_API_KEY` | only if you bought a GNews plan |

3. **New → Web Service** from `Bienos/doddy.2`:
   - branch `claude/elegant-knuth-hc1aql` until PR #5 is merged, then the default branch;
   - region Frankfurt, **Root Directory** `server/messaging`, runtime Node;
   - Build `npm ci && npm run build`, Start `npm start`, Health Check Path `/healthz`;
   - link the environment group; turn **Auto-Deploy** off for now.
4. **New → Background Worker** from the same repo, branch and root directory:
   Build `npm ci && npm run build`, Start `npm run worker`, same environment group.
   The worker sends the messages and runs the daily schedule; without it nothing goes out.
5. Check:
   - open `https://<your web service>.onrender.com/healthz`; it should answer `{"ok":true}` (it checks the database);
   - in the web service's **Logs**, the line `configured features` should show `newsWriter: true`,
     and `push: true` on the notification path (`newsSearch: true` only with GNews). `sms: false`
     and `calls: false` are expected here.

The server creates its tables on first start (migrations run automatically).

## 4. The app (about 15 minutes, on a Mac with Xcode)
1. Notification path only: in `project.yml` set `DODDY_PUSH_ENTITLEMENTS: DoddyApp/Doddy.entitlements`
   (it is empty by default so a free Apple ID can build; ADR-174).
2. `xcodegen generate`, open `Doddy.xcodeproj`, target **Doddy** → Signing & Capabilities →
   choose your **Team** (`DEVELOPMENT_TEAM` is empty in the repo on purpose). On the notification
   path, check Push Notifications is listed.
3. Run on your **iPhone** from Xcode. This is a Debug build, which is what shows the server
   address field below (ADR-175: shipped builds use only the address built into
   `ServerConfig.swift`). Debug builds use Apple's sandbox push service; the server picks the
   matching one from what the app reports.
4. In Doddy: **Settings → Messages from Doddy → Notifications and texts**:
   - **Server (development)**: paste `https://<your web service>.onrender.com` and press Return;
   - notification path: **Turn on notifications** → allow when iOS asks, then optionally
     **Send a test notification**; it should arrive within a few seconds.
5. **Settings → Messages from Doddy → Daily news**: turn it on, pick topics (and own keywords or
   feeds), the time and language. Switch on **Notification** for the notification path, or leave
   both switches off for in the app only. **Save**.
6. **Send me one now** to see a digest straight away. It appears under **Recent** on that screen,
   with links and a note saying how it reached you ("Sent to you" or "In the app only").

## If something goes wrong
| What you see | Likely cause |
|---|---|
| "Updates need a Doddy messaging server" | The address is empty, not https, or has a path |
| Test notification never arrives | Bundle ID on Render ≠ the app's, Push not enabled on the App ID, the key's Team ID ≠ the signing team, or notifications are off in iOS Settings |
| Digest says "Only here: notifications or texts weren't on" | You chose Notification, but notifications aren't on for this iPhone (step 4.4). The digest is still in the app |
| "This build of Doddy can't receive notifications" | The build has no push permission: set `DODDY_PUSH_ENTITLEMENTS` and sign with a paid team (step 4.1) |
| Server answers 429 `too_many_attempts` on a code | Verify codes are limited per number (3 an hour, 6 a day) and per server per day |
| Lines are plain headlines, no AI line | `ANTHROPIC_API_KEY` missing or rejected, or Claude's answer couldn't be used; the logs say which (`writer_*`) |
| Own keyword topic finds nothing | No `GNEWS_API_KEY`; only RSS stories are searched |

## What leaves the iPhone and the server
- App → messaging server: an anonymous account token, the notification token, your news topics,
  keywords, feeds, time and language. Settings → Privacy → What leaves this iPhone lists this.
- Server → Anthropic: topic names and public headlines with their one-line summaries. Never
  notes, phone numbers or account IDs. Server → GNews: your own keywords. Server → Apple: the
  notification text.

## After it works
Tell me the Render URL (not any key) and I can read the service logs with the Render connector,
or set the default server address in `ServerConfig.swift` so the field doesn't need filling in.
