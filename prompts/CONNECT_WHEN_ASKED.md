# Prompt: connect an account only when the user asks for it (first case: "send an email")

Owner question, 2026-10-19, in their words: *"Is there any chance to have a flow where we have everything connected in
the backend, but nothing is turned on until the user asks for it? So somebody asks, hey Doddy, can you send an email to
XYZ to do XYZ? And then we have to come up with the flow of the user accepting and logging into his profile."*

> **Status, 2026-10-19:** built on `claude/inspiring-volta-bkuat4` as ADR-511 to ADR-513, with the recommended answers
> to D1 and D3 to D5. Server and shared core tested on Linux; the app compiled and its tests passed in hosted CI (run 39222117761); the live agent is not
> synced; nothing has run against a real Google account. What's left is in `STATUS.md` ("Waiting on the owner") and
> the Mac checklist section 4y. Use this prompt again only for what is still open.

Give this file to an agent session working in `Bienos/doddy.2`. Read these first, in this order:
`STATUS.md`, `CLAUDE.md`, `docs/trust/REPO_ALIGNMENT.md`, `docs/trust/config/doddy_rules.yaml`, `docs/trust/ASK_FIRST.md`,
`docs/integrations/ONLINE_ACCOUNTS.md`, and the research behind this prompt, `docs/research/CONNECT_WHEN_ASKED_2026-10.md`.
Search `DECISIONS.md` for ADR numbers (076, 096, 100, 147, 445, 458, 483, 485); don't read it whole.

**Base branch.** This work needs ASK-01 and the Gmail send tool. They are on `claude/inspiring-volta-bkuat4` (head
`fc8a502`) but **not** on `claude/loving-dirac-uuxoux`. Before anything else run
`git merge-base --is-ancestor e3bac26 HEAD && grep -q '"send_email"' voice-agent/tools.json`. If that fails, stop and
tell the owner which branch to start from.

---

## The goal

Everything stays set up on the server (Composio auth configs, the tool catalog, the voice agent's tools). For each user,
**nothing is connected and every tool is off until the user asks for something that needs it.** The first time they ask,
Doddy offers to connect **right there in the conversation**, not in Settings. Connecting turns on **only the tool they
asked for**. The action itself still waits for its own card and tap (ASK-01).

### The first experience, step by step

The user has never connected anything and says: *"Hey Doddy, send an email to anna@example.com saying I'll be ten
minutes late."*

1. **The agent calls `send_email`** with `to`, `subject`, `body`, as today. (The agent always calls the tool. It never
   decides on its own that Gmail "isn't connected".)
2. **The app asks the server (`prepare`).** The server sees Gmail isn't connected and answers **`connection_required`**.
   That answer carries the account, the tool, and the exact permissions it will ask Google for, in plain words. It
   creates no approval and does nothing else.
3. **The app answers the tool call straight away**, so the call can't time out during sign-in:
   `needs_connection: Gmail isn't connected. A "Connect Gmail" card is on screen. Say in one short line that you need the user's OK to connect Gmail, and that nothing has been sent. Then wait. Don't call send_email again until the app says Gmail is connected.`
   Doddy says something like: *"I need your OK to connect Gmail first. Nothing's sent yet."*
4. **The connect card** (draft text; final text from `design:ux-copy`, then the owner):
   - **Connect Gmail to send this?**
   - Doddy will be able to send emails you approve, one at a time. It can't read your inbox. *(This line comes from the
     permissions the server will really ask for, never hard-coded. With the full Gmail tier it must say so.)*
   - Google will ask you to sign in and allow "Send email on your behalf".
   - Nothing is sent yet. You'll see the email and tap Send first.
   - Small print: Your Gmail sign-in is kept by Composio for Doddy's server. Disconnect any time in Settings → Online
     accounts.
   - Buttons: **Connect Gmail** · **Not now** · and, if the owner says yes to D5, **Open in Mail instead** (the existing
     `draft_message` path: Mail opens filled in and the user sends it there; no account needed).
