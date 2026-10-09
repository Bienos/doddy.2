# Connections, iPhone actions and a proactive Doddy — research and design proposal
Date: 2026-10-09. Status: **research + design proposal, nothing built.** Owner question (paraphrased): *can Doddy
connect to my calendar, Google, MCP servers and other things; do stuff inside my phone; and message me (iMessage,
WhatsApp…) when something I care about happens, e.g. "there is this event today" or "news came up about the thing
I told you to watch", with a link?*

Short answer: **yes, in three layers, each with hard limits that shape the design.**

| Layer | What it gives Doddy | What it costs | Verdict |
|---|---|---|---|
| **A. On the iPhone** (Apple frameworks, permissions) | Calendar, Reminders, Contacts, alarms, location, weather, run the user's Shortcuts | Nothing external; one permission prompt each | **Build first.** Covers the "event today" case without any account |
| **B. Accounts and MCP** (OAuth, remote MCP servers) | Google Calendar/Gmail, Notion, Linear, anything that speaks MCP | OAuth verification, token handling, a small gateway | Build second, Google Calendar first; Gmail read is expensive to get approved |
| **C. A small "Watcher" backend** | Watch the news for a topic, nudge at the right time while the phone is asleep | Server, push certificate, model + search spend, privacy work | Needed for anything that must happen **when the app is not open** |

And the honest message about messaging: **an app cannot send an iMessage by itself.** The native equivalent is a push
notification that *looks like a message from Doddy* (Apple's communication-notification style, with Doddy's face as
the sender). WhatsApp and Telegram are possible as opt-in channels through a Doddy backend; iMessage only via a
Shortcuts recipe the user builds and owns. Details and sources in §2.2.

Labels: **OBSERVED** = read in vendor docs or code on 2026-10-09; **ANECDOTAL** = forum/blog, not vendor;
**UNVERIFIED** = plausible, not tested here; **PROPOSED** = our design choice, owner approval pending.

---

## 1. The four jobs behind the question

| Job | Example | Who must be awake |
|---|---|---|
| **J1 Connect** | "Doddy, you can see my calendar / my Google account / this MCP server" | Phone (permission or OAuth once) |
| **J2 Act inside the phone** | "Remind me Thursday", "put it in my calendar", "run my Leaving-work shortcut" | Phone, with the user confirming writes |
| **J3 Reach me** | "Hey, the dentist is at 15:00 today, here's the address" | A server, or a notification the phone scheduled earlier |
| **J4 Watch for me** | "Tell me when something comes out about the Kraków tram tender I mentioned" | A server (the phone cannot poll the web in the background reliably) |

J1 and J2 extend what the repo already has (tool proposals → confirm → verified receipt, `docs/architecture/TOOLS_AND_ACTIONS.md`).
J3 and J4 are new and need **explicit "watch notes"**: the user tells Doddy, in so many words, what to watch and how to be
reached. This keeps the product's rule *explicit memory only, nothing inferred from ambient conversation*
(`docs/00_START_HERE/DECISIONS_AND_STATUS.md`).

---

## 2. Research findings

### 2.1 Inside the iPhone (layer A)

Extends `VOICE_SHORTCUT_ISLAND_TOOLS_2026-10.md` §4. All items need the user's permission at point of use.

| Capability | Framework | Notes (OBSERVED unless marked) |
|---|---|---|
| Read today's/this week's events, create events | EventKit | iOS 17+: **write-only** access creates events but cannot read them back (so cannot verify); **full access** reads calendars. The system editor `EKEventEditViewController` needs no permission at all. Google/Outlook calendars **already synced to iPhone Calendar are readable through EventKit with no Google OAuth** — the cheapest "connect my Google Calendar" there is |
| Reminders | EventKit | Full access only (no write-only tier). Already planned as M4 |
| Alarms and timers that ring through silent/Focus | AlarmKit (iOS 26+) | Uses ringer volume; per-app volume control arrives iOS 27 (ANECDOTAL, forum) |
| Who is "Marta"? | Contacts | Lookup only; Google contacts synced to the phone are included |
| Where am I, nearby places, weather | Core Location, MapKit, WeatherKit | WeatherKit is billed above a free tier (check current terms) |
| Run any Shortcut the user already has | `shortcuts://run-shortcut?name=…` | Briefly opens Shortcuts; the user's shortcuts can reach other apps' actions |
| Expose Doddy to Siri/Shortcuts | App Intents | "Save to Doddy", "Ask Doddy", "What's on today" as intents |
| Schedule a notification for later **without a server** | UserNotifications (local) | The app can pre-schedule "Dentist at 15:00 today" the evening before, while it is open or during a background refresh |
| **Not possible** | — | Read other apps' data or screen, act in the background unasked, send iMessage/SMS silently, make calls silently, assign Back Tap |

