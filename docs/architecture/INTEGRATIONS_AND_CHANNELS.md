# Integrations and channels catalog

> **Merged 2026-10-10:** this work now sits on the combined branch line. The server lives in
> `server/messaging/` (it was `server/`), its ADRs are 139–168 (were 036–065), the
> `/v1/voice/token` route is gone (the app uses the Vercel `server/voice-token`), and this line's
> M4 Reminders was replaced by the main line's. See `docs/implementation/MERGE_PLAN.md`.

Date: 2026-10-10. This is the list of what Doddy can connect to on an iPhone, how each one connects, and its status.
Each connection is opt-in, one at a time. Each becomes one entry in the tool registry (`TOOLS_AND_ACTIONS.md`): Doddy proposes, the user confirms, and a result counts only once it is verified.

## Connection pattern (every integration)
1. Explanation screen.
2. iOS permission prompt, or a web login sheet (OAuth).
3. Test read.
4. "Connected ✓".
5. Disconnect, which revokes access and deletes cached data.

Cloud tokens live on the server (`server/messaging/`), never in the app.

## A. Apple apps on the phone (permission prompt, no account)
| App | API | Status |
|---|---|---|
| Reminders | EventKit | Planned M4 |
| Calendar | EventKit | Later |
| Contacts | Contacts / ContactAccessPicker | Later |
| Alarms, timers | AlarmKit (iOS 26+) | Later |
| Photos | PhotosPicker | Later |
| Location | CoreLocation (when in use) | Later |
| Health | HealthKit | Later |
| Music | MusicKit | Later |
| Maps | MapKit / Maps URL | Later |
| Home | HomeKit | Later |
| Mail / Messages / Phone | Compose sheets / `tel:`; the user taps Send or Call | Later |
| Spotlight | Core Spotlight | Later |
| On-device model | Foundation Models (iOS 26+) | Research |
| Notes, WhatsApp, banking apps | No API; share sheet or Shortcuts only | — |

## B. Ways to reach Doddy
- Siri / App Shortcuts (App Intents)
- Action Button and Back Tap (the user sets these up)
- Control Center control
- Lock Screen and Home Screen widgets
- Share Extension
- Actionable notifications
- Live Activities, only for real ongoing state
- Watch / CarPlay: later; CarPlay needs an entitlement

## C. Cloud services (OAuth via server)
| Service | Notes |
|---|---|
| Google (Gmail, Calendar, Drive, Contacts) | Gmail read scopes need Google's paid security assessment |
| Microsoft 365 (Graph) | Work tenants may need admin consent |
| Notion, Todoist, Slack, Spotify, Strava | Per-service app review |
| Telegram | Bot API; simplest chat channel |
| WhatsApp | Business Platform; Doddy's own number, template rules |
| EU banking | Licensed aggregator only; not early |
| Aggregators (Composio, Nango, Pipedream Connect) | Hold user tokens; privacy review first |

## D. Doddy → user updates (owner decision 2026-10-10: **push + SMS**)
| Channel | Status |
|---|---|
| Push (APNs) | **Server + app built (S1)**; not yet run on a device |
| SMS (Twilio, verified number + explicit opt-in, STOP honoured) | **Server + app built (S1)**; not yet run with real Twilio |
| iMessage via Apple Messages for Business | Owner applying; live-agent requirement, see `APPLE_MESSAGES_FOR_BUSINESS_APPLICATION.md` |
| WhatsApp Business via the ElevenLabs Agents integration, on its own number (WhatsApp only), chosen by the user next to SMS (ADR-442) | **Decided 2026-10-13; not built, not run.** Needs the number free of any other WhatsApp registration; Meta-approved templates for Doddy-initiated messages |
| Telegram | Not chosen |
| Mac-relay iMessage services | **Rejected**: against Apple's terms, numbers get blocked |

## D2. News (owner decision 2026-10-10: **RSS + GNews, Claude Haiku one-liners, daily digest**)
| Source | Status |
|---|---|
| Curated RSS (10 topics, 28 publisher feeds) + the user's own RSS/Atom feeds | **Built (N1)**; feeds verified live |
| GNews keyword search for the user's own topics | **Built (N1)**; needs `GNEWS_API_KEY` (paid plan) |
| Claude Haiku writes the daily DM | **Built (N1)**; needs `ANTHROPIC_API_KEY`; falls back to headlines |

## E. Calls (owner decision: **Twilio + ElevenLabs**)
| Option | Status |
|---|---|
| Doddy phone number: Twilio number imported into the ElevenLabs agent (native integration) for inbound and outbound calls | **Built (S2)**: server + app + agent setup script; not yet run with real Twilio/ElevenLabs (see `docs/implementation/S2_CALLS_STATUS.md`) |
| In-app call screen (CallKit + VoIP push) | Later |
| Siri "ask Doddy" | Later |

Required before calls go live:
- PIN before Doddy reads private memories (caller ID can be faked);
- AI disclosure at the start of every call (EU AI Act);
- prior consent for outbound calls;
- a retention decision for recordings and transcripts;
- per-minute cost limits.
