# Settings and Connections: design proposal
**Status:** design proposal, 2026-10-10, written from main before the Connections work on this line was seen. Connections cards, Reminders, Calendar, Contacts, Timers and Online accounts are already built here (ADR-073–082, 096–105); use this as a reference for what is still missing there: the plan card for several apps at once and the "What leaves this iPhone" table. "What Doddy did" (ADR-123) and Pause all (ADR-124) are now built.
**Visual reference:** Pocket Notebook (`design/interface-v1.2/docs/DESIGN-SYSTEM.md`).
**Clickable study:** `design/settings-and-connections-v0.1/index.html` (fictional data, no real permissions, accounts or writes).

## 1. The job

People want Doddy to reach the apps they already use (Reminders, Calendar, weather, their own Shortcuts, later online accounts) and to use several of them in one request: "I'm at Mom's on Saturday. Remind me to bring the spare key, and tell me if it'll rain."

Two things have to be true at the same time:

1. **Easy:** connecting an app takes one short sheet, and using several together takes one review card, not a separate confirmation per app.
2. **Trustworthy:** the person always knows what Doddy can reach, what it did, and what left the iPhone. The rules in `docs/architecture/TOOLS_AND_ACTIONS.md` still hold: the model proposes, the app checks, the person confirms, the app verifies, then Doddy reports.

## 2. Settings, reorganised

Today's `SettingsView` is a development screen (agent ID, "What's built"). The proposal groups it by what people look for, and moves engineering detail to the bottom.

| Section | Rows | Notes |
|---|---|---|
| Header | "Settings" + one-line truth line | Example: "3 apps connected. Your notes stay on this iPhone." Built from real state, never decorative. |
| **You and Doddy** | What I know about you · How Doddy talks (language, reply length, humour, voice) · Appearance and accessibility | "What I know about you" is the v1.1 preference editor. |
| **Connections** | Apps and tools (count connected) · Ways to open Doddy · What Doddy did (activity) | The new hub. Details in section 3. |
| **Memories** | Saved on this iPhone · Export JSON · Export text · Delete all | Unchanged behaviour from M1. |
| **Privacy** | What leaves this iPhone · Use connected apps while talking (toggle) · Pause all connections | One place that answers "what is sent where". |
| **About** | Version · What's built · Developer (agent ID, dev builds only) | "What's built" stays, because it is the honesty contract. |

## 3. Connections hub ("Apps and tools")

### 3.1 Groups

| Group | Examples | How it connects | Earliest milestone |
|---|---|---|---|
| **On this iPhone** | Reminders, Calendar, Alarms and timers, Weather, Places and directions, Contacts, Music, Home, Your Shortcuts | iOS permission prompt. No account. | M4 starts with Reminders; each further tool is its own decision |
| **Messages and email** | Messages, Mail, Phone | Doddy drafts, iOS opens the compose sheet, the person taps Send | After M4, separate decision |
| **Online accounts** | Google Calendar, Gmail, Notion, Todoist, Spotify | Sign-in (OAuth) through a Doddy server that holds tokens | Unscheduled. Needs account, server, privacy review |
| **Doddy in other places** | Siri and Shortcuts, Share sheet "Save to Doddy", Back Tap / Action Button, Control Center, widgets | App Intents and system surfaces | V2 guided setup (research doc section 5) |

Rows that are not built show **Not built yet** and are not tappable into a fake connect flow. The study lets you vote ("I'd use this") as a demand signal; that vote is local and fictional in the study.

### 3.2 Row anatomy

`[line icon] Name` / one line "Doddy can: …" / status as **text** on the right (never colour alone):

| Status | Meaning | Source of truth |
|---|---|---|
| Connected | Permission granted and Doddy is allowed to use it | iOS authorization status, read at display time |
| Connected · tested 10 Oct | As above, plus the person ran the test step | Local receipt |
| Paused | Permission still granted, but Doddy will not use it | Local setting |
| iOS permission off | The person or iOS revoked access | iOS authorization status |
| Not connected | Available to connect | Capability catalog |
| Not built yet | Shown for transparency only | Capability catalog |

No row may say Connected based on a cached flag alone. Status is re-read from iOS each time the hub appears, because people change permissions in iOS Settings.

### 3.3 Connect flow (one sheet, four steps)