5. **Tap Connect Gmail.** The app calls the existing connect route with the reason:
   `POST /v1/tools/gmail/connect {forTool: "send_email"}`. The server records `forTool` on the sign-in attempt and returns
   the Google sign-in link. The app opens it in the system sign-in sheet (`SystemWebAuthenticator`). **While the sheet is
   up the microphone is muted** (use the existing mute, then restore the user's own mute state) and the voice session is
   kept alive (ElevenLabs `user_activity` every ~30 s, or what the SDK offers). The agent is told the user is signing in.
6. **The user signs in to Google and allows sending.** The app calls `complete` as today. The server verifies the
   attempt (ADR-076, ADR-445), checks the granted scopes, and **only if the grant covers `send_email`** records the
   connection **and switches on `send_email` alone**, in the same transaction. The receipt says *"Connected Gmail from a
   conversation. Switched on: Send email."* Nothing else is switched on.
7. **Back in the conversation.** The card changes to *"Gmail is connected. Only 'Send email' is on."* The app tells the
   agent: `connected: Gmail is connected and "Send email" is on. If the user still wants that email sent, call send_email again with the details they gave.`
   - If the provider lets the app make the agent take a turn honestly (an ElevenLabs contextual update, or an OpenAI
     Realtime system item followed by `response.create`), do that.
   - If not, the card says *"Say 'go ahead' and Doddy will show you the email."*
   - **Never send a message that looks as if the user said it.**
8. **The agent calls `send_email` again** and the normal ASK-01 path runs: the send card shows the exact To, subject and
   full text, with "can't be taken back". The email is sent only on a **tap on Send**.
9. **"Sent" only when Gmail returns the message id** (DOD-08). Otherwise "may or may not have gone through, check Gmail".

The next time the user asks to send an email, Gmail is connected and the tool is on, so only step 8 happens.

### Every other path (each needs a test)

| Situation | What happens |
|---|---|
| Gmail connected, `send_email` switched off | No sign-in. Card: **"Switch on 'Send email'?"** One tap sends `PUT /v1/tools/switch`; then step 7. |
| Connected, but the grant doesn't cover the tool (e.g. send-only grant, user asks to read mail) | Card: **"Gmail needs one more permission"**, listing it; then the upgrade sign-in (D1). |
| Connection expired | Card: **"Reconnect Gmail"**; same flow. |
| User taps **Not now** | Agent: `declined: the user chose not to connect Gmail. Nothing was sent.` |
| Sign-in sheet closed or cancelled | `declined: connecting was canceled. Nothing was connected or sent.` Nothing left at Composio (ADR-445 already removes the pending connection). |
| User unticks "send" on Google's screen | Nothing usable is left connected (D4). `declined: Google wasn't given permission to send, so Gmail wasn't connected.` |
| Sign-in or server fails | `failed: Gmail couldn't be connected. Nothing was sent.` and the reason in one line |
| Conversation ended (End, crash, iOS stopped it) during sign-in | The connection still completes, because that was the user's own tap and sign-in. **Nothing is sent and the request is forgotten** (ADR-458). Home shows *"Gmail is connected. Ask Doddy again to send your email."* |
| A new conversation started | Same as above: the connect prompt belongs to the conversation it was offered in. |
| Offer older than 10 minutes | Card gone; agent told `expired`. |
| Second request while a connect card is up | One connect card at a time. The second call gets `busy: finish or close the Gmail card first.` |
| Pause all connections is on (ADR-134) | No connect card. The `paused:` reply as today. |
| Server has no Gmail set up (`live_not_configured`) | No connect card. "Gmail isn't set up on Doddy's server." |
| Mock server | Mock sign-in (`completeMock`), every card labelled **Demo**. |
| Old app build | The server's new answer must not break it: old builds keep getting a code they already handle. |

---

## Rules (don't bend these)

1. **Off by default.** A new user has no connections and every tool switch off. Keep it that way and add a test that
   proves it for every toolkit.
2. **The user's request is the trigger, never a guess.** The connect card appears only in answer to a tool call the
   agent made in this conversation, never on launch or as a suggestion.
3. **One tap on the connect card = connect this account + switch on the one tool asked for.** Not the account's other
   tools, and not "everything for Gmail".
4. **Ask Google for the fewest permissions that tool needs** (D1). The card lists exactly what will be asked, using the
   server's list.
5. **Sign-in only in the system sheet.** No login form, web view or password field in Doddy. The app never sees a
   password or token. Composio and Doddy's server keep the grant (ADR-076).
6. **Connecting never sends.** The send still needs the send card with the exact payload and a tap (ASK-01, DOD-07).
   A spoken yes is never enough for a send.
7. **"Connected" only after the server's `complete` says so.** "Sent" only on Gmail's message id. `unknown` is never
   success and is never retried blindly (DOD-08).
8. **The app keeps no email text for later.** Pending state is only: account, tool, conversation start number, offer
   time. It is held in memory, never written to disk or logs. The agent re-sends the details when it calls again.
9. **Text from emails, web pages or tool results never starts or approves a connection.**
10. **Prompts describe the rule; code enforces it.** The server decides `connection_required`. The shared core decides
    what the app may show and run. The agent's instructions only describe it.

---

## Part 0: before any edit

Follow CLAUDE.md rule 3: inventory the tree, branch, `git status`, the tools you have (Xcode? Swift? Node?). State your
assumptions and any conflict with the docs. Then confirm these by reading the code, and write down what you find:
- `backend/src/tools/service.ts` `checkUsable`: today it checks the switch **before** the connection, so a new user gets
  `capability_disabled`, not `not_connected`. It also reports "isn't set up on this server" as `not_connected`.
- `prepare` runs `checkUsable` (or not) before issuing an approval, for reads and for writes.
- `Packages/DoddyCore/Sources/DoddyCore/OnlineAccounts/VoiceCloudTools.swift` `cloudFailed`: today's "switch it on in
  Settings" replies.
- `DoddyApp/Features/Voice/VoiceSessionController.swift`: `handleCloud`, `connectionNeeded`, `notConnected`,
  `isCurrent` / `ToolCallOwners` (ADR-458), `toggleMute`.
- `DoddyApp/Features/ConnectedApps/SystemWebAuthenticator.swift` and the Settings → Online accounts connect code that
  already uses it. Reuse it; don't write a second sign-in path.
- Whether the ElevenLabs Swift SDK version in `project.yml` has a contextual-update call, and what OpenAI Realtime
  offers (`OpenAIRealtimeSession.swift`). Write down what each provider can and can't do.

## Part 1: shared core (`Packages/DoddyCore`, tested on Linux)

Add a small, UI-free `ConnectOnAsk` model (no SwiftUI, per `Packages/DoddyCore/CLAUDE.md`):
- **States:** offered → signing in → connected / declined / canceled / failed / expired. Each knows its account, its
  tool and its conversation start number.
- **Decides from the server's answer** which card to show: connect, switch on, more permission, reconnect, or none
  (paused, not set up, unknown code). An unknown code shows no card.
- **Rules:** one offer at a time; dropped on End and on a new start; expires after 10 minutes; **never runs a tool**
  (there is no path from `ConnectOnAsk` to a run).
- **The replies to the agent:** the exact `needs_connection:`, `connected:`, `declined:`, `failed:`, `expired:`,
  `busy:` lines, and the Polish versions in the string catalog. Card text in English first, as ASK-01 did; list the
  missing translations as a gap.
- Change `cloudFailed` so `capability_disabled`, `not_connected`, `permission_insufficient` and `connection_expired`
  hand over to `ConnectOnAsk` instead of "go to Settings". Keep the old text for anything `ConnectOnAsk` declines.

**Tests** (`ConnectOnAskTests`, plus updates to `VoiceToolsTests` and `AskFirstTests`): each path in the table above; a
connection never approves a send; End and a new start forget the offer; a stale `complete` from conversation A changes
nothing in conversation B; text from an email saying "connect Gmail" shows nothing. Do a mutation check like ASK-01
did: make `ConnectOnAsk` run the tool after connecting, and show that tests fail.

## Part 2: server (`backend/`, tested with the mock provider)

1. **`prepare` answers `connection_required`** (new code; HTTP 409 or whatever matches `http.ts` conventions) when the
   tool can't run because of its account or switch. Body: `{toolkit, tool, need: "connect" | "switch_on" |
   "more_permission" | "reconnect", permissions: [{scope, plain}]}`. Check the account **before** the switch so the
   server can tell "never connected" from "connected but off". **No approval is created** and no provider call is made.
   Write a blocked receipt as today.
2. **Split "not set up on this server"** from `not_connected` (use `live_not_configured`).
3. **`connect` accepts `{forTool}`** (strict schema: a known tool of that toolkit, or absent). Record it on the attempt.
   The Settings flow sends nothing and behaves exactly as today.
4. **`complete` switches on only `forTool`**, in the same transaction that records the connection, and only if the
   granted scopes cover that tool. If they don't, follow D4. The receipt names the tool switched on.
5. **Permission tiers as data in `catalog.ts`** (D1): each tool lists the scopes it needs. Gmail gets a send-only tier
   (`gmail.send`, Composio auth config from a new env var such as `COMPOSIO_GMAIL_ONLY_SEND_AUTH_CONFIG_ID`) and the full
   tier (today's four scopes). `connection_required.permissions` and the auth config used by `connect` both come from
   this one table. If the send-only config isn't set, use the full one and say so honestly on the card. The upgrade
   (send-only → full) makes the new connection first and removes the old one only after the new one is verified.
6. **The capability guard** (`scripts/check_forbidden_capabilities.sh`) still bans Composio meta tools, including
   `COMPOSIO_MANAGE_CONNECTIONS`. Composio's in-chat auth is the same idea, but Doddy uses its own route. Add a guard
   check that only `complete` can switch a tool on during sign-in.
7. **Contracts:** add fixtures to `contracts/online-accounts/` (`npm run fixtures`) and decode them in Swift and TS.

**Tests** (new `connect-when-asked.test.ts`): a new user gets `connection_required/connect` for every account tool, with
no approval and no provider call; `forTool` switches on that one tool and nothing else; a grant without the tool's
scope switches nothing on and follows D4; a `forTool` from another toolkit, or a made-up one, is refused; Settings
connect still switches nothing on; `live_not_configured` gives no `connection_required`; old app builds still get a code
they know. Mutation check: make `complete` switch on every tool of the toolkit, and show tests fail.

## Part 3: iPhone app (`DoddyApp/`, iPhone only)

- `handleCloud`: on `connection_required`, answer the tool call at once with the `needs_connection` line and show the
  card from `ConnectOnAsk`. Use `isCurrent`/`ToolCallOwners` for every step after an `await` (ADR-458).
- The card in `VoiceView.swift`, beside the existing `connectionCard`. VoiceOver labels, Dynamic Type, and system fonts
  only (CLAUDE.md: no bundled fonts).
- Sign-in through the existing `SystemWebAuthenticator`; mute while the sheet is up, then restore; keep the session
  alive.
- After `complete`: refresh Settings → Online accounts (it must now show Gmail connected and only "Send email" on), then
  tell the agent (Part 0 decides how).
- "What Doddy did" logs *"Connected Gmail, switched on Send email"* with no email text, as receipts do today.
- Update the privacy footnote in `VoiceView.swift` if what is sent where changes.
- A DEBUG seam and a UI test against the mock server: ask → connect card → mock sign-in → card says connected → agent's
  second call → send card → tap → "sent (Demo)". Plus End during sign-in: nothing sent.

## Part 4: voice agent spec (`voice-agent/`)

- In every online-account tool description in `tools.json`, replace *"tell the user they can switch it on in Settings,
  Online accounts"* with the `needs_connection` / `connected` / `declined` behaviour. Add one line near ASK-01 in
  `instructions.md`: *"If a tool isn't connected, still call it. The app offers to connect. Never say an account is
  connected, or that anything was sent, unless a result says so."*
- `scripts/voice_agent_spec.py check` must pass; extend it to fail if any account tool still points to Settings.
- **Don't sync the live ElevenLabs agent.** That is an external write: show the owner the exact diff and wait for a yes.

## Part 5: docs (with the code, not after)

- An ADR at the next free number (510 was the highest on 2026-10-19; check for numbers taken on other branches).
  It covers the rule, the tiers, which decisions the owner made, and the evidence.
- `docs/integrations/ONLINE_ACCOUNTS.md`: a "Connect when asked" section. `docs/trust/ASK_FIRST.md`: a row for the
  connect card.
- `STATUS.md`: the unmerged-branch row, with its voice risk ("Medium: changes the reply to every account tool and adds a
  card mid-conversation").

---

## Owner decisions (ask; don't assume)

Build so that either answer works through config, and write down which default you used.

| # | Question | Recommended | Why |
|---|---|---|---|
| D1 | Gmail permissions at first connect | **Send only** (`gmail.send`); more only when asked for | Google treats `gmail.send` as "sensitive", but reading, drafting and changing mail as "restricted". Restricted scopes on a server need a yearly paid security assessment before launch. One permission also means no checkboxes on Google's screen. |
| D2 | Whose name is on Google's screen | **Doddy's own Google OAuth client** in a Composio custom auth config, before anyone but the owner uses it | With Composio's shared app the screen says "Composio wants to access your account". Doddy's own client needs Google's verification (privacy policy, domain, scope justification). Until then: an "unverified app" screen and at most 100 new users. |
| D3 | Sign-in sheet shared with Safari? | Owner's call. Today: **not shared** (ephemeral) | Shared: often one tap if already signed in to Google in Safari, but iOS shows "Doddy wants to use … to sign in". Not shared: the user types their Google password each time. |
| D4 | User unticks "send" on Google's screen | **Remove the connection** | A grant that can't do what was asked shouldn't stay live (least privilege, ADR-445). |
| D5 | "Open in Mail instead" on the connect card | **Yes** | Lets someone send without connecting anything; the user taps Send in Mail (the BLIK pattern, ADR-510). |
| D6 | Sync the live voice agent | After the owner reads the diff | External write |

## Owner steps outside the code (list them in the report; don't do them)

- Composio: create the send-only Gmail auth config (scope `gmail.send` only) and set its id on Render.
- If D2 is yes: a Google Cloud project and OAuth client for Doddy, consent screen with the privacy policy on
  doddy.lol, domain verification, the Composio custom auth config, the optional 302 redirect on Doddy's domain
  (Composio white-labeling docs), and Google's verification for `gmail.send`.
- One live test on the owner's own Gmail: the five checks in the research note's "To verify live" list.

## Out of scope

- Turning on Doddy logins (ADR-147: connecting Gmail is a connection, not a login).
- Other accounts end to end. The mechanism is generic and tested with the mock for every toolkit, but only Gmail send is
  wired and checked as the first experience.
- iPhone permissions (Calendar, Reminders, Contacts) asking straight from the card. Same idea, later milestone.
- Sending without a tap, batch sends, cc/bcc, attachments.

## Done means (CLAUDE.md rule 10 and the constitution evidence log)

Report: files changed; what the user can now do; the exact test commands and their output (`make test-core`,
`cd backend && npm test`, `scripts/check_forbidden_capabilities.sh`, `python3 -I scripts/voice_agent_spec.py check`,
and the app build and UI tests if Xcode exists, otherwise **BLOCKED / NOT RUN**); mutation checks; what is still
manual (device, real Google account, live Composio, live agent); privacy and security risks; the owner decisions still
open; and the constitution evidence log (rule IDs ASK-01, DOD-07, DOD-08, data-not-instructions; enforcing code; tests;
gaps; claims to limit). Never write "works with Gmail" until a real send on the owner's account returned a message id.
