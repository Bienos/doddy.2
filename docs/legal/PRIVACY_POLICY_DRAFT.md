# Doddy privacy policy: DRAFT

> **DRAFT. NOT LEGAL ADVICE. NOT REVIEWED. NOT PUBLISHED.**
>
> - This file was written from the code and the docs in this repository on 2026-10-11. It is for the owner and a lawyer to review.
> - It is not published, not linked from the app or the website, and not an approved notice under GDPR, the EU AI Act or App Store rules.
> - Text in [BRACKETS] is a placeholder. Text tagged **[CONFIRM: ...]** is something the code or docs do not settle.
> - Every statement is meant to match what the code does today. Where the app's own screens say something different, this is noted in Appendix B.
> - Many features here are built but never run on a device or against a live service (`docs/implementation/GO_LIVE_STATUS_2026-10-11.md`). A published policy must describe what is really running at launch, so every section needs a re-check.
> - It depends on these owner decisions: who the controller is; which servers are really deployed; ElevenLabs retention; which processor agreements exist; the age rating; whether the website keeps Google Fonts and Google Analytics. See Appendix B.

Effective date: [DATE]
Version: [VERSION]
Languages: English. A Polish version is [CONFIRM: owner decision; the app has Polish screens, ADR-223, ADR-234].

---

## 1. Who we are (the controller)

