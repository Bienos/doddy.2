# Doddy calls on your behalf: architecture and open questions

Date: 2026-10-18. Owner request: "Doddy makes short outbound calls in Polish on the user's behalf, asks first, and brings the answer back as a card." ADRs 500–507 in `DECISIONS.md`. Build status: `docs/implementation/CALL_CASES_STATUS.md`.

This page is the decision. It says what was chosen, why, what the code enforces, and what is still open. It does not say anything works on a real phone: see the status doc for what has run.

## What a call is (v1)
- **Kind:** ASK. One question (for example "Czy laptop z serwisu jest gotowy?"). Doddy listens, may ask at most one clarifying question, thanks the person and ends the call.
- **Language:** Polish only. Destinations: Polish numbers only.
- **Never commits.** If the other side asks for anything outside the brief, Doddy says it will check with the user and call back.
- **Asks first.** Nothing is dialled until the user approves a brief card. The card shows:
  - who is being called (name and number) and where the number came from;
  - the goal in one sentence;
  - the exact opening line and question;
  - the facts Doddy may say (only the ones the user ticked);
  - what Doddy must not do;
  - the maximum duration (default 4 min).
- **After the call:** an answer card. It has:
  - a summary;
  - the key answer quoted from the transcript;
  - a confidence flag;
  - the transcript, stored on the iPhone;
  - a suggested next step;
  - the cost;
  - receipts showing what was deleted from the server and from ElevenLabs.
- **Failed calls** (no answer, busy, voicemail, wrong number, phone menu, technical failure) get an honest card and an option to retry at a set time.
- **During the call:** a live view with the transcript and a big **Przejmij** (take over) button, plus **Zakończ** (end now). A Live Activity shows the status and time, never words.
- **Rehearsal:** the user can practise the call first, with Doddy playing the receptionist, then choose "Doddy dzwoni" or "Dzwonię sam" (the script on screen).