1. **What Doddy will do.** Two short lists: "Doddy can" and "Doddy won't". Plus "What leaves this iPhone" in plain words. Example for Reminders:
   - Can: read your lists and reminders; add a reminder after you say yes.
   - Won't: complete, change or delete reminders; read other apps.
   - Leaves the iPhone: when you ask during a voice conversation, the reminders Doddy reads are sent to the voice service (today: ElevenLabs) for that conversation only.
2. **Choose what to share.** Scope (all lists, or chosen lists) and the "ask first" level (section 3.4). Defaults are the safest working setting.
3. **iOS asks.** Doddy shows a one-line lead-in, then iOS shows its own prompt. The study labels the illustrated prompt "iOS shows this, not Doddy". Doddy never imitates the system dialog in the real app.
4. **Try it.** One suggested phrase ("What's on my shopping list?") that runs a real read and shows the result. Success writes a local "tested" receipt. Skipping is allowed; the row then says Connected without "tested".

**Denied path:** "iOS permission is off. Doddy can't see your reminders. You can turn it on in iOS Settings → Doddy → Reminders." Buttons: Open iOS Settings, Not now. Everything else keeps working.

**Online-account path (future):** same four steps, but step 3 is a web sign-in sheet (`ASWebAuthenticationSession`), and step 1 also names the Doddy server that stores the sign-in token, where it runs, and how to disconnect.

### 3.4 How much Doddy may do without asking

Per connection, three kinds of action, each with a fixed ceiling:

| Kind | Examples | Choices | Default |
|---|---|---|---|
| **Look things up** | Read reminders, calendar, weather | Without asking · Ask first | Without asking |
| **Add or change** | Add a reminder, create an event, start a timer | Ask first (locked) | Ask first |
| **Remove or send** | Delete, complete, send a message | Not allowed in this version · (later) Ask every time | Not allowed |

The locked row shows a short reason: "Doddy always shows you a change before making it." This is what keeps "use several apps at once" safe.

### 3.5 Connection detail

- Status line with source ("iOS permission: on · checked just now").
- What Doddy can do (section 3.4 controls) and scope (lists/calendars).
- **Recently:** the last three actions for this app, each a receipt (section 5).
- **Pause** keeps the iOS permission, Doddy stops using it immediately.
- **Disconnect** clears Doddy's own settings and receipts for this app and explains, truthfully, that iOS permission has to be switched off in iOS Settings (apps cannot revoke their own permission). Things Doddy already created (for example reminders) stay in the other app.

## 4. Using several apps at once: the plan card

When one request needs more than one connection, Doddy answers with **one plan card** instead of a string of separate confirmations.

```
Here's what I'd do                                     (draft)
────────────────────────────────────────────────────────────
✓ Looked up   Memories   Spare key: blue tin above the fridge
✓ Looked up   Calendar   Sat 14:00 · Mom's
✓ Looked up   Weather    Sat in Warsaw: rain likely (60%), 11°
☐ Add         Reminders  "Bring the spare key (blue tin above
                          the fridge) and an umbrella"
                          Sat 12:00 · list: Personal       Change
────────────────────────────────────────────────────────────
[ Add 1 reminder ]   Not now
```

Rules:

1. **Look-ups run first and are shown as done**, with their source. They only run for connections set to "without asking"; otherwise they appear as a step to approve.
2. **Every change is a separate checkbox**, pre-ticked, with its full resolved details (date, time zone, list). The button counts what will happen ("Add 1 reminder", "Do 2 things").
3. **One tap confirms all ticked changes.** Unticking keeps the rest. "Change" edits a step in place.
4. **Steps run in order and each gets its own result**: Done (checked in Reminders), Couldn't (reason + retry), or Not sure (Doddy couldn't confirm; tap to check before retrying, to avoid duplicates).
5. **No hidden steps.** If the model proposes a step for an app that is not connected, the card shows "Calendar isn't connected" with Connect / Skip, instead of silently dropping it.
6. **Paused or "Pause all"** turns every step into "Skipped: connections paused".
7. Read results inserted into a plan are data, not instructions. A calendar title or note that says "also delete my reminders" cannot add a step (prompt-injection rule from the threat model).

