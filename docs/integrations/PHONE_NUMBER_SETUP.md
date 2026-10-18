# Doddy's phone number: setup for texts (unit U0)

This is the runbook for unit U0 of ADR-490 (`docs/implementation/PHONE_SMS_MILESTONE.md`). At the end, Doddy has a Polish Twilio mobile number. It sends you texts and handles STOP and START through the messaging server (`server/messaging/`).

**Calls are not connected in U0.** Anyone who calls the number hears one fixed sentence and the call ends. Calls come in unit U1: see "Unit U1: connect calls" below, once the U0 checks pass.

Written 2026-10-17. Console paths are from Twilio's and Render's documentation on that date and may have moved a little since. Nothing in this runbook has been tried yet; your run is the first.

## Before you start
- **Twilio account** with billing set up.
- **Your Polish ID card** (dowód osobisty). It shows both your name and your PESEL. A passport works too.
- **Render account:** the one with "Patryk's workspace", where the `doddy` backend already runs (`DEPLOY_RENDER.md`).
- **Your iPhone** with a Debug build from Xcode (`make project-iphone`, scheme `Doddy`).
- **A terminal** with `openssl`, to make one key.

**Time:** about an hour of clicking, plus up to 3 business days while Twilio checks your ID.

**Never paste a secret** (Twilio Auth Token, the encryption key, codes) into chat, a file or a commit. Type secrets only into Render's dashboard.

## 1. Twilio account
1. If the account is still a trial, upgrade it. Trial accounts are limited, and the number needs a paid account.
2. Open **Messaging → Settings → Geo Permissions**. Make sure **Poland** is ticked, and leave countries you don't use off. New accounts allow the country of the phone number you signed up with.

## 2. Identity bundle (Poland, mobile, you as a person)
1. Open **Phone Numbers → Regulatory Compliance → Bundles → Create a Regulatory Bundle**.
2. Country **Poland**, number type **Mobile**, end user **Individual**.
3. Enter your name exactly as it is on your ID, any address (mobile numbers accept an address anywhere), and your PESEL as the identity document number.
4. Upload a photo or scan of your ID card. It proves both your identity and your PESEL.
5. Name the bundle `Doddy mobile PL`, add your email, and submit.
6. Twilio's help pages say the review takes up to 2 to 3 business days. The result comes by email from numbers-regulatory-review@twilio.com. If it is rejected, fix what the email names and use **Edit and Resubmit**.

## 3. Buy the number
1. Open **Phone Numbers → Manage → Buy a number**.
2. Country **Poland**, capabilities **Voice** and **SMS**. Under **Advanced**, choose type **Mobile**.
3. Pick a number starting with +48 73 or +48 79 and buy it ($4.00 a month on 2026-10-17). When asked, choose the approved bundle.

## 4. TwiML Bin for calls (until U1)
1. Open **TwiML Bins** (under Developer tools) and create one named `Doddy calls not connected` with this TwiML:

   ```xml
   <?xml version="1.0" encoding="UTF-8"?>
   <Response>
     <Say language="pl-PL" voice="Polly.Ola-Neural">Tu Doddy, asystent AI. Rozmowy telefoniczne nie są jeszcze włączone. Do usłyszenia.</Say>
     <Say language="en-US" voice="Polly.Joanna">This is Doddy, an AI assistant. Phone calls aren't connected yet. Goodbye.</Say>
     <Hangup/>
   </Response>
   ```
2. Open **Phone Numbers → Manage → Active numbers →** your number. Under Voice, set **A call comes in** to TwiML Bin `Doddy calls not connected`. Set **Primary handler fails** to the same bin, then save.

In U1 "A call comes in" changes to the server. The fallback keeps this bin, so callers still hear an honest sentence if the server is down.

This TwiML records nothing. Don't add `<Record>`: recording stays off (ADR-490, ADR-158).

## 5. Verify service (the code that proves the number is yours)
1. Open **Verify → Services → Create new**.
2. Friendly name `Doddy`: it appears in the code text. Turn on the **SMS** channel and leave the others off.
3. Copy the **Service SID**. It starts with `VA`.

