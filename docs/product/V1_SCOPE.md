# Doddy v1: what ships (proposal for the owner)

> **PROPOSAL. Not owner-approved.**
>
> - Written 2026-10-18 from the code, docs, git history and read-only checks of the live services at `754e5d6` (default branch). Nothing in the app changes because of this file.
> - **How to use it:** in each table, fill the **Owner** column with Ship, Hide or Cut. Leave it blank to accept the suggestion. Then answer the decisions in "Owner decisions" at the end.
> - Once marked up, ADR-520 records the result and this file becomes the v1 scope. It replaces `docs/product/PRODUCT_REQUIREMENTS.md` (10 Oct). That file describes a typed-memory MVP the app has outgrown. It stays unchanged as history, because `scripts/verify_imported_pack.py` locks it byte for byte.
> - The steps to get this scope into testers' hands are in `docs/implementation/GO_LIVE_CHECKLIST.md`.

## What "v1" means

- **v1 beta:** the first build anyone other than the owner gets, through external TestFlight. The beta plan suggests 20–24 adults who aren't friends (`docs/quality/VALIDATION_AND_METRICS.md`).
- **v1.0 (App Store):** the same scope once the beta passes. Between beta and 1.0 the only additions are fixes and the paywall decision. No new features.

## The one promise (owner decision 1)

Three different promises are in use today:

| Where | Promise |
|---|---|
| `docs/product/PRODUCT_REQUIREMENTS.md` (10 Oct) | "Tell Doddy before you forget; find the original later." |
| Tagline (README, site, app) | "Your mate in your pocket." |
| Homepage hero (ADR-482, 14 Oct) | "Say it once. Tap once. Done." A plan card that changes Calendar, Maps, Messages and Lists in one tap. |

**Suggestion:** v1 promises **"Tell Doddy before you forget. He remembers it, reminds you, and finds it when you ask."** Keep "Your mate in your pocket" as the tagline.

Why:
- Saving and finding notes by voice is the only thing recorded working on the owner's iPhone (`save_memory` and `search_memories`, 9 and 11 Oct; `STATUS.md`, `V1_VOICE_STATUS.md`).
- Reminders and lists run on the phone with Apple's own frameworks. They need no server or outside account.
- The pricing plan's free tier is exactly this: memory and search with no cloud AI (`docs/business/MONETIZATION_MODEL_V2.md` §3).
- "Say it once. Tap once. Done." depends on the plan card (`propose_plan`), which has never been called, even in the owner's own conversations. It also depends on Gmail, Notion and Calendar actions that have never run against a real account. Keep it on the site as where Doddy is heading, and say plainly that the beta is memory, reminders and lists.

## Who v1 is for (owner decision 2)

**Suggestion:**
- **The person:** adults who already text themselves, keep notes in Notes or Keep, or ask Siri to remind them, and still lose things (hypothesis H1 in `docs/00_START_HERE/DECISIONS_AND_STATUS.md`).
- **What they'd switch from:** Apple Notes, Reminders and Siri, and ChatGPT's voice mode. Nobody has tested this yet: the customer interviews and the competitor test (D03/D04) were never done. The beta should compare Doddy against each tester's current habit.
- **First market:** Poland, in English and Polish. The evidence:
  - the prices are in złoty and the pricing plan opens with a Polish soft launch (`MONETIZATION_MODEL_V2.md` §7);
  - the phone-number branch uses a Polish Twilio number (`claude/awesome-cray-2lb9ia`, ADR-490 there);
  - English and Polish are the only languages anyone has read.
- **The other eight app languages** are machine drafts that no native speaker has read (`l10n/REVIEW_NOTES.md`). On 14 Oct the owner said "no native review for now". Suggestion: hide them from the language picker in v1 and add each one back after one native read. Voice still answers in whatever language the user speaks.

## How each call was made

- **Ship:** serves the promise, needs only the servers v1 keeps, and can be checked on an iPhone before the beta. Every Ship row still has to pass the device pass in the checklist. A row that fails it becomes Hide.
- **Hide:** the code stays on main, but v1 shows no way in: no Settings row, no Home card, no widget, and no voice tool on the agent. **There is no switch for this today** (no feature flags; only 8 `#if DEBUG` blocks in the app). The checklist adds one small list in DoddyCore as the switch.
- **Cut:** left out of the v1 build. Its server, vendor, permission, entitlement, privacy-policy section and App Review note drop out with it.
- **Default rule:** a feature that has never run on a device *and* needs a server or vendor v1 otherwise doesn't is Hide or Cut.

