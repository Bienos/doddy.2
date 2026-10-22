# Settings, simplified (ADR-580)

Owner, 22 Oct 2026: "Settings should be for controlling DODDY, not reading technical documentation."

Before: one Form of about 25 sections and 70 rows, with 17 explanatory paragraphs. The longest, the privacy paragraph, was about 3,400 characters. After: six groups on one short screen, each row a switch, a picker or a page. **No preference was removed, renamed or re-keyed.** Every control keeps its `PreferenceKey` and its accessibility identifier, so nothing a user set changes. The one migration is Back Tap's "Small island", which became its own switch (ADR-579, below).

Code: `DoddyApp/Features/Settings/SettingsView.swift` (the groups), `SettingsScreens.swift` (the pages), `SettingsSupport.swift` (the profile editor, exports, voice pickers, moved unchanged).

## New structure

| Group | Row | Opens / does |
|---|---|---|
| **Profile** | My profile | About you answers, Edit, intro again, "Use in voice conversations", exports, Forget |
| | Voice and personality | unchanged (`PersonalityView`) |
| | Language | App language picker (ADR-459) |
| | Appearance | Light/Dark/System, Hide character artwork |
| **Voice and interaction** | Voice | Provider picker, Auto-start voice, voice account (sign out, delete, ask again), connection; Debug: developer voice switch |
| | Action Button | Picker: Dynamic Island / Open App / Automatic (ADR-579); footer: what it does + where to assign it |
| | Dynamic Island style | unchanged (`IslandStyleView`, with previews) |
| | Expand when Doddy speaks | switch (was Back Tap's "Small island") |
| | Siri and Back Tap (Siri on iPad) | Back Tap status, Ways to open Doddy guide, weekly reminder, "When Siri or Back Tap opens Doddy", Siri can read my notes |
| **Memory and privacy** | Memories | Count, export JSON/text/Markdown, restore, Delete all, encrypted backup, import |
| | What Doddy knows | Remember conversations, remembered list, forget, suggest notes, What I've learned |
| | Privacy | Face ID lock, iPhone search, What leaves this iPhone, Everything Doddy sends (the old paragraph, word for word), Privacy Policy, "Right now" status rows, widgets, Apple Watch |
| **Connected apps** | Pause all connections | switch (footer art and text unchanged, ADR-323) |
| | Calendar, reminders, contacts / Connected Apps / Online accounts / What Doddy did | unchanged pages |
| | Ask Doddy (typed questions) | consent, notes, status, gateway, invite code |
| **Notifications** | Notifications and texts / Daily news / Phone calls | unchanged pages |
| | Check-ins and reminders | morning check-in, evening wrap-up, weekly look-back, tidy-up, note reminders |
| | Alarms / Birthdays | unchanged pages |
| **About** | Help | doddy.lol/what-can-doddy-do (Polish page for Polish) |
| | Try a plan card | unchanged |
| | Terms & Conditions / Privacy Policy | doddy.lol pages (Polish for Polish), ADR-581 |
| | Terms accepted | date, once accepted |
| | TikTok / Instagram / Version | unchanged links |
| | Advanced | build note, What's built, Connected Apps development server (Debug builds, or when one is already set so it can be removed) |

## What moved where

| Before (old Settings section) | Now |
|---|---|
| Header footnote "Text capture and search work locally…" | removed (said elsewhere) |
| About this build (version + "Development build…") | About › Version; the note in Advanced |
| Follow Doddy | About |
| About you (+ 2 paragraphs) | Profile › My profile; one-line footers, the voice-sharing consequence kept at the switch |
| Your memories (+ "where memories live" paragraph) | Memory › Memories; a shorter footer that still names every place a copy can be (DOD-11). Delete all's full consequences stay in its confirmation |
| Morning check-in, Evening wrap-up, Weekly look-back, Tidy-up, Note reminders | Notifications › Check-ins and reminders |
| Backup, Import | Memory › Memories |
| Apple Watch, Widgets (+ paragraph) | Memory › Privacy |
| Privacy (lock, summary, iPhone search, What leaves, 6 status rows, the long paragraph) | Memory › Privacy; the paragraph on its own page, "Everything Doddy sends" |
| Connected Apps, Online accounts (each with a footer) | Connected apps group, no footers |
| Connected Apps server (development) | About › Advanced (Debug, or when set) |
| What Doddy knows (+ 2 paragraphs) | Memory › What Doddy knows, one-line footers |
| Voice (personality, island style, listen on open + paragraph, provider, developer + paragraph, account, connection + paragraph) | Profile › Voice and personality; Voice and interaction › Voice / Dynamic Island style |
| Back Tap and Siri (status, guide, reminder + paragraph, "When I use Talk to Doddy" + paragraph, Siri + paragraph) | Voice and interaction › Siri and Back Tap; the Action Button gets its own picker |
| Connections (pause, calendar…, What Doddy did, Alarms, Birthdays, Try a plan card) | Connected apps; Alarms and Birthdays to Notifications; Try a plan card to About |
| Messages from Doddy (3 pages) | Notifications |
| Ask Doddy (typed questions) | Connected apps › Ask Doddy |
| App language | Profile › Language |
| Appearance and accessibility (+ 2 paragraphs) | Profile › Appearance, one-line footer |
| What's built | About › Advanced |

## Rules used (from the owner's brief)

1. A short name; a subtitle only when it helps a choice ("Auto-start voice · Start talking when Doddy opens").
2. No infrastructure words (App Intents, tokens, Composio internals) in the groups. The development server is in Advanced.
3. Progressive disclosure: the long texts live on the page a row opens, "Everything Doddy sends", Help and the Privacy Policy.
4. Where a switch sends something off the iPhone, one plain line says what and where, at the switch: profile to the voice service, Ask Doddy to Doddy's server and OpenAI, Delete all's confirmation.

## Checks

- UI tests moved with the rows: `LaunchSmokeTests` open the right page first (`openSettingsPage`), and `DoddyArtTests`' Pause-all footer is unchanged. **Hosted CI passes them ([run 39786285579](https://github.com/Bienos/doddy.2/actions/runs/39786285579): 56 UI tests, 1 skipped).
- Strings: `tools/build_strings_catalog.py --check` PASS; 31 Polish and 23 lines in each other language for removed sentences were deleted; 73 new Polish lines (machine-written, `l10n/REVIEW_NOTES.md`). The other eight languages show the new rows in English.
- Not checked on a device: Dynamic Type at AX sizes, VoiceOver order, iPad sidebar layout.