## 6. Messaging Service
1. Open **Messaging → Services → Create Messaging Service** and name it `Doddy`. When Twilio asks what it is for, pick the closest option (for example "Engage in a discussion").
2. **Sender Pool:** add your new number.
3. **Integration:**
   - Under Incoming Messages, choose **Send a webhook**.
   - Request URL: `https://<your server address>/webhooks/twilio/sms`, method **HTTP POST**. You get the address in step 7; come back then.
   - Leave the fallback URL and the delivery status callback empty. The server asks for a receipt on each text itself.
4. **Opt-Out:**
   - Turn on **Advanced Opt-Out**.
   - Keep the standard keywords (STOP, START, HELP and the others). The server knows exactly these words (`server/messaging/src/sms.ts`).
   - Add `POMOC` to the **Help** keywords.
   - Don't add other opt-out words here unless they are added to `sms.ts` too. Otherwise Twilio blocks texts while the server still thinks they are on.
   - Don't use **Country Code** keywords for +48: they replace the standard ones for Poland.
   - Replace the three confirmation messages. These are suggestions; please check the Polish:

   | Keyword group | Confirmation message |
   |---|---|
   | Opt-out (STOP) | `Doddy: nie wyślę Ci już SMS-ów. Wyślij START, żeby je włączyć. / Doddy won't text you any more. Text START to turn texts back on.` |
   | Opt-in (START) | `Doddy: SMS-y są znowu włączone. Wyślij STOP, żeby je wyłączyć. / Texts from Doddy are back on. Text STOP to stop them.` |
   | Help (HELP, POMOC) | `Doddy to asystent AI i pisze tylko do właściciela aplikacji Doddy. STOP wyłącza SMS-y. / Doddy is an AI assistant that texts only its owner. Text STOP to stop.` |

   Twilio sends these to anyone who texts the keyword; Polish carriers expect that. Each one has Polish letters, so it costs about 3 segments, roughly $0.14.
5. **Content Settings:** turn **Smart Encoding off**, so Twilio never changes the text you approved.
6. Copy the **Messaging Service SID**. It starts with `MG`.

## 7. The messaging server on Render
Don't use **New → Blueprint**: `render.yaml` would also create a separate paid worker and a second `doddy` backend. Create two things by hand instead.

1. **New → Postgres:**
   - name `doddy-db`, region **Frankfurt**, PostgreSQL **16**, a paid plan (`render.yaml` uses Basic-256mb; Render shows the price);
   - after it is created, copy the **Internal Database URL**.