**Evidence key** (column "Seen"):
- **device:** recorded working on the owner's iPhone.
- **built:** in `ce02763`, the 11 Oct build the owner ran, but with no record of anyone trying it.
- **CI:** compiled in hosted CI (since `c8aff7a`, 13 Oct) and never on a device.
- **never:** never compiled.

The newest commits (`f40861c`, `754e5d6`, 16 Oct) have never compiled (checklist A1).

## 1. Memory: the core

| Feature | What it does | Seen | Leaves the phone | Suggested | Why, and what to check first | Owner |
|---|---|---|---|---|---|---|
| Capture | Type a note (or add a photo), Save | built (simulator UI test passes) | Note text goes to the voice provider at each conversation start | **Ship** | Core | |
| Memories | List, Find, note screen, corrections that keep every wording, tags | device (via voice); screens built | Non-private notes, up to 6,000 characters, go to OpenAI or ElevenLabs at each conversation start | **Ship** | Core. Check VoiceOver and the largest text size on a phone | |
| Privacy | Face ID lock, private notes, "What leaves this iPhone" | built; data-flow screen CI | none | **Ship** | The trust promise, and the screen the App Store privacy answers rest on. Fix the hard-coded `tokenServerSet: true` (`DataFlowView.swift:16,33`) | |
| Backup | A passphrase-locked backup file you save yourself | built; never made or restored | Only to where you save it | **Ship** | A memory app needs a way out, and export and delete are never paywalled. Set `ITSAppUsesNonExemptEncryption`. Settle whether voice memos go in backups (ADR-230 says no, ADR-234 and `BackupViews.swift:111` say yes) | |
| What Doddy did + Undo | Every change Doddy made, with Undo for 24 h | Undo built; receipts CI | none | **Ship** | The constitution's receipts and undo rule. Run checklist steps U1–U14 on a phone | |
| Share Sheet "Save to Doddy" | Save text or a link from any app | CI (didn't compile on Xcode 26.6 until `81fd5623`) | none | **Ship** | Cheapest way to capture. Needs the App Group signed and its own privacy manifest | |
| Quick actions | Long-press the icon: Talk, New note, Find, Parking | built | none | **Ship** | 39 lines. Drop the Parking item if Parking is hidden | |
| Photos | One photo on a note; reads its text on the phone | CI (the text reader didn't compile until `ae409062`) | The text it reads becomes note text | **Ship** if the device pass is clean, else Hide | Apple's photo picker, no permission prompt | |
| Find by meaning | "Close in meaning" results in Find | built | none | **Hide** | The thresholds are guesses and speed with hundreds of notes is unmeasured. Find works without it | |
| Import | Google Keep and text files, with a review step | built; never tried on a real Takeout export | none | **Hide** | Good for people switching from Keep. Try one real export, then ship it in 1.0 | |
| Voice memos | Record up to 5 min, transcribe on the phone, offer to-dos | built; never recorded on a phone | none | **Hide** | A second microphone path. A clash with a live conversation is untested. Two more permission prompts | |
| Tidy up | Weekly offer to remove duplicates and done lists | built | none | **Hide** | Later | |
| Spotlight | Notes in iPhone search (off by default) | built | none | **Hide** | Off by default already | |

## 2. Voice

| Feature | What it does | Seen | Leaves the phone | Suggested | Why, and what to check first | Owner |
|---|---|---|---|---|---|---|
| Live conversation | Talk to Doddy; he saves, finds and changes things through tools | device (ElevenLabs logs up to 16 Oct, from a build newer than `ce02763`) | Audio, notes, lists, profile and recent conversations go to the voice provider | **Ship** | The core. Today it can't connect at all (checklist A3–A6): the app points at a disabled server | |
| One voice provider | ElevenLabs or OpenAI Realtime | ElevenLabs device; OpenAI never heard on a phone | as above | **Ship one, hide the picker** | Owner decision 5. Every recorded call ran on ElevenLabs. Weather, Wikipedia and place lookup work only on ElevenLabs | |
| Model picker | Realtime 2.1 or mini on Home and in Settings | CI | none | **Hide** | A test switch, not a user choice | |
| Plan card (`propose_plan`) | Up to 5 changes (note, event, reminder, timer) approved in one card | built; never called | as above | **Hide** | Never called. One action per card is enough for v1 and easier to verify. The homepage hero shows this card, so the site needs a line saying it isn't in the beta | |
| Dynamic Island and Lock Screen | Doddy's island while you talk; Back Tap's big island | base built; big island CI | none | **Ship** if the device pass is clean | The owner saw the island on 10 Oct (ADR-207 report). Check whether App Review accepts a `LiveActivityIntent` as a button action | |
| "Hey Doddy" | Wake word while Doddy is in the background | **removed 20 Oct 2026 (ADR-549)**; had never run (no keyword file, no key) | none | **Cut (done)** | Needs a Picovoice commercial licence and the `.ppn` file. Always-on listening is the biggest App Review question. A false wake starts a paid conversation | |
| Read aloud | Reads a note with iOS's own voice | built | none | **Ship** | On the phone, free. Uses the Tools Live Activity, so keep that code | |
| Back Tap guide | Shows how to bind Double Back Tap to "Talk to Doddy" | device (owner's spoken report, 9 Oct, earlier branch) | none | **Ship** | Low risk, and the fastest way to start talking | |
| Translator | Face-to-face translation inside a conversation | device (10-16 logs; one call titled "Translator activation failed") | Both people's speech goes to the voice provider | **Hide** | Failed once on a device. The latest change isn't on the live agent. The other person never agreed to be recorded | |
| What Doddy learned | Learned facts and routines, shown and deletable in Settings | built (in `ce02763`); screens never run | none (local SQLite) | **Hide** | Its own status doc puts it after the beta decision, so it doesn't skew the beta's results (`M6_LEARNING_LOOP_STATUS.md`) | |
| Typed Ask | A typed question goes to OpenAI through Doddy's gateway | built; never run | Question plus up to 5 notes to OpenAI | **Cut** | The gateway has no settings, so every call fails. Typing a note and Find already work without AI | |

## 3. Reminders, lists and your day

| Feature | What it does | Seen | Leaves the phone | Suggested | Why, and what to check first | Owner |
|---|---|---|---|---|---|---|
| Note reminders (time) | A notification about one note at a set time, set by tap or voice | built | none | **Ship** | "He reminds you" is in the promise | |
| Note reminders (place) | When arriving at or leaving a place | built | Typed place search goes to Apple Maps | **Hide** | Never run. Background location alerts are where phones differ most from tests. Hiding it means v1 asks for no location at all | |
| Lists | Lists by voice or tap, ticks, Undo, templates, share as a picture | built (the list screen changed after, CI) | List names and counts go to the voice provider | **Ship** | Core everyday use | |
| Shopping mode | The list on the Lock Screen with tick buttons | built; never run | none | **Hide** | Lock Screen buttons are a `LiveActivityIntent` behind Face ID, and the App Review risk hasn't been assessed | |
| Calendar, Reminders, Contacts | Doddy reads and changes them by voice; each change waits for your tap | built | Event, reminder and contact names go to the voice provider | **Ship** | The main integration, with no server needed. Full Calendar access must be explained to App Review | |
| Today card | The rest of today's events and due reminders on Home | built + CI | none | **Ship** | Rides on Calendar and Reminders | |
| Morning check-in | Optional morning notification and briefing | built; never rang | Briefing data only after a tap | **Ship**, off by default | One routine to bring people back. Off by default | |
| Evening wrap-up | Moves overdue Reminders to tomorrow | built; never touched real data | none | **Hide** | It writes to the user's Reminders and has never been tried | |
| Weekly look-back | A week of notes and changes | built | none | **Hide** | Later | |
| Birthdays | Yearly notification for picked contacts | built; never run against real contacts | Name and day go to the voice provider | **Hide** | One more permission and more notifications (see the 64-notification limit, checklist B6) | |
| Alarms | "Wake me at 7" by voice (AlarmKit) | CI; never rang | none | **Hide** | iOS 26 only, and never rang | |
| Leave by | Travel time and a "leave now" notification | CI | Position and place to Apple Maps | **Hide** | Needs location | |
| Parking | Save and find where you parked | built | none (location stays local) | **Hide** | Needs location | |
| Focus and breathing | Timers on the Lock Screen and island | built | none | **Hide the screens** | Keep the Tools code: read aloud uses its Live Activity | |
| Widgets | Home and Lock Screen widgets, New note widget, controls | base built; New note CI | none | **Ship** read-only widgets and New note; **Hide** tick-from-widget | A tick from a cold start is untested and may do nothing | |
| Shared lists (iCloud) | Share a list with other people | CI; off at runtime | iCloud | **Cut** | Needs a paid team, an iCloud container and the Production schema. Remove the `remote-notification` background mode and `CKSharingSupported` so App Review doesn't see an unused mode | |

## 4. Online accounts and Doddy's own servers

| Feature | What it does | Seen | Leaves the phone | Suggested | Why | Owner |
|---|---|---|---|---|---|---|
| Online accounts (Gmail, Outlook, Drive, Notion, Todoist, Google Calendar) | Tools through Composio and `backend/`, each off by default; since PR #87 (18 Oct) they include sending and changing mail, calendars and pages, each behind ASK-01 | built; mock tests only | Mail, files and tasks through Composio | **Hide** | Never run against a real account. Gmail's scopes need Google's verification (ADR-099). No real user sign-in on the backend (ADR-077). Composio's terms aren't reviewed | |
| Web search | Doddy looks something up | device (11–14 Oct) | Query to Monid through `backend/` | **Hide** (owner call) | The one online feature seen working. It needs the backend, which is reached only through a developer token pasted in Settings | |
| Connected Apps (Google Calendar) | Tomorrow's Google events in Settings | built | Through Composio | **Cut** | The iPhone's own Calendar already shows Google calendars synced to it | |
| Daily news | A daily digest | built | Topics to the messaging server, headlines to an AI | **Cut** | A release build has no server address. The server's database expires 10 Nov. GNews' free plan isn't for commercial use | |
| Phone calls with Doddy | Call Doddy's number; a PIN unlocks your notes | built; can't run | A copy of your notes on the server; calls through Twilio | **Cut** | No real call has ever been made, and the phone agent doesn't exist. Phone numbers are stored in plain text | |
| Texts and server notifications | Push and SMS through Twilio | built; can't run | Phone number and message text | **Cut** | Same server, never run. App Attest still open (ADR-143) | |

## 5. Platforms

| Platform | Seen | Suggested | Why | Owner |
|---|---|---|---|---|
| iPhone | device | **Ship** | The product | |
| iPad | CI | **Cut for v1** (iPhone-only build) | Apple doesn't let an update drop a device family an app has already shipped on, so iPad is easy to add later and hard to take back. It also needs its own screenshots and gets its own App Review pass | |
| Apple Watch | CI; never run on a watch or simulator | **Cut for v1** | Build v1 from `project-iphone.yml`, which leaves the Watch app out | |
| Mac | never compiled | **Cut** | A prototype, and a separate App Store record | |

## 6. Work in progress on branches

On 18 Oct several branches were adding more scope, and one (PR #87) has since merged. Suggestion: until this file is marked up, merge only fixes, and hold anything that adds a tool, a vendor or a permission.

| Branch or PR | What it adds | Suggested |
|---|---|---|
| PR #84 `laughing-darwin` | Fixes the checks `754e5d6` broke (ADR-494); one conversation at a time (ADR-496); start logging; 1Password; a `render.yaml` secrets fix | **Merge first** once CI can run (checklist A2) |
| `sweet-albattani`, `upbeat-ride`, `awesome-cray` | Other fixes for the same broken checks | Close in favour of #84 |
| PR #85 `dreamy-cannon` | BLIK bank transfers by voice (Doddy prepares, you send in your bank app) | **Hold.** Payments are the highest-trust action there is, even when Doddy only prepares them, and they aren't in the promise |
| PR #86 `connect-in-conversation` (draft) | Connect an online account from the conversation | **Hold** while online accounts are hidden |
| PR #87 `trusting-sagan` (**merged into main on 18 Oct** at the owner's request) | ASK-01 "always ask first" for every tool, plus Gmail send, Outlook, Google Calendar, Notion and Monid tools (ADR-483 to 489) | **Keep ASK-01.** It is the trust rule v1 needs. The new account tools are on main and on the live agent (85 tools, `agtvrsn_6401…`), so for v1 they stay hidden: no Settings row, and off the live agent (section 4). Hosted CI couldn't run, so none of it has been built |
| `awesome-cray` | Doddy's phone number (Twilio texts) | **Hold** (calls and texts are cut) |
| `jolly-clarke` | One persona for both providers, Wiktor voice | Take if it improves the one beta provider |
| PR #78 | "Big brain. Small body." share card (claims ADR-444, already used) | Site only; renumber before merging |

## 7. Money in v1

- **The beta is free.** No StoreKit and no paywall in the beta. The paywall decision comes at 1.0, judged by the pricing plan's thresholds (`MONETIZATION_MODEL_V2.md` §7).
- **The voice cost no longer matches the plan.**
  - The plan's included voice is a turn-by-turn pipeline at about €0.020 a minute. It was never built.
  - The plan keeps live speech-to-speech for Pro only, at about €0.081 a minute.
  - ADR-442 made OpenAI Realtime (the live kind) the default for everyone.
  - One measured 14-minute session cost $2.05 (`MONETIZATION_MODEL_V2.md`). The app's session cap is 600 s; the plan assumed 5 minutes.
- **For the beta:**
  - set a daily minute cap per tester on the token server;
  - set a monthly spend limit at the beta's voice provider;
  - record real cost per minute (the plan's "Real unit cost" metric).
  
  Pricing v3 uses those measured numbers.

## 8. What this scope removes

If the suggestions stand:
- **Vendors out of v1:** Composio, Monid, Twilio, GNews, the news writer's AI, Picovoice, iCloud/CloudKit, and one of OpenAI or ElevenLabs.
- **Servers v1 needs:** only the voice token server (with its Redis), plus the website.
  - `backend/`, `gateway/` and `server/messaging/` aren't needed.
  - So the 10 Nov database expiry stops being a v1 blocker.
- **Permissions v1 asks for:**
  - microphone;
  - Calendars, Reminders and Contacts (only when the user connects them);
  - notifications;
  - Face ID.
  
  No location, no speech recognition prompt (voice memos are hidden), and no Always-on microphone.
- **Privacy policy:**
  - §5.4 to §5.10 drop: Ask, the messaging server, texts, calls, memory on calls, news, Composio.
  - §5.1 to §5.3 (voice provider and token server), §5.11 and §5.12 (website) stay.
- **App Review questions that drop:**
  - always-on listening;
  - the unused `remote-notification` mode;
  - shopping mode's Lock Screen buttons;
  - Google's restricted Gmail scopes.

## 9. Owner decisions

| # | Decision | Suggestion |
|---|---|---|
| 1 | The one promise | "Tell Doddy before you forget. He remembers it, reminds you, and finds it when you ask." |
| 2 | First market and languages | Poland; English and Polish; the other eight hidden until a native read |
| 3 | The Owner column in sections 1–5 | As suggested |
| 4 | iPhone only for v1 | Yes; iPad, Watch and Mac later |
| 5 | The beta's one voice provider | Whichever passes the device pass first. On today's evidence, ElevenLabs: every recorded call ran on it. If it stays, turn off voice recording and set a retention limit (today `retention_days -1`, kept forever) |
| 6 | Sign in with Apple for voice (`754e5d6`, no ADR yet) | Keep it. It closes the public-agent hole on the app side. Record it as an ADR, because it reverses ADR-147 ("No login for now"). Deleting the account should also revoke the Apple token (checklist C8) |
| 7 | Beta free, paywall at 1.0 | Yes |
| 8 | Freeze feature merges until this file is marked up | Yes; fixes only (section 6) |

## When v1 is done

The v1 beta is ready when every Ship row has passed the device pass and every item in stages A to C of `docs/implementation/GO_LIVE_CHECKLIST.md` is closed. v1.0 is ready when stage D is closed and the beta has hit the thresholds the owner sets before it starts (checklist C10).
