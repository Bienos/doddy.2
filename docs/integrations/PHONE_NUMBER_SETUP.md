# Doddy's phone number: setup for texts (unit U0)

This is the runbook for unit U0 of ADR-490 (`docs/implementation/PHONE_SMS_MILESTONE.md`). At the end, Doddy has a Polish Twilio mobile number. It sends you texts and handles STOP and START through the messaging server (`server/messaging/`).

**Calls are not connected in U0.** Anyone who calls the number hears one fixed sentence and the call ends. Calls come in unit U1.

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

## When something goes wrong
| What you see | Likely cause |
|---|---|
| Render logs show Twilio webhooks answered with 403 | `PUBLIC_BASE_URL` isn't exactly the address Twilio calls: it must be https, the same host, and no path |
| The code never arrives | Poland isn't ticked in Geo Permissions, or the Verify SID is wrong. Look for a `twilio_verify_…` code in Render's log. |
| The test text says "Not delivered" | The Twilio error code tells you why: 21610 means you replied STOP, 21408 means Poland isn't enabled in Geo Permissions, 21614 means the number isn't a mobile |
| The server stops at start-up | The log names the missing or wrong variable |

**Known limit until unit U2:** the server retries a Twilio 500 error, so a test text could, rarely, arrive twice (ADR-490, section 4A of the plan).

## What leaves your iPhone in U0
- Your phone number and your consent go to the messaging server (Render, Frankfurt) and to Twilio, which checks the number and delivers texts.
- The text of an update is erased from the server's database once it reaches a final status (ADR-144).
- Twilio keeps its own message logs. Deleting them is built in unit U3.
- Your memories stay on your iPhone.

## Sources (read 2026-10-17)
- Twilio, submitting a regulatory bundle: https://help.twilio.com/articles/8338625205147
- Twilio, Poland regulatory requirements: https://www.twilio.com/en-us/guidelines/pl/regulatory
- Twilio, SMS Geo Permissions: https://www.twilio.com/docs/messaging/guides/sms-geo-permissions
- Twilio, Advanced Opt-Out: https://www.twilio.com/docs/messaging/tutorials/advanced-opt-out
- Twilio, Messaging Services (Smart Encoding): https://www.twilio.com/docs/messaging/services
- Twilio, TwiML Bins: https://www.twilio.com/docs/serverless/twiml-bins/getting-started
- Twilio, text-to-speech voices (Polish): https://www.twilio.com/docs/voice/twiml/say/text-speech