2. **New → Web Service:**
   - repo `Bienos/doddy.2`, branch `claude/loving-dirac-uuxoux` (the default branch; its `server/messaging` is the same as on this plan's branch);
   - name `doddy-messaging`, region **Frankfurt**, runtime **Node**, root directory `server/messaging`;
   - build `npm ci && npm run build`, start `npm start`, health check path `/healthz`;
   - plan **Starter** (paid), auto-deploy **off**.
3. Render shows the service's address (`https://doddy-messaging….onrender.com`) as soon as the service exists. Add these under **Environment**:

| Key | Value |
|---|---|
| `NODE_VERSION` | `22` |
| `DATABASE_URL` | the Internal Database URL from step 7.1 |
| `RUN_WORKER_IN_WEB` | `1`: this one service also sends the queued texts, so no separate worker is needed |
| `TRUST_PROXY_HOPS` | `1` |
| `VERIFY_DAILY_CAP` | `20`: code texts per day for the whole server (you are the only user) |
| `PUBLIC_BASE_URL` | the service's address, `https://…onrender.com`, with no path. Twilio's signatures are checked against it, so it must be exactly the address Twilio calls. |
| `TWILIO_ACCOUNT_SID` | **secret.** Twilio Console → Account Info |
| `TWILIO_AUTH_TOKEN` | **secret.** Same place. The server also uses it to check that webhooks come from Twilio. |
| `TWILIO_MESSAGING_SERVICE_SID` | `MG…` from step 6 |
| `TWILIO_VERIFY_SERVICE_SID` | `VA…` from step 5 |
| `MEMORY_ENCRYPTION_KEY` | **secret.** Run `openssl rand -base64 32` on your computer and paste the output. Keep a copy in your password manager: if it is lost, queued texts can't be read and are never sent. |

Leave these out for now:
- `ELEVENLABS_*` and `DODDY_PHONE_NUMBER`: calls, unit U1;
- `APNS_*`: notifications, optional, needs Apple's `.p8` key;
- `ANTHROPIC_API_KEY`, `OPENAI_API_KEY` and `GNEWS_API_KEY`: daily news, optional.

4. Deploy, then check:
   - The log line `configured features` should show `"sms":true` and `"webhooks":true`.
   - `https://<address>/healthz` should answer `{"ok":true}`.
   - If the server refuses to start, the log names the variable (never its value).
5. Go back to step 6.3 and put the address into the Messaging Service's webhook.

## 8. Your iPhone (Debug build)
1. Run `Doddy` from Xcode on your iPhone.
2. Open **Settings → Notifications and texts**. In **Server (development)**, paste `https://<address>` and press Return.
3. Under **Text messages**, type your number (+48 …) and tap **Text me a code**. Enter the code and tap **Confirm**.
4. Turn on **Texts from Doddy**. This records your consent, wording `sms-v1`.
5. Tap **Send a test text**.

A Release or TestFlight build ignores the development field (ADR-175). Send Claude the address, and it goes into `ServerConfig.defaultBaseURL` in the app.

## 9. The U0 checks
Send Claude the results: what you saw, the app's wording, or Twilio's error code. Never send secrets or codes.

| # | Check | Expected |
|---|---|---|
| 1 | Open `https://<address>/healthz` | `{"ok":true}` |
| 2 | The code text | Arrives within a minute. It may come from a Twilio sender rather than Doddy's number. |
| 3 | The test text | Arrives from Doddy's +48 number. **Last test** says "Delivered", or "Handed to Twilio for delivery" if your network sends no receipt. |
| 4 | Reply `STOP` to Doddy's number | Twilio's Polish and English confirmation arrives. After you reopen the screen, the app says "You replied STOP, so texts are blocked by the carrier…" and a test text is refused. |
| 5 | Reply `START` | The confirmation arrives, and a new test text arrives. |
| 6 | Reply something else, like "cześć" | Nothing comes back. Doddy doesn't read texts until unit U3. |
| 7 | Call Doddy's number | The fixed sentence in Polish, then English, then the call ends. |
| 8 | Render logs for the steps above | Request lines and counts only: no phone numbers, no message text. |
| 9 | Twilio Console → Monitor → Logs → Messaging | The test text shows `delivered` (or `sent`). |

Optional: tap **Delete my Doddy messaging data**, check that the number is gone from Settings, then verify again.

## Unit U1: connect calls (after the U0 checks pass)
Calls reach the messaging server first (ADR-490). It lets your number through to the "Doddy (phone)" agent at ElevenLabs. Anyone else hears one fixed sentence and the call ends. **Don't import the number into ElevenLabs.**

1. **Deploy the U1 code.** It is on branch `claude/awesome-cray-2lb9ia` until it is merged. In Render, set the `doddy-messaging` service's branch to it, or to the default branch once U1 is merged, and deploy. The database update (migration 008) runs by itself at start-up.
2. **Twilio voice permissions:** under **Voice → Settings → Geo permissions**, tick Poland (low-risk numbers), so Doddy can call your Polish number. Without it, Twilio refuses with error 21215.
3. **Make the tool secret:** run `openssl rand -base64 32` and keep the output for the next two steps. The server refuses a secret shorter than 32 characters.
4. **Create the phone agent** from a checkout of the repo on your computer:
   ```sh
   cd server/messaging && npm ci
   ELEVENLABS_API_KEY=… PUBLIC_BASE_URL=https://<address> ELEVENLABS_TOOL_SECRET=… node scripts/setup-phone-agent.mjs --dry-run
   ELEVENLABS_API_KEY=… PUBLIC_BASE_URL=https://<address> ELEVENLABS_TOOL_SECRET=… node scripts/setup-phone-agent.mjs
   ```
   - The script creates a workspace secret, the agent's three tools and the agent, with μ-law audio for phone lines and no audio recording.
   - It prints `ELEVENLABS_PHONE_AGENT_ID` and the Twilio settings for step 6.
   - The keys sit only in that terminal command on your own computer.
5. **Render → doddy-messaging → Environment:** add these, then deploy again.

   | Key | Value |
   |---|---|
   | `ELEVENLABS_API_KEY` | **secret.** ElevenLabs → API keys |
   | `ELEVENLABS_TOOL_SECRET` | **secret.** The value from step 3 |
   | `ELEVENLABS_PHONE_AGENT_ID` | Printed by the script in step 4 |
   | `DODDY_PHONE_NUMBER` | Doddy's number, as `+48…`. It is the caller ID of Doddy's calls, and the app shows it with a Call button. |

   The log line `configured features` should now show `"calls":true` and `"outboundCalls":true`.
6. **Twilio → Phone Numbers → Active numbers →** Doddy's number, under Voice:
   - **A call comes in:** Webhook, HTTP POST, `https://<address>/webhooks/twilio/voice`
   - **Primary handler fails:** keep the TwiML Bin `Doddy calls not connected` from step 4 of U0
   - **Call status changes:** `https://<address>/webhooks/twilio/call-status`
7. **On your iPhone, Settings → Phone calls:** set a PIN, turn on **Answer calls from my number** and **Doddy may call me**. **Let Doddy use my memories on calls** is optional.

### The U1 checks
Send Claude what you saw and heard. Never send the PIN, keys or the tool secret.

| # | Check | Expected |
|---|---|---|
| 1 | Call Doddy's number from your phone | Doddy answers ("Hi, this is Doddy, an AI assistant…") and asks for your PIN before anything about your memories |
| 2 | After the right PIN, ask about something you saved (memories on calls turned on) | An answer from your memories. **If Doddy says it can't use its memory on this call, tell Claude:** that means the call's session key didn't arrive through `register-call`, which is the one thing these checks prove for the first time. |
| 3 | Call from another phone, or with your number withheld | The fixed sentence, "…This number only works for its owner. Goodbye.", and the call ends |
| 4 | Turn off **Answer calls from my number**, then call | "…Phone calls are turned off in the Doddy app. Goodbye." Turn it back on afterwards. |
| 5 | Tap **Call me now** and answer | Your phone rings from Doddy's number, Doddy speaks after you answer, and **Recent calls** shows "answered" |
| 6 | Tap **Call me now** and don't answer | After about 30 seconds of ringing, **Recent calls** shows "no answer". Doddy doesn't call again. |
| 7 | ElevenLabs → the agent's conversations | The calls from checks 1, 2 and 5 are there with transcripts and no audio |
| 8 | Render logs | `call_refused` lines with a reason only, never a phone number |
| 9 | Twilio → Monitor → Logs → Calls | Your calls, with no recordings |

## Unit U2: texts you approve (after the U0 checks pass)
Doddy can text your own number, and only yours, when you ask it to in a conversation ("text me the parcel code"). A card shows the exact text first; nothing is sent until you tap **Send text** (ADR-493).

1. **Deploy the U2 code**, the same way as U1 (branch `claude/awesome-cray-2lb9ia` until it is merged). The database update (migration 009) runs by itself at start-up. No new Render keys are needed.
2. **Build the iPhone app from the same branch** in Xcode. With OpenAI voice (the default), the app brings the new `text_me` tool with it.
3. **ElevenLabs voice only:** the live agent doesn't have `text_me` yet. Ask Claude to sync it, or follow `voice-agent/README.md` ("Source of truth and syncing"): add the tool and the new prompt lines, then run the compare step.
4. **On your iPhone, Settings → Notifications and texts:** your number must be verified and texts turned on (U0 checks 3 and 4).

### The U2 checks
Send Claude what you saw. Never send codes or keys.

| # | Check | Expected |
|---|---|---|
| 1 | In a conversation, say "text me the word banana" | A card: "Send this text to you?", the last three digits of your number, and the text. Doddy says only one short line before it. |
| 2 | Tap **Send text** | A text from Doddy's number with exactly that text. Doddy says it was delivered, or that Twilio accepted it and delivery isn't confirmed yet. It never says "delivered" before Twilio's receipt. |
| 3 | Ask again and tap **Don't send** | Nothing arrives; Doddy accepts it |
| 4 | Ask for a text with Polish letters, longer than 70 characters | It arrives exactly as the card showed; the card says "Sent as 2 SMS parts" |
| 5 | Turn texts off in **Settings → Notifications and texts**, then ask | Doddy says texts are switched off; no card, nothing arrives. Turn them back on. |
| 6 | Ask Doddy to text someone else, e.g. "text Marta that I'm late" | Doddy uses the Messages draft instead (`draft_message`); it never texts another number itself |
| 7 | **What Doddy did** | A row "Text you from Doddy's number", with no text in it |
| 8 | Render logs | No text of any message, only ids and codes |

## Unit U3: texts to Doddy (after the U0 checks pass)
You can text Doddy's number. Each text waits as a note in the app, or, with replies on, Doddy (Claude, on the server) answers by text. Texts from any other number are dropped without a reply (ADR-494).

1. **Deploy the U3 code**, as for U1 and U2. The database update (migration 010) runs by itself at start-up.
2. **For replies only, Render → doddy-messaging → Environment:**

   | Key | Value |
   |---|---|
   | `ANTHROPIC_API_KEY` | **secret.** Anthropic Console → API keys. Also turns on the AI writer for daily news if it wasn't on. Set a monthly spending limit in the Anthropic Console too. |
   | `TEXT_REPLY_MODEL` | Optional. Default `claude-opus-5-5` (decision 7), about $0.03 a reply. |
   | `TWILIO_RECORD_DELETE_AFTER_HOURS` | Optional. Default 24: Doddy deletes its message and call records at Twilio a day after they finish. `0` deletes them after about 2 minutes. |

   The log line `configured features` should show `"textReplies":true` and `"twilioDeleteAfterMinutes":1440`.
3. **Twilio:** nothing new. Texts already reach the server through the Messaging Service webhook from U0 step 6.
4. **Build the iPhone app from the same branch.** In **Settings → Phone calls → Texts to Doddy**, turn on **Accept texts from my number** (read the wording under it). For replies, also **Doddy replies by text**; for answers from your notes, **Replies may use my memories** (it needs **Memory on calls**).

### The U3 checks
Send Claude what you saw. Never send codes or keys.

| # | Check | Expected |
|---|---|---|
| 1 | Replies off: text Doddy's number "Kupić mleko" | No answer. In **Settings → Phone calls**, a note "Kupić mleko" under **Notes waiting for you**, marked "From your text" |
| 2 | Tap **Save to memories** on it | It's in your memories; the note leaves the list |
| 3 | Text Doddy from another phone | Nothing back, no note. Render shows `text dropped` with `not_allowed` and no number |
| 4 | Replies on: text "What can you do by text?" | One answer from Doddy's number within a minute, at most 3 SMS parts |
| 5 | Text "Remember to buy batteries" | The answer says it left a note to confirm; the note appears in the app |
| 6 | Text "Text my sister that I'm late" | The answer says Doddy can't text anyone else |
| 7 | With **Replies may use my memories** on, ask by text about something you saved | The answer uses that note. With it off, Doddy says it can't see your notes by text |
| 8 | Text `POMOC` | Only Twilio's help message; no note, no AI answer |
| 9 | **Export phone and text history**, then share it to yourself | A JSON file with your calls, text statuses and waiting notes; no other numbers |
| 10 | The next day, Twilio Console → Monitor → Logs → Messaging | Yesterday's texts are gone (Twilio may keep deleted bodies in backups for up to 30 days) |
| 11 | Render logs | `text received` and `text reply` lines with ids, states and costs only, never a text |

## When something goes wrong
| What you see | Likely cause |
|---|---|
| Render logs show Twilio webhooks answered with 403 | `PUBLIC_BASE_URL` isn't exactly the address Twilio calls: it must be https, the same host, and no path |
| The code never arrives | Poland isn't ticked in Geo Permissions, or the Verify SID is wrong. Look for a `twilio_verify_…` code in Render's log. |
| The test text says "Not delivered" | The Twilio error code tells you why: 21610 means you replied STOP, 21408 means Poland isn't enabled in Geo Permissions, 21614 means the number isn't a mobile |
| The server stops at start-up | The log names the missing or wrong variable |
| U1: every caller, you included, hears "Phone calls aren't connected yet" | One of `ELEVENLABS_API_KEY`, `ELEVENLABS_PHONE_AGENT_ID`, `ELEVENLABS_TOOL_SECRET` or `MEMORY_ENCRYPTION_KEY` is missing on Render |
| U1: you hear "I can't talk right now" | The server didn't get a usable answer from ElevenLabs `register-call`. Render's log shows `call_not_connected` with a code, such as `elevenlabs_401` for a wrong key or `elevenlabs_422` for a wrong agent id. |
| U1: Call me now says the phone service couldn't place the call | Twilio refused it. Error 21215 means Poland isn't ticked under Voice → Settings → Geo permissions. |
| U2: Doddy says your number changed after the card was shown | You verified a different number while the card was open. Ask again for a new card. |
| U2: Doddy says it reached the most texts allowed for today | 20 approved texts a day per account (`contact_policy` in `docs/trust/config/doddy_rules.yaml`) |
| U3: your text gets no note and no answer | **Accept texts from my number** is off, or the Messaging Service webhook isn't the server. Render's `text dropped` line gives the reason. |
| U3: "Doddy couldn't answer that just now" | Render's `text reply` line has the code: `anthropic_401` (wrong key), `anthropic_429` (rate or spending limit), `refusal`, `deadline`. Your text is kept as a note. |
| U3: the replies switch can't be turned on | Replies are texts from Doddy, so texts in **Notifications and texts** must be on (and no STOP since), and `ANTHROPIC_API_KEY` must be set |

**Since U2:** a Twilio 500, 502 or 504 is never retried. The text shows as "Unclear whether it was sent" while the server looks for it in Twilio's message list; it is never sent twice (ADR-493).

## What leaves your iPhone
- Your phone number and your consent go to the messaging server (Render, Frankfurt) and to Twilio, which checks the number and delivers texts.
- The text of an update is erased from the server's database once it reaches a final status (ADR-144).
- Twilio keeps its own message logs. Deleting them is built in unit U3.
- **U3:** texts you send Doddy's number go through Twilio to the messaging server and wait there as encrypted notes until you save or discard them. With replies on, your text (and, if you allowed it, the notes it finds) goes to Anthropic to write the answer. Doddy deletes its records at Twilio a day after each text or call by default.
- **U2:** a text you approve goes to the messaging server and then to Twilio. The server stores it encrypted with `MEMORY_ENCRYPTION_KEY` (set in step 7) and erases it once the text has a final status. It keeps a hash of it only while an unclear outcome is being checked.
- Your memories stay on your iPhone.

## Sources (read 2026-10-17)
- Twilio, submitting a regulatory bundle: https://help.twilio.com/articles/8338625205147
- Twilio, Poland regulatory requirements: https://www.twilio.com/en-us/guidelines/pl/regulatory
- Twilio, SMS Geo Permissions: https://www.twilio.com/docs/messaging/guides/sms-geo-permissions
- Twilio, Advanced Opt-Out: https://www.twilio.com/docs/messaging/tutorials/advanced-opt-out
- Twilio, Messaging Services (Smart Encoding): https://www.twilio.com/docs/messaging/services
- Twilio, TwiML Bins: https://www.twilio.com/docs/serverless/twiml-bins/getting-started
- Twilio, text-to-speech voices (Polish): https://www.twilio.com/docs/voice/twiml/say/text-speech
- Twilio, voice geo permissions: https://www.twilio.com/docs/sip-trunking/voice-dialing-geographic-permissions
- ElevenLabs, register Twilio calls: https://elevenlabs.io/docs/eleven-agents/phone-numbers/twilio-integration/register-call