**Needs a tap every time:** send a text/email (`MFMessageComposeViewController` compose sheet), make a call. There is
no API for unattended sending from an App Store app; the carrier-messaging entitlement is for default messaging apps
only (Apple forums, OBSERVED via search summary).

### 2.2 How Doddy can reach the user (J3) — channel comparison

| Channel | Can Doddy send it alone? | What it needs | Cost | Privacy | Fit |
|---|---|---|---|---|---|
| **Push notification, message-style** | Yes | Doddy backend + APNs key; a Notification Service Extension that calls `UNNotificationContent.updating(from:)` with an `INSendMessageIntent` so iOS shows **Doddy's avatar and promotes it like a message**; "Communication Notifications" capability | Free | Device token stored on our server | **Primary channel.** Looks like a text from Doddy, deep-links into the app, respects Focus like a person would. Reports exist of the avatar not appearing when set up wrong (ANECDOTAL); needs a device test |
| **Local notification scheduled by the app** | Yes, if the app knew in advance | Nothing external | Free | Fully local | **First channel to ship:** "today's events" nudges can be scheduled from EventKit data the night before |
| **Time-sensitive / critical** | Yes | Time Sensitive interruption level (breaks through Focus); Critical Alerts need an Apple entitlement | Free | — | Use sparingly, only for watch notes the user marked urgent |
| **iMessage** | **No** | — | — | — | Not possible from an app. Two honest alternatives: (a) Doddy opens the compose sheet pre-filled and the user taps Send; (b) a **Shortcuts personal automation built by the user** ("At 08:00 → Get Doddy's nudges → Send Message to me" with *Show When Run* off and *Run Immediately*) which sends through Messages without a confirmation screen. iOS 27 beta adds a **notification trigger** in Shortcuts ("When I get a notification from Doddy → Send Message"), but content filtering was broken in Developer Beta 1 (ANECDOTAL). Label any of this "set up by you, runs in Shortcuts", never "Doddy texts you" |
| **Apple Messages for Business** | Business-only program via messaging providers | Registration as a business | — | — | Not a fit for a personal companion; not pursued |
| **Telegram** | Yes, after the user taps `/start` once | Bot token on the backend; store the chat id | Free | Telegram servers see the message | **Easiest external channel**; a good opt-in for people who already live in Telegram |
| **WhatsApp** | Yes, with constraints | Meta Business account + verification, WhatsApp Cloud API, approved **template** messages outside a 24-hour window the user opened, explicit opt-in; per-delivered-message billing by country; Meta reportedly starts billing in-window service messages on **1 Oct 2026** with a free allowance (third-party reports, UNVERIFIED against Meta's own page) | Per message | Meta is a processor | Possible later; costs money and review time; opt-in rules are strict |
| **Email** | Yes | Any transactional email provider | ≈ free | Provider | Good for a daily digest, poor for "now" |
| **SMS** | Yes | Twilio or similar | Per message | Provider | Works everywhere; feels less like Doddy |
| **Phone call from Doddy** | Yes | ElevenLabs outbound call via a SIP trunk / Twilio number (`POST /v1/convai/sip-trunk/outbound-call` with `agent_id`, `agent_phone_number_id`, `to_number`) | Per minute + number rental | ElevenLabs + telco | Striking for the "mate" feeling ("Doddy is calling") for urgent watch notes; later, opt-in only |

**Design consequence:** the in-app **Nudge inbox + message-style push** is the backbone; Telegram/WhatsApp/call are
*delivery options* layered on the same nudge record. Every nudge carries a link, a "why" and a mute action (§3.4).

### 2.3 Why a backend is unavoidable for J3/J4

OBSERVED (Apple engineer on Apple forums, via search): `BGAppRefreshTask` gets about 30 s, runs at the system's
discretion based on usage patterns; silent pushes are budgeted at roughly 1–2 per hour **device-wide across all
apps**; neither can be relied on for a schedule. Apple's own advice for time-sensitive content: *have your server
push the notification at the right time.* Therefore:

- "Event today" nudges → the app pre-schedules **local** notifications whenever it runs (foreground or refresh). No server, but misses events added after the last run.
- "News about X" and "at 08:00 even if I haven't opened the app for a week" → a **Watcher** job on a server, delivering via APNs/Telegram/WhatsApp.

The gateway that `V1_VOICE_STATUS.md` already requires (ElevenLabs conversation tokens before anyone but the owner
uses voice) is the natural home for the Watcher, the push sender and later the OAuth broker. One small service, not three.

### 2.4 MCP: state of the art and what it means for Doddy

- **Spec:** the current revision is **2026-07-28** (OBSERVED, modelcontextprotocol.io). Authorization is OAuth 2.1; the MCP server is a resource server publishing Protected Resource Metadata (RFC 9728); clients discover the authorization server from it; Client ID Metadata Documents replace Dynamic Client Registration (deprecated). Transport is Streamable HTTP. A secondary article says 2026-07-28 removed the `initialize` handshake and session header (UNVERIFIED against the transport spec text).
- **ElevenLabs Agents support MCP servers** (OBSERVED in docs and in the connector's `agents_create_mcp_server` schema): transports `SSE` or `STREAMABLE_HTTP`; auth by `secret_token` or `request_headers` whose values may be plain strings, workspace secrets **or dynamic variables** (set per conversation by the app); `approval_policy` is `require_approval_all` (default), `require_approval_per_tool` (each tool auto-approved / requires approval / disabled, pinned by a `tool_hash` of its description and schema) or `auto_approve_all`; per-tool `execution_mode`, timeouts (5–300 s), interruption behaviour. Servers are workspace resources attached to agents by `mcp_server_ids`. **Not available on Zero Retention Mode.** The workspace currently has **no MCP servers registered** (OBSERVED via `agents_list_mcp_servers`).
  - Consequence: an MCP server attached to the Doddy agent is **shared by every conversation of that agent**. A connection to *the owner's* Google Calendar is fine for the single-owner prototype; for other users, per-user credentials must be injected per conversation (dynamic-variable header → Doddy gateway) or the tool must run on the phone as a client tool.
- **Google's official Calendar remote MCP server** exists (OBSERVED): `https://calendarmcp.googleapis.com/mcp/v1`, Streamable HTTP, OAuth 2.0, **Developer Preview** (requires the Google Workspace Developer Preview Program), tools `list_calendars, list_events, get_event, search_events, suggest_time, create_event, update_event, delete_event, respond_to_event`; the consent page currently lists **read and free/busy scopes only**, so write tools are doubtful until verified; Google warns about prompt injection from event content. No official Gmail or Drive remote MCP server was found; community ones exist, one of the larger ones was archived in September 2026.
- **On-device MCP client in Swift:** the official `modelcontextprotocol/swift-sdk` (0.12.x) builds for iOS and contains OAuth authorization-code, discovery and token-endpoint code (OBSERVED in Swift Package Index build logs); whether it tracks the 2026-07-28 revision and how it handles iOS redirects via `ASWebAuthenticationSession` is **UNVERIFIED**. Means "bring your own MCP server" could run on the phone with tokens in the Keychain, never touching our server.
- **Server-side agent runtimes** (for the Watcher) commonly ship an MCP connector, scheduled runs and a credential vault (e.g. Anthropic's Managed Agents with scheduled deployments; equivalents exist). Provider choice stays open per ADR-006.

### 2.5 Google account scopes (why "Google" is not one checkbox)

| Access | Google class | What it takes | Verdict |
|---|---|---|---|
| Calendar read/write (`calendar.events`, `calendar.readonly`) | **Sensitive** | OAuth app verification: narrowest scopes, justification, demo video; no security audit | OK after verification; **or skip it entirely by reading the synced calendar through EventKit** |
| Gmail read/modify (`gmail.readonly`, `gmail.modify`) | **Restricted** | Verification **plus an annual CASA security assessment** by an approved lab; reported prices range from a few hundred dollars (self-serve tiers) to tens of thousands (legacy track) — sources disagree | Not day one (matches PRD non-goals "Gmail/Calendar on day one") |
| Gmail send only (`gmail.send`) | Sensitive | Verification, no audit | Possible for "draft an email for me", later |
| Any scope while the OAuth app is in **Testing** or has < 100 users | Exempt | Users see an "unverified app" warning | Fine for the owner's prototype and a closed beta |

### 2.6 Watching the news (J4) — sources and cadence

| Option | Shape | Notes |
|---|---|---|
| Web search API called by the Watcher (model + search tool) | Hourly/daily job: "anything new about *watch note X* since last run?" | Simplest; relevance judged by the model against the **exact watch-note text**; dedupe by URL |
| Exa Websets **monitors** | Scheduled (cron, at most daily in one integration), enrich items | Good for "new articles about X" daily, not for breaking news; webhook support UNVERIFIED |
| Apify "News & Press Release Monitor" | Polls RSS/newsrooms, keyword filter, signed webhooks | Cheap, decent latency |
| 1322.io | Streaming (WebSocket/webhook), ~15 outlets, finance/politics | Real-time but narrow |
| GDELT | Free global event firehose | Context, not alerts; noisy |
| Google News RSS | Free | One measurement found only ~8 % of items fresh within 6 h (ANECDOTAL); fragile |
| Google Alerts | No API | Not usable |

PROPOSED: start with the search-API job (one dependency, provider-neutral), hourly for "urgent" watch notes and
daily for the rest, with a per-user cap. Everything a watch note returns is **untrusted content**: it can be shown
and linked, never used to trigger actions or change settings.

---

## 3. Design: the **Connections** section

### 3.1 Principles (carry-overs from the repo, applied to connections)

1. **A connection is a receipt, not a promise.** "Connected" is shown only after a real read succeeded (e.g. the first calendar query returned, the Telegram bot got a test message back). Permission denied → "Not connected" with the exact Settings path, never a grey half-state.
2. **Reads can be automatic once connected; writes and sends always confirm.** Same contract as `TOOLS_AND_ACTIONS.md`: proposal → confirmation card → execution → verified receipt (`verified | unknown | failed`).
3. **Every nudge shows its provenance:** which watch note or event caused it, when the user created that note, and a one-tap "Stop watching this". No nudge comes from inferred interests.
4. **Each connection has a privacy card** written before the permission prompt: what Doddy can see, what leaves the phone (nothing for layer A; "the events of the day, when the Watcher runs" for layer C), where it goes, how to disconnect, what deletion removes.
5. **Tool results and news pages are data, not instructions.** Calendar invites, email bodies and articles cannot authorise actions or escalate scopes (Google's own MCP guidance says the same).
6. **Quiet by default.** Default cap 3 nudges/day, quiet hours 22:00–07:30 local, "urgent" only for notes the user marked urgent. The user can always lower it; Doddy never raises it.
7. **Nothing fake.** Channels that do not exist yet (WhatsApp, calls) are listed as "Planned", exactly like the capability catalog does today.

### 3.2 Information architecture

```
Settings
└── Connections                       ← new screen (V4a)
    ├── On this iPhone                  Calendar · Reminders · Contacts · Alarms · Location & weather · Shortcuts
    ├── Accounts                        Google Calendar (via account) · Gmail (planned) · Add an MCP server…
    ├── How Doddy reaches you           Notifications (on/off, quiet hours, daily cap) · Telegram · WhatsApp (planned) · Messages recipe
    └── What Doddy watches              list of watch notes → editor
Home
├── Today card (V4a): next events + reminders, only when Calendar is connected; tap = detail, long-press = "nudge me before this"
└── Nudges (V4b): inbox of everything Doddy sent, with provenance; empty state explains how to create a watch note
Talk to Doddy / Ask Doddy
└── Tool proposals surface as confirmation cards exactly like "Save this note?" today
```

### 3.3 Screens (text wireframes)

**Connections (list)**
```
Connections
Doddy only uses what you connect here. Reads happen when you ask or when
a watch note runs; anything Doddy adds or sends is confirmed by you first.

ON THIS IPHONE
Calendar            Connected · read & add · last read 08:12      >
Reminders           Not connected                                 >
Contacts            Not connected                                 >
Alarms & timers     Needs iOS 26                                  >
Shortcuts           3 shortcuts Doddy may run                     >

ACCOUNTS
Google Calendar     Not needed — your Google calendar is already in iPhone Calendar   >
Gmail               Planned                                       >
Add an MCP server…                                                >

HOW DODDY REACHES YOU
Notifications       On · quiet 22:00–07:30 · max 3 a day          >
Telegram            Not connected                                 >
WhatsApp            Planned
Messages (iMessage) Doddy can't send texts. See the Shortcuts recipe >

WHAT DODDY WATCHES
"Kraków tram tender" news · hourly · notification                 >
Add a watch note…                                                 >
```

**Connection detail (example: Calendar)**
```
Calendar
Status: Connected (full access) · verified by reading 4 calendars at 08:12

What Doddy can do
  • See events when you ask or when a watch note runs
  • Add an event after you confirm it (never silently)
  • Schedule a nudge before an event, on this iPhone, no server involved

What leaves this iPhone
  • Nothing, unless a voice conversation looks something up: then the events it
    read are sent to the voice agent (ElevenLabs), like notes are today.

Calendars Doddy may read     [Personal ✓] [Work ✓] [Birthdays ✗]
Recent receipts              Added "Dentist" Thu 15:00 → verified · 3 Oct
Disconnect                   (Doddy forgets the permission choice; events
                              you added stay in your Calendar)
```

**Add an MCP server (advanced)**
```
Add an MCP server
Server URL   https://…
[Connect]  → sign-in in the browser (OAuth) → tool list appears:

  list_events         Read     ● Auto when connected
  create_event        Write    ● Ask me each time
  delete_event        Write    ○ Off
  …
Tools are pinned to their current description; if the server changes one,
Doddy switches it back to "Ask me" and tells you.
```

**Watch note editor**
```
Watch note
What should Doddy watch?
  [Anything new about the Kraków tram tender I mentioned on 3 Oct]
Source note: "The tram tender for Kraków line 4 opens in October…"  (saved 3 Oct)
How often?        ○ Hourly (urgent)   ● Daily at 08:00   ○ Weekly
Reach me by       [Notification ✓] [Telegram ✓]
Until             ○ You stop it   ● 30 Nov 2026
[Save watch note]
```

**A nudge, as the user sees it (lock screen, message-style)**
```
🙂 Doddy                                                   now
Tram tender: the city published the shortlist this morning.
krakow.pl/… · because you asked on 3 Oct
[Open]  [Save]  [Stop watching]
```
Text-only, no emoji in production copy; Doddy's avatar comes from the communication-notification sender image.

### 3.4 Data model (additions to `docs/architecture/MEMORY_AND_DATA.md`, PROPOSED)

```
Connection      id, kind (calendar|reminders|contacts|alarms|location|shortcuts|googleCalendar|mcp|telegram|whatsapp|push),
                status (notConnected|connected|denied|revoked|error), grantedScope, connectedAt, lastVerifiedAt,
                providerRef? (MCP server URL, bot chat id — never the token itself; tokens live in Keychain/gateway)
WatchNote       id, sourceMemoryID (provenance: the explicit note it came from), query, cadence (hourly|daily|weekly),
                urgent, channels[], quietHoursOverride?, endsAt?, createdAt, lastRunAt, lastResultDigest
Nudge           id, watchNoteID? | eventRef?, title, body, url?, evidence[{source, url, publishedAt}], deliveredVia[],
                deliveredAt, outcome (delivered|opened|saved|muted|failed)
DeliveryChannel kind, address (chat id / device token id), verifiedAt, lastDeliveredAt
ToolKind (+)    readCalendar, createCalendarEvent, createReminder, lookupContact, setAlarm, runShortcut, mcpTool(server, name)
```
Receipts keep the existing `{operationID, outcome, externalID}` shape. `Nudge.evidence` is what makes "with a link" and
"why" possible on every delivery.

### 3.5 Architecture

```
iPhone (SwiftUI)                                  Doddy gateway (small, one service)        Third parties
┌──────────────────────────────┐                  ┌──────────────────────────────┐
│ Connections screen           │                  │ token server (already needed │
│ ConnectionAdapters           │                  │   for ElevenLabs V1)         │
│   EventKit / Contacts /      │                  │ APNs sender                  │──▶ Apple Push
│   AlarmKit / Shortcuts       │   HTTPS, per-    │ Watcher scheduler            │──▶ search / news API
│ ToolExecutor (confirm→verify)│   device token   │ delivery: Telegram, WhatsApp │──▶ Telegram / Meta
│ Local nudge scheduler        │◀────────────────▶│ OAuth broker (Google, later) │──▶ Google
│ Nudge inbox (SQLite)         │                  │ MCP server "doddy-tools"     │
│ Notification Service Ext.    │                  │   (per-user, token in header)│
│   (message-style nudges)     │                  └──────────────┬───────────────┘
│ Voice: ElevenLabs SDK        │                                 │ MCP (streamable HTTP,
│   client tools run on phone  │──▶ ElevenLabs agent ────────────┘  Authorization = dynamic variable)
└──────────────────────────────┘
```

Rules of the split (PROPOSED):
- **Anything the phone can do, the phone does** (layer A as client tools, exactly like `search_memories` today). No calendar data is copied to the gateway for J1/J2.
- The gateway holds **per-user state only for watch notes and delivery channels**, keyed by an anonymous device identity (ADR-006/008 style), plus Google tokens if and when account connections ship. Minimal content: the watch-note query text and the nudges sent.
- The ElevenLabs agent gets *one* MCP server, the gateway's, with `require_approval_per_tool` and a per-conversation `Authorization` header from a dynamic variable. Reads auto-approved; writes stay **client tools** so the on-screen confirmation card remains the only path to a side effect (ElevenLabs' spoken approval is not a substitute for the card).
- "Bring your own MCP server" runs **on the phone** if the Swift SDK's OAuth works on iOS (tokens in Keychain), else through the gateway as a proxy with the user's tokens encrypted at rest. Tool descriptions are hash-pinned; a changed description resets that tool to "Ask me".

### 3.6 Flows

**Connect Calendar (V4a):** Connections → Calendar → privacy card → "Connect" → iOS prompt (full access requested only
if "see my day" is wanted; write-only if the user picks "only add events") → immediate test read → "Connected,
verified by reading N calendars" → Today card appears on Home. Denied → "Not connected" + Open Settings; nothing else changes.

**"Remind me before the dentist" (V4a):** Today card long-press or voice → proposal "Nudge you at 14:30 on Thursday
(30 min before Dentist, Europe/Warsaw)?" → confirm → local notification scheduled → receipt "scheduled, id …" (verified
by reading pending requests back) → listed under Nudges as "Scheduled".

**Create a watch note from a saved memory (V4c):** memory detail → "Watch this" → editor pre-filled from the note →
save (local + gateway) → gateway runs at cadence → each run: search → model judges relevance against the note text →
new, non-duplicate hit → `Nudge` with evidence → APNs (message-style) and any other channel → phone stores it in the
inbox → tapping opens the inbox entry with the link; "Stop watching" ends the note locally and on the gateway.

**Add Telegram (V4b):** Connections → Telegram → shows a deep link `t.me/<bot>?start=<one-time code>` → user taps Start
in Telegram → gateway pairs chat id to the device → sends "Hi, it's Doddy. Nudges will arrive here." → the app shows
"Connected, test message delivered at …" only after Telegram's API confirmed delivery.

**MCP tool call during voice (V4d):** agent proposes `list_events` → auto-approved read → result returned → agent
speaks it; agent proposes `create_event` → the app shows the confirmation card (client tool) → user taps Add → EventKit
write → read-back → receipt → agent told "added" or "declined".

### 3.7 Privacy, security and legal implications (preflight, not clearance)

- **New personal data on our server** (new for this product): push device tokens, Telegram chat ids, WhatsApp numbers, watch-note text, nudge history, later Google tokens. Needs the data-inventory rows in `PRIVACY_GDPR_AI_ACT.md` extended, retention (proposal: nudges 90 days server-side, forever locally until deleted), export and delete-everything paths, and processor terms for Apple/Telegram/Meta/search provider/model provider.
- **Lock-screen exposure:** nudges show on the lock screen; offer "hide content until unlocked" and keep bodies short. Never put memory text in a notification unless the user chose to.
- **Prompt injection:** event titles, invite bodies, MCP tool results and articles are untrusted. The policy gate must sit outside the model (typed schemas, confirmation card, allow-listed tools, hash-pinned tool descriptions).
- **Spend control:** per-user caps on Watcher runs, search calls and model tokens; a global monthly cap with alerting, as the voice minutes already need.
- **App Store:** justify background modes and notification use; communication notifications must represent real messages to the user (they do); WhatsApp opt-in must be collected in-flow with the business named; EU: no Siri AI, so Shortcuts/App Intents stay the system entry points.
- **Honesty copy:** "Doddy watches the news for *the notes you marked*", never "Doddy knows what you care about".

---

## 4. Proposed build order (each slice usable on its own; one slice per approval)

| Slice | What the user gets | Needs from owner | Device tests that gate "done" |
|---|---|---|---|
| **V4a Calendar & Reminders in your pocket** | Connections screen; Calendar + Reminders + Contacts connections; Today card; voice/text tools `read_calendar`, `create_calendar_event`, `create_reminder`, `lookup_contact` with confirm + verified receipts; **local** "before this event" nudges | Nothing external; approve full-access vs write-only default | Permission denied, revoked mid-session, write-only read-back limitation, duplicate prevention, timezone, Polish calendar names |
| **V4b Doddy can reach you** | Gateway (also the voice token server); APNs message-style nudges with Doddy's face; Nudge inbox; quiet hours and daily cap; Telegram channel | Apple Developer account, a host for the gateway, APNs key, a Telegram bot | Avatar renders; Focus behaviour; delivery when app killed; token rotation; delete-everything removes server rows |
| **V4c Watch notes** | "Watch this" on any memory; Watcher job (hourly/daily); nudges with link + evidence + Stop watching; export of nudge history | Search/news API, model provider for relevance (provider-neutral), monthly cap | Relevance precision on 20 seeded notes; dedupe; no nudge outside quiet hours; cost per watch note per day measured |
| **V4d Accounts and MCP** | Google Calendar via Google's remote MCP (preview) or the gateway's OAuth broker; "Add an MCP server" with per-tool approvals; ElevenLabs agent attached to the gateway MCP server | Google Cloud project + Developer Preview membership; decision on on-phone vs gateway MCP client | OAuth on iOS; token refresh; tool-hash change handling; reads only until write scopes confirmed |
| **V4e Optional channels** | WhatsApp templates; "Doddy calls you" for urgent notes; the Messages (Shortcuts) recipe with a tap test | Meta business verification + budget; a phone number; iOS 27 for the notification trigger | Opt-in flow; cost per nudge; recipe works after reboot |

Nothing in V4 changes M1 behaviour: a user who connects nothing keeps the same local app.

---

## 5. Decisions needed from the owner

1. **Scope of the first slice:** V4a as described (Calendar + Reminders + Contacts, local nudges), or Calendar only?
2. **Permission default:** ask for Calendar *full access* (needed for the Today card and read-back verification) or start write-only and upgrade on demand?
3. **Gateway hosting and identity:** where the small service runs (EU region), and the anonymous device identity scheme; this also unblocks the voice token server.
4. **Primary external channel:** Telegram first (free, fast) — yes/no? WhatsApp deferred until a budget exists?
5. **Watcher provider and cap:** which search/news API and which model provider; monthly spend cap; EU residency requirement.
6. **MCP placement:** on-phone client (Keychain tokens, needs the Swift SDK's OAuth verified on a device) vs gateway proxy (simpler, tokens on our server).
7. **Google:** join the Workspace Developer Preview for the official Calendar MCP server now, or rely on EventKit for synced Google calendars until a real account feature is needed?
8. **Nudge policy defaults:** 3/day, quiet 22:00–07:30, 90-day server retention — confirm or change.
9. **Phone-call nudges:** in scope at all (brand moment) or out (cost, telco setup)?

---

## 6. What this document does not claim

- No code, screen or server from this proposal exists. Capability catalog rows stay "not built" until executed tests say otherwise.
- The communication-notification avatar, the Swift MCP SDK's OAuth on iOS, Google's write scopes on the Calendar MCP server, WhatsApp's October 2026 pricing and the iOS 27 notification trigger are **UNVERIFIED** here and must be tested or re-read before planning dates.
- Prices and vendor names were read on 2026-10-09 and change often.

## Sources

Apple
- Communication notifications: https://developer.apple.com/documentation/usernotifications/unnotificationcontent/updating(from:) ; forum reports https://developer.apple.com/forums/thread/725263 , https://developer.apple.com/forums/thread/691684
- EventKit access levels: https://developer.apple.com/documentation/eventkit/accessing-the-event-store
- AlarmKit: https://developer.apple.com/documentation/alarmkit
- Background tasks and silent push limits (Apple engineer reply): https://developer.apple.com/forums/thread/837675 ; https://developer.apple.com/forums/thread/125912
- Silent SMS not possible: https://developer.apple.com/forums/thread/102839 ; MessageUI https://developer.apple.com/documentation/messageui
- Shortcuts iOS 26 what's new: https://support.apple.com/en-gb/125148 ; communication triggers https://support.apple.com/guide/shortcuts/apdd711f9dff/ios
- iOS 27 notification trigger (beta hands-on, ANECDOTAL): https://www.derekseaman.com/2026/06/home-assistant-notifications-that-run-apple-shortcuts-yes-really.html ; https://mjtsai.com/blog/?p=52271

MCP and agents
- MCP 2026-07-28 authorization: https://modelcontextprotocol.io/specification/2026-07-28/basic/authorization ; overview of the revision https://pub.towardsai.net/model-context-protocols-2026-07-28-spec-puts-governance-before-speed-2b240295a1c5
- ElevenLabs Agents MCP: https://elevenlabs.io/docs/eleven-agents/customization/tools/mcp ; security https://elevenlabs.io/docs/eleven-agents/customization/tools/mcp/security
- ElevenLabs outbound calls: https://elevenlabs.io/docs/eleven-agents/api-reference/sip-trunk/outbound-call ; Twilio native https://elevenlabs.io/docs/eleven-agents/phone-numbers/twilio-integration/native-integration
- Google Calendar remote MCP server: https://developers.google.com/workspace/calendar/api/guides/configure-mcp-server
- Swift MCP SDK builds (OAuth files present): https://swiftpackageindex.com/builds/07166F71-D5EE-4438-B734-47E6FC84C432

Google scopes
- Sensitive scope verification: https://developers.google.com/identity/protocols/oauth2/production-readiness/sensitive-scope-verification
- Restricted scopes / CASA (vendor summaries, prices disagree): https://developer.nylas.com/docs/provider-guides/google/google-verification-security-assessment-guide ; https://www.unipile.com/integrating-google-oauth-2-0-user-authentication-into-your-app/ ; https://deepstrike.io/blog/google-casa-security-assessment-2025

Messaging channels
- WhatsApp pricing (Meta): https://developers.facebook.com/documentation/business-messaging/whatsapp/pricing ; 1 Oct 2026 change reports: https://respond.io/blog/whatsapp-pricing-change-2026.md , https://edna.io/resources/whatsapps-new-pricing-structure-what-will-be-charged-starting-october-1-2026/ ; opt-in policy summary https://docs.amio.io/docs/whatsapp-policy
- Telegram Bot API sendMessage: https://www.unipile.com/telegram-api-send-message-a-comprehensive-guide/ ; https://advancedweb.hu/the-easiest-way-to-set-up-a-chat-with-your-telegram-bot/

News monitoring
- Exa Websets monitors: https://exa.ai/docs/websets/api/monitors/create-a-monitor.md
- Apify news monitor: https://apify.com/cynix_dev/news-press-monitor
- 1322.io: https://1322.io/platforms/news
- News API comparison 2026: https://geekflare.com/guides/global-news-api/ ; Google News RSS freshness (ANECDOTAL): https://apiserpent.com/blog/best-google-news-api-media-monitoring
