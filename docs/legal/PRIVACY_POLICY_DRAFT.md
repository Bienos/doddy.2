# Doddy privacy policy: DRAFT

> **DRAFT. NOT LEGAL ADVICE. NOT REVIEWED. NOT PUBLISHED.**
>
> - This file was written from the code and the docs in this repository on 2026-10-11. It is for the owner and a lawyer to review. On 2026-10-18, sections 5.6, 5.7, 9.1 and Appendix C were updated for Doddy's phone number (units U1 to U4, ADR-750 to ADR-754), which isn't live yet.
> - It is not published, not linked from the app or the website, and not an approved notice under GDPR, the EU AI Act or App Store rules.
> - Text in [BRACKETS] is a placeholder. Text tagged **[CONFIRM: ...]** is something the code or docs do not settle.
> - Every statement is meant to match what the code does today. Where the app's own screens say something different, this is noted in Appendix B.
> - Many features here are built but never run on a device or against a live service (`docs/implementation/GO_LIVE_STATUS_2026-10-11.md`). A published policy must describe what is really running at launch, so every section needs a re-check.
> - **Updated 2026-10-23 for ADR-603** (notes and conversations kept on Doddy's server, Section 5.13). That feature is built and tested on the server and in DoddyCore, but the iPhone screens are **not compiled** and the server code is **not deployed**. Section 5.13 describes what the code does; it must not be published until the feature really runs and has been checked on a device.
> - **Updated 2026-11-12 and 13** from `main` (`6ed38890`) for what changed since: the required Doddy account (5.0), Messages on by default, with photos and files and a copy for Doddy Web (5.4), calls Doddy places for you (5.7a), Logbook (5.16), errands and shopping (5.17), files Doddy makes and Studio (5.18), Doddy looking at the screen (5.19), the camera, photos and Apple Health (5.20), trips and flights (5.21), parcels and deliveries (5.22), what Doddy Web shows (5.23), the permissions (6), account deletion (8), retention (9.1), the processors (9.3) and Appendix C. Many of these are merged but switched off on the server, not deployed, or never seen working end to end (`STATUS.md`); each section says which. Sections not named here were not re-read against the code on that date. It is still a draft for the owner and a lawyer, not legal advice.
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

1. the Doddy app for iPhone and iPad, with its widgets, Share extension ("Save to Doddy"), screen-sharing extension and notification view (the Apple Watch app is paused, ADR-572, and is not in the shipping build);
2. your Doddy account and Doddy's servers that the app can talk to (Section 5);
3. Doddy Web, the browser version of your account (Section 5.23), at [WEB APP ADDRESS] (today served by Doddy's server, `https://doddy-yaci.onrender.com`, `STATUS.md`);
4. the Doddy website at [WEBSITE ADDRESS] (today `www.doddy.lol`, `STATUS.md`) and its waitlist.

It does not cover the services you connect yourself (Google, Microsoft, Notion, Todoist, Apple, your mobile carrier), the shops and apps Doddy opens for you to finish something yourself (a food app, a shop's checkout page, a booking page), or the sites we link to (TikTok, Instagram, Telegram). They have their own policies.

## 2. What Doddy is, and the short version

Doddy is an AI character. Doddy is software, not a person. Doddy has no feelings and does not know you the way a person does. Doddy can be wrong. (Sources: `voice-agent/instructions.md` line 1, ADR-191, `HomeView.swift`.)

In short:

- **Everyone signs in with a Doddy account,** with Apple or Google (email codes are built but hidden for now). The account holds your email address and how you sign in, and every Doddy server knows you by it (Section 5.0; decisions `2026-11-08-required-account`, `2026-11-09-email-sign-in-off-for-now`). `PrivacyDefaults.v1Voice` still says `accountRequired: false`; that line is out of date. Texts and calls also ask for your phone number (Sections 5.6, 5.7).
- **Your notes, lists, About you answers, photos and voice memos are stored on your iPhone.** They leave it only through features you switch on, listed in Section 5.
- **Doddy's server keeps your notes and conversations only if you switch that on** (Settings, Doddy on the web, Keep on Doddy's server). Then it keeps them as text, never audio, for 1 year, and you can read, search, download and delete them on the web or ask Doddy about them there (Section 5.13). Off by default.
- **Messages is on by default** (decision `2026-11-09-messages-on-by-default`). What you type, and a photo or file you attach to one question, go to Doddy's messaging server and Anthropic when you tap Send; the photo or file is kept by neither. A text copy of the conversation is kept on Doddy's server so Doddy Web can show it (Section 5.4).
- **A voice conversation sends a lot.** When you talk to Doddy, your voice, the conversation and your saved notes (except notes you mark Private) go to ElevenLabs. ElevenLabs keeps a recording and a transcript. **[CONFIRM: how long, see 5.1]**
- **Logbook counts how you use Doddy, and is on unless you turn it off** (decision `2026-11-09-usage-counts-on-by-default`). Counts only, never words. You see them on Doddy Web; Doddy's team sees every account's counts with the account (Section 5.16).
- **There are no ads, no sale of data and no tracking in the app,** and no third-party analytics or crash-reporting code. Logbook is the app's own analytics. (Sources: `PrivacyInfo.xcprivacy` `NSPrivacyTracking` false, `DEPENDENCIES_AND_LICENSES.md`.) The website uses analytics too (Section 5.12).
- **You can see where your data goes** in the app: Settings, Privacy, "What leaves this iPhone". It changes with your switches.
- **You can export and delete** most of what is on your iPhone, and delete your Doddy account with what Doddy's servers keep for it (Section 8). Some data already held by a service (ElevenLabs' recordings of app conversations, and others) is not deleted by the app.
- **Doddy makes no automated decisions** about you with legal or similar effects (Section 7).
- **This is an early test build.** (`site/index.html` privacy note.)

## 3. Data that stays on the iPhone

The app has no third-party analytics, no crash reporter and no advertising code (`DEPENDENCIES_AND_LICENSES.md`); its own usage counts are Logbook (Section 5.16). The following is kept on your iPhone. It is sent off the phone only as described in Section 5.

| Data | Where it is kept | Notes and source |
|---|---|---|
| Notes (text, original text, source, dates, type, corrections history) | SQLite database in Application Support, iOS Data Protection `completeUntilFirstUserAuthentication`, `secure_delete` on | ADR-028, ADR-252. Included in your iPhone backups (iCloud or computer) because it is ordinary app data. |
| Lists and list items | Same database | ADR-216 |
| Photos added to notes | `NotePhotos` folder next to the database, JPEG, same protection class | ADR-218, ADR-569. Chosen with Apple's photo picker, or taken with the camera when you tap Take a photo or Open camera. Text in the photo is read on the iPhone with Apple's Vision. A photo you send with a question in Messages is not kept here (Section 5.4). |
| Messages (the conversation with Doddy) | Same database | ADR-585. Your messages and Doddy's answers, until you delete them. A photo you sent is not kept, only that the message had one (`v20_thread_photo`); a file Doddy made is kept as its name and link. A text copy is on Doddy's server for Doddy Web (Section 5.4). |
| Logbook's counts waiting to be sent | UserDefaults | Decision `2026-11-09-usage-counts-on-by-default`. Each finished conversation's start, length, way in, ending and language (never words), for the 8 days that can still be sent, at most 500. Emptied when you turn Logbook off. |
| Voice memos | `NoteAudio` folder, same protection class | ADR-230. Words are written out on the iPhone (on-device speech recognition is required). If the iPhone cannot do that for your language, nothing is written out and nothing is sent. |
| About you answers (name, preferences) | Same database, separate table | ADR-085. Saved only after you review them. |
| Personal settings, switches, pinned note IDs, private note IDs, parking spot | UserDefaults (app preferences) | ADR-019, ADR-043, ADR-187, ADR-301, ADR-310. The parking spot holds a position and your note (see Section 6, Location). |
| Remembered conversations (the last 10, as text) | JSON file, same protection class | ADR-047. Optional switch "Remember recent conversations". Off for a conversation you mark Private (ADR-170). |
| "What Doddy did" activity list (30 days, up to 300 entries) | JSON file, same protection class | ADR-135, ADR-169. Online-account entries keep the tool name only. |
| Private notes (Face ID) | The note stays in the database. Its ID is on a "private" list. | ADR-310. Private notes are held back from voice, Siri, Ask Doddy, widgets, the watch and the call copy. They are not encrypted separately in the app. |
| Widget snapshot (up to 4 pinned notes, 3 next reminders, 8 lists with 12 items each, parking time and note) | File in the App Group, `completeUntilFirstUserAuthentication` | ADR-219, ADR-315. Reminder text is hidden by default. Note text is marked privacy sensitive for the Lock Screen. |
| Apple Watch sync | Paused: the watch app is not in the shipping build (ADR-572). When it was, the iPhone sent the same snapshot to the watch by WatchConnectivity; the watch app has no database or networking. | ADR-232, ADR-572 |
| The shared screen picture | One JPEG of the screen in the App Group, replaced about once a second, only while you share the screen with Doddy; deleted when sharing pauses or ends | Decision `2026-11-09-doddy-looks-at-the-screen`. Sent only as in Section 5.19. |
| Share extension inbox ("Save to Doddy") | `share-inbox.json` in the App Group, complete file protection, removed when read | ADR-311 |
| iPhone search index (CoreSpotlight) | Doddy's own index domain | ADR-330. Off by default. Private notes are never indexed. |
| Access codes and tokens (voice token server code, Doddy server token, Ask Doddy token) | iOS Keychain | The server token is `AfterFirstUnlockThisDeviceOnly` (ADR-149). **[CONFIRM: accessibility class of each other secret]** |
| Exchange-rate file (last good copy) | On the iPhone | ADR-300 |
| Exported files and encrypted backup files | Wherever you save them | Section 8 |

Face ID: iOS checks your face. Doddy learns only whether it matched. (`NSFaceIDUsageDescription`.)

## 4. What Doddy does not do

Stated only where the code or docs show it:

- No advertising, no data sale, no cross-app tracking in the app (`PrivacyInfo.xcprivacy`: `NSPrivacyTracking` false, no tracking domains).
- No third-party analytics or crash-reporting SDK in the app (`DEPENDENCIES_AND_LICENSES.md`). The app's own usage counts, Logbook, are on by default (Section 5.16). On `main` the Settings row still reads "Analytics and telemetry: Off (not built)"; it must follow Logbook's switch before release (Appendix B). **[CONFIRM: the final build is checked for third-party SDK privacy manifests, see Appendix B]**
- No location tracking. Location is read once when you ask (Section 6). Place reminders are watched by iOS, not by Doddy (ADR-196).
- "Always" location and background location are not used (ADR-196, enforced by the guard script).

## 5. Data that leaves the iPhone

One subsection per destination. "Opt-in" means off until you turn it on. Where the default build cannot reach a service because no address is set, that is said.

Common points:

- The app's own list of destinations is `DataFlow.rows` (`Packages/DoddyCore/Sources/DoddyCore/DataFlow.swift`). This section starts from it and adds what the code and docs show beyond it. Differences are listed in Appendix B.
- "Pause all connections" (Settings) switches off Doddy's use of calendar, reminders, contacts and online accounts in conversations (`DataFlow`, `pauseAll`).

### 5.0 Your Doddy account (Supabase)

Status: required in the app since decision `2026-11-08-required-account`; Google sign-in fails until an owner setting is fixed (`STATUS.md`, owner queue 25).

| Item | Detail |
|---|---|
| Who | Supabase Auth (project `doddy-gateway`), which runs Doddy's sign-in. The app talks to it directly with the project's public key (`DoddyAccount.swift`). Apple (Sign in with Apple) and Google (Google sign-in) prove who you are to it. **[CONFIRM: Supabase entity, region of the project, processor agreement; Google's and Apple's roles]** |
| What is sent | With Apple or Google: their proof of who you are, which gives the account your email address (with Apple, possibly a private relay address that Apple forwards) and whatever else they include, such as the name on a Google account. With an email code (built, hidden for now): the email address you type. Then the account's session, which the iPhone renews about every hour. |
| What is kept | The account's id, email address, sign-in method and dates, at Supabase. Every Doddy server (5.2, 5.4 to 5.10, 5.13, 5.16 to 5.23) knows you by that id. Doddy's team can see each account's email address, sign-in method and dates on an owner-only page (`/admin`, `backend/src/web/owner.ts`, decision `2026-11-09-usage-counts-on-by-default`). |
| Linking earlier data | An iPhone used before the account can bring its data on Doddy's servers into the account only with a code it asks for, with a 24-hour undo (#383, `DoddyAccount.swift`). |
| Deletion | Settings › About › Your Doddy account › Delete (Section 8). The backend deletes the sign-in at Supabase with the account, and retries until it is gone (#384, ADR-818). |
| Legal basis | **[CONFIRM: proposed: performance of the service; the account is required to use Doddy]** |

### 5.1 ElevenLabs: voice conversations

| Item | Detail |
|---|---|
| Who | ElevenLabs (runs the voice agent: speech to text, the language model, text to speech). **[CONFIRM: ElevenLabs legal entity, location and processor terms]** |
| What is sent | Your voice. The conversation. Your saved notes, newest first, up to 6,000 characters (never notes marked Private). List names (a list's items only when Doddy reads or changes a list). Your personality settings. If on: your last few conversations (up to 4,000 characters) and your About you answers. Your nickname or first name appears in the profile when About you is shared. A random install ID is sent as the conversation user ID. In a morning check-in conversation: today's Doddy reminders and lists with things left. |
| Also sent when you use the matching switch | Calendar entries, reminders, contact names with birthday day and month (never the year or an age), message drafts, results from your online accounts (for example email previews, file names, Notion page titles, Todoist tasks, and one whole email or page if "Read an email" or "Read a Notion page" is on). When you ask: one day's steps, distance and floors (Motion & Fitness); how many photos and videos you took and when (never the pictures); the week's Apple Health summary, only after its own consent and your yes in that conversation (Section 5.20); the name of a light, outlet, fan or scene and whether it worked (HomeKit); what Doddy's server found for a search, task, file or call. |
| When | Only while a conversation is open (maximum 10 minutes per conversation, `voice-agent/session.json`). The microphone is used only while you talk, or from app open if you turned that on. |
| Opt-in? | Starting a conversation is your action. Using the voice feature sends the data above. The extra items depend on your switches (Settings, Connections). |
| Language model behind the agent | The live agent uses OpenAI's `gpt-6-luna`, with backup models, as read on the live agent between 24 Oct and 10 Nov 2026 (`voice-agent/README.md`, `voice-agent/session.json`). So your conversation is also processed by OpenAI (or the backup model's provider) through ElevenLabs. The Apple Health consent names "ElevenLabs, with an OpenAI model"; the other screens name ElevenLabs only. **[CONFIRM: which model runs at launch; ElevenLabs' sub-processors; OpenAI's (and any backup provider's) terms for this route, and whether they keep or train on it]** |
| Weather and facts | ElevenLabs makes the request for Doddy. The place name and coordinates go to Open-Meteo. Search words go to Wikipedia. The app makes no such request itself. (`DataFlow` row `lookups`.) |
| Recording and transcript | ElevenLabs keeps a recording and a transcript of each conversation (`DataFlow` note). The dev agent setting is: audio recording on, retention unlimited, no auto-delete, zero-retention off (`V1_VOICE_STATUS.md`, ADR-057). The transcript can include your first name. ADR-057 says this was accepted only for the owner's own phone and "revisit before any other user". **[CONFIRM: retention period for launch; whether recording is turned off; zero-retention mode (the status doc says it and EU residency are Enterprise-only); deletion of existing recordings; ElevenLabs data location]** |
| Who can start a conversation | Only a signed-in Doddy account: the app asks the token server (5.2) for a one-conversation token. Agent authentication is on, with a daily limit (`STATUS.md` "Live services", owner queue 4). **[CONFIRM: authentication and limits as set at launch]** |
| Private conversation | The Private switch on the Talk screen means nothing of the conversation is kept on the iPhone. ElevenLabs still runs it and keeps its own recording (ADR-170). |
| Translator mode | The other person's voice and everything said while translating also go to ElevenLabs. Opened from Translate on Home, your notes, conversations and profile are not sent. Started inside a conversation, what Doddy already had stays there, and Doddy is told never to repeat it. Nothing is kept on the iPhone unless you tap Copy or Save within 5 minutes of the end. (`DataFlow` row `translator`, ADR-215.) The other person has not agreed to anything. **[CONFIRM: what you tell people you record, and the lawful basis for their voices]** |
| Phone-call agent | Separate agent for phone calls, see 5.7. |
| Transfers | ElevenLabs and its sub-processors may be outside the EU or UK. **[CONFIRM: transfer mechanism]** |
| Legal basis | **[CONFIRM: proposed: performance of the service you asked for, and your consent for the microphone and the optional items]** |

### 5.2 Doddy voice token server

| Item | Detail |
|---|---|
| Who | Doddy's own small server (`server/voice-token`) on Vercel Functions: project `doddy-voice-token`, team `doddyyyy`, address `doddy-voice-token-beta.vercel.app` (ADR-521). It keeps its records in Upstash Redis. **[CONFIRM: Vercel and Upstash regions, and the processor agreements with both]** |
| What is sent | **Each conversation:** your Doddy account's access token (Section 5.0), which the server checks (`server/voice-token/src/doddy-account.js`), and the provider, ElevenLabs (the only voice; other values are refused, decision `2026-11-09-elevenlabs-only-voice`). **Older voice accounts:** Apple's identity token from Sign in with Apple, a one-time number (nonce) that ties it to this request, and Apple's one-time authorization code (used only so the link can be revoked later; ADR-524). No audio, transcripts, notes or profile. (ADR-522, `server/voice-token/README.md`.) |
| What it does | Checks the Apple token with Apple's published keys. If Doddy's Sign in with Apple key is set up, it also swaps the authorization code with Apple for a token that lets it end the Sign in with Apple link when you delete your voice account. Then it swaps your session for a one-conversation ElevenLabs token, so the provider API key stays on the server. It limits each account to 30 conversations an hour by default. |
| What it keeps | A keyed pseudonym of your Apple account ID (not the ID itself), your session records, hashes of your refresh tokens (not the tokens), and short-lived counters for one-time numbers and rate limits. If Doddy's Sign in with Apple key is set up, also Apple's refresh token for you, encrypted, kept only to revoke the link and deleted with your account. Refresh tokens last 30 days and rotate on use; access tokens last 10 minutes and stay on the iPhone. **[CONFIRM: whether Apple's identity token carries your email and whether the server reads it; the code keeps only the subject]** |
| Logged | One line per request: action or provider, outcome, status and duration. No content, credentials, Apple account ID or user identifier (`server/voice-token/README.md`). The hosting platform may keep its own request logs. **[CONFIRM: Vercel log retention and IP logging]** |
| Opt-in? | Required for voice; nothing else in the app needs it. Settings, Voice has Sign out of voice and Delete voice account. Deleting removes your sessions on the server. Once Doddy's Sign in with Apple key is set up, it first asks Apple to revoke the Sign in with Apple link (ADR-524); the account is deleted even if Apple doesn't answer. Until then, and for accounts made before it, the app tells you to remove it in your Apple ID settings (go-live checklist C8). **[CONFIRM: the key is set and a revoke was seen to work, before this sentence is published]** |
| Legal basis | **[CONFIRM: proposed: performance of the service you asked for]** |

### 5.3 OpenAI as a voice: removed on 9 Nov 2026

OpenAI Realtime, and the voice picker that chose it, were removed from the app and the token server (decision `2026-11-09-elevenlabs-only-voice`). Nothing goes to OpenAI for voice. OpenAI still appears as the language model behind the ElevenLabs agent (section 5.1, checked 24 Oct 2026), for Ask Doddy's fallback and for the news writer (5.x below). Conversations kept on a phone from before this date may be marked as run by OpenAI; they stay on the phone.

### 5.4 Messages (typed questions, photos and files): Doddy's messaging server and Anthropic

| Item | Detail |
|---|---|
| Who | Doddy's messaging server (`server/messaging`, Render service `doddy-messaging`, region Frankfurt, `render.yaml`), which passes the question to Anthropic's Messages API (Claude) with Doddy's key (`POST /v1/assistant/ask`, ADR-587). **[CONFIRM: Anthropic entity, terms, region; Render's processor terms]** |
| What is sent | Your typed question and the last few messages of the conversation. If "Use relevant saved notes" is on (it is by default): the notes that match your question (never Private notes), under short aliases. **A photo** you attach (Choose a photo, or Home's + › Take a photo): made smaller on the iPhone (at most 1,600 px, JPEG) and drawn again, so its location and camera details are not sent; it goes with that one question only (`docs/implementation/MESSAGES_PHOTOS.md`). **A file** you attach (a PDF or a text file, ADR-732): with that one question only. Every request carries your account's session. |
| When | Only when you tap Send. |
| Opt-in? | **On by default** since decision `2026-11-09-messages-on-by-default`: nothing is sent until you send a message; Settings › Ask Doddy › "Turn on Ask Doddy" turns it off, and turning it on again shows the disclosure. **[CONFIRM: an opt-out model is acceptable for this; the legal basis]** |
| Limits | 100 questions an account and 1,000 for the server a UTC day by default (`ASSISTANT_DAILY_PER_ACCOUNT`, `ASSISTANT_DAILY_PER_SERVER` in `server/messaging/src/config.ts`); a smaller shared pool for accounts under a day old (`server/messaging/README.md`). |
| Retention at Doddy | The messaging server does not store the question, notes, photo, file or answer, and its logs keep counts and whether a photo was attached, never words (`MESSAGES_PHOTOS.md`). The conversation is kept in Messages on the iPhone until you delete it (Section 3). |
| Copy for Doddy Web | After every change, the iPhone sends the text of the newest 200 messages (yours and Doddy's) to Doddy's server (`backend/`, Render service `doddy`), which keeps them encrypted at rest and readable by the server so Doddy Web can show them (`ThreadSync.swift`, `backend/src/messages/`). A photo is never sent there, only that a message had one; a file is its name and kind, never the file or its link. There is no switch for this copy. "Delete conversation" in Messages deletes it and says so only when the server confirms; a copy the iPhone stops sending is deleted after 365 days. **[CONFIRM: the copy needs its own notice or consent; it now holds an Apple Health summary you send in Messages, Section 5.20]** |
| Retention at Anthropic | Not verified. **[CONFIRM: Anthropic retention terms for the API key's organisation; host log retention]** |
| Also through this route | Doddy looking at your screen (5.19) and recaps (5.14) use the same server, key and daily caps. |

### 5.5 Doddy messaging server: anonymous account and notifications

| Item | Detail |
|---|---|
| Who | Doddy's own server (`server/messaging`): a web service with the worker inside it and a Postgres database on Render, region Frankfurt (`render.yaml`, ADR-139). It is deployed (`doddy-messaging`, `STATUS.md` "Live services") and the app has its address built in. **[CONFIRM: what is deployed at launch; Render's processor terms]** |
| What is created | An account on this server tied to your Doddy account, made when the iPhone signs in there (`POST /v1/accounts/sign-in`). Anonymous accounts are made only with `ANONYMOUS_ACCOUNTS=1`; the default is off (#375; the live service runs an older version until it is deployed, `STATUS.md`). A device token, stored only as a SHA-256 hash. The date the account was made and last used. |
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
| **Texts you approve (U2, ADR-752)** | When you ask Doddy in a conversation to text you, a card shows the exact text; only after you tap Send does the text go to the server and then to Twilio, to your own verified number only. It is stored encrypted and erased once Twilio reports a final status. While an outcome is unclear, the server keeps a SHA-256 hash of the text to find it in Twilio's message list, then erases it. 20 approved texts a day per account. |
| **Texts you send to Doddy's number (U3, ADR-753)** | Off by default ("Accept texts from my number", consent wording `texts-in-v1`). A text from your verified number travels carrier → Twilio → the server. It waits as an encrypted note (`call_notes`, source `text`) until you save or discard it in the app; at most 20 notes wait. Texts from any other number are dropped without a reply: only Twilio's message id is kept, to delete Twilio's record. No model reads it and nothing is sent back by this switch. The server keeps a row per text from you (Twilio's id, state, time) with no text in it. |
| **Answers by text** | Not part of this feature. An answer by text is "Text with Doddy" (ADR-656, its own switch and consent wording; **[CONFIRM: this draft does not describe it yet. It sends your question to Anthropic, as Messages does, and its answer by text over the phone network. Someone must add it.]**). It sends nothing from your notes or memories. When "Texts to Doddy" is on for your number, your text becomes a note and gets no answer; when it is off, Text with Doddy decides. One handler per text, never both. |
| **Records at Twilio** | Doddy deletes its message and call records at Twilio `TWILIO_RECORD_DELETE_AFTER_HOURS` after they are final (default 24 hours), strangers' texts included. Twilio says deleted message bodies can stay in its backups for up to 30 days. The server keeps the Twilio ids of deleted records for 30 days. **[CONFIRM: Twilio's own retention]** |

### 5.7 Doddy messaging server: phone calls with Doddy

| Item | Detail |
|---|---|
| What | Doddy can answer calls from your verified number, and can call you ("call me now"). Calls reach the messaging server first (U1, ADR-750), which lets only your verified number through to an ElevenLabs phone agent; other callers hear one fixed sentence. You set a 6 to 8 digit PIN, stored only as a scrypt hash. Rows record each call: direction, status, conversation ID, call ID, time. |
| Recording and transcript | The phone agent is set up with no audio recording and transcripts kept 30 days at ElevenLabs (`voice-agent/phone/session.json`, ADR-158). The setup script has not been run: on 2026-10-18 there was no phone agent in ElevenLabs (`voice-agent/README.md`). The agent is configured to use Google's `gemini-2.5-flash` model. Doddy deletes its call records at Twilio a day after each call by default (5.6, "Records at Twilio"). **[CONFIRM: all of this; Twilio call-record retention]** |
| Notes from calls | Notes Doddy takes on a call wait on the server, encrypted, until you confirm or discard them in the app. At most 20 wait. They have no expiry in the code reviewed for this draft. **[CONFIRM: add an expiry?]** |
| **Calls you book for later (U4, ADR-754)** | You ask Doddy to call you at a time "about" something. A card shows the time, the exact sentence Doddy will say and a quiet-hours switch; nothing is booked until you tap Book. The server stores the time, the reason (encrypted, at most 200 characters) and your iPhone's time zone (to check quiet hours, 21:00 to 08:00, where you are). At the time, Twilio places the call and Doddy says the reason to whoever answers, voicemail included (the card says so). The reason is erased when the call ends or won't happen; the row (time, state) stays. The time zone stays in your call settings. |
| Limits | Outbound calls: 3 per hour, 10 per day; at most 10 booked calls waiting, from 1 minute to 7 days ahead. |
| Opt-in? | Yes: calls are off until turned on; outbound calls need separate consent (`calls-v1`). Turning "Doddy may call me" off cancels booked calls and erases their reasons. |
| Export | Settings → Phone calls → "Export phone and text history" gives a JSON file of your calls, text statuses and waiting notes (`GET /v1/phone/history`). |

### 5.7a Calls Doddy places for you (to a business or a person)

Status: built; the server switch is on in code by default (`TASK_CALLS_KILL_SWITCH=0`) but calls need the server's calling line set up and your verified number; `call_places` (calling places found in a conversation) is not on the live voice agent yet; **no real call has been seen end to end** (`STATUS.md`). Sources: `server/messaging/src/taskCalls/`, `server/messaging/README.md` "What is kept", `DataFlow` row `callCases`, ADR-500 to 507, decision `2026-11-12-book-agent`.

| Item | Detail |
|---|---|
| What you set up | A card (Settings › Phone calls › Calls for you, or in a conversation, up to three places Doddy found): the name and Polish phone number of whom Doddy calls (typed, or one number picked with Apple's contact picker), who the call is for (your first name from About you), the goal, the one question, and only the facts you tick (a PESEL or an address only if you tick it as that kind). Nothing is dialled until you approve the card. |
| Who | Twilio places the call from Doddy's calling number (on a Twilio account of its own where one is set up) with **recording off** (`record: false`). Twilio transcribes both sides live, using its Google engine (`twiml.ts`). ElevenLabs speaks as Doddy (a separate task agent with no recording, `agentSafety.ts`) and so hears the other person. Anthropic (Claude) reads the transcript, with your goal and question, to write the answer card. A booking call uses a separate booking agent that may accept only the booking on the card. |
| What the other person hears | The opening line is fixed: Doddy says he is an AI assistant calling on your behalf, then asks the question (`opening.ts`). A spoken recording notice is off by default (`CALL_RECORDING_NOTICE=off`). **[CONFIRM: whether the other person must be told the call is transcribed and read by an AI; the lawful basis for their voice and words; Polish rules on recording and transcribing calls]** |
| When | Between 8:00 and 23:00 Warsaw time, at most 5 minutes a call. For several places, one at a time after your one tap, stopping at the first clear yes. If the card says so, the answer is texted to your own verified number. "Take over" rings your own number. |
| Limits | 3 calls an hour and 10 a day per account, 2 a day to the same number per account, 3 a day to one number in all, 50 a day for the server (`config.ts`); an operator do-not-call list. |
| Kept | The brief until the case is done; the live transcript lines, encrypted, until the answer card is built (24 hours at most); the answer card (with the quoted transcript), encrypted, until the app saves it (7 days at most); each with a receipt. The task agent's conversation at ElevenLabs is deleted once the answer card is built and checked gone. Twilio's call records are deleted 24 hours after the call by default. A dial log of keyed hashes for the limits, 2 days. On the iPhone the answer is kept with the case until you delete it. |
| Opt-in? | Yes: each call is your own tap on its card. |
| Legal basis | **[CONFIRM: for you, performance of the service you asked for; for the person called, legitimate interests or another basis, and how they can object or ask for deletion]** |

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
| What the app sends | A session token. What you ask for, only after you say yes (ASK-01, ADR-483): a date, a search word, or the text of a draft, email, reply or task you tap to confirm. An email you send, reply to or forward goes on through Gmail to its recipients (ADR-485). Never your saved notes. (`SECURITY_AND_PERMISSIONS.md`, `DataFlow` row `doddyServer`.) |
| What comes back | Results (calendar entries, email previews, file names, page titles, tasks, web results). They go to the app and, during a conversation, to ElevenLabs so Doddy can speak them. |
| Stored by the backend | A map from your Doddy user to a random Composio user ID. Connection metadata (provider, status, granted scopes, a masked account label). Short-lived attempt records. Receipts (tool, time, status, counts; no titles, subjects, search words or text). Usage counters, never pruned. **A ledger of each Claude call the backend makes for you** (time, the feature that asked, the model, token counts including cache counts, the cost worked out from a price list, and whether it worked; never a prompt, material or answer), kept 400 days (decision `2026-11-14-backend-usage-ledger`). (`SECURITY_AND_PERMISSIONS.md` "Data boundaries", `ONLINE_ACCOUNTS.md`.) The backend stores no event titles, email text or notes. |
| Stored by Composio and the providers | Composio holds the sign-in tokens and its own run logs. Google and the others hold your data. Doddy never sees your Google password or tokens. **[CONFIRM: per Composio's policy]** |
| Access scope | Gmail: read, compose, send and modify (labels, archive, read/unread, Trash), ADR-485. Sending, forwarding, label changes and Trash each run only after a tap on a card with the exact email; Doddy never deletes email for good, and full Gmail access (`https://mail.google.com/`) is refused as too broad. Before 2026-10-18: drafting only (ADR-099). Google Calendar (ADR-486): `calendar.events` (events only). Outlook (ADR-486/487): Mail.Read, Mail.ReadWrite, Mail.Send, Calendars.Read, Calendars.ReadWrite; an event change or deletion notifies its guests, and the card says so. Gmail read, Drive (metadata) and Calendar are read-only scopes. Outlook scopes: **[CONFIRM: see `backend/src/tools/catalog.ts`]**. **[CONFIRM: owner accepts the wider Gmail scope or drops drafting]** |
| Opt-in? | Yes. Every account and every tool is off until you connect and switch it on. Anything that adds or creates asks you first. You can disconnect: this deletes the connection record and asks Composio to revoke and delete. If that fails the screen says so. |
| Identity | Your Doddy account (Section 5.0), since decision `2026-11-08-required-account`; before it, the iPhone's own device session. **[CONFIRM: ADR-077's live-mode gate as deployed; `STATUS.md` says the live `doddy` service runs with `env: development`]** |
| Retention | The backend's database is Postgres (Supabase, `STATUS.md`). Receipts and usage counters have no time limit in the code; the Claude-call ledger is pruned after 400 days; deleting your Doddy account erases every table that holds your rows (`ERASED_TABLES` in `backend/src/store.ts`, ADR-674) and disconnects the online accounts at Composio. Export of backend data, apart from kept notes and conversations, is not built. **[CONFIRM: a retention period for receipts and usage counters]** |

### 5.11 Other services the app reaches

| Service | What is sent | When | Opt-in | Source |
|---|---|---|---|---|
| **Apple Maps** (MapKit) | Words you type to find a place, and roughly where you are if Doddy already knows. For "remind me when to leave": where your iPhone is and the place you name. | Only when you search for a place or ask when to leave | You do it | `DataFlow` row `placeSearch`, ADR-196, ADR-335 |
| **European Central Bank** | Nothing about you. The app downloads the public daily rates file (`eurofxref-daily.xml`). The ECB server sees your IP address as any web server does. | When you ask Doddy to convert money, at most every 6 hours | You ask | `DataFlow` row `exchangeRates`, ADR-300 |
| **Apple Siri** | What you say to Siri and the matching note Siri reads back. Doddy searches on the iPhone. Siri works under your Siri settings and can use Apple's servers. | Only when you say "Ask Doddy what I saved" with the iPhone unlocked | Settings, "Siri can read my notes aloud". The code defaults the switch to on (`DataFlowView` `@AppStorage`). **[CONFIRM: default on or off]** | `DataFlow` row `siri`, ADR-248 |
| **iCloud (Apple CloudKit)** and the people you share with | For each list you share or join: the list name and items, and every change; a reminder's place only if you tap Share this place. Silent notifications from iCloud tell Doddy a list changed. | While a list is shared | Yes: you confirm each share. **Off unless the build has an iCloud container; the default build has none and never touches CloudKit** (`project.yml`, ADR-263). | `DataFlow` row `iCloudSharing`, ADR-263, ADR-284, ADR-307. People you invite see what you share. |
| **Apple Push (APNs)** | The notification token goes to Doddy's messaging server (5.5). For shared lists the token goes only to Apple. | See 5.5 | Yes | ADR-142, ADR-284 |
| **Where you save a backup file** | Your notes, lists, photos, voice memos, time reminders and About you answers, sealed with your passphrase. | When you make a backup and choose where to save it | You do it | `DataFlow` row `backup`, ADR-222. Doddy keeps no copy of the file or the passphrase. |
| **Open Food Facts** | Only the barcode number of a product you scan on a list. The photo stays on the iPhone and isn't kept. | When you scan a barcode, at most 10 a minute | You do it | `DataFlow` row `openFoodFacts`, ADR-631 |
| **InPost** | Only a parcel number you add or refresh; InPost sees the iPhone's internet address | When you add a parcel or tap Refresh | You do it | `DataFlow` row `inPost`, ADR-641; Section 5.22 |
| **Ministry of Finance VAT register; CEIDG through the messaging server** | Only a buyer's NIP you say for an invoice | When you dictate an invoice | You do it | `DataFlow` rows `vatRegister`, `ceidg`, ADR-685 |
| **inFakt** | An invoice you confirm, with your own inFakt key, from the iPhone. **Not switched on in this build** (`InFaktAPI.createVerified`) | Only on Confirm | You do it | `DataFlow` row `inFakt`, ADR-640 |
| **Shopify's Shop service** | See Section 5.17 | | | |
| **TikTok, Instagram** | Nothing from the app. Plain links that open outside Doddy. | When you tap | You do it | ADR-130 |

### 5.12 The website and its waitlist

| Item | Detail |
|---|---|
| Hosting | Vercel (project `doddy`). Vercel keeps its own server logs. **[CONFIRM: Vercel terms, log retention, transfers]** |
| Waitlist form | You enter your email. We store the email, the page, a consent wording version (`waitlist-note-v1` on the English page; on the other language pages a version for that language, for example `waitlist-note-v1-de` for German; see `site/README.md`), the time, and a hash of a one-time key that lets your browser add answers. No IP address or user agent is stored by our code. Emails are not written to logs. After sign-up you may answer three optional questions: iPhone, Android or other; where you heard about Doddy; what you want Doddy to do (300 characters). (`site/api/waitlist.js`, `waitlist-answers.js`, `site/README.md`.) |
| Where stored | A private Vercel Blob store `doddy-waitlist`, region fra1 (Frankfurt), one file per email named by a hash. |
| Who can read it | The owner, through a password-protected admin page and a CSV download. Both use one shared password and have no lockout (`site/README.md`). |
| Purpose | To tell you when early access opens. The form says: "We'll only use your email to tell you when early access opens, and we'll delete it whenever you ask." |
| Retention | No fixed period in the code. **[CONFIRM: delete after launch, after [N] months, or on request only]** Deletion on request is possible through the admin page. The form promises it but names no contact address. |
| Legal basis | **[CONFIRM: consent]** |
| Vercel Web Analytics | Counts page views and visitors on the landing page. No cookies. Vercel identifies a visitor by a hash of the request that it discards after 24 hours and keeps page, referrer, country, device and browser class (`site/README.md`, Vercel's documentation). It runs without asking. **[CONFIRM: lawful basis and notice in the EU]** |
| Google Analytics 4 | Loaded only after the visitor taps Allow in the site's banner; No thanks, or no choice yet, loads nothing from Google and removes any `_ga` cookies left from an earlier visit. The choice is kept in the browser's localStorage (`doddy-analytics-consent`), and "Analytics choices" in every footer changes it. Once allowed, it sets cookies (`_ga`, `_ga_*`); the site turns Google signals and ad personalisation off and sends ad consent as denied. Measurement ID `G-MRF40685L1` (property "doddy"). (`site/analytics.js`, decision `2026-11-12-site-analytics-after-consent`, which replaces ADR-245 as amended on 15 October.) **[CONFIRM: Google as processor or controller; GA data location and retention setting; transfers; that the banner's wording is enough for consent from EU visitors]** |
| Google Fonts | The page loads two fonts from `fonts.googleapis.com` and `fonts.gstatic.com` as soon as it opens, before any choice. That sends your IP address to Google. (`site/index.html`, `site/README.md` "Needs the owner" 4.) **[CONFIRM: self-host the fonts, or give notice and a basis]** |
| Links | Telegram group, TikTok, Instagram. They open in a new tab. We send them nothing. |
| Cookies and storage | Only GA cookies (if you allow) and one localStorage entry for your analytics choice. The site has no other cookies. |
| Blog | Pages are static (`site/blog`). No comments or forms were found. |

### 5.13 Doddy's server: notes and conversations kept for the web (ADR-603)

Status: server and web pages built and tested; iPhone rules built and tested in DoddyCore; **iPhone screens not compiled; not deployed.** Describes what the code does (`docs/product/CLOUD_MEMORY.md`).

| Item | Detail |
|---|---|
| Who | Doddy's own server (`backend/`, Render service `doddy`, Frankfurt **[CONFIRM: region of the hosted database]**). For a question asked on the web, the best matches are also given to Anthropic's Messages API (Claude) with Doddy's key. **[CONFIRM: Anthropic entity, terms, region, retention; Render's processor terms]** |
| What is kept | **Notes:** the text, how it was saved (voice, typed, shared, imported), its type and when. **Conversations:** what you and Doddy said, as text, each turn marked yours or Doddy's, with the language, when it started and ended and how it ended. Up to 400 turns of 4,000 characters, 1,500 conversations and 24 MiB per person. |
| What is never kept | Audio. Private notes and private conversations (ADR-310, ADR-170). Photos, voice memos, lists, About you answers, contacts, anything from connected apps, sample notes. The phone leaves these out before sending; the server cannot tell them apart. |
| Opt-in? | Yes. Two switches, notes and conversations, both off until you turn each on after a screen that says what goes, to which server, how it is stored, who can read it and how to delete it. Only the iPhone can switch keeping on; a browser cannot (tested). |
| When it is sent | Notes: the whole current list when you turn it on and again after a change (one send for a burst of edits) and once per launch, so the server matches the iPhone. A note you delete on the iPhone is gone from the server at the next send. Conversations: one at a time when it ends, and again at launch if a send failed (the last 50 are remembered). |
| How it is stored | Postgres, each note and conversation as one blob encrypted with AES-256-GCM, key held in the host's environment and bound to your account, the kind and the row. This is encryption at rest, **not end-to-end**: Doddy's server can read it so it can be searched and so the chat can use it. Ids, times and the number of turns are stored unencrypted. There is no key rotation yet. |
| Who can read it | You, in the app's web page after signing in (Doddy Web), and Doddy's server code. The owner and anyone with access to the server's environment and database could in principle read it with the key. **[CONFIRM: who at Doddy has production database and key access, and how that is logged]** Not sold, not used for ads, not used to train models by Doddy. **[CONFIRM: Anthropic's API terms on training and retention]** |
| Chat | When you write to Doddy in the web chat (ADR-604), the server gives Claude, as data and with no tools: the best matching notes and conversation excerpts, and about your account the names of the documents Doddy made in the last 7 days, Doddy's latest receipts (what he did, when, with which account, how it ended), your online accounts' names and status, and Logbook's counts (numbers only). Never the content of an email, event or file. The question and answer are not stored by the server; the page sends the last ten turns. **The list of chats is kept in your browser** (its local storage) until you sign out or delete it, never on Doddy's server. Shares the same daily limits as Ask Doddy (50 per person, 500 for everyone). |
| Retention | Conversations: 365 days from when they started. Notes: they mirror the iPhone; a phone that stops sending for 365 days loses them. Turning a kind off, or "Delete everything", deletes it at once. |
| Deletion | Turn a switch off in the app (deletes that kind). "Delete everything on Doddy's server" in the app, or on the web, deletes both and switches both off. On the web you can also delete a single conversation. Deleting on the web removes the server's copy only; the iPhone keeps its own. Backups of the database by the host. **[CONFIRM: host backup retention]** |
| Export | Everything, decrypted, as a JSON file from the web page. Limited to 20 a minute. |
| Logs | Counts, token numbers and timings only, never a note, a turn, a question or an answer (tested with planted strings). The host's own request logs (IP, path, status) are kept by Render. **[CONFIRM: host log retention]** |
| Legal basis | **[CONFIRM: consent, withdrawn by switching off]** |

### 5.14 Recaps of conversations ("Remember what we talked about"; decision 2026-11-09-conversation-recaps)

A recap is a short note of what was discussed, agreed and left to do after a conversation: three lists of short points, never the words themselves. **Off until you turn on "Remember what we talked about"** (Settings › What Doddy knows). Never for a Private conversation, a conversation with under 30 words from you, or anything from before you turned it on. Each recap is a normal note you can edit or delete.

| Item | Detail |
|---|---|
| Four kinds | A conversation with Doddy in the app; a recording written out on this iPhone (Recordings, by a tap on "Write a recap" or automatically with the switch on); a call to or from Doddy's phone line; a call Doddy made for you. |
| Who writes it | **A conversation or a recording:** Apple's on-device model on this iPhone (iOS 26 with Apple Intelligence in your language): nothing leaves the phone. If it can't, Doddy's messaging server asks Anthropic (Claude), **only** with the separate switch "Recaps on Doddy's server" on (off by default; a tap on "Write a recap" is never that yes). **A call to or from the phone line:** Doddy's messaging server, from the call's transcript, which ElevenLabs sends it after the call (the workspace post-call webhook, signed; the server reads only the phone agent's payloads), and Anthropic (Claude). Only while "Remember what we talked about" is on for your account. **A call Doddy made for you:** this iPhone, by fixed rules, from the call's card and answer; no model and no transcript. |
| What is sent | For the server writer: the lines of the conversation or recording, or the phone call's transcript, for that one recap. Nothing else: no notes, no profile, no phone number. The same instructions are used on the iPhone and the server (`schemas/fixtures/recap_instructions_v1.json`). |
| What the server keeps | **Nothing of the words.** `POST /v1/recaps` uses the lines for the one call and drops them. For phone calls the server keeps only the three lists, encrypted with a key bound to your account and the call (`phone_recaps`), until this iPhone has saved them as a note and said so (then the server deletes its copy), or for 30 days. Turning the switch off deletes the ones waiting. Logs hold counts, token numbers and timings, never a word (tested with planted strings: `server/messaging/test/recap.test.ts`, `phoneRecaps.test.ts`). A recap counts as one Messages request against the daily limits (`ASSISTANT_DAILY_PER_ACCOUNT`, `ASSISTANT_DAILY_PER_SERVER`). |
| What the app checks | A model's answer is a proposal: it must be exactly three lists, at most 6 points of 240 characters, and no point may copy 10 or more words in a row from the conversation, or nothing is saved. "Saved" is shown only after the note was read back. |
| What stays elsewhere | **ElevenLabs** keeps its own record of a call to the phone line for the retention set on the agent (30 days, no audio: `voice-agent/phone/session.json`; read 10 Nov 2026 on the live agent: audio recording off, retention 30 days, zero-retention off). This feature neither adds to nor shortens it. **Anthropic**: how long it keeps requests is not verified. Render keeps its own request logs (IP, path, status). |
| Recordings | Until this feature, a recording's words never left the iPhone (ADR-588; the Recordings code still cannot reach the network). They now do only with "Recaps on Doddy's server" on, from a different part of the app. |
| Legal basis | **[CONFIRM: consent, by the two switches; withdrawn by switching off]** |
| **[CONFIRM]** | Anthropic entity, terms, region and retention for the API key's organisation; whether telling the caller that a recap is made is required for phone calls (the phone agent says it is an AI in its first sentence; it does not say a recap is made); Apple's terms for the on-device model; the effect on the retention table in Section 9. |

### 5.15 On my radar (Following) and its alerts (ADR-656; decision 2026-11-10-radar-alerts)

What you follow is kept on the iPhone. Each time you open or refresh the screen, the follows (topic ids, your own words, your own feed's address) go to Doddy's messaging server, which fetches the publishers' public feeds through a shared cache and keeps nothing of yours. **Alerts are off until you turn on "Let Doddy's server check this for you" for one follow**, and the server feature is off until the owner switches it on (`RADAR_ALERTS_ENABLED`).

| Item | Detail |
|---|---|
| What is sent and kept | Only for a follow with that switch on: its name, its words or feed address, the words to look out for, how to tell you (as it happens or once a day, and at what time), your time zone and language (`radar_alerts`). The stories found for it: the publisher's headline, summary, link and name, and which of your words they mention (`radar_hits`). |
| What the server does | Reads the follow's feeds about every 20 minutes (a daily alert every 2 hours) and, for a new story that mentions your words, queues a notification through Apple: the publisher's headline and name. As it happens: not in quiet hours (21:00–08:00 in your time zone), at most 8 a day. Once a day: a count and up to three lines; if the server has a news writer, Anthropic (Claude) or OpenAI gets those public headlines and summaries, with your follow's name, to write the lines, and the notification says so. |
| Your own feed | Fetched by the server from its address (https, public addresses only). The address is kept only while the alert is on. |
| Retention | Found stories: 14 days. Alerts: until you turn the switch off, remove the follow or delete the account (all deleted with it). Notifications queued: as other notifications (section 5.5). Logs: counts only. |
| Opt-in? | Yes, per follow, off by default. |
| **[CONFIRM]** | The live privacy page and App Store answers before the switch goes on; the news writer's terms and retention (as section 5.9). |

### 5.16 Logbook: counts of how you use Doddy (decision 2026-11-09-usage-counts-on-by-default)

| Item | Detail |
|---|---|
| What is sent | For each day, counts only (`LogbookDay`, schema `doddy.logbook.day.v1`, checked by the server's allow-list in `backend/src/web/logbook.ts`): how many conversations and how long, in which hours, how they started (app, Action Button, widget, Siri, island) and ended, and in which languages; how often each of Doddy's tools ran and how it ended; notes saved by type and source, edits; list items added and ticked; tasks handed over; translator sessions and minutes. Never a word anyone said, a note's text, a name, a place, an email or audio. Private notes and private conversations are not counted. |
| Where | Doddy's server (`backend/`, Render service `doddy`), with your account. |
| When | **On unless you turn it off** (Settings › Doddy on the web › Logbook). The first time, the last 7 days and today; then today at most once an hour, and each day once more after it ends. |
| Who sees it | You, on Doddy Web's Logbook page. **Doddy's team sees every account's counts and totals with the account** (email address, sign-in method, dates) on an owner-only page (`/admin`). When you ask Doddy a question on Doddy Web, the counts added up go with it to Anthropic (Section 5.13 "Chat"). |
| Retention | 365 days. Turning Logbook off stops counting at once and asks the server to delete the days it holds; the app says "deleted" only after the server confirmed, and asks again at the next sync if it couldn't reach it. |
| Purpose | Showing you your own use, and the owner's view of what people use and what works and fails (product analytics). |
| Legal basis | **[CONFIRM: on by default with an off switch; whether this needs consent (and the ePrivacy rules on reading from the device) or can rest on legitimate interests; the hour-by-hour pattern shows when someone is awake]** |

### 5.17 Errands, shopping and food

Sources: `DataFlow` rows `errands`, `deals`, `watches`, `dealWatches`, `shopify`; `server/messaging/src/errands/`, `shopping/`, `deals/`, `watches/`; `backend/src/shopify/ucp.ts`; `docs/implementation/ERRANDS.md`, `SHOPPING.md`, `SHOPPING_WATCH.md`.

| Feature | What is sent, and to whom | Kept |
|---|---|---|
| **A task you hand over** (Tasks; ADR-570) | After your tap on its card: the task's words, Doddy's one-line note, its language and, for shopping, what matters most to you, to Doddy's messaging server. Anthropic (Claude) searches the web and reads pages for it, so search words made from the task go to Anthropic's search provider; for shopping, search words Claude writes also go to Serper (Google Shopping results), and the server opens shops' pages. Never your notes, lists, profile or earlier conversations. | Encrypted on the server until the result is saved on the iPhone, then deleted; a result never fetched, 30 days. The notification has no words from the task. |
| **This week's leaflets** | The names of the items you ask about and which shops to check. The server reads the shops' leaflet pages itself (a shared catalog it reads once for everyone, decision `2026-11-12-leaflet-catalog`); leaflets that are only pictures go with the item names to Anthropic to read; for Rossmann, the item names go to rossmann.pl as a search from the server. Nothing that identifies you goes to a shop. | Only daily counts of checks. |
| **A price you watch** (`WATCHES_ENABLED=1` on the live server, `STATUS.md`) | The shop's name and page address, the product's title and your price. The server reads that page a few times a day for 30 days and notifies you once if the price reaches yours. No model is involved. | Encrypted while the watch runs and 30 days after it ends; Delete removes it at once. |
| **A price alert** (`DEAL_WATCHES_ENABLED`, off on the live server; decision `2026-11-14-price-alerts-screen`) | The item's words, your price if you set one, the shops you pick and your language, to Doddy's messaging server after your tap on "Save the alert". Once a day, after the server has read the shops' leaflets (the shared catalog above), it checks the alert against what it already read: no leaflet page is read for it, no model is involved and nothing goes to a shop. A new match sends one notification through Apple that says only "Something you're watching is on offer in a leaflet": never the item, the shop or the price. Opening the list asks the server for your alerts with your device token and no words. | The words are encrypted on the server (bound to you and the alert) until the alert ends (a date the server sets, 60 days by default) or you delete it. Delete removes the alert and what it found at once; deleting your account deletes them. Offers an alert found are kept only as keyed hashes, so each is told once. **[CONFIRM: review before the switch goes on]** |
| **Shopify shops** (#369) | The words you search for; on Prepare checkout, that offer's variant id, the shop's domain and the quantity, to Shopify's Shop service from Doddy's server, with a fixed country and currency and nothing about you. A prepared checkout is a cart at the shop; you finish and pay on the shop's page. | Search words are not logged. |
| **Food** (decisions `2026-11-11-food-button`, `2026-11-12-food-restaurant-pages`) | Doddy opens a food app, or a restaurant's own order page that a search found, after your tap. Nothing is ordered or paid by Doddy, and nothing about you goes to the app from Doddy. | Nothing. |
| **Deliveries by Uber Direct** (decision `2026-11-12-uber-direct-deliveries`) | **Off** (`UBER_DIRECT_ENABLED=0`, test mode). When on: after a quote and your tap, the sender's and recipient's names, addresses and phone numbers (yours is your verified number), the items and a note go to Uber. | Encrypted per row on the server and erased when the delivery ends or the quote lapses. **[CONFIRM: Uber's role and terms before it is switched on]** |

**[CONFIRM: Serper's and the search provider's terms and retention; Shopify's terms; whether shops' pages read by the server need a notice]**

### 5.18 Files Doddy makes, and Studio

| Item | Detail |
|---|---|
| Files (decks, documents, spreadsheets, PDFs, text) | What you ask for in a conversation or in Messages goes to Doddy's server (`backend/`), which researches it (web search through Monid, Wikipedia) and has Anthropic (Claude) write and design it (`backend/src/decks/`). The file is kept on Doddy's server for 7 days, then deleted (`DOCUMENT_KEPT_DAYS`); the iPhone keeps a link in Messages and Files. If you ask to be told when it is ready, the messaging server keeps the file's private link, encrypted, for at most a day, and sends one notification with fixed words. **No deck has come out of the live pipeline yet** (`STATUS.md`). |
| Studio (ADR-740) | **Off on the server** (`STUDIO_ENABLED=0`, `STATUS.md`). When on, after your tap on a job's card: the topic, your words about it, who it's for, its length, style and language, and pages you picked, to Doddy's messaging server; Anthropic's Claude searches the web, reads pages and makes the files in Anthropic's code-execution container. Web research and code execution at Anthropic are not zero-retention. The server keeps the job and its files, encrypted, until you delete them in Studio; files left at Anthropic are deleted by the server and swept if a run stops half-way (#393). |
| **[CONFIRM]** | Monid's and Anthropic's terms and retention for this; Anthropic's Files API retention. |

### 5.19 Doddy looks at your screen (decision 2026-11-09-doddy-looks-at-the-screen)

| Item | Detail |
|---|---|
| How | You start sharing your screen with Doddy from iOS's own sheet; iOS shows that it is shared until you stop. While it is, the screen-sharing extension keeps one picture of the screen on the iPhone (Section 3). It reads no sound. |
| What is sent | When you ask Doddy about your screen in a conversation while sharing is on: that one picture (long edge 1,280 px), the question and your language, to Doddy's messaging server (`POST /v1/screen/look`), which has Anthropic (Claude) read it once, with no tools. A picture more than 10 seconds old is never sent. Since 11 Nov 2026 sharing being on counts as your yes for each look (decision `2026-11-11-asked-for-runs-at-once`). |
| Kept | The server keeps neither the picture nor the question; it logs the model, outcome, the picture's age and token counts. What Doddy said about it is part of the conversation (ElevenLabs, and your remembered conversations if that is on). |
| Others on your screen | The screen often shows other people (a profile, a chat). Doddy is told not to identify anyone from a face and to treat what is on screen as information only. **[CONFIRM: the basis for processing third parties' data shown on the screen; App Store privacy answers name "screen content"]** |

### 5.20 The camera, photos and Apple Health

| Item | Detail |
|---|---|
| Camera (ADR-569) | Opened only when you tap Take a photo, Open camera or Scan a barcode. A photo for a note stays in that note on the iPhone. A barcode's number goes to Open Food Facts (5.11). A photo you take to ask Doddy about goes to Messages and leaves only when you tap Send (5.4). Nothing is saved to your photo library. |
| Photo library (read only) | Doddy counts the photos and videos you took on days you ask about and shows them on screen; only how many and when go to ElevenLabs in that conversation. A photo you choose with Apple's picker to ask about in Messages goes as in 5.4; the picker needs no permission. Doddy never changes your library. |
| Apple Health (read only, ADR-621 to 623) | Doddy reads workouts, heart rate, resting heart rate, heart rate variability, sleep and VO2 max to show them on its Apple Health screen. Only a short summary of the week can leave the iPhone, each way after its own consent: **in Messages**, when you tap Send, to Doddy's messaging server and Anthropic for the answer; the message then stays in Messages on the iPhone and, as text, in the Messages copy on Doddy's server (5.4) until you delete it; **to the voice**, when you ask and say yes, to ElevenLabs (and the model behind it, 5.1), where it is kept with that conversation's recording and transcript. Doddy writes nothing to Health. Not in the build made for a free Apple team (`project-iphone.yml`). |
| Motion & Fitness | One day's steps, distance and floors, when you ask, to ElevenLabs in that conversation. |
| **[CONFIRM]** | Health data is special-category data (GDPR Art. 9): explicit consent wording, and whether the Messages copy on Doddy's server is covered by the consent shown today (it says the server keeps no words); the app's consent and the permission text are being changed to say so (`claude/privacy-texts-match-code`). |

### 5.21 Trips and flights

| Item | Detail |
|---|---|
| Flight search (`FLIGHT_SEARCH_ENABLED=1`, `STATUS.md`) | Places, dates, number of people and bags go from Doddy's server to Kiwi.com; results open on Kiwi.com, where you book yourself. Nothing is saved (decision `2026-11-11-flights-kiwi-search-duffel-booking`). |
| Flight booking through Duffel | **Off, test mode only** (`FLIGHT_BOOKING_ENABLED`, a test key). When on, after a card that shows the exact booking: every passenger's name, birth date and contact, the flights and the total go to Duffel. **[CONFIRM: before any live booking, Duffel's role, the airline's, and a policy line]** |
| Trips from Gmail (Trips, with Read an email on) | On your tap, the server reads up to 25 booking emails from Gmail through Composio, removes links, PINs and card numbers, and sends the rest of each to Anthropic to read the booking; it keeps none of it, and trips are saved on the iPhone only (`DataFlow` row `doddyServer`). |
| Trip planner | The words you type go to Doddy's server and Anthropic to become a brief; then only places, dates, people and bags go to Kiwi.com. Nothing is saved, booked or paid. |

### 5.22 Parcels and deliveries

| Item | Detail |
|---|---|
| Parcels (Przesyłki, ADR-641) | The parcel number you add or refresh goes from the iPhone to InPost's public tracking address; no account or key. A number in a message or email is never looked up by itself. Your list of parcels stays on the iPhone. |
| Deliveries | Uber Direct is off (5.17). |

### 5.23 Doddy Web: what your account shows in a browser

Doddy Web (ADR-600, decision `2026-11-09-web-sign-in-same-account`) opens with the same Doddy account (Apple or Google). It shows only what Doddy's server already keeps for the account: files Doddy made (7 days), online accounts and their tools, Doddy's receipts, Logbook (5.16), the Messages copy (5.4) and, if you switched them on, kept notes and conversations (5.13). A browser stays signed in for 30 days at most; Settings › Doddy on the web signs it out. The web chat (5.13) sends what it uses to Anthropic. **[CONFIRM: the web pages' own notice and cookies, `web/`]**

## 6. Permissions the app asks for

The app asks for these only, each when you first use the matching feature (`project.yml` `INFOPLIST_KEY_*`, `Config/Doddy-Info.plist`; the forbidden-capability guard, `scripts/check_forbidden_capabilities.sh`, fails on any other). It does not ask for Bluetooth, the advertising ID, tracking or "Always" location. The app's own permission texts are in those files and, translated, in `l10n/*_infoplist.json`; this table says what the code does, and the texts must say the same (Appendix B, item 25).

| Permission | What Doddy uses it for, and what leaves the iPhone |
|---|---|
| **Microphone** | Talking to Doddy: your voice goes to ElevenLabs, which keeps a recording and transcript (5.1); in translator mode the other person's voice too. Voice memos and Recordings stay on the iPhone; Doddy shows a recording the whole time it runs. |
| **Speech recognition** | On the iPhone only: voice memos, Recordings and the mic in Messages are written out here and not sent. Words you dictate into Messages leave only if you send them (5.4). |
| **Contacts** | Finding a contact by name, birthdays coming up, and birthdays of people you pick. In a conversation, names and birthday day and month go to ElevenLabs; numbers, email addresses and birth years stay on the iPhone (they are used only to open a message or email draft on the iPhone). A number for a call Doddy places for you is picked with Apple's contact picker, which needs no permission (5.7a). |
| **Calendar (full access), Reminders (full access)** | Reading the days you ask about; adding, changing or deleting only after you tap the card. What Doddy uses in a conversation goes to ElevenLabs. |
| **Location, while using** | Place reminders (iOS watches the place), where you parked, and when to leave (Apple Maps). Where you parked is kept on the iPhone until you clear it (ADR-301). **[CONFIRM: the permission text says "Doddy doesn't keep it"; it and this policy must agree]** |
| **Face ID** | The app lock and private notes. iOS checks your face; Doddy only learns whether it matched. |
| **Motion & Fitness** | One day's steps, distance and floors, when you ask; to ElevenLabs in that conversation (5.20). |
| **Apple Health (read only)** | The Apple Health screen; a week's summary only as in 5.20. Doddy writes nothing to Health (`NSHealthUpdateUsageDescription` exists only because iOS's permission screen covers both). |
| **Camera** | A photo for a note, a barcode on a list, or a photo to ask about in Messages (5.20, 5.4). |
| **Photo library (read only)** | Counting and showing the photos and videos you took on days you ask about (5.20). Choosing one photo to send uses Apple's picker, which needs no permission. |
| **Home (HomeKit)** | Turning a light, outlet or fan on or off, or running a scene, after a tap on a card that names it; never locks, garage doors, alarms or cameras. The name and whether it worked go to the voice in that conversation. Only in builds with the HomeKit entitlement. |
| **Alarms (AlarmKit, iOS 26+)** | Alarms and timers you ask for, after a tap; they ring in Silent mode or a Focus. |
| **Notifications** | Asked when you turn on timers, reminders, check-ins or push. No usage-description text is needed. Reminder text is hidden by default (ADR-190). |
| **Live Activities and Dynamic Island** | Shows the state of a conversation, a call Doddy places, a focus timer or a shopping list on the Lock Screen. Shopping mode asks you to confirm that its items will be readable on the Lock Screen (ADR-257). |
| **Background audio** | Keeps a conversation you started running after you leave the app, mixing with other apps' audio (ADR-053, decision `2026-11-12-action-button-audio-and-island`). |
| **Background remote notifications** | iCloud's "a shared list changed" wake-up (ADR-284), and a finished task's push waking the app to put the result in Messages (decision `2026-11-12-results-reach-messages`). |

Screen sharing is not a permission: you start it from iOS's own sheet each time, and iOS shows that the screen is shared (5.19). The Share extension, the widgets, the notification view and the screen-sharing extension ask for nothing. The Apple Watch app is paused (ADR-572). **[CONFIRM after the first build]**

## 7. Children, AI transparency, automated decisions, sale of data

**Children.** The code has no age gate, no parental controls and no children's mode (searched `DoddyApp` and `Packages`). Doddy is not designed for children. **[CONFIRM: age rating for the App Store; the minimum age for the voice features and the open-ended AI chat; whether the policy says "13", "16" or "18"; parental consent rules]**

**AI transparency (draft statement, EU AI Act Article 50).**
- Doddy is an AI system. When you talk to Doddy, you are talking to software and not to a person.
- Doddy's voice is generated by a speech system (ElevenLabs; OpenAI Realtime was removed on 9 Nov 2026).
- Doddy's answers can be wrong. Check anything that matters.
- Since 11 Nov 2026 the app's own screens do not call Doddy an AI, and the website's footer says "Doddy is a digital companion, not a person" (decision `2026-11-09-companion-not-ai-label`). The voice prompt tells Doddy to say plainly that he is an AI when asked (checked by `scripts/voice_agent_spec.py`). The phone line's fixed sentence for callers it doesn't let through, and the opening line of every call Doddy places for you, say it first (`voice-agent/phone/instructions.md`, `server/messaging/src/taskCalls/opening.ts`, ADR-191, ADR-194, ADR-502).
- The voice agent's own greeting does not say it is an AI, and there is no on-screen disclosure in the app any more; the disclosure is Doddy's answer when asked. **[CONFIRM: whether that meets Article 50 and the companion-chatbot laws the decision names (California SB 243, New York)]** **[CONFIRM: with a specialist whether Article 50 needs more, and from what date; whether synthetic audio must be marked; ElevenLabs' and OpenAI's role as provider and ours as deployer]**
- Doddy is not meant to claim feelings of a person, to flatter, or to make you feel guilt or dependence. This is a design rule (`docs/trust/`), enforced in part by a prompt check (`voice_agent_spec.py check`), not by code in every case.

**Automated decisions.** Doddy makes no decision about you with legal or similarly significant effects. It proposes; you confirm. Anything that changes your calendar, reminders, drafts, tasks or lists by voice shows a card and needs your tap, except small list edits that you ask for by voice, which are shown in "What Doddy did" with Undo (ADR-216, ADR-258, ADR-268). Doddy has no profiling for ads or scoring. **[CONFIRM: lawyer agrees there is no Article 22 issue]**

**Sale, ads, tracking.** We do not sell personal data. The app has no ads and no tracking (`PrivacyInfo.xcprivacy`, `DEPENDENCIES_AND_LICENSES.md`). The website uses analytics as in 5.12. **[CONFIRM: no data is shared for the processors' own purposes, for example ElevenLabs or Google model training]**

## 8. Your rights, export and deletion

If GDPR or UK GDPR applies to you, you have the rights of access, rectification, erasure, restriction, portability, objection, withdrawing consent, and complaint to a supervisory authority. Write to [PRIVACY EMAIL ADDRESS]. We will answer within [ONE MONTH] **[CONFIRM]**. **[CONFIRM: identity checks; how we find an anonymous account, which has no email, when someone asks for access to server data]**

What the app lets you do today:

| You want to | What the app does | Source |
|---|---|---|
| See where data goes | Settings, Privacy, "What leaves this iPhone" | `DataFlowView.swift` |
| Delete your Doddy account | Settings › About › Your Doddy account › Delete. In order: the messaging server deletes the account and everything it keeps that names it, and queues for deletion what it left at Twilio and the phone line's and task calls' conversations at ElevenLabs, checked gone; Sign in with Apple is ended where it can be; Doddy's server deletes what it keeps (kept notes and conversations, the Messages copy, Logbook, files, receipts, online-account connections at Composio, and the sign-in at Supabase), retrying clean-ups until they are done; this iPhone's older voice account, if any, is deleted; then the iPhone signs out. It says the account was deleted only after each server confirmed; if one doesn't, nothing after it runs and you stay signed in. With no messaging token on this iPhone (after a reinstall, say), it signs in to the messaging server with the account first, so that account is found and deleted too (decision `2026-11-12-account-deletion-truth`, proposed, owner approval pending). Notes on the iPhone stay. | `DoddyAccountApp.swift` (`DoddyAccountServers.deleteAccount`), `ServerAccountErasure`, `AccountErasurePlan` (DoddyCore), `DELETE /v1/account` on both servers, `backend/src/store.ts`, `server/messaging/README.md` "What is kept", #384, #391, ADR-818 |
| Turn Logbook off | Counting stops at once; the server deletes the days it holds; "deleted" is said only after it confirmed | `LogbookModel.setOn` (DoddyCore) |
| Delete the Messages conversation | "Delete conversation": deleted on the iPhone, then the copy on Doddy's server, said only when the server confirms | `MessagesModel.deleteConversation` |
| Delete a Studio job, stop a price watch | In Studio and in Shopping; the server deletes it | `DataFlow` rows `studio`, `watches` |
| Export notes and lists | Export as JSON, plain text, or Markdown (share sheet). JSON can be restored. | ADR-030, ADR-203, `SettingsView.swift` |
| Export About you and settings | JSON or text | ADR-176 |
| Export remembered conversations | Plain text | ADR-177 |
| Make a full backup | Encrypted backup file (`.doddybackup`): notes, lists, photos, voice memos, time reminders, About you answers. AES-256-GCM, key from your passphrase (at least 10 characters) with PBKDF2-HMAC-SHA256, 600,000 rounds. Opened again and compared before the save sheet. Restore only adds. | ADR-222, ADR-234 |
| Delete one note, or one remembered conversation | Delete (notes: a 10-second Undo; the delete itself is immediate). A deleted or corrected-away word of a note, list, learned fact or routine is overwritten in Doddy's database file, its full-text search entries included: tests read the file and its `-wal` and `-journal` files. That check does not cover remembered conversations, backups, exports, iCloud copies or iPhone search | ADR-177, ADR-183, ADR-584 |
| Delete all notes and lists | "Delete all memories" (`deleteAll`): removes every note, list and item, corrections, photo and voice memo files, the search index entries, and note reminders. It stops your shared lists, tries to empty the "Memory on calls" server copy, and says plainly if either failed. It is read back before it says done. | `SettingsView.swift` `deleteAll()`, `SQLiteMemoryRepository.deleteAll`, `MemoryStore.deleteAll`, ADR-026, ADR-028 |
| Forget About you | "Forget all of this" (`forgetProfile`). It does not delete notes. | ADR-085, `SQLiteProfileRepository` |
| Forget conversations | "Forget remembered conversations" | `SettingsView.swift` |
| Clear the activity list | "Clear" in What Doddy did | `ActivityView.swift` |
| Delete the messaging server data | "Delete my Doddy messaging data": the server deletes the account and, by cascade, the devices, phone number, queued and past messages, call notes, memory copies, call records, news settings and topics. The app then switches push and Memory on calls off. Notes on the iPhone are not touched. | `UpdatesModel.deleteServerAccount`, `DELETE /v1/account`, ADR-143 |
| Turn off Memory on calls | Deletes every server copy of your notes | `server/messaging/README.md`, ADR-153 |
| Turn off keeping notes or conversations on Doddy's server | The app asks the server first; the switch follows its answer. The server deletes that kind in the same step. | `WebMemoryModel.setKept`, `PUT /v1/web/memory/state`, ADR-603 |
| Delete everything Doddy's server keeps | "Delete everything on Doddy's server" in the app, or "Delete everything here" on the web. Both switches go off. It says plainly if the server did not confirm. Notes and conversations on the iPhone stay. | `WebMemoryModel.deleteEverythingOnServer`, `DELETE /v1/web/memory`, ADR-603 |
| Read, search, download or delete one conversation on the server | The web page (sign in with the iPhone) | `web/src/pages/MemoryPage.tsx`, `GET /v1/web/memory/export`, ADR-603 |
| Stop sharing a list | Deletes the iCloud copy for everyone. Leave takes you off someone else's list. | ADR-263 |
| Disconnect an online account | Deletes the connection record and asks Composio to revoke and delete. You can also remove access in your Google account. | `SECURITY_AND_PERMISSIONS.md` |
| Delete your waitlist email | Ask [PRIVACY EMAIL ADDRESS]. The owner deletes it in the admin page. | `site/README.md` |

What the app **cannot** delete:

- Recordings and transcripts of conversations in the app at ElevenLabs, and anything its model providers keep. Deleting the Doddy account does not delete them (`STATUS.md`, security review of 12 Nov 2026); the phone line's and task calls' conversations are deleted as in 5.7a. **[CONFIRM: how a user can have them deleted; whether you can delete through the ElevenLabs API by conversation or install ID]**
- Data already at OpenAI (the model behind the voice, the news writer), Anthropic, GNews, Twilio (Verify; message and call records are deleted as in 5.6), Apple (APNs, Siri, iCloud, Maps), Composio, Monid, Serper, Kiwi.com, Shopify, Google, Microsoft, Notion, Todoist, Vercel, Supabase and Render logs. **[CONFIRM for each]**
- An export of what Doddy's server keeps, apart from kept notes and conversations (5.13): not built. **[CONFIRM]**
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
| Phone-line conversations at ElevenLabs | 30 days, no audio (live agent read 10 Nov 2026); deleted with the account, checked gone | ADR-158, `server/messaging/README.md` |
| Doddy account (Supabase) | Until you delete the account | Section 5.0 |
| Messages copy on Doddy's server | Until "Delete conversation" or account deletion; 365 days without a send | `backend/src/app.ts` (`pruneMessageThreads`) |
| Logbook days | 365 days; deleted when Logbook is turned off | `backend/src/web/logbook.ts` (`LOGBOOK_KEPT_DAYS`) |
| Files Doddy made | 7 days on Doddy's server | `backend/src/web/routes.ts` (`DOCUMENT_KEPT_DAYS`) |
| Calls Doddy places: live transcript lines / answer card / task-agent conversation at ElevenLabs / dial log | 24 hours at most / until saved, 7 days at most / until the answer card is built / 2 days | `server/messaging/README.md` "What is kept" |
| Tasks you hand over | Until the result is saved on the iPhone; 30 days if never fetched | `DataFlow` row `errands` |
| Price watches | While the watch runs and 30 days after | `DataFlow` row `watches` |
| Studio jobs and files | Until you delete them | `DataFlow` row `studio` |
| The shared screen picture | Never kept by the server; on the iPhone until sharing stops | Section 5.19 |
| Uber Direct delivery details (off) | Until the delivery ends or the quote lapses | decision `2026-11-12-uber-direct-deliveries` |
| Messaging server account, phone number, news settings | Until deleted | `001_init.sql`, `003_news.sql` |
| Queued message text | Until the message reaches a final state | `001_init.sql` |
| Memory copy | Until Memory on calls is turned off | ADR-153 |
| Notes kept on Doddy's server for the web | Until you turn it off or delete; mirrors the iPhone; 365 days without a send | ADR-603, `backend/src/store.ts` |
| Conversations kept on Doddy's server for the web | 365 days from when they started, or until you delete them | ADR-603 |
| Call notes, and notes from your texts | Until you confirm or discard them **[CONFIRM: expiry]** | `002_calls.sql`, `019_texts_to_doddy.sql` |
| A row for each text you sent Doddy with "Texts to Doddy" on: state and time only, no text (the text is the note above) | Until the account is deleted **[CONFIRM: retention of these rows]** | `019_texts_to_doddy.sql` |
| Reason of a booked call | Until the call ends or won't happen; 2 hours after a placed call whose end Twilio never reported | `020_scheduled_calls.sql`, `scheduledCalls.ts` |
| Booked-call rows (time, state) and your time zone | Until the account is deleted **[CONFIRM: retention]** | `020_scheduled_calls.sql` |
| Message and call records at Twilio | Deleted by Doddy 24 hours after final by default; Twilio backups up to 30 days | `providerRecords.ts`, ADR-753 |
| Verification-start records | 2 days (hash of number only) | `routes/phone.ts` |
| News sent records / digests / feed cache | 14 days / 30 days / 24 hours | `news/digest.ts`, `news/sources.ts` |
| On my radar: alerts / stories found | Until turned off / 14 days | `026_radar_alerts.sql`, `news/radar.ts` |
| Price alerts: the alert / the offers it found | Until it ends (a date the server sets, 60 days by default), you delete it or the account is deleted / as keyed hashes until a month after the offer's last day | `038_deal_watches.sql`, `deals/dealWatches.ts` |
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

### 9.3 Processors and international transfers

Services that receive personal data from Doddy, as the code on `main` shows them (12 Nov 2026). "Off" means built but switched off on the server or in the build. **[CONFIRM for every row: the processor agreement (DPA) or the service's role as controller, its sub-processors, the data location and the transfer mechanism (adequacy, standard contractual clauses, the EU-US Data Privacy Framework)]**

| Service | What for | In the code | Region shown in the repository |
|---|---|---|---|
| Anthropic (Claude) | Messages, the screen look, recaps, tasks, leaflets that are pictures, call answer cards, trips from Gmail and the trip planner, files, Studio, the web chat | In use (`server/messaging`, `backend`) | Not shown |
| ElevenLabs | Voice conversations, translator mode, the phone line, calls Doddy places | In use | Not shown (EU residency is Enterprise-only, `V1_VOICE_STATUS.md`) |
| OpenAI | The model behind the live voice agent (5.1); the news writer when the messaging server has its key (`news/writer.ts`) | In use through ElevenLabs; the news writer as set up | Not shown |
| Twilio | Verify, texts, calls to and from Doddy's number, calls Doddy places and their live transcription (Twilio's Google engine) | In use; calls Doddy places need the calling line set up | Not shown |
| Supabase | Doddy accounts (Auth, project `doddy-gateway`); the database of Doddy's server `doddy` (`STATUS.md`) | In use | Not shown |
| Render | Doddy's server `doddy` and the messaging server `doddy-messaging` with its Postgres | In use | Frankfurt (`render.yaml`) |
| Vercel | The website and its waitlist (Blob), Web Analytics, the voice token server (Functions) | In use | Blob: Frankfurt (fra1); Functions: not shown |
| Upstash | Redis for the voice token server's sessions and limits (`server/voice-token/src/voice-auth.js`) | In use | Not shown |
| Composio | Your connected Google, Microsoft, Notion and Todoist accounts (tokens held by Composio) | In use when you connect an account | Not shown |
| Apple | Sign in with Apple, push (APNs), Maps, Siri, iCloud (off in the default build), the on-device model for recaps | In use | Apple's |
| Google | Google sign-in (through Supabase); Gmail, Calendar and Drive through Composio; Twilio's transcription engine; Google Analytics and Google Fonts on the website. Gemini is named in `voice-agent/session.json` but is not the live voice model (5.1) | In use | Not shown |
| Monid | Web, news and places search; research for files | In use | Not shown |
| Serper | Google Shopping results for shopping tasks | In use when a key is set | Not shown |
| GNews | Your own news keywords | In use when daily news or Following uses it | Not shown |
| Kiwi.com | Flight search | On (`FLIGHT_SEARCH_ENABLED=1`) | Not shown |
| Shopify | Search and prepared checkouts at Shopify shops | In use | Not shown |
| Duffel | Flight booking | Off, test only | Not shown |
| Uber (Uber Direct) | Deliveries | Off, test mode | Not shown |
| Coinbase | Paying for web pages (x402) | Off, test network only (`STATUS.md`) | Not shown |
| Public data, nothing about you beyond a request | ECB rates, Open-Meteo and Wikipedia (through ElevenLabs), Open Food Facts (a barcode), InPost (a parcel number), the Ministry of Finance VAT register and CEIDG (a buyer's NIP), IMGW, GIOŚ and NBP (Poland Pack, `STATUS.md`) | In use | Not applicable |

### 9.4 Changes to this policy

We will post changes at [POLICY ADDRESS] and change the date above. For material changes we will [tell you in the app] **[CONFIRM]**.

### 9.5 Contact

[PRIVACY EMAIL ADDRESS], [POSTAL ADDRESS]. Complaints can go to [SUPERVISORY AUTHORITY].

---

## Appendix A. Claim to source map

Paths are relative to the repository root. "ADR" means a row in `DECISIONS.md`.

| # | Claim in this draft | Source |
|---|---|---|
| A1 | ~~No account is required~~ replaced 8 Nov 2026: a Doddy account is required (see A53) | `PrivacyDefaults.swift` (`v1Voice`, out of date) |
| A2 | App has no third-party analytics or crash SDK; Logbook is its own analytics (A56) | `DEPENDENCIES_AND_LICENSES.md`; `project.yml` packages; `PrivacyInfo.xcprivacy` |
| A3 | Voice data list sent to ElevenLabs | `DataFlow.swift` (`rows`, row `elevenlabs`); `DoddyApp/Features/Settings/SettingsView.swift` privacy paragraph |
| A4 | Notes budget 6,000 chars, conversations 4,000 | `Packages/DoddyCore/Sources/DoddyCore/VoiceContext.swift` |
| A5 | Max 10 minutes per conversation; live agent model OpenAI `gpt-6-luna`, `session.json` says Gemini | `voice-agent/session.json` (`max_duration_secs`, `elevenlabs.llm`); `voice-agent/README.md` (live reads, 24 Oct to 10 Nov 2026) |
| A6 | ElevenLabs recording on, unlimited retention, zero-retention off, EU residency Enterprise-only | `V1_VOICE_STATUS.md`; ADR-057 |
| A7 | Agent authentication on, with a daily limit; a Doddy account session for every voice token | `STATUS.md` "Live services"; `server/voice-token/src/doddy-account.js`; decision `2026-11-09-elevenlabs-only-voice` |
| A8 | Private conversation is on-device only | ADR-170 |
| A9 | Translator mode data | `DataFlow.swift` row `translator`; ADR-215 |
| A10 | Token server behaviour and logs | `server/voice-token/README.md`; `docs/implementation/VOICE_TOKEN_SERVER_STATUS.md` |
| A11 | ~~OpenAI voice, direct from the phone~~ removed 9 Nov 2026 | decision `2026-11-09-elevenlabs-only-voice` |
| A12 | Messages data, limits, no storage at the messaging server, photos and files with one question, on by default | `server/messaging/src/assistant/` (`request.ts`, `responder.ts`), `server/messaging/src/config.ts`; `docs/implementation/MESSAGES_PHOTOS.md`; ADR-587, ADR-732; decision `2026-11-09-messages-on-by-default` |
| A13 | Messaging server tables, anonymous account, phone number plain, hash-only token | `server/messaging/migrations/001_init.sql` to `007`; `server/messaging/src/routes/account.ts` |
| A14 | ~~Built-in messaging address empty~~ the app has the messaging server's address built in, and it is deployed | `STATUS.md` "Live services" |
| A15 | Render Frankfurt, Postgres; both services deployed | `render.yaml`; ADR-139; `STATUS.md` |
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
| A26 | Removed 20 Oct 2026: Picovoice and the "Hey Doddy" wake word are gone from the app (ADR-549) | none |
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
| A37 | The permission list in Section 6, and no others | `project.yml`; `Config/Doddy-Info.plist`; `scripts/check_forbidden_capabilities.sh` (its passing line lists the permissions) |
| A38 | Delete all, forget profile, delete account | `SettingsView.swift`; `MemoryStore.swift`; `SQLiteMemoryRepository.swift`; `SQLiteProfileRepository.swift`; `UpdatesModel.swift`; `ServerClient.swift` |
| A39 | Export formats | ADR-030, ADR-176, ADR-177, ADR-203 |
| A40 | Website data, waitlist storage, admin | `site/api/*.js`; `site/README.md`; `site/index.html` |
| A41 | Analytics: Vercel Web Analytics and GA4 on every page, no consent banner | `site/analytics.js`; `site/README.md`; ADR-245 |
| A42 | Google Fonts load without consent | `site/index.html` lines 21 to 23; `site/vercel.json` CSP; `site/README.md` "Needs the owner" 4 |
| A43 | AI disclosure: answered when asked; said first on the phone line and on calls Doddy places; no on-screen label since 11 Nov 2026 | `voice-agent/instructions.md`; `voice-agent/phone/instructions.md`; `server/messaging/src/taskCalls/opening.ts`; `HomeView.swift` (comment where the header was); decision `2026-11-09-companion-not-ai-label`; ADR-191, ADR-194 |
| A44 | No age gate | Searched `DoddyApp` and `Packages` for age gate, parental terms; none found |
| A45 | Privacy manifest content | `DoddyApp/Resources/PrivacyInfo.xcprivacy`; ADR-118 |
| A46 | Legal review not done, no privacy policy yet | `docs/security/PRIVACY_GDPR_AI_ACT.md`; `GO_LIVE_STATUS_2026-10-11.md` |
| A47 | Notes and conversations are kept on Doddy's server only if switched on; text only; private ones left out; 365 days | `backend/src/memory/{contract,service,routes}.ts`; `Packages/DoddyCore/Sources/DoddyCore/OnlineAccounts/WebMemoryClient.swift` (`KeptNote.from`, `KeptConversation.mayBeSent`); ADR-603 |
| A48 | Encrypted at rest with AES-256-GCM bound to user, kind and row; server can read it; no key rotation | `backend/src/memory/crypto.ts`; `docs/product/CLOUD_MEMORY.md` |
| A49 | Browser can read, search, export and delete, never switch keeping on | `backend/src/memory/routes.ts`; `backend/test/memory.test.ts` |
| A50 | Logs hold no note, turn, question or answer | `backend/test/memory.test.ts` (planted strings) |
| A51 | The switch follows the server's answer; a delete is only reported when the server confirmed | `Packages/DoddyCore/Sources/DoddyCore/OnlineAccounts/WebMemoryModel.swift`; `WebMemoryModelTests.swift` |
| A53 | A Doddy account is required: Apple or Google through Supabase Auth; email codes hidden; email and method kept; owner page shows them | `Packages/DoddyCore/Sources/DoddyCore/Account/DoddyAccount.swift`; `DoddyApp/Features/Account/`; `backend/src/web/owner.ts`; decisions `2026-11-08-required-account`, `2026-11-09-email-sign-in-off-for-now` |
| A54 | The Messages copy for Doddy Web: newest 200 messages, text only, no photo, file name and kind, encrypted at rest, deleted with Delete conversation, 365 days without a send | `Packages/DoddyCore/Sources/DoddyCore/Messages/ThreadSync.swift`; `DoddyApp/Features/Messages/MessagesModel.swift`; `backend/src/messages/`; `backend/src/app.ts` |
| A55 | Calls Doddy places: brief, Twilio with recording off, live transcription (Google engine), ElevenLabs task agent, Anthropic answer card, opening line, hours, limits, retention | `server/messaging/src/taskCalls/` (`payload.ts`, `twiml.ts`, `opening.ts`, `worker.ts`, `agentSafety.ts`); `server/messaging/src/config.ts`; `server/messaging/README.md` "What is kept"; `DataFlow` row `callCases` |
| A56 | Logbook: counts only, allow-list, on by default, owner sees every account, 365 days, deletion confirmed by the server | `Packages/DoddyCore/Sources/DoddyCore/Logbook/`; `backend/src/web/logbook.ts`; `backend/src/web/owner.ts`; decision `2026-11-09-usage-counts-on-by-default` |
| A57 | Errands, leaflets, price watches, Shopify, food, Uber Direct (off) | `DataFlow` rows `errands`, `deals`, `watches`, `dealWatches`, `shopify`; `backend/src/shopify/ucp.ts`; `backend/src/tools/foodPages.ts`; decisions `2026-11-12-leaflet-catalog`, `2026-11-12-uber-direct-deliveries` |
| A58 | Files Doddy makes (7 days) and Studio (off on the server) | `backend/src/decks/`; `backend/src/web/routes.ts` (`DOCUMENT_KEPT_DAYS`); `server/messaging/src/studio/`; `server/messaging/src/config.ts` (`STUDIO_ENABLED`); `DataFlow` rows `studio`, `fileReady` |
| A59 | The screen look: one picture, fresh, read once by Claude, kept by neither server | `Shared/Screen/ScreenShareFiles.swift`; `DoddyScreen/`; `POST /v1/screen/look` in `server/messaging`; decision `2026-11-09-doddy-looks-at-the-screen` |
| A60 | Camera, photo library, Apple Health and Motion & Fitness | `DoddyApp/Features/Photos/`; `DoddyApp/Infrastructure/Connections/PhotoLibrarySearch.swift`; `DoddyApp/Features/Health/HealthConnectionView.swift`; `Packages/DoddyCore/Sources/DoddyCore/HealthVoice.swift`, `HealthShare.swift`; ADR-569, ADR-621 to 623 |
| A61 | Flights (Kiwi.com on, Duffel off), trips from Gmail, trip planner | `backend/src/flights/`; `DataFlow` row `doddyServer`; decisions `2026-11-11-flights-kiwi-search-duffel-booking`, `2026-11-11-travel-agent-plan` |
| A62 | Account deletion order and what each server deletes | `DoddyApp/Features/Account/DoddyAccountApp.swift`; `backend/src/store.ts` (the erased tables); `server/messaging/README.md`; #384; ADR-818 |
| A63 | Processors and where they are used | Section 9.3; a search of `backend/src`, `server/messaging/src`, `server/voice-token/src` for each service's name |
| A52 | Recaps: off by default, never Private, no words kept on the server, the phone-call recap keeps only three encrypted lists until saved or 30 days, the iPhone and the server use the same instructions, a tap is not a yes to the server | `Packages/DoddyCore/Sources/DoddyCore/Recap/`; `DoddyApp/Features/Recaps/`; `server/messaging/src/assistant/recap.ts`, `phoneRecaps.ts`, `routes/phoneRecaps.ts`; `server/messaging/migrations/025_phone_recaps.sql`; decision 2026-11-09-conversation-recaps |

## Appendix B. Open questions for the owner and the lawyer

### B1. Where the app's own statements and the code disagree, or are silent

1. **The model behind the voice is not named consistently.** The live agent runs on OpenAI's `gpt-6-luna` (read 24 Oct to 10 Nov 2026), `session.json` says Gemini, and the phone agent's spec says Gemini 2.5. Only the Apple Health consent names "ElevenLabs, with an OpenAI model"; `DataFlow`, the Settings privacy paragraph and the website name ElevenLabs only.
2. **ElevenLabs retention is not stated.** The app says ElevenLabs "keeps a recording and transcript". The live setting is unlimited retention, recording on, zero-retention off. ADR-057 allowed it for the owner's own phone only.
3. **Whole notes go to voice in every conversation** (up to 6,000 characters). The Settings paragraph does say this. The website privacy panel says notes "leave it only for things you switch on". Starting a conversation is the switch. Make sure users see it before the first conversation.
4. **Web search (Monid) has no row of its own in `DataFlow`;** it is named in the `doddyServer` row and in the Settings paragraph. `PrivacyInfo.xcprivacy` does not list search queries (Appendix C, "Search history").
5. **A Doddy account is now required** (decision `2026-11-08-required-account`), but `PrivacyDefaults.v1Voice` still says `accountRequired: false`, and Settings › Privacy says "Voice sign-in: Optional for notes; required for voice". Check the website's "No account" lines too.
6. ~~The "Network" status row omits services.~~ It is built from `DataFlow.rows` since ADR-447, so it lists what "What leaves this iPhone" lists.
7. **Location text says "Doddy doesn't keep it"** but the parking spot is kept in UserDefaults (ADR-301).
8. **Siri note readback default.** `DataFlowView` defaults `siriReadsNotes` to true. The Settings text says "it can be turned off".
9. **"What leaves" for the voice token server** still says "the selected voice provider/model"; since 9 Nov 2026 there is one voice and no model choice.
10. **Outlook** is in the Settings paragraph and the code (`backend/src/tools/catalog.ts`) but not in `ONLINE_ACCOUNTS.md`'s tool table.
11. **Deployment:** both Render services and the token server are deployed (`STATUS.md` "Live services"), each a few pull requests behind `main`, and several features are merged but off on the server (Section 5 says which). The privacy policy must describe only what runs at launch.
12. **Account deletion** is one button since the Doddy account (Settings › About › Your Doddy account › Delete), which runs both servers' `DELETE /v1/account` (Section 8). Exporting backend data, apart from kept notes and conversations, is not built.
13. **Website promises deletion on request** but lists no contact address.
14. **Google Fonts** load before consent; the footer says so, but a notice and a basis are needed.
15. **`PrivacyInfo.xcprivacy` exists only for the main app on `main`,** and declares six collected types, three as "not linked". A separate change in review (branch `claude/privacy-texts-match-code`) gives the widgets, Share and screen extensions their own manifests and makes the app's types the list in Appendix C, all linked, checked against `DataFlow` by a test. The Watch is paused.
16. **Voice greeting does not say "AI".** On-screen text and the answer when asked do.
17. **The Settings privacy paragraph, "What leaves this iPhone" (`DataFlow.rows`) and the website say notes stay on the iPhone.** With "Keep on Doddy's server" on they do not. `DataFlow` now has rows for it, but the Settings paragraph and the website text must be checked against Section 5.13 before launch.
18. **"Remember recent conversations" is about this iPhone.** Sending a conversation to the server is a separate switch, and does not need that setting. A person who turns the first off but the second on will have conversations on the server and none on the iPhone. Check that the consent text makes this clear.
19. **The server's key was generated in a working session and is in that session's transcript.** Treat it as exposed to the people who can read that transcript; decide whether to rotate it before real people's notes are stored (rotation is not built).
20. **Production code and settings differ.** The key is set on Render, but the memory code is not deployed, so nothing is kept today.
21. **Anthropic reads the best matches when you ask on the web.** The in-app consent says so; confirm the Anthropic terms for the API key's organisation (retention, training).
22. **The web chat sends account details to Anthropic (ADR-604):** document names, receipt summaries, account names and status, Logbook's counts. Check that this is covered by the Anthropic terms and the consent wording, and that "chats are kept in your browser" is acceptable on shared computers.
23. **Settings › Privacy says "Analytics and telemetry: Off (not built)"** and "What leaves this iPhone" says "no ads or analytics", while Logbook is on by default. The separate change above words the intro by Logbook's switch and adds `DataFlow.analyticsSummary`; `SettingsScreens.swift` still has to show it.
24. **The Apple Health consent for Messages says Doddy's server doesn't keep what you write.** The messaging server doesn't, but the Messages copy on Doddy's server does (5.4, 5.20). The separate change rewords it and asks again (consent version 2).
25. **The camera and photo-library permission texts say a photo never leaves the iPhone,** the Health text says Doddy keeps none of it, and the microphone, Motion and photo texts still offer OpenAI as a voice. The separate change rewrites them in all ten languages; Section 6 here is written from the code.
26. **Deleting the Doddy account does not delete the app's conversations at ElevenLabs** (security review, 12 Nov 2026). The phone line's and task calls' conversations are deleted. A proposal waits for the owner: record each conversation under the account when its token is issued, delete them with the account, and keep them 30 days at most (decision `2026-11-12-voice-conversations-per-account`).
27. **Messages and Logbook moved from opt-in to on by default** (9 Nov 2026), and the Messages copy on Doddy's server has no switch. Each is a change of consent model; the legal basis must be settled before outside testers. A proposal waits for the owner to start with less leaving the phone, item by item (decision `2026-11-12-privacy-defaults`); this draft describes today's defaults and must follow whatever is chosen.
28. **Calls Doddy places for you process a third party's voice and words** (Twilio transcription, ElevenLabs, Anthropic). The opening line says Doddy is an AI assistant; it does not say the call is transcribed or read by an AI.
29. **"What leaves this iPhone" on `main` has no rows** for the Doddy account, the Messages copy, Logbook or the screen look. The separate change adds them.
30. **The app has no on-screen AI disclosure** since 11 Nov 2026 (Section 7).

### B2. Checklist

**Controller and structure**
- [ ] Who is the controller (legal name, address, country)? Natural person or company?
- [ ] Is an EU or UK representative needed? Is a DPO needed?
- [ ] Privacy contact address, and a deletion-request process with a deadline.
- [ ] Which supervisory authority.

**Processors and agreements (data processing agreement, sub-processors, region)**
- [ ] ElevenLabs: agreement, sub-processors (including Google Gemini), region, EU residency, retention, zero-retention mode, recording on or off, deletion by conversation or user ID, training use.
- [ ] OpenAI: voice test and news writer; retention; region; agreement. Anthropic: Ask Doddy (ADR-587), Claude tools (ADR-564) and errands; retention; region; agreement.
- [ ] Google (Gemini via ElevenLabs; Google Analytics; Google Fonts; Calendar, Gmail and Drive APIs). Google OAuth verification and the wider Gmail compose scope (ADR-099).
- [ ] Anthropic (news writer). GNews. Twilio (Verify, SMS, calls). Apple (APNs, Maps, Siri, CloudKit).
- [ ] Composio and Monid: terms, regions, sub-processors, retention, agreement.
- [ ] Render (Frankfurt), Vercel (site, Blob, Functions), Upstash, Supabase (accounts and the backend database): agreements, log retention, IP logging, transfers.
- [ ] Serper, Kiwi.com, Shopify; before they are switched on, Duffel, Uber Direct and Coinbase (Section 9.3).

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
- [ ] Required-reason API audit: the app declares UserDefaults, system boot time, file timestamps and disk space (`scripts/check_privacy_manifest.sh`); the extensions' manifests are in the separate change (Appendix B, item 15).
- [ ] Privacy policy URL and support URL in App Store Connect.
- [ ] Account deletion rule (5.1.1(v)): the app requires a Doddy account and has Delete in Settings › About (Section 8). Check that it deletes enough, given item 26.

**Product changes the policy depends on**
- [ ] Turn on ElevenLabs agent authentication and limits; set retention before any outside tester (ADR-034, ADR-057, ADR-068).
- [ ] Real app sign-in for the backend (ADR-077).
- [ ] Waitlist: retention, contact address, rate limit, shared password.
- [ ] Self-host fonts, or notice; decide on Vercel Web Analytics notice.
- [ ] Fix the location text and the other mismatches in B1.
- [ ] Add Monid and the model behind the voice to `DataFlow`; `DataFlow` names Monid in the `doddyServer` row since then.

## Appendix C. Draft App Store Connect "App Privacy" answers

Based on the code (12 Nov 2026) and on the app manifest proposed in the separate change (`claude/privacy-texts-match-code`, whose `DataFlow.collectedData` names the rows of "What leaves this iPhone" behind each type and is checked against the manifest by a test). On `main` the manifest still declares six types, three as "not linked". Apple counts data that leaves the device and is kept by you or your partners longer than it takes to answer the request; data processed only on the device is not "collected". "Linked to you" means tied to your identity; since everyone has a Doddy account, every type below is answered as linked. Every row is **[CONFIRM]** until the owner and a lawyer review it. The text on this page is for the review; do not copy it into App Store Connect unchecked.

**Tracking: No.** The app does not track (`NSPrivacyTracking` false, no tracking domains, no advertising ID, no ATT prompt).

| Apple data type | Collected? | Linked to user? | Used for tracking? | Purpose | What and why | Status |
|---|---|---|---|---|---|---|
| Audio data | Yes | Linked | No | App functionality | Your voice to ElevenLabs, which keeps recordings of app conversations; calls Doddy places and the phone line run on ElevenLabs and are tied to the account (5.1, 5.7, 5.7a). The conversation user id sent to ElevenLabs by the app is a random install id. | **[CONFIRM: linked or not; ElevenLabs keeps it]** |
| Other user content | Yes | Linked | No | App functionality | Notes, lists, conversations, what you type in Messages and its copy for Doddy Web, tasks, Studio topics, files you ask for, a shared screen's picture, recaps, a call's brief and answer, results from your accounts (5.1, 5.4, 5.7a, 5.13, 5.17 to 5.19). | **[CONFIRM]** |
| Name | Yes | Linked | No | App functionality | Your first name on a call's brief and in About you shared with the voice; the name Apple or Google gives the account. | **[CONFIRM]** |
| Email address | Yes | Linked | No | App functionality | The Doddy account's email address at Supabase; Doddy's team sees it with the account (5.0). | **[CONFIRM]** |
| Phone number | Yes, if you use texts or calls | Linked | No | App functionality | Your verified number, at the messaging server and Twilio (5.6, 5.7). | **[CONFIRM]** |
| Contacts | Yes, when used | Linked | No | App functionality | Contact names and birthday day and month to ElevenLabs; the name and number of whom Doddy calls for you (5.1, 5.7a). | **[CONFIRM: missing from the manifest]** on `main`; added in the separate change |
| Photos or videos | Yes, when you send one | Linked | No | App functionality | A photo you send with a question in Messages, to the messaging server and Anthropic; kept by neither Doddy server; how long Anthropic keeps it is not verified (5.4). | **[CONFIRM: "collected" given Anthropic's retention]** |
| Health | Yes, when you send it | Linked | No | App functionality | The week's Apple Health summary: in Messages (Anthropic, and the Messages copy on Doddy's server) or to the voice (ElevenLabs) (5.20). | **[CONFIRM]** |
| Fitness | Yes, when you ask | Linked | No | App functionality | One day's steps, distance and floors (Motion & Fitness) to ElevenLabs; workouts in the Health summary (5.20). | **[CONFIRM]** |
| User ID | Yes | Linked | No | App functionality | The Doddy account's id on every Doddy server (5.0). | **[CONFIRM]** |
| Device ID | Yes | Linked | No | App functionality | The random device id that signs the iPhone in to Doddy's server, and the notification token (not the advertising id). | **[CONFIRM: a notification token may be a device ID]** |
| Product interaction | Yes, unless Logbook is off | Linked | No | Analytics; App functionality | Logbook's counts of how you use Doddy, for you on Doddy Web and for Doddy's team (5.16). | **[CONFIRM: on by default]** |
| Emails or text messages | **Open.** Texts you approve and texts you send Doddy's number (kept as notes); one email read through a connected account reaches ElevenLabs; trips read booking emails and send them to Anthropic (5.6, 5.10, 5.21). | Would be linked | No | App functionality | | **[CONFIRM: the owner and the lawyer decide (ADR-752, ADR-753, ADR-754). If yes, `PrivacyInfo.xcprivacy` gains `NSPrivacyCollectedDataTypeEmailsOrTextMessages`, linked, app functionality.]** With the separate change, `DataFlow.collectedData` must gain it in the same commit, or its test fails. |
| Search history | **Open.** Web, news and places searches go to Doddy's server and Monid, shopping searches to Serper, Shopify searches to Shopify; Doddy's server doesn't keep the words. | | No | App functionality | | **[CONFIRM]** |
| Precise or coarse location | Mostly no. Apple Maps is Apple. The time zone goes to the messaging server for quiet hours. A delivery's addresses would go to Uber (off). | | No | App functionality | | **[CONFIRM: does Apple Maps use count as collection by the app? Does a time zone count as coarse location? The lawyer decides.]** **[CONFIRM: Uber Direct before it is on]** |
| Purchases, financial info | No today. Flight booking (Duffel) and paying for web pages (Coinbase) are off; invoices to inFakt are not switched on. | | | | | **[CONFIRM before any is switched on]** |
| Diagnostics | No for the app. The servers keep request logs (IP, path, status). | | | | | **[CONFIRM: whether server logs count as "diagnostics" or "performance data"]** |
| Sensitive info | The app does not ask for it, but notes, voice, Messages and a shared screen may contain it. | | | | | **[CONFIRM]** |

Declared accessed APIs (app): UserDefaults `CA92.1`, system boot time `35F9.1`, file timestamp `C617.1`, disk space `E174.1` (`PrivacyInfo.xcprivacy`, `scripts/check_privacy_manifest.sh`). **[CONFIRM: the third-party SDKs' own manifests (ElevenLabs, LiveKit) in the archive]**

The website's analytics (Vercel Web Analytics, Google Analytics) are not part of the App Store label. They belong in the web privacy notice.