| Item | Value |
|---|---|
| Controller (legal entity or person) | [LEGAL NAME] **[CONFIRM: not stated anywhere in the repository. The GitHub organisation and bundle ID say "Bienos", but that is not shown to be a legal entity]** |
| Address | [POSTAL ADDRESS] |
| Contact for privacy requests | [PRIVACY EMAIL ADDRESS] **[CONFIRM: none exists yet; `site/README.md` "Needs the owner" 2 and 3]** |
| Data protection officer | [NAME AND CONTACT, or "not appointed"] **[CONFIRM: whether one is required]** |
| Representative in the EU or UK | [NAME AND ADDRESS, or "not needed"] **[CONFIRM: depends on where the controller is established]** |
| Supervisory authority you can complain to | [AUTHORITY] **[CONFIRM: if the controller is in Poland, this would be the Polish authority (UODO). The repository only shows the Warsaw time zone and a Frankfurt server region, not the owner's establishment]** |

This policy covers:

1. the Doddy iPhone app (with its widgets, Share extension and Apple Watch app);
2. Doddy's servers that the app can talk to (Section 5);
3. the Doddy website at [WEBSITE ADDRESS] (today `https://doddy-eight.vercel.app`, `site/README.md`) and its waitlist.

It does not cover the services you connect yourself (Google, Microsoft, Notion, Todoist, Apple, your mobile carrier) or the sites we link to (TikTok, Instagram, Telegram). They have their own policies.

## 2. What Doddy is, and the short version

Doddy is an AI character. Doddy is software, not a person. Doddy has no feelings and does not know you the way a person does. Doddy can be wrong. (Sources: `voice-agent/instructions.md` line 1, ADR-191, `HomeView.swift`.)

In short:

- **No account is needed to use the app.** (`PrivacyDefaults.v1Voice`, `accountRequired: false`.) Some optional features create an anonymous server account or ask for a phone number (Sections 5.5 to 5.9).
- **Your notes, lists, About you answers, photos and voice memos are stored on your iPhone.** They leave it only through features you switch on, listed in Section 5.
- **A voice conversation sends a lot.** When you talk to Doddy, your voice, the conversation and your saved notes (except notes you mark Private) go to ElevenLabs. ElevenLabs keeps a recording and a transcript. **[CONFIRM: how long, see 5.1]**
- **There are no ads, no sale of data and no tracking in the app.** (Sources: `DataFlowView.swift` intro text, `PrivacyInfo.xcprivacy` `NSPrivacyTracking` false, `DEPENDENCIES_AND_LICENSES.md` "No analytics, no crash reporting".) The website does use analytics (Section 5.12).
- **You can see where your data goes** in the app: Settings, Privacy, "What leaves this iPhone". It changes with your switches.
- **You can export and delete** most of what is on your iPhone (Section 8). Data already held by a service (ElevenLabs and others) is not deleted by the app.
- **Doddy makes no automated decisions** about you with legal or similar effects (Section 7).
- **This is an early test build.** (`site/index.html` privacy note.)

## 3. Data that stays on the iPhone

The app has no analytics, no crash reporter and no advertising code. (`DEPENDENCIES_AND_LICENSES.md`.) The following is kept on your iPhone. It is sent off the phone only as described in Section 5.

| Data | Where it is kept | Notes and source |
|---|---|---|
| Notes (text, original text, source, dates, type, corrections history) | SQLite database in Application Support, iOS Data Protection `completeUntilFirstUserAuthentication`, `secure_delete` on | ADR-028, ADR-252. Included in your iPhone backups (iCloud or computer) because it is ordinary app data. |
| Lists and list items | Same database | ADR-216 |
| Photos added to notes | `NotePhotos` folder next to the database, JPEG, same protection class | ADR-218. Chosen with Apple's photo picker. The app has no camera or photo-library permission. Text in the photo is read on the iPhone with Apple's Vision. |
| Voice memos | `NoteAudio` folder, same protection class | ADR-230. Words are written out on the iPhone (on-device speech recognition is required). If the iPhone cannot do that for your language, nothing is written out and nothing is sent. |
| About you answers (name, preferences) | Same database, separate table | ADR-085. Saved only after you review them. |
| Personal settings, switches, pinned note IDs, private note IDs, parking spot | UserDefaults (app preferences) | ADR-019, ADR-043, ADR-187, ADR-301, ADR-310. The parking spot holds a position and your note (see Section 6, Location). |
| Remembered conversations (the last 10, as text) | JSON file, same protection class | ADR-047. Optional switch "Remember recent conversations". Off for a conversation you mark Private (ADR-170). |
| "What Doddy did" activity list (30 days, up to 300 entries) | JSON file, same protection class | ADR-135, ADR-169. Online-account entries keep the tool name only. |
| Private notes (Face ID) | The note stays in the database. Its ID is on a "private" list. | ADR-310. Private notes are held back from voice, Siri, Ask Doddy, widgets, the watch and the call copy. They are not encrypted separately in the app. |
| Widget snapshot (up to 4 pinned notes, 3 next reminders, 8 lists with 12 items each, parking time and note) | File in the App Group, `completeUntilFirstUserAuthentication` | ADR-219, ADR-315. Reminder text is hidden by default. Note text is marked privacy sensitive for the Lock Screen. |
| Apple Watch sync | The iPhone sends the same snapshot to the watch by WatchConnectivity. The watch app has no database or networking. | ADR-232. On by default. A switch exists in Settings, Apple Watch. |
| Share extension inbox ("Save to Doddy") | `share-inbox.json` in the App Group, complete file protection, removed when read | ADR-311 |
| iPhone search index (CoreSpotlight) | Doddy's own index domain | ADR-330. Off by default. Private notes are never indexed. |
| Access codes and tokens (voice token server code, Doddy server token, Ask Doddy token, Picovoice AccessKey) | iOS Keychain | The server token is `AfterFirstUnlockThisDeviceOnly` (ADR-149). **[CONFIRM: accessibility class of each other secret]** |
| Exchange-rate file (last good copy) | On the iPhone | ADR-300 |
| Exported files and encrypted backup files | Wherever you save them | Section 8 |

Face ID: iOS checks your face. Doddy learns only whether it matched. (`NSFaceIDUsageDescription`.)

## 4. What Doddy does not do

Stated only where the code or docs show it:

- No advertising, no data sale, no cross-app tracking in the app (`PrivacyInfo.xcprivacy`: `NSPrivacyTracking` false, no tracking domains).
- No analytics or crash-reporting SDK in the app (`DEPENDENCIES_AND_LICENSES.md`). The Settings row reads "Analytics and telemetry: Off (not built)". **[CONFIRM: the final build is checked for third-party SDK privacy manifests, see Appendix B]**
- No location tracking. Location is read once when you ask (Section 6). Place reminders are watched by iOS, not by Doddy (ADR-196).
- "Always" location and background location are not used (ADR-196, enforced by the guard script).

## 5. Data that leaves the iPhone

One subsection per destination. "Opt-in" means off until you turn it on. Where the default build cannot reach a service because no address is set, that is said.

Common points:

- The app's own list of destinations is `DataFlow.rows` (`Packages/DoddyCore/Sources/DoddyCore/DataFlow.swift`). This section starts from it and adds what the code and docs show beyond it. Differences are listed in Appendix B.
- "Pause all connections" (Settings) switches off Doddy's use of calendar, reminders, contacts and online accounts in conversations (`DataFlow`, `pauseAll`).

### 5.1 ElevenLabs: voice conversations

| Item | Detail |
|---|---|
| Who | ElevenLabs (runs the voice agent: speech to text, the language model, text to speech). **[CONFIRM: ElevenLabs legal entity, location and processor terms]** |
| What is sent | Your voice. The conversation. Your saved notes, newest first, up to 6,000 characters (never notes marked Private). List names (a list's items only when Doddy reads or changes a list). Your personality settings. If on: your last few conversations (up to 4,000 characters) and your About you answers. Your nickname or first name appears in the profile when About you is shared. A random install ID is sent as the conversation user ID. In a morning check-in conversation: today's Doddy reminders and lists with things left. |
| Also sent when you use the matching switch | Calendar entries, reminders, contact names with birthday day and month (never the year or an age), message drafts, results from your online accounts (for example email previews, file names, Notion page titles, Todoist tasks, and one whole email or page if "Read an email" or "Read a Notion page" is on) |
| When | Only while a conversation is open (maximum 10 minutes per conversation, `voice-agent/session.json`). The microphone is used only while you talk, or from app open if you turned that on, or with "Hey Doddy" on (see 5.11). |
| Opt-in? | Starting a conversation is your action. Using the voice feature sends the data above. The extra items depend on your switches (Settings, Connections). |
| Language model behind the agent | The agent is configured to use Google's `gemini-3.5-flash` model (`voice-agent/session.json`, `V1_VOICE_STATUS.md`). So your conversation is also processed by Google through ElevenLabs. **[CONFIRM: ElevenLabs' sub-processors, Google's terms for this route, and whether Google keeps or trains on it. The app's own screens do not mention Google]** |
| Weather and facts | ElevenLabs makes the request for Doddy. The place name and coordinates go to Open-Meteo. Search words go to Wikipedia. The app makes no such request itself. (`DataFlow` row `lookups`.) |
| Recording and transcript | ElevenLabs keeps a recording and a transcript of each conversation (`DataFlow` note). The dev agent setting is: audio recording on, retention unlimited, no auto-delete, zero-retention off (`V1_VOICE_STATUS.md`, ADR-057). The transcript can include your first name. ADR-057 says this was accepted only for the owner's own phone and "revisit before any other user". **[CONFIRM: retention period for launch; whether recording is turned off; zero-retention mode (the status doc says it and EU residency are Enterprise-only); deletion of existing recordings; ElevenLabs data location]** |
| Who can start a conversation | With a token server set, the app sends your access code to it and gets a one-conversation token (5.2). Without one, the app uses the public development agent ID. Agent authentication is off today (ADR-034, `GO_LIVE_STATUS` "Live services"). **[CONFIRM: authentication on before any other person uses it]** |
| Private conversation | The Private switch on the Talk screen means nothing of the conversation is kept on the iPhone. ElevenLabs still runs it and keeps its own recording (ADR-170). |
| Translator mode | The other person's voice and everything said while translating also go to ElevenLabs. Opened from Translate on Home, your notes, conversations and profile are not sent. Started inside a conversation, what Doddy already had stays there, and Doddy is told never to repeat it. Nothing is kept on the iPhone unless you tap Copy or Save within 5 minutes of the end. (`DataFlow` row `translator`, ADR-215.) The other person has not agreed to anything. **[CONFIRM: what you tell people you record, and the lawful basis for their voices]** |
| Phone-call agent | Separate agent for phone calls, see 5.7. |
| Transfers | ElevenLabs and its sub-processors may be outside the EU or UK. **[CONFIRM: transfer mechanism]** |
| Legal basis | **[CONFIRM: proposed: performance of the service you asked for, and your consent for the microphone and the optional items]** |

### 5.2 Doddy voice token server

| Item | Detail |
|---|---|
| Who | Doddy's own small server (`server/voice-token`), written for Vercel Functions. `VOICE_TOKEN_SERVER_STATUS.md` and `GO_LIVE_STATUS` say a token server is deployed with one owner code. **[CONFIRM: host, region and what is live]** |
| What is sent | Your access code, when a conversation starts. |
| What it does | Swaps the code for a one-conversation ElevenLabs token (or, for the OpenAI voice, a 120-second OpenAI client secret for the model you picked), so the ElevenLabs API key stays on the server. |
| Logged | One JSON line per request: status, error, tester label, upstream status, duration. No codes, tokens, keys, IP addresses or spoken content. (`server/voice-token/README.md`.) The hosting platform may keep its own request logs. **[CONFIRM: Vercel log retention and IP logging]** |
| Opt-in? | Only if a token server address is set in Settings, Voice. |

### 5.3 OpenAI: Doddy's voice (the default where a token server is set)

| Item | Detail |
|---|---|
| Who | OpenAI (Realtime API). **[CONFIRM: OpenAI entity, terms, region]** |
| What is sent | The same as 5.1: your voice, the conversation, notes, list names, personality settings and the rest of the prompt. The prompt, notes and tools go from the phone straight to OpenAI, not through Doddy's server. (`server/voice-token/README.md`, ADR-265.) |
| When | Only while a conversation is open and Home's voice switch says OpenAI. OpenAI is the default when a token server is set (ADR-442); with none, ElevenLabs runs. |
| Retention | The app says: how long OpenAI keeps the audio and transcript "isn't verified in this build" (`DataFlow`). **[CONFIRM]** |
| Opt-in? | No longer a separate switch: it is the default once a token server is set. You can switch to ElevenLabs under Talk to Doddy on Home; Home also picks the model (`gpt-realtime-2.1` or `gpt-realtime-2.1-mini`). **[CONFIRM: the consent wording for a default that sends voice to OpenAI]** |

### 5.4 Ask Doddy (typed questions): Doddy's gateway and OpenAI

| Item | Detail |
|---|---|
| Who | A separate small server (`gateway/`, written for Vercel Functions) that passes questions to OpenAI's Responses API. It uses an Upstash Redis store for rate limits and spend counters. **The gateway is "written, tested and not deployed" (`gateway/README.md`).** **[CONFIRM: host, region, and whether Upstash is used]** |
| What is sent | Your typed question and up to 6 earlier messages from that screen. If "Use relevant saved notes" is on: up to 5 notes that match your question (never Private notes). At sign-up: an invite code and a random device ID. Every call: a 24-hour token. (`docs/architecture/ASSISTANT_GATEWAY.md`.) Notes are given to OpenAI under short aliases (n1, n2), not their IDs. |
| When | Only when you send a typed question. |
| Opt-in? | Yes. Off until you confirm a dialog. |
| Retention | The gateway asks OpenAI not to store (`store: false`). Whether that is honoured is not verified (ADR-113). The gateway's logs keep short hashed tags, status codes, timings and counts. No question, note or answer text. The host's own request logs (IP, path, status) are kept by the host. Chat history is in memory only and never saved as notes. **[CONFIRM: OpenAI terms and retention; host log retention]** |

### 5.5 Doddy messaging server: anonymous account and notifications

| Item | Detail |
|---|---|
| Who | Doddy's own server (`server/messaging`): a web service and a worker with a Postgres database on Render, region Frankfurt (`render.yaml`, ADR-139). `render.yaml` says it was "not deployed"; the app's built-in server address is empty, so a shipped build reaches no messaging server until one is set (`ServerConfig.swift`). **[CONFIRM: what is deployed at launch; Render's processor terms]** |
| What is created | An anonymous account (random IDs, no name, no email). A device token, stored only as a SHA-256 hash. The date the account was made and last used. |
| Push notifications | If you turn notifications on: this iPhone's APNs notification token and its environment. The server sends through Apple (APNs). The push never contains a note. |
| Opt-in? | Yes. The server token is kept in the Keychain and is not backed up, so a restored iPhone starts a new anonymous account (ADR-149). |
| Retention | Until you delete your messaging data or an operator deletes the account. Sent-message rows lose their text when they reach a final state, but metadata rows (state, channel, times, provider ID) are not pruned in the code reviewed for this draft. **[CONFIRM: retention period for these rows]** |

### 5.6 Doddy messaging server: texts (SMS) and your phone number

| Item | Detail |
|---|---|
| What is sent | Your phone number. A code from Twilio Verify to confirm it. Your agreement to texts and the wording version you agreed to. The text of messages you ask Doddy to send you (up to 640 characters). |
| Who | Twilio (Verify and messaging). **[CONFIRM: Twilio entity, region, processor terms, carrier data]** |
| Stored | The number is stored in the database in plain form (`phone_numbers.e164`). Only a hash of the number is kept in the 2-day table that limits repeated codes. Message text is encrypted while queued if the server has its key (otherwise plain) and is erased when the message reaches a final state. **[CONFIRM: encrypt the stored phone number or accept]** |
| Opt-in? | Yes: you verify the number and agree in the app. A STOP reply cancels texts. |
| Logs | Ids and counts only. No message text, phone numbers or tokens. (`server/messaging/README.md`, `src/log.ts`.) |

### 5.7 Doddy messaging server: phone calls with Doddy

| Item | Detail |
|---|---|
| What | Doddy can answer calls from your verified number, and can call you ("call me now"). Calls run on an ElevenLabs phone agent through a Twilio number. You set a 6 to 8 digit PIN, stored only as a scrypt hash. Rows record each call: direction, status, conversation ID, call ID, time. |
| Recording and transcript | The phone agent is set up with no audio recording and transcripts kept 30 days at ElevenLabs (`voice-agent/phone/session.json`, ADR-158). The setup script has not been run: "The phone agent is not created yet" (`voice-agent/README.md`). The agent is configured to use Google's `gemini-2.5-flash` model. Twilio keeps its own call records. **[CONFIRM: all of this; Twilio call-record retention]** |
| Notes from calls | Notes Doddy takes on a call wait on the server, encrypted, until you confirm or discard them in the app. They have no expiry in the code reviewed for this draft. **[CONFIRM: add an expiry?]** |
| Limits | Outbound calls: 3 per hour, 10 per day. |
| Opt-in? | Yes: calls are off until turned on; outbound calls need separate consent (`calls-v1`). |

### 5.8 Doddy messaging server: "Memory on calls" (copy of your notes)

| Item | Detail |
|---|---|
| What is sent | A full snapshot of your saved notes (current text only; Private notes excluded), synced from the app when the switch is on. |
| Where stored | The messaging server's Postgres, each note encrypted with AES-256-GCM bound to your account and the row, using a server-held key. This is encryption at rest, **not end-to-end**: the server can read the notes to answer a call. (`server/messaging/README.md`, ADR-153.) |
| Opt-in? | Yes, off by default ("Let Doddy use my memories on calls"). |
| Deletion | Turning it off deletes every copy. "Delete all memories" in the app also empties the copy and tells you if that failed. Key rotation is not done yet (`SECURITY_REVIEW_MESSAGING.md`). Backups of the database by the host. **[CONFIRM: host backup retention]** |
| Calls | During a call, the notes that match are read to the model (ElevenLabs and its model provider). |

### 5.9 Doddy messaging server: daily news

| Item | Detail |
|---|---|
| What is sent to Doddy's server | The topics and feeds you pick, your own keywords, send time, time zone, language and channels (push or SMS). |
| What the server sends on | Your own keywords to GNews. Topic labels and public headlines and summaries to Anthropic (Claude) or OpenAI, whichever key the server has, to write short lines. Never notes, phone numbers or account IDs (ADR-163, ADR-197). Your own feed addresses are fetched by the server from the internet. |
| Who | GNews, Anthropic or OpenAI, and the feeds you add. **[CONFIRM: terms and retention for each]** |
| Retention | Sent-story records pruned after 14 days. Digest records after 30 days. Shared feed cache after 24 hours. (`server/messaging/src/news/digest.ts`, `sources.ts`.) Topics, feeds and settings stay until you change them or delete the account. |
| Opt-in? | Yes, off by default. |

### 5.10 Doddy backend: Connected Apps and online accounts (Composio)

| Item | Detail |
|---|---|
| Who | Doddy's backend (`backend/`, Node), which talks to Composio and on to Google (Calendar, Gmail, Drive), Microsoft (Outlook), Notion and Todoist; and to Monid for web search. Render, Frankfurt, free plan (`render.yaml`). `ONLINE_ACCOUNTS.md` says web search ran on a Render service; the account connections have not been run against real accounts. **[CONFIRM: what is deployed; hosting terms; Composio and Monid terms, regions, sub-processors, retention; a data processing agreement]** |
| What the app sends | A session token. What you ask for: a date, a search word, or the text of a draft, reply or task you confirm. Never your saved notes. (`SECURITY_AND_PERMISSIONS.md`, `DataFlow` row `doddyServer`.) |
| What comes back | Results (calendar entries, email previews, file names, page titles, tasks, web results). They go to the app and, during a conversation, to ElevenLabs so Doddy can speak them. |
| Stored by the backend | A map from your Doddy user to a random Composio user ID. Connection metadata (provider, status, granted scopes, a masked account label). Short-lived attempt records. Receipts (tool, time, status, counts; no titles, subjects, search words or text). Usage counters, never pruned. (`SECURITY_AND_PERMISSIONS.md` "Data boundaries", `ONLINE_ACCOUNTS.md`.) The backend stores no event titles, email text or notes. |
| Stored by Composio and the providers | Composio holds the sign-in tokens and its own run logs. Google and the others hold your data. Doddy never sees your Google password or tokens. **[CONFIRM: per Composio's policy]** |
| Access scope | Gmail drafting uses a scope that also permits sending; Doddy has no send tool (ADR-099). Gmail read, Drive (metadata) and Calendar are read-only scopes. Outlook scopes: **[CONFIRM: see `backend/src/tools/catalog.ts`]**. **[CONFIRM: owner accepts the wider Gmail scope or drops drafting]** |
| Opt-in? | Yes. Every account and every tool is off until you connect and switch it on. Anything that adds or creates asks you first. You can disconnect: this deletes the connection record and asks Composio to revoke and delete. If that fails the screen says so. |
| Identity today | Sign-in is by a token the owner mints. Real app sign-in is not built. Live production mode is refused until it is (ADR-077). **[CONFIRM: how users will sign in before public launch]** |
| Retention | Backend records have no retention policy; the free-plan database file resets on restart or deploy (`render.yaml`, `SECURITY_AND_PERMISSIONS.md` gate 2). Account deletion and export for backend data are "not built". **[CONFIRM]** |

### 5.11 Other services the app reaches

| Service | What is sent | When | Opt-in | Source |
|---|---|---|---|---|
| **Picovoice** ("Hey Doddy" wake word) | Your own Picovoice AccessKey, so Picovoice can check it and count its use. No sound: the wake word is detected on the iPhone. After the wake word, the conversation goes to ElevenLabs as in 5.1. | When "Hey Doddy" listening starts | Yes, off by default. You bring your own key. | `DataFlow` row `picovoice`, ADR-254. **[CONFIRM: what else Picovoice's SDK sends, such as device or platform data; licence terms for a public release]** |
| **Apple Maps** (MapKit) | Words you type to find a place, and roughly where you are if Doddy already knows. For "remind me when to leave": where your iPhone is and the place you name. | Only when you search for a place or ask when to leave | You do it | `DataFlow` row `placeSearch`, ADR-196, ADR-335 |
| **European Central Bank** | Nothing about you. The app downloads the public daily rates file (`eurofxref-daily.xml`). The ECB server sees your IP address as any web server does. | When you ask Doddy to convert money, at most every 6 hours | You ask | `DataFlow` row `exchangeRates`, ADR-300 |
| **Apple Siri** | What you say to Siri and the matching note Siri reads back. Doddy searches on the iPhone. Siri works under your Siri settings and can use Apple's servers. | Only when you say "Ask Doddy what I saved" with the iPhone unlocked | Settings, "Siri can read my notes aloud". The code defaults the switch to on (`DataFlowView` `@AppStorage`). **[CONFIRM: default on or off]** | `DataFlow` row `siri`, ADR-248 |
| **iCloud (Apple CloudKit)** and the people you share with | For each list you share or join: the list name and items, and every change; a reminder's place only if you tap Share this place. Silent notifications from iCloud tell Doddy a list changed. | While a list is shared | Yes: you confirm each share. **Off unless the build has an iCloud container; the default build has none and never touches CloudKit** (`project.yml`, ADR-263). | `DataFlow` row `iCloudSharing`, ADR-263, ADR-284, ADR-307. People you invite see what you share. |
| **Apple Push (APNs)** | The notification token goes to Doddy's messaging server (5.5). For shared lists the token goes only to Apple. | See 5.5 | Yes | ADR-142, ADR-284 |
| **Where you save a backup file** | Your notes, lists, photos, voice memos, time reminders and About you answers, sealed with your passphrase. | When you make a backup and choose where to save it | You do it | `DataFlow` row `backup`, ADR-222. Doddy keeps no copy of the file or the passphrase. |
| **TikTok, Instagram** | Nothing from the app. Plain links that open outside Doddy. | When you tap | You do it | ADR-130 |

### 5.12 The website and its waitlist

| Item | Detail |
|---|---|
| Hosting | Vercel (project `doddy`). Vercel keeps its own server logs. **[CONFIRM: Vercel terms, log retention, transfers]** |
| Waitlist form | You enter your email. We store the email, the page, a consent wording version (`waitlist-note-v1`), the time, and a hash of a one-time key that lets your browser add answers. No IP address or user agent is stored by our code. Emails are not written to logs. After sign-up you may answer three optional questions: iPhone, Android or other; where you heard about Doddy; what you want Doddy to do (300 characters). (`site/api/waitlist.js`, `waitlist-answers.js`, `site/README.md`.) |
| Where stored | A private Vercel Blob store `doddy-waitlist`, region fra1 (Frankfurt), one file per email named by a hash. |
| Who can read it | The owner, through a password-protected admin page and a CSV download. Both use one shared password and have no lockout (`site/README.md`). |
| Purpose | To tell you when early access opens. The form says: "We'll only use your email to tell you when early access opens, and we'll delete it whenever you ask." |
| Retention | No fixed period in the code. **[CONFIRM: delete after launch, after [N] months, or on request only]** Deletion on request is possible through the admin page. The form promises it but names no contact address. |
| Legal basis | **[CONFIRM: consent]** |
| Vercel Web Analytics | Counts page views and visitors on the landing page. No cookies. Vercel identifies a visitor by a hash of the request that it discards after 24 hours and keeps page, referrer, country, device and browser class (`site/README.md`, Vercel's documentation). It runs without asking. **[CONFIRM: lawful basis and notice in the EU]** |
| Google Analytics 4 | Loaded only after you tap Allow in the banner. It sets cookies (`_ga`, `_ga_*`). Ads storage, ad personalisation and Google signals are off. Your choice is kept in your browser's localStorage. "Analytics choices" in the footer lets you change it, and No thanks deletes the `_ga` cookies. Measurement ID `G-WQXYVSGD4Q`. (`site/analytics.js`, ADR-245.) **[CONFIRM: Google as processor or controller; GA data location and retention setting; transfers]** |
| Google Fonts | The page loads two fonts from `fonts.googleapis.com` and `fonts.gstatic.com` as soon as it opens, before any choice. That sends your IP address to Google. (`site/index.html`, `site/README.md` "Needs the owner" 4.) **[CONFIRM: self-host the fonts, or give notice and a basis]** |
| Links | Telegram group, TikTok, Instagram. They open in a new tab. We send them nothing. |
| Cookies and storage | Only GA cookies (if you allow) and one localStorage entry for your analytics choice. The site has no other cookies. |
| Blog | Pages are static (`site/blog`). No comments or forms were found. |

## 6. Permissions the app asks for

The app asks for these only. Each text below is the app's own wording (`project.yml` and `Config/Doddy-Info.plist`). Not listed means the app does not ask: no camera, no photo library, no motion, no Bluetooth, no health data, no advertising ID, no "Always" location.

| Permission | Why (the app's own words) |
|---|---|
| **Microphone** | "Doddy listens while you are talking to him: after you tap Talk to Doddy, or as soon as you open Doddy if you turned that on in Settings. If you turn on Hey Doddy, the microphone also listens on this iPhone for the wake word; that sound isn't kept or sent. Your voice in a conversation is sent to OpenAI to run it, or to ElevenLabs if you switch Home's voice to ElevenLabs. A voice memo you record on a note stays on this iPhone." |
| **Speech recognition** | "Doddy writes out a voice memo on this iPhone when you record one, so you can check its words before saving. The recording and its words are not sent anywhere." |
| **Contacts** | "Doddy looks up a contact by name, or whose birthday is coming up, when you ask, and reads birthdays for the people you pick to be reminded of. In a voice conversation, the names it finds and their birthday's day and month go to ElevenLabs, which runs Doddy's voice; numbers, email addresses and birth years stay on this iPhone. Turn this off in Settings, Connections." |
| **Calendar (full access)** | "Doddy reads your events for the days you ask about, and adds, changes or deletes an event only after you tap Add, Change or Delete. Turn this off in Settings, Connections." |
| **Reminders (full access)** | "Doddy adds, changes, completes or deletes a reminder only after you tap Add, Change, Mark done or Delete. Turn this off in Settings, Connections." |
| **Location, while using** | "Doddy uses your location only when you ask: for reminders you set at a place (to find where you are when you tap Use where I am now, and so iOS can remind you when you arrive or leave), to save where you parked, and to work out with Apple Maps when to leave for somewhere. Doddy doesn't keep it or track where you go." **This sentence is not fully accurate: "Where did I park?" keeps the saved position on the iPhone until you clear it (ADR-301). The text and this policy must be made to agree. [CONFIRM]** |
| **Face ID** | "Doddy uses Face ID to open the app or a private note when you turn the lock on. iOS checks your face; Doddy only learns whether it matched." |
| **Alarms (AlarmKit, iOS 26+)** | "Doddy sets an alarm only when you ask and tap Set alarm. Its alarms ring even in Silent mode or a Focus. Turn them off in Doddy's Settings, Alarms." |
| **Notifications** | Asked when you turn on timers, reminders, check-ins or push. No usage-description text is needed. Reminder text is hidden by default (ADR-190). |
| **Live Activities and Dynamic Island** | Shows the state of a conversation, focus timer or shopping list on the Lock Screen. Shopping mode asks you to confirm that its items will be readable on the Lock Screen (ADR-257). |
| **Background audio** | Keeps a conversation you started running after you leave the app (ADR-053). With "Hey Doddy" on, it keeps the wake-word listening running (ADR-254). |
| **Background remote notifications** | Used only for iCloud's "a shared list changed" wake-up (ADR-284). |

The Share extension and the widgets ask for nothing (ADR-311). The Apple Watch app has no permissions of its own in `project.yml`. **[CONFIRM after the first build]**

## 7. Children, AI transparency, automated decisions, sale of data

**Children.** The code has no age gate, no parental controls and no children's mode (searched `DoddyApp` and `Packages`). Doddy is not designed for children. **[CONFIRM: age rating for the App Store; the minimum age for the voice features and the open-ended AI chat; whether the policy says "13", "16" or "18"; parental consent rules]**

**AI transparency (draft statement, EU AI Act Article 50).**
- Doddy is an AI system. When you talk to Doddy, you are talking to software and not to a person.
- Doddy's voice is generated by a speech system (OpenAI Realtime by default, or ElevenLabs).
- Doddy's answers can be wrong. Check anything that matters.
- The app says "Doddy is an AI, not a person" on Home and on the Ask screen (`HomeView.swift`, `AskView.swift`). The voice prompt tells Doddy to say plainly that it is an AI when asked. The phone agent says it in its first sentence (`voice-agent/instructions.md`, `voice-agent/phone/instructions.md`, ADR-191, ADR-194).
- The voice agent's own greeting ("Hey, it's Doddy. what's up?") does not say it is an AI. The disclosure on the voice screen is by text on screen and by answer when asked. **[CONFIRM: with a specialist whether Article 50 needs more, and from what date; whether synthetic audio must be marked; ElevenLabs' and OpenAI's role as provider and ours as deployer]**
- Doddy is not meant to claim feelings of a person, to flatter, or to make you feel guilt or dependence. This is a design rule (`docs/trust/`), enforced in part by a prompt check (`voice_agent_spec.py check`), not by code in every case.

**Automated decisions.** Doddy makes no decision about you with legal or similarly significant effects. It proposes; you confirm. Anything that changes your calendar, reminders, drafts, tasks or lists by voice shows a card and needs your tap, except small list edits that you ask for by voice, which are shown in "What Doddy did" with Undo (ADR-216, ADR-258, ADR-268). Doddy has no profiling for ads or scoring. **[CONFIRM: lawyer agrees there is no Article 22 issue]**

**Sale, ads, tracking.** We do not sell personal data. The app has no ads and no tracking (`PrivacyInfo.xcprivacy`, `DEPENDENCIES_AND_LICENSES.md`). The website uses analytics as in 5.12. **[CONFIRM: no data is shared for the processors' own purposes, for example ElevenLabs or Google model training]**

## 8. Your rights, export and deletion

If GDPR or UK GDPR applies to you, you have the rights of access, rectification, erasure, restriction, portability, objection, withdrawing consent, and complaint to a supervisory authority. Write to [PRIVACY EMAIL ADDRESS]. We will answer within [ONE MONTH] **[CONFIRM]**. **[CONFIRM: identity checks; how we find an anonymous account, which has no email, when someone asks for access to server data]**

What the app lets you do today:

| You want to | What the app does | Source |
|---|---|---|
| See where data goes | Settings, Privacy, "What leaves this iPhone" | `DataFlowView.swift` |
| Export notes and lists | Export as JSON, plain text, or Markdown (share sheet). JSON can be restored. | ADR-030, ADR-203, `SettingsView.swift` |
| Export About you and settings | JSON or text | ADR-176 |
| Export remembered conversations | Plain text | ADR-177 |
| Make a full backup | Encrypted backup file (`.doddybackup`): notes, lists, photos, voice memos, time reminders, About you answers. AES-256-GCM, key from your passphrase (at least 10 characters) with PBKDF2-HMAC-SHA256, 600,000 rounds. Opened again and compared before the save sheet. Restore only adds. | ADR-222, ADR-234 |
| Delete one note, or one remembered conversation | Delete (notes: a 10-second Undo; the delete itself is immediate with secure delete on) | ADR-177, ADR-183 |
| Delete all notes and lists | "Delete all memories" (`deleteAll`): removes every note, list and item, corrections, photo and voice memo files, the search index entries, and note reminders. It stops your shared lists, tries to empty the "Memory on calls" server copy, and says plainly if either failed. It is read back before it says done. | `SettingsView.swift` `deleteAll()`, `SQLiteMemoryRepository.deleteAll`, `MemoryStore.deleteAll`, ADR-026, ADR-028 |
| Forget About you | "Forget all of this" (`forgetProfile`). It does not delete notes. | ADR-085, `SQLiteProfileRepository` |
| Forget conversations | "Forget remembered conversations" | `SettingsView.swift` |
| Clear the activity list | "Clear" in What Doddy did | `ActivityView.swift` |
| Delete the messaging server data | "Delete my Doddy messaging data": the server deletes the account and, by cascade, the devices, phone number, queued and past messages, call notes, memory copies, call records, news settings and topics. The app then switches push and Memory on calls off. Notes on the iPhone are not touched. | `UpdatesModel.deleteServerAccount`, `DELETE /v1/account`, ADR-143 |
| Turn off Memory on calls | Deletes every server copy of your notes | `server/messaging/README.md`, ADR-153 |
| Stop sharing a list | Deletes the iCloud copy for everyone. Leave takes you off someone else's list. | ADR-263 |
| Disconnect an online account | Deletes the connection record and asks Composio to revoke and delete. You can also remove access in your Google account. | `SECURITY_AND_PERMISSIONS.md` |
| Delete your waitlist email | Ask [PRIVACY EMAIL ADDRESS]. The owner deletes it in the admin page. | `site/README.md` |

What the app **cannot** delete:

- Recordings and transcripts already at ElevenLabs, and anything its model providers keep. No app function deletes them. **[CONFIRM: how a user can have them deleted; whether you can delete through the ElevenLabs API by conversation or install ID]**
- Data already at OpenAI (voice test, Ask Doddy, news writer), Anthropic, GNews, Twilio (SMS and call records, Verify), Apple (APNs, Siri, iCloud, Maps), Composio, Monid, Google, Microsoft, Notion, Todoist, Vercel and Render logs, and Picovoice. **[CONFIRM for each]**
- Backend records for online accounts. Backend account deletion and export "are not built" (`SECURITY_AND_PERMISSIONS.md`). **[CONFIRM]**
- Your own exported files, backup files and iPhone or iCloud device backups. Your device backups contain Doddy's database because it is ordinary app data (ADR-028).
- A note you put into a list someone else shares, once the other person has copied it.
- "Delete all memories" does not clear: About you, remembered conversations, the activity list, the parking spot, or settings (each has its own control). **[CONFIRM: widget snapshot, Apple Watch copy and iPhone search index refresh after Delete all; the code read for this draft does not show it]**

## 9. Retention, security, transfers, changes, contact

### 9.1 Retention

| Data | Kept | Source |
|---|---|---|
| Notes, lists, photos, voice memos, About you | Until you delete them | ADR-028 |
| Remembered conversations | Last 10; until you forget them | ADR-047 |
| Activity list | 30 days or 300 entries | ADR-135 |
| Parking spot | Until replaced or cleared | ADR-301 |
| Voice conversations at ElevenLabs | **[CONFIRM: unlimited today]** | ADR-057, `V1_VOICE_STATUS.md` |
| Phone-call transcripts at ElevenLabs | 30 days, no audio, when the agent is created | ADR-158 |
| Messaging server account, phone number, news settings | Until deleted | `001_init.sql`, `003_news.sql` |
| Queued message text | Until the message reaches a final state | `001_init.sql` |
| Memory copy | Until Memory on calls is turned off | ADR-153 |
| Call notes | Until you confirm or discard them **[CONFIRM: expiry]** | `002_calls.sql` |
| Verification-start records | 2 days (hash of number only) | `routes/phone.ts` |
| News sent records / digests / feed cache | 14 days / 30 days / 24 hours | `news/digest.ts`, `news/sources.ts` |
| Backend receipts and usage counters | **[CONFIRM: no pruning today]** | `SECURITY_AND_PERMISSIONS.md` |
| Waitlist | **[CONFIRM]** | `site/README.md` |
| Web server logs | **[CONFIRM: Vercel and Render]** | |

### 9.2 Security measures (only those the code or docs show)

- Data on the iPhone uses iOS file protection `completeUntilFirstUserAuthentication` (database, photos, voice memos, conversation and activity logs, widget file). The share inbox uses complete protection. Secrets are in the Keychain.
- An optional Face ID lock and private notes (ADR-310).
- Encrypted backup files: AES-256-GCM, PBKDF2-HMAC-SHA256 (ADR-222).
- Server tokens are 256-bit and stored only as hashes. Device and session bearer tokens are sent over HTTPS. The iPhone transport refuses redirects, pins the host and caps responses (`SECURITY_REVIEW_MESSAGING.md`). The messaging server address must be https (`ServerConfig.validated`).
- Messaging server: memory copies and call notes are encrypted at rest with AES-256-GCM, bound to account and row. Queued message text is encrypted if the key is set. Calls need a PIN stored as a scrypt hash, with escalating lockouts. Rate limits apply. Logs carry IDs and counts only. A security review was done by an automated reviewer and the fixes made (ADR-175); it is not a penetration test.
- Backend: the user comes from the session token only. Connection IDs, user IDs and tool names in request bodies are rejected. Write tools need an approval bound to the exact arguments, with a 2-minute expiry. Composio holds provider tokens, not Doddy. The log has no bodies or tokens (`SECURITY_AND_PERMISSIONS.md`).
- Gateway: no AI key on the phone; limits and a daily spend cap; logs use an allow-list with no text.
- Website: Content-Security-Policy, `X-Content-Type-Options`, strict referrer policy and a permissions policy that turns off camera, microphone and geolocation (`site/vercel.json`). Waitlist inputs are checked; admin routes use one password.
- **No security measure above is a guarantee.** Independent review, the threat model rerun and device tests are still open (`THREAT_MODEL.md`, `GO_LIVE_STATUS`). Do not say "secure" or "GDPR compliant" in the final policy without that review.

### 9.3 International transfers

Servers named in the code: Render, Frankfurt, EU; Vercel Blob, Frankfurt. The location of Vercel Functions, ElevenLabs, OpenAI, Google (Gemini), Anthropic, GNews, Twilio, Composio, Monid, Picovoice, Upstash and Google Analytics is not shown in the repository. **[CONFIRM: for each, the data location, the transfer mechanism (adequacy, standard contractual clauses, data privacy framework) and sub-processors]**

### 9.4 Changes to this policy

We will post changes at [POLICY ADDRESS] and change the date above. For material changes we will [tell you in the app] **[CONFIRM]**.

### 9.5 Contact

[PRIVACY EMAIL ADDRESS], [POSTAL ADDRESS]. Complaints can go to [SUPERVISORY AUTHORITY].

---

## Appendix A. Claim to source map

Paths are relative to the repository root. "ADR" means a row in `DECISIONS.md`.

| # | Claim in this draft | Source |
|---|---|---|
| A1 | No account is required | `Packages/DoddyCore/Sources/DoddyCore/PrivacyDefaults.swift` (`v1Voice`) |
| A2 | App has no analytics or crash SDK | `DEPENDENCIES_AND_LICENSES.md`; `project.yml` packages; `PrivacyInfo.xcprivacy` |
| A3 | Voice data list sent to ElevenLabs | `DataFlow.swift` (`rows`, row `elevenlabs`); `DoddyApp/Features/Settings/SettingsView.swift` privacy paragraph |
| A4 | Notes budget 6,000 chars, conversations 4,000 | `Packages/DoddyCore/Sources/DoddyCore/VoiceContext.swift` |
| A5 | Max 10 minutes per conversation, agent LLM Gemini | `voice-agent/session.json` (`max_duration_secs`, `elevenlabs.llm`); `docs/implementation/V1_VOICE_STATUS.md` |
| A6 | ElevenLabs recording on, unlimited retention, zero-retention off, EU residency Enterprise-only | `V1_VOICE_STATUS.md`; ADR-057 |
| A7 | Agent auth off, public development agent | ADR-034 (cited in `GO_LIVE_STATUS_2026-10-11.md`); `DoddyApp/Features/Voice/VoiceConfig.swift` |
| A8 | Private conversation is on-device only | ADR-170 |
| A9 | Translator mode data | `DataFlow.swift` row `translator`; ADR-215 |
| A10 | Token server behaviour and logs | `server/voice-token/README.md`; `docs/implementation/VOICE_TOKEN_SERVER_STATUS.md` |
| A11 | OpenAI voice (default), direct from the phone | `server/voice-token/README.md`; ADR-265; `DataFlow.swift` row `openaiVoice` |
| A12 | Ask Doddy gateway data, limits, `store:false`, not deployed | `docs/architecture/ASSISTANT_GATEWAY.md`; `gateway/README.md`; ADR-113 |
| A13 | Messaging server tables, anonymous account, phone number plain, hash-only token | `server/messaging/migrations/001_init.sql` to `007`; `server/messaging/src/routes/account.ts` |
| A14 | Built-in messaging address empty | `DoddyApp/Infrastructure/Server/ServerConfig.swift` |
| A15 | Render Frankfurt, Postgres, not deployed | `render.yaml`; ADR-139 |
| A16 | SMS consent, STOP, outbox erase | `server/messaging/README.md`; `001_init.sql` |
| A17 | Phone calls, PIN, notes, limits | `server/messaging/README.md`; `002_calls.sql`; `SECURITY_REVIEW_MESSAGING.md` |
| A18 | Phone agent: no recording, 30-day transcripts, Gemini 2.5 | `voice-agent/phone/session.json`; ADR-158 |
| A19 | Memory copy, AES-256-GCM, not end-to-end | `server/messaging/README.md`; ADR-153 |
| A20 | Daily news data to Anthropic or OpenAI and GNews | `server/messaging/README.md`; ADR-163, ADR-197; `DataFlow.swift` row `messagingServer` |
| A21 | News retention 14 / 30 days, 24 h cache | `server/messaging/src/news/digest.ts`; `news/sources.ts` |
| A22 | Backend, Composio, receipts, no retention policy | `docs/integrations/SECURITY_AND_PERMISSIONS.md`; `docs/integrations/ONLINE_ACCOUNTS.md` |
| A23 | Web search through Monid, search words not stored | `ONLINE_ACCOUNTS.md` (ADR-173) |
| A24 | Gmail compose scope can send | ADR-099 |
| A25 | Production live mode refused until sign-in | ADR-077; `SECURITY_AND_PERMISSIONS.md` |
| A26 | Picovoice AccessKey only; wake word on device | `DataFlow.swift` row `picovoice`; ADR-254 |
| A27 | Apple Maps place search and travel time | `DataFlow.swift` row `placeSearch`; ADR-196, ADR-335 |
| A28 | ECB rates file | `DataFlow.swift` row `exchangeRates`; `Packages/DoddyCore/Sources/DoddyCore/Currency.swift`; ADR-300 |
| A29 | Siri readback | `DataFlow.swift` row `siri`; ADR-248; `DataFlowView.swift` (`siriReadsNotes` default true) |
| A30 | iCloud sharing off in default build | `project.yml` (`DODDY_CLOUD_CONTAINER: ""`); ADR-263, ADR-284, ADR-307 |
| A31 | Backup file crypto | ADR-222; `docs/implementation/ENCRYPTED_BACKUP_STATUS.md` |
| A32 | Local storage and file protection | ADR-028; `ActivityLogStore.swift`; `ConversationLogStore.swift`; `PhotoFiles.swift`; `AudioFiles.swift`; `WidgetSnapshotFile.swift`; `ShareInboxFile.swift`; `SpotlightSync.swift` |
| A33 | Parking spot saved in UserDefaults | `DoddyApp/Features/Parking/ParkingStore.swift`; ADR-301 |
| A34 | Face ID lock, private notes filter | ADR-310 |
| A35 | Watch sync | ADR-232 |
| A36 | Permission texts | `project.yml` (`INFOPLIST_KEY_NS*`); `Config/Doddy-Info.plist` (`NSAlarmKitUsageDescription`) |
| A37 | No other permission keys | `project.yml`; `Config/*.plist` (searched for camera, photo library, motion, Bluetooth, tracking keys) |
| A38 | Delete all, forget profile, delete account | `SettingsView.swift`; `MemoryStore.swift`; `SQLiteMemoryRepository.swift`; `SQLiteProfileRepository.swift`; `UpdatesModel.swift`; `ServerClient.swift` |
| A39 | Export formats | ADR-030, ADR-176, ADR-177, ADR-203 |
| A40 | Website data, waitlist storage, admin | `site/api/*.js`; `site/README.md`; `site/index.html` |
| A41 | Analytics: Vercel Web Analytics and GA4 with consent | `site/analytics.js`; `site/README.md`; ADR-245 |
| A42 | Google Fonts load without consent | `site/index.html` lines 21 to 23; `site/vercel.json` CSP; `site/README.md` "Needs the owner" 4 |
| A43 | AI disclosure texts | `voice-agent/instructions.md`; `voice-agent/phone/instructions.md`; `HomeView.swift`; `AskView.swift`; ADR-191, ADR-194 |
| A44 | No age gate | Searched `DoddyApp` and `Packages` for age gate, parental terms; none found |
| A45 | Privacy manifest content | `DoddyApp/Resources/PrivacyInfo.xcprivacy`; ADR-118 |
| A46 | Legal review not done, no privacy policy yet | `docs/security/PRIVACY_GDPR_AI_ACT.md`; `GO_LIVE_STATUS_2026-10-11.md` |

## Appendix B. Open questions for the owner and the lawyer

### B1. Where the app's own statements and the code disagree, or are silent

1. **Google (Gemini) is not named.** The ElevenLabs agent runs on Gemini (`session.json`), and so does the phone agent. `DataFlow`, the Settings privacy paragraph, `DataFlowView`, the Home text and the website never name Google. The "Cloud AI" row says "ElevenLabs (voice); OpenAI if Ask Doddy is on".
2. **ElevenLabs retention is not stated.** The app says ElevenLabs "keeps a recording and transcript". The live setting is unlimited retention, recording on, zero-retention off. ADR-057 allowed it for the owner's own phone only.
3. **Whole notes go to voice in every conversation** (up to 6,000 characters). The Settings paragraph does say this. The website privacy panel says notes "leave it only for things you switch on". Starting a conversation is the switch. Make sure users see it before the first conversation.
4. **Web search (Monid) has no row in `DataFlow`.** It is in the Settings paragraph and in `ONLINE_ACCOUNTS.md`. Monid is also not in the "Network" status row, and `PrivacyInfo.xcprivacy` does not list search queries.
5. **Settings "Account required: No"** is true for using the app. The messaging server creates an anonymous account, and the phone feature stores a phone number. The website says "No account. No sign-up, no email, no password." Say "no account to use Doddy; optional features create an anonymous server account".
6. **The "Network" status row** (`SettingsView`) lists ElevenLabs, token server, Connected Apps and Ask Doddy only. It omits the messaging server, Apple Maps, ECB, Picovoice, CloudKit and OpenAI voice.
7. **Location text says "Doddy doesn't keep it"** but the parking spot is kept in UserDefaults (ADR-301).
8. **Siri note readback default.** `DataFlowView` defaults `siriReadsNotes` to true. The Settings text says "it can be turned off".
9. **"What leaves" for the voice token server** shows only "Your access code". The OpenAI token mint also goes through it.
10. **Outlook** is in the Settings paragraph and the code (`backend/src/tools/catalog.ts`) but not in `ONLINE_ACCOUNTS.md`'s tool table.
11. **Deployment status is unclear.** `render.yaml` says neither Render service is deployed. `ONLINE_ACCOUNTS.md` says web search ran on a Render service. `GO_LIVE_STATUS` says the token server is deployed. The privacy policy must describe only what runs.
12. **Backend data deletion.** `SECURITY_AND_PERMISSIONS.md` says deleting a backend account and exporting backend data is not built, while the messaging server has `DELETE /v1/account`. The two servers differ.
13. **Website promises deletion on request** but lists no contact address.
14. **Google Fonts** load before consent; the footer says so, but a notice and a basis are needed.
15. **`PrivacyInfo.xcprivacy` exists only for the main app** (`GO_LIVE_STATUS`). Widgets, share extension and watch have none.
16. **Voice greeting does not say "AI".** On-screen text and the answer when asked do.

### B2. Checklist

**Controller and structure**
- [ ] Who is the controller (legal name, address, country)? Natural person or company?
- [ ] Is an EU or UK representative needed? Is a DPO needed?
- [ ] Privacy contact address, and a deletion-request process with a deadline.
- [ ] Which supervisory authority.

**Processors and agreements (data processing agreement, sub-processors, region)**
- [ ] ElevenLabs: agreement, sub-processors (including Google Gemini), region, EU residency, retention, zero-retention mode, recording on or off, deletion by conversation or user ID, training use.
- [ ] OpenAI: voice test, Ask Doddy gateway and news writer; retention and `store:false`; region; agreement.
- [ ] Google (Gemini via ElevenLabs; Google Analytics; Google Fonts; Calendar, Gmail and Drive APIs). Google OAuth verification and the wider Gmail compose scope (ADR-099).
- [ ] Anthropic (news writer). GNews. Twilio (Verify, SMS, calls). Apple (APNs, Maps, Siri, CloudKit).
- [ ] Composio and Monid: terms, regions, sub-processors, retention, agreement.
- [ ] Render (Frankfurt), Vercel (site, Blob, Functions), Upstash: agreements, log retention, IP logging, transfers.
- [ ] Picovoice: what the SDK sends; commercial licence.

**Legal basis and consent**
- [ ] Basis per purpose: service you ask for, consent for microphone and optional items, consent for SMS and calls, consent for GA, legitimate interests for security logs.
- [ ] Special-category data: notes can contain health or other sensitive facts the user types or says. How is that handled?
- [ ] Voices of other people (translator mode, calls near the phone).
- [ ] Data protection impact assessment needed? (voice, AI, contacts, location)
- [ ] Retention periods for every row marked **[CONFIRM]** in 9.1.

**Data location**
- [ ] Where is each processor's data? Transfer mechanisms.

**AI Act**
- [ ] Article 50 duties for Doddy as deployer and for providers. Is the spoken greeting enough? Is marking of synthetic audio needed? Dates of application.
- [ ] Polish and English wording of the AI statement; native Polish review of privacy text (ADR-234).

**Children and age**
- [ ] Age rating and minimum age. App Store age questionnaire (AI chat, user-generated content, contacts).

**App Store**
- [ ] Review and answer Appendix C.
- [ ] Privacy manifests for widgets, share extension, watch and the third-party SDKs (ElevenLabs, LiveKit, Porcupine).
- [ ] Required-reason API audit (only UserDefaults CA92.1 is declared).
- [ ] Privacy policy URL and support URL in App Store Connect.
- [ ] Account deletion rule (5.1.1(v)): the app has no sign-in account, but the messaging server has an anonymous account with a delete function. Is that enough?

**Product changes the policy depends on**
- [ ] Turn on ElevenLabs agent authentication and limits; set retention before any outside tester (ADR-034, ADR-057, ADR-068).
- [ ] Real app sign-in for the backend (ADR-077).
- [ ] Waitlist: retention, contact address, rate limit, shared password.
- [ ] Self-host fonts, or notice; decide on Vercel Web Analytics notice.
- [ ] Fix the location text and the other mismatches in B1.
- [ ] Add Monid and Google (Gemini) to `DataFlow`.

## Appendix C. Draft App Store Connect "App Privacy" answers

Based on the code and `PrivacyInfo.xcprivacy`. Apple counts data that leaves the device and is collected by you or your third-party partners. Data processed only on the device is not "collected". "Linked to you" means tied to your identity (account, device or other ID). Every row is **[CONFIRM]** until the owner and a lawyer review it. The text on this page is for the review; do not copy it into App Store Connect unchecked.

**Tracking: No.** The app does not track (`NSPrivacyTracking` false, no tracking domains, no advertising ID, no ATT prompt).

| Apple data type | Collected? | Linked to user? | Used for tracking? | Purpose | What and why | Status |
|---|---|---|---|---|---|---|
| Audio data (Voice or sound recordings) | Yes | Declared "not linked" in `PrivacyInfo.xcprivacy`. A random install ID is sent as the conversation user ID. | No | App functionality | Your voice goes to ElevenLabs (or OpenAI). | **[CONFIRM: linked or not; ElevenLabs keeps it]** |
| Other user content | Yes | Declared "linked" | No | App functionality | Notes, list names and items, conversations, drafts, calendar and reminder text, email previews and other results sent to ElevenLabs, the gateway or the server. | **[CONFIRM]** |
| Name | Yes | Declared "not linked" | No | App functionality | Your first name or nickname when About you is shared with voice. | **[CONFIRM]** |
| Phone number | Yes, only if you use texts or calls | Declared "linked" | No | App functionality | Sent to the messaging server and Twilio. | **[CONFIRM]** |
| User ID | Yes | Declared "linked" | No | App functionality | Anonymous account ID and device token (messaging), session token (backend), gateway device ID. | **[CONFIRM]** |
| Device ID | Yes | Declared "not linked" | No | App functionality | Random install ID (not the advertising ID). Notification token. | **[CONFIRM: a notification token may be a device ID]** |
| Contacts | Yes, when asked in a voice conversation | Not declared. Probably linked to the voice conversation. | No | App functionality | Contact names and birthday day and month go to ElevenLabs. | **[CONFIRM: missing from the manifest]** |
| Precise or coarse location | Mostly no. Where you are is sent to Apple Maps, which is Apple. A parking spot stays on the iPhone. | Not declared | No | App functionality | Place reminders, leave-by, parking. | **[CONFIRM: does Apple Maps use count as collection by the app?]** |
| Emails or text messages | Possibly: email previews and one whole email reach ElevenLabs through your connected account. | Not declared | No | App functionality | Only when you switch the matching tool on. | **[CONFIRM: "Emails or text messages", "Other user content"]** |
| Search history | Possibly: web search words go to the backend and Monid; Ask Doddy questions go to the gateway. | Not declared | No | App functionality | | **[CONFIRM]** |
| Photos or videos | No. Photos stay on the iPhone and are chosen with the picker. | | | | | **[CONFIRM]** |
| Health, fitness, financial info, browsing history, purchases | No | | | | | |
| Usage data, diagnostics, advertising data | No for the app. The server has request logs. **[CONFIRM: whether server logs count as "diagnostics" or "performance data"]** | | | | | **[CONFIRM]** |
| Sensitive info | The app does not ask for it, but notes and voice may contain it. | | | | | **[CONFIRM]** |

Declared accessed API: UserDefaults, reason `CA92.1` (`PrivacyInfo.xcprivacy`). **[CONFIRM: other required-reason APIs, such as file timestamp or disk space, are used by the app or its SDKs]**

The website's analytics (Vercel Web Analytics, Google Analytics) are not part of the App Store label. They belong in the web privacy notice.
