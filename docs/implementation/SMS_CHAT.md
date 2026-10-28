# Texting Doddy, and calling him (ADR-653)

Owner, 28 Oct 2026, after the Instinct comparison (`docs/strategy/KONKURENCJA_INSTINCT_2026-10.md`): "zrób też sms i dzwonienie". Instinct is reached by text or a call, with no app. Doddy can now answer a text; calling him was already built (S2) and needs the owner's setup.

## Texting Doddy (new)

**What it does.** The person texts Doddy's number from their own verified number and gets one answer by text, from the same Claude as Messages (ADR-586): same prompt, model, daily caps and usage rows.

**Rules, enforced in code** (`server/messaging/src/smsChat.ts`):
- **Its own yes.** Settings › Notifications and texts › "Text with Doddy", shown only while "Texts from Doddy" is on. The consent text is `SMSChatConsent.text`, version `sms-chat-v1`, stored with the time (`PUT /v1/phone/sms-chat`, migration `014_sms_chat.sql`). Texts off, STOP, or a new number all turn it off; START brings it back with the earlier yes.
- **Text only.** No tools: by text Doddy can't search, send, buy or change anything (ASK-01). No notes are sent, so nothing from memory goes over a phone network. When Claude would offer a card (a file, a training plan), the reply says it is made in the app; nothing is made.
- **Only known senders.** A text from any other number, or from one with texting off, gets no reply and no model call (no cost, and no hint that the number is Doddy's).
- **Nothing kept.** The question is not stored or logged; the reply is queued encrypted (`MEMORY_ENCRYPTION_KEY`) and erased once Twilio accepts it, like every other text. Without the key texting Doddy is off.
- **Once per message.** The reply's idempotency key is `sms-chat:<Twilio MessageSid>`, so a retried webhook neither answers nor counts twice.
- **Honest failures, fixed wording:** daily cap reached, Claude unavailable or refused, Messages switched off on the server. Each is one fixed Polish line.
- **Length.** At most 600 characters (Polish letters make a text UCS-2, so at most 9 parts); longer answers end on a word with "… (dalej w aplikacji Doddy)". The question is in Polish by default (`locale: "pl"`); Claude answers in the language it was written in.
- **No conversation memory.** Each text is answered on its own; earlier texts are not sent with it.

**How it runs.** Twilio posts the text to `/webhooks/twilio/sms` (signature checked). STOP/START work as before. Any other text returns empty TwiML at once (Twilio waits at most 15 s), and the answer is made after and queued as an ordinary text for the worker.

**Checked here (Linux, 28 Oct):** messaging server `npm test` with Postgres 16: 407 of 407 (7 new in `test/smsChat.test.ts`); a mutation check (dropping the texting consent from the sender lookup) fails a test. DoddyCore `swift test` (Swift 6.1.2): 2,153 of 2,153 (2 new: the consent route and version, and reading an older server as off). String catalogs up to date (3 Polish lines). `scripts/ci.sh --core-only` on the whole tree: every step passes except "Messages screen's state tests", which fails the same way without this change (92 Swift 6.1 actor-isolation errors in `MessagesModelTests.swift`, from `662728e`). **Not checked:** `UpdatesSettingsView` and `UpdatesModel` are not compiled (no Xcode); no real text has gone through Twilio; nothing deployed.

**To turn it on (owner):**
1. Deploy `doddy-messaging` from this branch (runs migration 014).
2. Twilio console › the Messaging Service in `TWILIO_MESSAGING_SERVICE_SID` › Integration › incoming messages: check it sends a webhook to (STOP handling needs the same URL, so it may already be set) `https://doddy-messaging-zw1n.onrender.com/webhooks/twilio/sms`.
3. The number people text must be SMS-capable and in that Messaging Service's sender pool, and `DODDY_PHONE_NUMBER` should be that number (the app shows it as Doddy's number). Polish Twilio numbers often can't receive SMS; check the number's capabilities before buying.
4. Render's free plan sleeps after 15 minutes of silence. The first text after a pause reaches a sleeping service, and Twilio gives up on a webhook after 15 s; whether that text is still answered is **not tested** and it may be lost. A paid instance avoids this.

## Calling Doddy (built in S2, not switched on)

Everything is in code since 10 Oct (`S2_CALLS_STATUS.md`): Doddy's number, PIN, answers from an opt-in memory copy, notes into an inbox, "Call me now". **State on 28 Oct (read from Render's startup log and ElevenLabs):** the server has Twilio texts, webhooks and the tool secret (`sms`, `webhooks`, `calls` true) but `outboundCalls` false; the ElevenLabs agent "Doddy (phone)" exists (`agent_4801m5q2sq5xft6ab6k0mnyda04v`) but **no phone number is imported into ElevenLabs**, so a call to Doddy has nowhere to ring.

**Owner steps** (needs the Twilio account's SID and auth token, which this session doesn't have):
1. Buy or pick a Twilio number with voice (and SMS, for texting Doddy).
2. ElevenLabs › Phone numbers › Import from Twilio; assign it to "Doddy (phone)".
3. On Render `doddy-messaging`: `ELEVENLABS_PHONE_AGENT_ID=agent_4801m5q2sq5xft6ab6k0mnyda04v`, `ELEVENLABS_PHONE_NUMBER_ID=<the imported number's id>`, `DODDY_PHONE_NUMBER=<+48…>`.
4. Check the agent's call-start webhook points at `/webhooks/elevenlabs/call-start` (`setup-phone-agent.mjs --set-workspace-webhook`; it changes the workspace-wide setting, so read the script first).
5. In the app: Settings › Phone calls, set a PIN and turn on "Answer calls from my number"; then one real call.

**Still open (from `docs/decisions/calls.md` and S2):** privacy wording for call transcripts at ElevenLabs (30 days) and Twilio's call records, consent rules for Doddy calling the person, and that nothing in calls has run against the real services.