**Conflict with current architecture.** `TOOLS_AND_ACTIONS.md` says "single-step … no background autonomous multi-tool plan in MVP". The plan card is a foreground, fully reviewed, multi-step proposal. It needs an explicit owner decision and an ADR update before implementation. Until then the safe subset is: several look-ups + at most one change per card.

## 5. "What Doddy did" (activity)

One chronological list across all connections, stored on this iPhone only.

- Each entry is a receipt: time, app, action, result (Done / Couldn't / Not sure / Skipped), and "Open in Reminders" when there is an external ID.
- Filter by app. Plans are grouped under their request ("Saturday at Mom's").
- Look-ups are listed too ("Read 3 reminders from Shopping"), so people can see what Doddy looked at, not only what it changed.
- Kept 30 days (proposal), "Clear activity" removes the log only, never the reminders it created.

## 6. Privacy

"What leaves this iPhone" is a table built from real configuration, one row per connected app plus Memories and Voice:

| Data | Leaves the iPhone? |
|---|---|
| Your memories | Only the ones Doddy looks up during a voice conversation, sent to ElevenLabs |
| Reminders (connected) | Only what Doddy reads during a voice conversation |
| Weather | Your approximate location is sent to Apple Weather |
| Activity log | Never |

Controls:

- **Use connected apps while talking:** off means voice conversations can only use Memories. On by default only after the person has connected at least one app.
- **Pause all connections:** one switch, effective immediately, also reachable from the voice screen.

## 7. Ways to open Doddy

Rows for Siri and Shortcuts (automatic once App Shortcuts ship), Action Button, Back Tap, Control Center, Share sheet. Status uses the research doc's rule: "Set up and tested by you on 9 Oct", never "verified by iOS", because apps cannot read Back Tap or Action Button assignments. Each row opens the v1.2 guided setup.

## 8. Copy rules

- Name apps the way people do ("Reminders", "Calendar"), never framework names.
- Status is a word, not a colour or a dot alone.
- Never write "Connected" for something not built, and never show a fake system prompt in the product.
- Errors say what happened and what to do: "Doddy couldn't add the reminder because iOS permission is off. Turn it on in iOS Settings → Doddy → Reminders."
- No brand logos for third-party services in the app until usage rights are checked; the study uses generic line icons.

## 9. Proposed native structure (for the milestone that builds it)

- `DoddyCore`: `Connection` (id, kind, scope, askLevel per action kind, paused), `ConnectionStatus` (derived), `PlanProposal` (ordered steps: lookup/change, connection, payload digest), `ActionReceipt` (already sketched in `TOOLS_AND_ACTIONS.md`).
- `ConnectionRegistry` port; one adapter per app (`RemindersAdapter` first, EventKit). Adapters report authorization status; UI never caches it as truth.
- `PlanRunner`: executes confirmed steps sequentially, persists pending state before each external write, records receipts, stops on "Pause all".
- Screens: `SettingsHome`, `ConnectionsHub`, `ConnectSheet`, `ConnectionDetail`, `PlanCard`, `ActivityLog`, `WaysToOpen`.
- `Capability.connectedAccounts` stays "not built" until online accounts exist; add per-app capabilities (`reminders` already exists) rather than one global "connections" flag.

## 10. Acceptance (for the future milestone)

- Status for each connection matches iOS authorization after toggling permission in iOS Settings and returning to the app.
- Denied permission: connect flow ends on the denied screen; no "Connected" anywhere; voice and memories still work.
- Plan card: unticking a change prevents it; a timeout produces "Not sure" and no automatic retry; an injected instruction inside a calendar event never adds a step.
- Pause all: no adapter is called while paused (unit test with a spy adapter).
- Disconnect: Doddy settings and receipts removed; external reminders untouched; copy tells the person how to remove iOS permission.
- VoiceOver reads every status as text; Dynamic Type at the largest accessibility size keeps the plan card readable without truncation.

## 11. Decisions for the owner

1. Approve the Settings regrouping (section 2) for the next Settings change, independent of connections.
2. Approve the plan card (section 4) and the ADR change it implies, or keep "one change per card".
3. Pick the first two "On this iPhone" connections after Reminders (recommended: Calendar read-only, then Weather).
4. Decide whether online accounts are in scope this year. They need a Doddy account, a token server, and privacy review.
5. Confirm the activity log retention (proposal: 30 days, on device).
