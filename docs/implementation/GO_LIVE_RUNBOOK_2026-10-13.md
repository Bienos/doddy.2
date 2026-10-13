# Go-live runbook: signing, a device build and the live services (2026-10-13)

Owner request: "build the section 'built but needs a service you must set up', do whatever you can, then guide me
step by step, and the real signing as well." This is the step-by-step guide. Do the parts in order: each part
depends on the one before it.

Where you'll type a secret, it says **secret**. Type secrets only into the dashboard named (Render, Vercel, Xcode, the
app). Never put them in chat, in git or in this file.

## Where things stand (checked 2026-10-13, read-only)

| Piece | Where | State today | What `scripts/check_live_services.sh` says |
|---|---|---|---|
| iOS app | GitHub Actions, Xcode 26.6 | Compiles; unit tests and all 26 UI tests pass (PR #69/#70) | n/a |
| Backend (web search, Gmail, Calendar, Notion, Todoist, Outlook through Composio) | Render `doddy`, https://doddy-yaci.onrender.com, free plan | Up, live mode, signed tokens. Only the Calendar capability reports in; no account has been connected through it yet | OK |
| Messaging server (notifications, texts, calls, daily news) | Render `doddy-messaging`, https://doddy-messaging-zw1n.onrender.com, free plan; free Postgres `doddy-messaging-db` expires **2026-11-10** | Up (`/healthz` ok). The worker runs inside the web process (`RUN_WORKER_IN_WEB`, log "worker started in the web process"), but the free plan sleeps, so scheduled sends stop while it sleeps. Log at start: push off, SMS off, calls off, news writer on, news search off | OK |
| Voice token server | Render `doddy-voice-token`, https://doddy-voice-token.onrender.com, free plan (moved from Vercel 2026-10-13, owner's choice) | Up (`/healthz` ok), branch `claude/affectionate-tesla-nqu0nj`, auto-deploy off. Answers `500 server_not_configured` until you add `ELEVENLABS_API_KEY` and `DODDY_ACCESS_CODES`. The old Vercel project still answers 402 | FAIL 500 until the two secrets are in |
| Ask Doddy gateway (OpenAI) | Render `doddy-gateway`, https://doddy-gateway.onrender.com, free plan (moved from Vercel 2026-10-13, ADR-442) | Up (`/healthz` ok). Answers `503 notConfigured` until you add the keys in Part 4 | FAIL 503 until Part 4 |
| ElevenLabs voice agent | `agent_0501m4et27vyeawrwqfdxxfszfa6` | Live. **Authentication off**, recordings kept forever (`retention_days: -1`), at most 2 calls at once and 10 a day | n/a |
| "Hey Doddy" | Picovoice, your own AccessKey typed into the app | Nothing to deploy; needs your key | n/a |

Re-run `scripts/check_live_services.sh` after each part below. It sends no secrets.

---

## Part 1. Signing and the first build on your iPhone (about 30 minutes)

You need: a Mac with Xcode 26 (the CI used 26.6), your paid Apple Developer account, the iPhone with a cable.

### 1.1 Get the project
```sh
git clone https://github.com/Bienos/doddy.2 && cd doddy.2
brew install xcodegen node
make project                 # writes Doddy.xcodeproj from project.yml
```
Run `make project` again every time you pull. It regenerates the project and forgets anything you clicked in Xcode,
which is why step 1.3 puts your team in `project.yml`.

### 1.2 Find your Team ID
1. Open https://developer.apple.com/account and sign in.
2. Scroll to **Membership details**. Copy **Team ID** (10 characters, like `AB12CD34EF`). It isn't secret.

### 1.3 Put the team in the project
In `project.yml`, line 35, change `DEVELOPMENT_TEAM: ""` to `DEVELOPMENT_TEAM: "AB12CD34EF"` (your ID). Then
`make project` again. Committing that line is your call (ADR-013/ADR-023): it saves every future session from asking.

### 1.4 Decide the bundle ID now (ADR-023)
Today it's `com.bienos.doddy2.dev`. **The bundle ID you upload to App Store Connect with is permanent for that app
record.** If you want something like `com.bienos.doddy`, change `DODDY_APP_BUNDLE_IDENTIFIER` in `project.yml`
(line 38) before step 1.6. Every other ID follows it automatically: `.widgets`, `.share`, `.watchkitapp`,
`.watchkitapp.widgets`, the App Group `group.<id>`, the iCloud container `iCloud.<id>`.

### 1.5 Sign in to Xcode
Xcode → Settings → **Accounts** → **+** → Apple ID → sign in with your developer account. Your team should show
"Admin" or "Account Holder".

### 1.6 Open and let Xcode register everything
1. `open Doddy.xcodeproj`.
2. Click the blue **Doddy** project at the top of the left sidebar.
3. Do this for **each** of the targets Doddy, DoddyWidgets, DoddyShare, DoddyWatch and DoddyWatchWidgets:
   1. Open **Signing & Capabilities**.
   2. Check that "Automatically manage signing" is on and Team is yours.
   3. Wait for the spinner to finish. Xcode creates the App ID and the App Group `group.com.bienos.doddy2.dev`.
4. If a target says "App Group … not registered", click **Try Again**. If it still fails, register the group by hand:
   1. Open https://developer.apple.com/account/resources/identifiers.
   2. Click **+** → **App Groups** → identifier `group.com.bienos.doddy2.dev`.
   3. Open each App ID → App Groups → **Configure** → tick the group.

### 1.7 Prepare the iPhone
1. Connect it by cable, unlock it, and tap **Trust**.
2. Turn on iPhone Settings → Privacy & Security → **Developer Mode**. It restarts; confirm after the restart.
3. In Xcode's top bar, pick the scheme **Doddy** and your iPhone as the destination.

### 1.8 Build and run
1. Press **⌘R**.
2. If the iPhone says "Untrusted Developer", go to Settings → General → **VPN & Device Management** → your profile
   → **Trust**.
3. If the build fails, copy the **first** red error (not the whole log) and send it to the next session.

### 1.9 The watch (optional now)
The watch app is built and installed with the iPhone app. On the watch, turn on Settings → Privacy & Security →
**Developer Mode**. Then open the Watch app on the iPhone → Doddy → **Install**.

### 1.10 Tick it off
In `docs/implementation/MAC_VERIFICATION_CHECKLIST_2026-10-10.md`, fill in the result log at the bottom: date, Xcode
version, iPhone model and iOS version, "§1 builds and runs on device".

At this point everything in the "works with no accounts" list works on the phone: notes, lists, search, export,
backup, widgets (App Group), the share sheet, Face ID lock, alarms (iOS 26), Siri phrases, the watch.

---

## Part 2. Vercel: un-block the voice token server and the gateway (10 minutes plus your payment)

Both Vercel projects answer `402 DEPLOYMENT_DISABLED`. That's Vercel refusing to serve, not a code problem.

1. Open https://vercel.com/doddyyyy and log in as `patcich55`.
2. Look for the red banner, or go to Settings → **Billing**. Either fix the payment method, or check whether the
   team is on Hobby and went over a limit. Hobby isn't meant for commercial use, so Pro ($20/month) is the clean
   fix if you'll put testers on it.
3. Once billing is fine, redeploy each project. For `doddy-voice-token` and then `doddy-gateway`: open the project →
   **Deployments** → the newest **Production** one → **⋯** → **Redeploy**.
4. Run `scripts/check_live_services.sh`. Expected: `voice-token 401` (a wrong code is refused, which is correct).
   The gateway shows `503` until Part 4.

Note: the old docs mention a team `bienos`. Your Vercel connector now sees only the team `doddyyyy`, which holds all
three projects (`doddy` = the website, `doddy-gateway`, `doddy-voice-token`).

---

## Part 3. Voice: private token, then lock the agent (20 minutes)

Today "Talk to Doddy" uses the public development agent: anyone with its ID can talk to it on your minutes, and
every recording is kept forever. Fix it in this order. Turning authentication on first would break the app.

### 3.0 Where the token server runs
Checked 2026-10-13: all three variables below are already set on Vercel `doddy-voice-token`. The only thing
stopping it is Vercel's 402. You have two ways out:
- **A. Fix Vercel billing** (Part 2). Nothing else changes. Address: `https://doddy-voice-token.vercel.app`.
- **B. Run it on Render instead** (**chosen 2026-10-13; the service exists**), on the free plan you already use. `server/voice-token/server.js` (added
  2026-10-13) runs the same code as a plain Node process; steps are in `server/voice-token/README.md`,
  "Deploy on Render". You type `ELEVENLABS_API_KEY` and `DODDY_ACCESS_CODES` into Render yourself. The address
  becomes `https://<service>.onrender.com`. Free instances sleep, so the first try after a pause can fail; the
  second works.

### 3.1 Check the token server's environment
Vercel → `doddy-voice-token` → Settings → **Environment Variables** (or Render → the service → Environment for
route B). Production needs all three:

| Name | Value |
|---|---|
| `ELEVENLABS_API_KEY` | **secret**: elevenlabs.io → Developers → API Keys. Scope: ElevenAgents **Read**; everything else No Access |
| `ELEVENLABS_AGENT_ID` | `agent_0501m4et27vyeawrwqfdxxfszfa6` |
| `DODDY_ACCESS_CODES` | **secret**: `owner:<code>`. Make the code with `openssl rand -base64 24` (16+ characters). Add `name:code` pairs for testers, comma-separated |

After changing any of them: Deployments → newest Production → Redeploy.

### 3.2 Point the app at it
On the iPhone, open Doddy → **Settings** → **Voice**:
1. **Token server**: `https://doddy-voice-token.vercel.app` (route A) or the Render address (route B).
2. **Access code**: your owner code → **Save**. It's stored in the Keychain.
3. The connection row must say **Private (token server)**.

### 3.3 Prove it works
1. Tap **Talk to Doddy** and allow the microphone.
2. Say something. Doddy must answer.
3. If it says the code wasn't accepted, step 3.1 is wrong.
4. If the error mentions permission, change the API key's ElevenAgents scope to **Write**.

### 3.4 Lock the agent (only after 3.3 worked)
In the ElevenLabs dashboard → Agents → Doddy:
1. **Security** → turn on **Enable authentication**. The public ID no longer works; only tokens from your server do.
2. Retention: the agent keeps every recording (owner, 2026-10-13: leave it as it is for now; ADR-057).
3. **Call limits**: concurrency 2 and 10 calls a day today. Raise the daily limit for testing if you need to.
4. Workspace → **Usage / Billing**: set a monthly spending or credit cap (ADR-068).
5. Talk to Doddy again from the app. It must still work.

### 3.5 The agent's missing tool
`voice-agent/README.md` lists one change not yet on the live agent (ADR-441: `note_capability_gap` and
`{{learned_context}}`). The prompt at the end of this file asks the next session to apply it. It needs your "yes".

---

## Part 4. Ask Doddy (typed questions through OpenAI) (30 minutes)

1. **OpenAI project and cap:**
   1. Go to platform.openai.com → Projects → **Create** "Doddy gateway".
   2. Open the project → **Limits**: set a hard monthly budget (e.g. $10).
   3. Open **API keys** → create a key for that project (**secret**).
2. **Model:** pick the model id you want, e.g. a current GPT mini model, and its input and output price per million
   tokens from openai.com/api/pricing.
3. **Redis for the limits:**
   1. Vercel → `doddy-gateway` → **Storage** → **Create** → Upstash Redis (Marketplace), free tier, region close
      to Frankfurt.
   2. **Connect** it to the project. That adds `KV_REST_API_URL` and `KV_REST_API_TOKEN` itself.
4. **Environment variables** (Vercel → `doddy-gateway` → Settings → Environment Variables, Production):

   | Name | Value |
   |---|---|
   | `OPENAI_API_KEY` | **secret** from step 1 |
   | `OPENAI_MODEL` | the model id from step 2 |
   | `OPENAI_PRICE_INPUT_PER_MTOK_USD` / `OPENAI_PRICE_OUTPUT_PER_MTOK_USD` | the two prices from step 2 |
   | `GATEWAY_TOKEN_SECRET` | **secret**: `openssl rand -base64 48` |
   | `GATEWAY_INVITE_CODES` | **secret**: one code per tester, 16+ characters each, comma-separated (`openssl rand -base64 24`) |
   | `REQUIRE_SHARED_LIMITS` | `1` |
   | `DAILY_BUDGET_USD` | e.g. `1.00` |
5. **Redeploy** the gateway (Deployments → newest Production → Redeploy). Then run `scripts/check_live_services.sh`.
   Expected: `gateway 400`.
6. **On the iPhone:**
   1. Settings → **Ask Doddy (typed questions)** → **Turn on Ask Doddy**.
   2. Gateway address: `https://doddy-gateway.vercel.app`.
   3. Enter your invite code.
   4. Ask something about a note you saved. The answer must cite the note; an uncited answer is labelled
      "Not from your notes".

Legal: OpenAI's data terms and the App Store privacy label are yours to decide (gateway README, step 6).

---

## Part 5. Online accounts and web search (backend on Render) (20 minutes per account)

The server is up (`doddy-yaci.onrender.com`). What's missing is a phone token and connected accounts.

### 5.1 Mint the phone token (on your Mac)
1. Render → `doddy` → **Environment** → reveal and copy `DODDY_SESSION_SIGNING_KEY` (**secret**, keep it in your terminal only).
2. Run:
   ```sh
   cd backend && npm ci && npm run build
   DODDY_SESSION_SIGNING_KEY='<paste>' npm run session:mint -- "$(uuidgen | tr A-Z a-z)" 30
   ```
   It prints a user line and a token valid for 30 days, once. The token is a password: put it only into the app.
   Keep the user id, so you can mint the next token for the same user.
3. On the iPhone: Settings → **Connected Apps server (development)** → address `https://doddy-yaci.onrender.com`,
   then the token.

### 5.2 Web search
1. Check that `MONID_API_KEY` is set in Render → `doddy` → Environment. If not, add it (app.monid.ai → Access →
   API keys), then **Manual Deploy → Deploy latest commit**.
2. App: Settings → **Online accounts** → Web search → switch on.
3. Ask Doddy something current. Render → `doddy` → Logs must show `POST /v1/tools/run` 200.

### 5.3 Google Calendar and Gmail (keys already in Render)
1. App: Settings → Online accounts → Google Calendar → **Connect**.
2. Sign in with Google in the browser that opens, then return to the app.
3. Ask Doddy "what's on tomorrow?".
4. Do the same for Gmail: "read my last email from …". A draft must show a card before anything is written.

Free-plan warning: the free Render disk resets on every restart, so switches and connections are forgotten. Composio
keeps the accounts, so just reconnect. A paid instance with a disk ($7/month plus a disk) fixes it.

### 5.4 More accounts (Drive, Notion, Todoist, Outlook)
1. On your Mac, with `COMPOSIO_API_KEY` in your shell, run:
   ```sh
   cd backend && npm run setup:tools -- --create
   ```
   It prints `COMPOSIO_<TOOLKIT>_AUTH_CONFIG_ID` and `_TOOLKIT_VERSION` pairs.
2. Paste each pair into Render → `doddy` → Environment, then redeploy.
3. Outlook has only ever run against demo data. The first real use is the test (ROUND6_REPORT, "Outlook").

---

## Part 6. Notifications, texts, phone calls, daily news (messaging server) (1 to 2 hours, costs money)

The web service is up, but four things are missing.

### 6.1 Add the worker
Render → `doddy-messaging` runs only the API. Nothing sends queued messages until a worker runs.
1. Render → **New → Background Worker** → repo `Bienos/doddy.2`, branch `claude/loving-dirac-uuxoux` (the same as
   the web service), region Frankfurt, plan Starter ($7/month; workers have no free plan).
2. Build: `cd server/messaging && npm ci && npm run build`. Start: `cd server/messaging && npm run worker`.
3. Environment: the same `DATABASE_URL` and keys as `doddy-messaging`. Use an **Environment Group** shared by both,
   so you type each key once.

### 6.2 Check the database
Render → `doddy-messaging` → Environment → `DATABASE_URL` must point at a Render Postgres.
- Free Render Postgres expires after 30 days, and the go-live note says yours ends **2026-11-10**.
- For anything longer, upgrade it to Basic ($6/month) before then.

### 6.3 Push notifications (APNs)
1. developer.apple.com → Certificates, IDs & Profiles → **Keys** → **+** → name "Doddy APNs" → tick **Apple Push
   Notifications service (APNs)** → Continue → Register.
2. **Download** the `.p8` once (it can't be downloaded again) and note the **Key ID**.
3. Render env:

   | Name | Value |
   |---|---|
   | `APNS_TEAM_ID` | your Team ID |
   | `APNS_KEY_ID` | the Key ID |
   | `APNS_PRIVATE_KEY` | **secret**: the whole `.p8` text |
   | `APNS_BUNDLE_ID` | `com.bienos.doddy2.dev` |
4. Build the app with push. In `project.yml`, set `DODDY_APP_ENTITLEMENTS: Config/Doddy-Push-AppGroup.entitlements`,
   then run `make project`. Xcode adds the Push capability to the App ID itself.
5. Xcode builds use the sandbox push environment; TestFlight uses production. The app sends the right one.

### 6.4 Texts and calls (Twilio), optional
Do it only if you want SMS or phone calls now. Polish and US numbers need regulatory paperwork that takes days.
1. Buy a number.
2. Create a Messaging Service with Advanced Opt-Out.
3. Create a Verify service.
4. Set `TWILIO_*` in Render.
5. Point the inbound SMS webhook at `https://doddy-messaging-zw1n.onrender.com/webhooks/twilio/sms`.
6. For calls, see `server/messaging/README.md` "Phone calls (S2)".

### 6.5 Daily news, optional
Set `ANTHROPIC_API_KEY` (or `OPENAI_API_KEY`) and `GNEWS_API_KEY` (gnews.io, free tier).

### 6.6 On the iPhone
1. Settings → **Notifications and texts** → **Server (development)** → `https://doddy-messaging-zw1n.onrender.com`.
2. Turn on notifications and tap the test.

---

## Part 7. "Hey Doddy" (10 minutes, free tier)

1. console.picovoice.ai → sign up → copy your **AccessKey** (**secret**).
2. Porcupine → create the wake word "Hey Doddy" → platform **iOS** → download the `.ppn` file to Files or iCloud Drive.
3. In the app: Settings → **Hey Doddy** → paste the AccessKey → choose the `.ppn` → turn it on.
4. The "Now" line must say it's listening, only while it really is.

Commercial use needs a paid Picovoice plan (go-live note, section 2).

---

## Part 8. Internal TestFlight (once Parts 1 to 3 work)

1. appstoreconnect.apple.com → Apps → **+ → New App**:
   1. Platform iOS, name "Doddy", language, the bundle ID from 1.4, SKU `doddy-001`.
2. Xcode, with the destination set to **Any iOS Device (arm64)**:
   1. **Product → Archive**.
   2. In the Organizer: **Distribute App** → **App Store Connect** → **Upload**.
3. Export compliance: if asked about encryption, the app uses only standard HTTPS/TLS.
   - The usual answer is "None of the algorithms mentioned above" (exempt).
   - Adding `ITSAppUsesNonExemptEncryption = NO` to `Config/Doddy-Info.plist` stops the question; that's your
     answer to give.
4. App Store Connect → the app → **TestFlight** → **Internal Testing** → **+** → add yourself.
   - Internal testers need no Apple review and no privacy policy.
   - **External** testers need a privacy policy URL and Beta App Review (go-live note, section 1).
5. Before anyone but you gets a build:
   - Part 3.4 is done (authentication on).
   - The developer-only fields in Settings are hidden (the next session's job, below).

---

## What only you can do (summary)

| # | Action | Where | Cost |
|---|---|---|---|
| 1 | Team ID in `project.yml`; pick the final bundle ID | Apple Developer, repo | paid account you have |
| 2 | Fix Vercel billing, redeploy two projects | vercel.com/doddyyyy | $0 to $20/month |
| 3 | Check token-server env vars; enable agent auth; set retention and spend cap | Vercel, ElevenLabs | ElevenLabs plan |
| 4 | OpenAI project, key, budget, Upstash Redis, gateway env vars | OpenAI, Vercel | pay per use, capped |
| 5 | Mint backend token; connect Google | Mac terminal, app | free |
| 6 | Messaging worker, APNs key, Postgres upgrade; Twilio if wanted | Render, Apple, Twilio | about $13/month plus Twilio |
| 7 | Picovoice AccessKey and `.ppn` | Picovoice | free to try |
| 8 | App Store Connect record, archive, internal TestFlight | Apple | none extra |

---

## Prompt for the next session (paste as-is)

```
Repo Bienos/doddy.2. Read CLAUDE.md, then docs/implementation/GO_LIVE_RUNBOOK_2026-10-13.md and
docs/implementation/GO_LIVE_STATUS_2026-10-11.md. The app compiles on Xcode 26.6 in CI; I'm following the runbook
on my Mac and iPhone.

Status from me (edit before sending):
- Part 1 signing/device build: [done / error: <first error>]
- Part 2 Vercel billing: [done / not yet]
- Part 3 voice token works in the app: [yes / no: <message shown>]; agent auth on: [yes/no]
- Part 4 Ask Doddy: [done / skipped]
- Part 5 backend token + Google connected: [yes/no]
- Part 6 messaging worker / APNs / Twilio: [...]
- Part 7 Hey Doddy: [...]

Do, in this order, one small PR each, and run scripts/ci.sh --core-only plus scripts/check_live_services.sh:
A. Fix any build or runtime error I listed above (root cause, no test skipping).
B. Testers must not see developer fields: hide the token server, agent ID, gateway address, Picovoice and
   Connected Apps server fields behind #if DEBUG (as UpdatesSettingsView already does), and bake the production
   addresses (doddy-voice-token.vercel.app, doddy-gateway.vercel.app, doddy-yaci.onrender.com,
   doddy-messaging-zw1n.onrender.com) into release builds the way ServerConfig does. Keep "not set up" honest.
C. ElevenLabs: show me the exact diff for ADR-441 (note_capability_gap + {{learned_context}}), apply it to agent
   agent_0501m4et27vyeawrwqfdxxfszfa6 only after I say yes, read it back, run voice_agent_spec.py compare.
D. Update the stale "never compiled" lines in BUILD_AND_TEST.md and FIRST_BUILD_GUIDE.md to the CI result, and fill
   the Mac checklist result log with what I reported (only what I reported).
Then, lighter touch, the "not built" list. Plan first, ask me before any paid or outward-facing step:
E. Privacy policy page on the site (site/, Vercel project "doddy") drafted from the Settings privacy text and
   docs/security/PRIVACY_GDPR_AI_ACT.md, marked DRAFT pending legal review; never claim compliance.
F. Real sign-in + App Attest plan (ADR-077, ADR-143, ADR-147): ADR and a design only, no code until I approve.
G. CarPlay: only if the entitlement has come through (docs/implementation/CARPLAY_PLAN.md).
Never deploy, change live agents, or spend money without my explicit yes in this session. End with the
milestone report CLAUDE.md asks for.
```

---

## Update 2026-10-13 (later): what changed after this runbook was written (ADR-442)

- **Voice token server and Ask Doddy gateway now run on Render** (free), not Vercel. Vercel billing no longer
  matters for them; Part 2 can be skipped.
- **The app has the four addresses built in** (`DoddyApp/Infrastructure/Server/ServiceAddresses.swift`). You no
  longer type a token server, gateway or server address in Settings: skip those lines in Parts 3.2, 4.6, 5.1 and
  6.6. Debug builds from Xcode still show the fields, pre-filled. TestFlight builds hide them.
- **Part 4 (Ask Doddy) on Render instead of Vercel:** in Render → `doddy-gateway` → **Environment**, add
  `OPENAI_API_KEY`, `OPENAI_MODEL`, both `OPENAI_PRICE_*_PER_MTOK_USD`, `GATEWAY_TOKEN_SECRET` (use Render's
  **Generate**) and `GATEWAY_INVITE_CODES`. `REQUIRE_SHARED_LIMITS=1` and `DAILY_BUDGET_USD=1.00` are already set.
  For the limits store, make a free database at console.upstash.com → **Redis** → Create (region eu-central-1,
  Frankfurt), open its **REST API** section, and copy `UPSTASH_REDIS_REST_URL` and `UPSTASH_REDIS_REST_TOKEN` into
  Render. Save, rebuild and deploy, then `scripts/check_live_services.sh` should show `gateway 400`.
- **Part 6.1 (messaging worker) is not needed:** the worker already runs inside `doddy-messaging`. What you need is
  for it to stay awake. In Render → `doddy-messaging` → **Settings** → **Instance Type**, choose **Starter**
  ($7/month), so scheduled news and texts go out on time. Before 2026-11-10, also upgrade the database:
  Render → `doddy-messaging-db` → **Upgrade** → Basic-256mb ($6/month). Otherwise it's deleted and every messaging
  account goes with it.