## Docs checked before choosing (2026-10-18)
| Source | What it said | What it decided |
|---|---|---|
| [ElevenLabs register-call](https://elevenlabs.io/docs/eleven-agents/phone-numbers/twilio-integration/register-call.md), [API](https://elevenlabs.io/docs/api-reference/twilio/register-call) | Our server creates the Twilio call. When it is answered, Twilio asks our webhook; we register the call with ElevenLabs, which returns TwiML connecting the call to the agent over a WebSocket. Agent audio must be μ-law 8000 Hz. ElevenLabs can't transfer these calls. | **Chosen.** Every Twilio parameter is ours. We don't need ElevenLabs transfers: takeover is our own Twilio redirect. |
| [ElevenLabs Twilio outbound-call](https://elevenlabs.io/docs/api-reference/twilio/outbound-call) (the S2 "Call me now" path) | Now takes `telephony_call_config` (ring timeout, Twilio AMD) and a per-call `max_duration_seconds` override; returns `conversation_id` and `callSid`. | Not chosen. ElevenLabs creates the call, so its status callbacks and limits are ElevenLabs', not ours, and we couldn't run a final check at the moment the call is answered. "Call me now" stays on it, unchanged. |
| [ElevenLabs real-time monitoring](https://elevenlabs.io/docs/eleven-agents/guides/realtime-monitoring.md) | WebSocket with live transcript and control commands. **Enterprise-only.** | Can't be used. The live transcript comes from Twilio. |
| [Twilio `<Transcription>`](https://www.twilio.com/docs/voice/twiml/transcription), [Real-time transcription API](https://www.twilio.com/docs/voice/api/realtime-transcription-resource) | Live transcription of both sides; `transcription-content` callbacks carry `TranscriptionData` (`transcript`, `confidence`), `Final`, `Track`, `SequenceId`. A `<Start>` fork survives redirects until stopped. Persisting transcripts needs an Intelligence Service, which we don't pass. | Live transcript source. Stopped at takeover. |
| [ElevenLabs post-call webhooks](https://elevenlabs.io/docs/eleven-agents/workflows/post-call-webhooks.md), [SDK signature code](https://github.com/elevenlabs/elevenlabs-js/blob/main/src/wrapper/webhooks.ts) | `post_call_transcription` carries the transcript, `metadata.cost`, `termination_reason` and the dynamic variables we passed. Header `ElevenLabs-Signature: t=<unix>,v0=<hex HMAC-SHA256(secret, "t.rawBody")>`, 30 minute tolerance. The webhook is set for the whole workspace. | The final transcript and voice cost come from here. We pass `doddy_attempt` to link the conversation to our attempt. Payloads from other agents (the S2 memory agent) are dropped before parsing. |
| [Twilio Call resource](https://www.twilio.com/docs/voice/api/call-resource) | A live call can be updated with new TwiML (`Twiml`/`Url`), ended (`Status=completed`), and given a new `TimeLimit`. `Price` is filled only after the call ends, is negative, and excludes add-ons. At most 4 media forks per call, shared by AMD, transcription (2 for both tracks) and streams. | Takeover and Zakończ are redirects of our own call. No Twilio AMD: it would use the 4th fork, its verdict arrives after Doddy has started speaking, and it often mistakes a receptionist's long greeting for a machine. |
| [ElevenLabs voicemail detection](https://elevenlabs.io/docs/eleven-agents/customization/tools/system-tools/voicemail-detection.md) | System tool; with no voicemail message the agent hangs up. | Voicemail handling, with no message left. |

## The design
**Our server places the Twilio call. ElevenLabs is only the voice.** The user approves one stored payload, and exactly those bytes are sent.

1. **Brief → preview.** The app sends the brief to `POST /v1/call-cases`. Only ticked facts ever leave the iPhone. The server then:
   - checks the brief and every limit below;
   - compiles the whole provider payload once: Twilio `To`, `From`, `TimeLimit`, ring timeout, no recording, and the exact variables the agent receives;
   - encrypts it (AES-256-GCM, bound to the account and case);
   - stores an HMAC digest of it;
   - returns a preview made from that payload. The card shows the server's preview, not the app's own rendering, so the user approves what will actually be sent.
   - The payload never changes: editing the brief creates a new case.
2. **Approve.** `POST /v1/call-cases/:id/approve {digest}` creates an attempt.
   - The attempt is tied to the case and that digest by a database foreign key, so Postgres refuses an approval of anything else.
   - The approval is valid for 10 minutes.
3. **Dial.** One function claims the attempt in a database update. The claim commits before the request to Twilio, so a crash can't dial twice. In the same transaction it:
   - checks the state is `scheduled` and now is inside the approved window;
   - writes the pending cost items;
   - writes a content-free dial log row.

   If Twilio refuses, the attempt is `not_placed`. A timeout is `unknown` and is never redialled.
4. **Answer.** When the call is picked up, Twilio asks `/webhooks/twilio/task-call/answer`. That handler:
   - checks Twilio's signature, that the call is the one we created, and the kill switch, hours and agent checks again;
   - registers the call with ElevenLabs (once, 5 s limit);
   - checks the returned TwiML is exactly one stream to an ElevenLabs host;
   - adds live transcription in front of it.

   Any failure plays a short Polish apology that says it is an AI assistant, then hangs up. It is never silent.
5. **First words are not left to the model.** The agent's first message is a variable that our server fills: the opening line plus the question, spoken word for word. The model only handles what comes after.
6. **During the call.**
   - Live lines arrive from Twilio and are stored encrypted.
   - The app reads them every second.
   - The Live Activity gets the phase (ringing, talking, ended) by push.
   - **Zakończ**, the kill switch and the time limit all use one end-call function: a fixed Polish goodbye, then hang up.
7. **Time limit.** At `answered + max duration` the server plays the goodbye and ends the call. Twilio's `TimeLimit` (max + 20 s) is the hard backstop if our server is down. The agent's own limit is set above both, so our code decides.
8. **Takeover (Przejmij).**
   1. The server rings the user's verified phone from Doddy's number. The user hears "Doddy rozmawia z … Naciśnij 1, aby przejąć rozmowę."
   2. Only after 1 is pressed, the other person's call is redirected: live transcription stops, a Polish voice says "Łączę z <imię>", and both join a private conference.
   3. Until then Doddy keeps talking, so a missed or voicemail-answered takeover loses nothing.
   4. The call's time limit is raised only once both are in the conference.

   Doddy does not listen to or transcribe the user's own conversation.
9. **After the call.** The ElevenLabs post-call webhook and Twilio's status start a job on the server. It:
   - decides the outcome: answered, no answer, busy, failed, voicemail, phone menu, wrong number, taken over;
   - finds the answer. **The quoted answer is always a span of the transcript itself.** A model, if one is configured, may only point to which reply and which words. Without a model, the card quotes the other person's replies after the question.
   - computes confidence in code;
   - checks Doddy's own lines for commitment words and for numbers that weren't in the brief, and lists any as warnings on the card;
   - records the costs;
   - sends a push that says only that the answer is ready.

   If the ElevenLabs webhook never arrives, the card is built from the live transcript, marked as less reliable.
10. **Deletion.** Each step writes a receipt to `server_data_deletions`: what, where, why, and whether it was confirmed. Receipts hold no content.
    - After processing, the ElevenLabs conversation is deleted. It counts as deleted only when a second request confirms it is gone.
    - A sweeper deletes any leftover conversation of the call agent older than 24 hours.
    - When the app has saved the result on the iPhone, it acknowledges it, and the server deletes the result, the live lines and the brief.
    - Results nobody fetches are deleted after 7 days.
    - Deletion jobs at ElevenLabs survive account deletion.
    - Twilio keeps its call log (numbers, times, duration, price) under Twilio's own retention. No audio and no text is kept there. The receipt says this.
11. **Retry at a set time.** The failed card offers only times where the whole call fits inside the calling hours.
    - Choosing one is a new approval of the same payload for a 10-minute window at that time.
    - If the server misses the window, the attempt expires; it never dials late.
    - At most 2 retries, and only while no earlier attempt reached a conversation. An attempt whose voice connected only to voicemail, a phone menu or a wrong number doesn't count as a conversation (`RETRYABLE_OUTCOMES` in `server/messaging/src/taskCalls/result.ts`, mirrored by `CallOutcome.isRetryable` in the app).
    - The server takes an approval for a time up to 24 hours ahead, while the card's payload is kept (at most two days after the card was made). The app offers only such times.

## What the code enforces (by construction)
These hold even if the model, the prompt or the app misbehaves. Each has a test in `server/messaging/test/taskCalls*.test.ts`.

**Calling only what was approved:**
- **No call without an approval** of the exact stored payload, inside its 10-minute window. Postgres refuses a mismatched approval (composite foreign key); dialling outside the window is refused by a CHECK constraint.
- **What reaches Twilio and ElevenLabs equals the approved payload exactly,** plus one attempt id. Request bodies are strict, so approve, end, takeover and ack can't carry a number, fact or duration.
- **Destinations:** an allowlist, not a blocklist. Allowed:
  - `+48` followed by 9 digits with a Polish mobile or geographic prefix;
  - `800` freephone numbers.

  Everything else is refused:
  - 112, 997, 998, 999 and every short number, in any spelling;
  - 116 and 118 numbers;
  - premium 70x numbers;
  - shared-cost 801 and 804 numbers;
  - 39;
  - foreign numbers;
  - Doddy's own number;
  - the user's own number.

  Checked when the brief is created, at approval, at dial and at answer.

**When and how often:**
- **Hours:** the whole call (ring + max duration + 20 s) must fit inside 8:00–23:00 Europe/Warsaw. Every day of the week (see the open questions). Checked at dial and again at answer.
- **Rate limits:**
  - per user: 3 an hour and 10 a day;
  - per destination: 2 a day from one user and 3 a day from all users, at least 15 minutes apart;
  - one live call per account;
  - a global daily cap.

  Destination limits count from a log that holds only hashes, so they survive account deletion. Environment variables can lower these limits but not raise them past the code's ceilings.
- **Kill switch:** `TASK_CALLS_KILL_SWITCH=1`.
  - Refuses new cases, approvals, retries, dials and takeovers.
  - The answer webhook plays the apology and hangs up.
  - The worker ends every call still in its AI part.
  - A harder, provider-level stop is suspending the dedicated Twilio subaccount (owner action, below).

**What Doddy can say and do:**
- **Duration:** default 4 minutes, at most 5. Ended by our server, with Twilio's limit as backstop.
- **No recording of audio**: Twilio `Record=false`, ElevenLabs `record_voice=false`. A text transcript is made; see the open questions.
- **The agent has no tools that act.** Only `end_call` and `voicemail_detection`. It cannot pay, book, send messages, read memories or transfer the call, because it has nothing to do it with.
- **Agent drift check:** every 10 minutes the server reads the ElevenLabs agent and compares its safety settings with the spec in `voice-agent/task-call/`. Any difference blocks calls. The settings checked are:
  - tools;
  - per-call overrides off;
  - no initiation webhook;
  - the first message;
  - language;
  - audio format;
  - no recording;
  - no knowledge base.
- **Sensitive data:** PESEL (checked with its checksum), Polish IBANs and card numbers are refused unless the fact is ticked as that kind. If no PESEL or address fact is ticked, the card says Doddy won't give them, and the agent never receives one.

## What the code does NOT enforce (said plainly)
- **"Never agrees to anything" and "never invents facts"** are rules in the agent's prompt, backed by the after-call check of Doddy's own lines. They are not guaranteed by construction: a model can say something it shouldn't. What is guaranteed is that it holds only the ticked facts and has no tool to act.
- **"Asks at most one clarifying question"** is a prompt rule.
- **The quoted answer** is exactly what the transcript says. A transcript can mishear a word, and the confidence flag can't catch every mishearing.

## Opening line and the recording notice
Fixed template in server code (`server/messaging/src/taskCalls/opening.ts`):

> Dzień dobry, mówi Doddy, asystent AI, dzwonię w imieniu <imię>.[ <notice>] Chciałbym zapytać: <pytanie>

`CALL_RECORDING_NOTICE`:
- `off` (**default**): no notice.
- `nagrywana`: "Rozmowa jest nagrywana."
- `zapisywana`: "Treść rozmowy jest zapisywana."

**It stays `off` until the owner confirms the legal basis.** In every setting, v1 never records audio but always keeps a text transcript (live from Twilio, final from ElevenLabs).

## Open questions (owner / legal)
1. **Legal basis for transcribing the other person.** The callee's words are personal data, processed by us, Twilio and ElevenLabs. What is the basis? Legitimate interest under GDPR art. 6(1)(f) is the likely candidate, with the information duty of art. 14 (where they can read how it works). Who is the controller for the user's calls: the user or Doddy?
2. **Does a transcript-only call need the notice?** No audio is recorded, but a full text transcript is kept until the user has it. Which wording is accurate and enough: none, "Rozmowa jest nagrywana." (says audio, which isn't true in v1), or "Treść rozmowy jest zapisywana."?
3. **AI disclosure.** Done in the first sentence ("asystent AI"), and again whenever asked. Confirm this meets EU AI Act art. 50(1) as it applies from 2 August 2026.
4. **Processors.** Twilio (telephony, live transcription) and ElevenLabs (voice, final transcript) need to be in the privacy policy and processor agreements.
5. **Do-not-call list.** Before anyone other than the owner uses this: a way for a number's owner to ask never to be called by Doddy again.
6. **Call-backs.** The callee sees Doddy's Twilio number. If they call back, they reach the S2 memory agent, which greets in English and treats them as an unknown caller. Options: a Polish greeting for unknown callers on that agent, or a dedicated Polish number (needs a Twilio regulatory bundle, which can take days).
7. **Days.** v1 allows every day 8:00–23:00. Should Sundays and public holidays be excluded?
8. **Polish numbering.** The allowlist uses the mobile and geographic prefixes of the national numbering plan (Dz.U. 2024 poz. 1862). Confirm `800` should be allowed and `39` refused.
9. **Twilio's call log** keeps numbers, times and price. Should the server delete each call record at Twilio once the cost is read?

## Owner actions before the first call
1. Use a dedicated Twilio **subaccount** for these calls, with Voice geographic permissions set to Poland only. Suspending it stops every call, whatever the code does.
2. Set the task-call environment on the server; `server/messaging/README.md` lists every variable.
3. Create the agent with `node server/messaging/scripts/setup-task-call-agent.mjs` (run `--dry-run` first). Pick a Polish voice.
4. Point the ElevenLabs post-call webhook at `/webhooks/elevenlabs/post-call` with its HMAC secret, with audio off.
5. Run live test #1 from a terminal with `server/messaging/scripts/task-call.mjs`, before using the app.

## Costs
Every attempt gets cost items in the same transaction that claims it for dialling, so a dialled call can't lack a cost. Each item says where its number came from:

| Item | Source | Status |
|---|---|---|
| Twilio call (and each takeover leg) | Twilio's `price`, read after the call (it can take minutes) | reported |
| Twilio live transcription | minutes × the configured price per minute | estimated |
| ElevenLabs voice | `metadata.cost` credits × the configured price per credit | estimated |
| Model (only if one ran) | exact tokens × the configured price | estimated |

An item still unknown after 24 hours stays `unknown`. It is never shown as zero. The case shows the total, whether it is complete, and whether any part is an estimate.

## Failure paths
| What happens | What the user sees | What the server does |
|---|---|---|
| Twilio refuses the call | "Nie udało się zadzwonić" card, no cost | attempt `not_placed`; cost items `zero` |
| No answer / busy / failed | honest card, retry option | from Twilio's final status |
| Voicemail | "Poczta głosowa, nic nie nagrano" card | agent hangs up without a message |
| Phone menu (IVR) | "Automat z menu, nikt nie odebrał" card | from the transcript, checked against a fixed list |
| Wrong number | "Pomyłka" card | from the transcript |
| ElevenLabs down at answer | "Problem techniczny" card | callee hears the AI apology, call ends |
| Request to Twilio timed out | "Nie wiadomo, czy zadzwonił" card; no redial | attempt `unknown`, matched later from Twilio's status if possible |
| Post-call webhook missing | card from the live transcript, marked less reliable | after 3 minutes |
| User presses Przejmij but doesn't press 1 | Doddy carries on | takeover leg ends, nothing changes |
| Kill switch turned on mid-call | "Przerwano" card | goodbye, hang up |
| Account deleted mid-call | — | call ended first, ElevenLabs deletion kept |

## Privacy summary
- **The iPhone keeps** the brief, the transcript, the answer card, the cost and the deletion receipts (`DoddyPersistence`, migration `v14_call_cases`).
- **The server keeps, encrypted, only until the app has it:** the brief payload, live lines and the result. After that it keeps content-free rows: states, times, costs, hashes for limits, and deletion receipts.
- **Logs** carry ids, states, durations and error codes only. Never numbers, names, transcripts, TwiML or provider error text.
- **The Lock Screen** shows "Doddy dzwoni", the phase and the time, never the callee's name or any words (ADR-240).
