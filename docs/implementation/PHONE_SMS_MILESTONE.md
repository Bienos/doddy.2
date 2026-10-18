# Doddy's own phone number: calls and texts (plan)

New milestone: cloud voice and external actions (CLAUDE.md rule 6). Date: 2026-10-17. Decision record: ADR-490.

Owner request: "Give Doddy his own phone number so he can (a) call me and take calls from me, and (b) send and receive SMS."

**Status: approved by the owner on 2026-10-17** ("approved, go with your recommendations, start U0"). U0 is in progress; see "Progress" below. Nothing else in this plan is built yet.

## The short version
1. **Most of this already exists in code, but it has never touched a real phone number.** S1 (texts) and S2 (calls in both directions) were built on 2026-10-10 in `server/messaging/` and the app: your verified number, consent, STOP, delivery receipts, signed webhooks, the "Doddy (phone)" agent with a PIN, "Call me now", call limits, and `unknown` never redialled. None of it has been deployed. No real text or call has gone through it (`S1_SERVER_STATUS.md`, `S2_CALLS_STATUS.md`). So the work starts by going live with what exists, not by building a second phone system.
2. **The number should be a Polish mobile number** (+48 73… or +48 79…) on Twilio, not a US local or toll-free one. A US number can't receive texts from a Polish phone. A2P 10DLC and toll-free verification are US and Canada rules, so they don't apply. Twilio needs your ID and PESEL before you can buy the number.
3. **One change to what is built: calls reach Doddy's server first.** The S2 design imports the number into ElevenLabs, so every caller, strangers included, talks to the AI, and only the AI's prompt sends them away. With ElevenLabs' `register-call`, the server checks the caller before any AI hears them. A stranger hears one fixed sentence and the call ends. Your number is handed to the phone agent.
4. **New code:** texts Doddy proposes and you approve, bound to a hash of the exact text; texts from you to Doddy; Doddy calling you at a time and for a reason you approved; quiet hours and caps as config.
5. **Nine decisions**, taken on 2026-10-17 (your recommendations), are at the end.

## Progress
| Unit | State |
|---|---|
| U0. Go live with texts | Setup runbook written (`docs/integrations/PHONE_NUMBER_SETUP.md`). The built server passes its tests on this branch (55 tests, 0 failures, 2026-10-17). Waiting on your setup steps and the iPhone checks. |
| U1. Calls through the server | Built on 2026-10-18 (ADR-492): voice routes, Twilio caller, `register-call`, migration 008, setup script, the app's call status words. Server tests: 61 pass, 0 fail, with stand-ins for Twilio and ElevenLabs; six deliberate breakages were each caught by a test. Not run: anything live (it needs U0 first), and the app compile (no Swift here). Waiting on U0, then your U1 steps and checks (`docs/integrations/PHONE_NUMBER_SETUP.md`). |
| U2 to U4 | Not started |

## What exists and what is new
"Built" below means the code exists and its automated tests pass with stand-ins for Twilio and ElevenLabs. The app side compiles in hosted CI. Nothing has run against the real services.

| You asked for | Built (S1, S2) | New in this milestone |
|---|---|---|
| **A.** Doddy proposes an exact text; you approve it; the approval is bound to a hash | Texts go only to your verified number after consent `sms-v1`. An idempotency key is bound to a SHA-256 of the text (migration 006). No card where Doddy proposes a text, and no approval hash checked at send time. | A `text_me` voice tool and an approval card. The app hashes what the card showed; the server and the worker check that hash again before sending. |
| **A.** Status queued → sent → delivered / failed from Twilio callbacks | `/webhooks/twilio/status` stores the delivery status. | "Delivered" only on Twilio's `delivered`. No receipt after 10 minutes: "Sent, delivery not confirmed". Status never moves backwards. |
| **A.** `unknown` is not success and is never blindly retried | The outbox never resends `unknown` (ADR-144). But a Twilio 500, 502 or 504 is retried as "transient", and a 500 can mean the text was created. | 500, 502 and 504 become `unknown`. Before any resend, Twilio's message list is checked. A resend needs a new tap that warns it may arrive twice. |
| **B.** Signed webhooks only | Built; fails closed. | The same check on the new voice routes. |
| **B.** Only your allowlist reaches Doddy; the rest is logged and dropped | Inbound texts only change STOP/START state. Their text isn't read or stored. | Texts from your verified number reach Doddy when you turn this on. Anything else is counted under a keyed hash of the number, dropped, and never answered. |
| **B.** Message text is data, never instructions | Not applicable yet (texts aren't read). | The text can't choose a recipient or a tool. Doddy has two tools for texts (search your memories, leave a note in the inbox), and a reply goes only to your verified number. |
| **B.** STOP / HELP / START | STOP and START are built. Twilio Advanced Opt-Out sends the confirmations. | Polish confirmations and `POMOC` (owner setting in Twilio). |
| **C.** Doddy calls only your number, after you approve the number and the reason; quiet hours; daily cap | "Call me now" (a tap in the app) to your verified number after consent `calls-v1`; 3 per hour and 10 per day as constants; a timeout is `unknown` and never redialled. No reason, no scheduled calls, no quiet hours. | An approval card with the time and the reason, also proposed by a `call_me_later` voice tool. Scheduled calls. Caps as config. Quiet hours. Call status from Twilio. |
| **C.** Doddy says he is an AI when you pick up | The phone agent's first sentence says it is an AI. `voice_agent_spec.py check --agent phone` fails if the prompt drops it (ADR-172). | The approved reason is added to the first sentence. |
| **D.** Caller-ID allowlist; strangers get a fixed message and a hang-up | Strangers get no session, so no memories and no notes. But they still talk to the AI, which is told to say it can't help them. | Server-first routing: strangers hear a fixed sentence and the call ends. No AI, no ElevenLabs minutes. |
| **D.** An honest "not available yet" when voice isn't wired | The agent says Doddy can't reach its memory if the server has a problem. If the server is down, what callers hear depends on ElevenLabs. | A fixed sentence for every case, including a fallback hosted at Twilio for when Doddy's server is down. |
| **E.** Secrets only on the server; `.env.example` with names only | `server/messaging/.env.example` has names only. The guard scans for key values (ADR-146). The app holds no provider keys. | New variable names only. |
| **E.** Allowlist, quiet hours and caps in `doddy_rules.yaml`, enforced in code | Caps are constants in `src/routes/calls.ts`. | The policy and defaults in `doddy_rules.yaml`. The server reads its caps from config, and a test fails if its defaults differ from the yaml. Phone numbers never go in the repo. |
| **F.** Tests | Server suite: 55 tests, 0 failures (run on this branch on 2026-10-17: real PostgreSQL 16, stand-ins for Twilio and ElevenLabs). Swift client tests and end-to-end runs with stand-ins (S1, S2 docs). | Per unit; see "Tests" below. |

## Where this plan differs from the request
1. **Your number stays out of the repo.** The request puts the allowlist in `docs/trust/config/doddy_rules.yaml`. That file is in git, so your phone number would be published in the history forever. The yaml gets the policy (only numbers verified in the app, at most one, the defaults). The number itself stays where it is today: in Doddy's database, after you confirm it with a Twilio Verify code.
2. **Doddy texts only you.** The request's payload is "(to, body)". This plan fixes "to" to your verified number. Texting other people from Doddy's number needs their consent and looks like spam to carriers. For texts to other people, Doddy already drafts them in your own Messages app (`draft_message`), where they go out from your own number.
3. **Hanging up on strangers needs a routing change.** While the number is imported into ElevenLabs, a fixed message and a hang-up can't be guaranteed in code. So calls go to Doddy's server first. This replaces the "number imported into ElevenLabs" part of ADR-152; the rest of S2 stays.
4. **Doddy still can't send texts during a call.** On a call there is no screen to tap. A spoken "yes" would be approval by the model alone, which `doddy_rules.yaml` forbids (`disallow_model_only_approval`).
5. **Quiet hours apply only to things that happen later.** A call or a text you ask for right now goes now.
6. **Twilio's own STOP and HELP confirmations go to any sender.** Doddy's code never answers a stranger, but Twilio's Advanced Opt-Out sends its fixed confirmation to anyone who texts STOP or HELP. Polish carriers expect that, and the text is fixed, with no AI and no data.
7. **Doddy's replies to your texts count as conversation, not as new external writes**, if you choose AI replies. They are allowed by one switch you turn on, and only as an answer to a text you just sent. This is decision 5.

## 1. Provider
**Recommendation:**
- Twilio for the number, the texts and the call routing.
- ElevenLabs' existing "Doddy (phone)" agent for the voice, connected through ElevenLabs' `register-call` API instead of importing the number into ElevenLabs.

Why:
- **Twilio** is the provider you already approved (ADR-141), and S1 and S2 are built on it.
- **ElevenLabs** for the voice keeps the phone agent, its three webhook tools (`verify_pin`, `search_memories`, `save_note`) and its CI spec check as they are (ADR-152, ADR-172).
- **Why not the native ElevenLabs integration** (the number imported, ElevenLabs answering every call and text): it is less code, but it puts every caller and every texter, strangers included, straight into the AI. Only a prompt then tells the AI to turn them away, and the constitution says prompts never enforce access. ElevenLabs also states that its SMS integration doesn't support zero-retention mode. With `register-call`, Doddy's server decides before any AI or third party gets the call.
- **What the switch costs:**
  - one more webhook route;
  - the phone agent's audio must be set to μ-law 8000 Hz, in and out;
  - call transfer isn't available (Doddy doesn't transfer calls);
  - the number no longer shows in the ElevenLabs dashboard.
- **Not chosen:**
  - Twilio ConversationRelay with our own speech stack, which would rebuild S2;
  - OpenAI Realtime over the phone. It has been the app's default voice since ADR-442, but the phone agent and its tools exist only on ElevenLabs. Revisit if call minutes cost too much.

If you choose AI replies to texts (decision 4), they run on Doddy's server with Claude, with the same two tools the phone agent has. ElevenLabs' own SMS replies were not chosen, for the reason above.

## 2. Architecture
The iPhone app never holds a Twilio, ElevenLabs or Anthropic key. It talks only to Doddy's server, with its own server token (Keychain, this device only). The server (`server/messaging/`, Render, Frankfurt) owns the number's webhooks and every provider key, as environment variables set in Render's dashboard.

**You call Doddy**
```
your phone → Twilio number → POST /webhooks/twilio/voice (signed) → Doddy's server
   ├─ not your verified number, number withheld, or calls off → fixed sentence, hang up (no AI)
   ├─ voice not configured                                     → "not set up yet" sentence, hang up
   └─ your number, calls on → open a call session → ElevenLabs register-call → TwiML → phone agent
                                                      (PIN before any memory or note, as today)
Twilio can't reach the server → the number's fallback URL, a TwiML Bin at Twilio → fixed sentence, hang up
```

**Doddy calls you**
```
approval card (tap) → POST /v1/calls → checks: consent calls-v1, your number, caps, quiet hours, hash
   → at the time: worker checks again → Twilio Calls API (status callback on)
   → you answer → POST /webhooks/twilio/voice/outbound/<call id> (signed) → register-call (outbound) → phone agent
   → Twilio status callbacks: ringing, answered, completed / busy / no-answer / failed
```

**A text Doddy sends you**
```
approval card (tap) → POST /v1/texts {body, approvalHash, idempotencyKey}
   → server: recomputes the hash with your stored number, checks consent, opt-out, caps → outbox (text encrypted)
   → worker: decrypts, checks the hash again → Twilio Messages API → status callbacks
```

**A text you send Doddy**
```
your phone → Twilio number → POST /webhooks/twilio/sms (signed)
   → STOP / START / HELP keywords first (as today)
   → sender must be your verified number with "Texts to Doddy" on; otherwise counted and dropped
   → each Twilio message id handled once → rate limit
   → replies off: the text becomes a note in the inbox (encrypted, as call notes are)
   → replies on: a reply job; Claude answers with search_memories / save_note; the reply goes to your number only
   → the message record is deleted at Twilio after it is handled
```

**Approval hash.** SHA-256 over a length-prefixed UTF-8 encoding of the fields shown on the card. For a text: version, your full number, the exact text. For a call: version, your number, the time in UTC, the exact reason, the quiet-hours override. It is not JSON, so Swift and JavaScript can't disagree on escaping. Shared test vectors go in `contracts/phone/approval-vectors.json`. The server never trims or rewrites an approved text. Twilio's Smart Encoding must be off on Doddy's Messaging Service, or Twilio could change characters after you approved them.

## 3. Number type and compliance
**Recommendation: one Twilio Polish mobile number, voice and SMS, in your name.**

| Option | You call it from your Polish phone | Your texts reach it | Its texts to you | Registration |
|---|---|---|---|---|
| **Polish mobile** (+48 73 / +48 79) | Yes | Yes: Twilio supports two-way SMS in Poland | From a Polish number you can reply to | Twilio identity check: your ID and your PESEL; address anywhere |
| Polish local (geographic) | Yes | Not suitable: Twilio's Poland price list shows inbound texts for mobile numbers only | – | ID, PESEL, and an address in that area |
| Polish toll-free (+48 800) | Yes | No: Twilio's toll-free numbers outside the US are for incoming calls | No | ID and PESEL |
| US local or toll-free | International call | **No:** Twilio says US numbers receive texts only from US and Canadian numbers | Polish networks may replace a foreign number with a letter sender, so you couldn't reply | A2P 10DLC (local) or toll-free verification |

**Rules for texts to Poland** (Twilio's Poland SMS guidelines, read 2026-10-17):
- Link shorteners (bit.ly and the like) are not allowed. Use full links.
- Polish networks tend to block long texts with links, so test before relying on one.
- Send during the day unless it is urgent; this is what quiet hours are for.
- Get consent first (you, `sms-v1`), and support HELP and STOP in the user's language.

**Polish letters change the length.** One letter such as ą, ę or ł makes the whole text Unicode: a segment then holds 70 characters (67 when a text is split), not 160. Caps and cost estimates below count segments.

**Costs** (Twilio's Poland price pages, read 2026-10-17, USD; carriers may add fees):

| Item | Price |
|---|---|
| Polish mobile number | $4.00 a month |
| Text from Doddy to a Polish mobile | $0.0457 per segment |
| Text you send to Doddy | $0.0075 each |
| You call Doddy | $0.0107 a minute at Twilio, plus what your own operator charges |
| Doddy calls you | $0.0715 a minute from the EEA, $0.2202 otherwise (the Twilio console shows which applies) |
| ElevenLabs phone minutes | Billed on your ElevenLabs plan; not checked here |
| Claude, per AI reply (only if on) | Estimates, not measured: about $0.03 with Claude Opus 5.5, under $0.001 with Claude Haiku 5.5 |
| Render: server, worker, Postgres | The paid plans in `render.yaml`, already needed for S1; not checked here |

**Example month (estimate):** 60 texts from Doddy at 2 segments each, 60 texts to Doddy, 30 minutes of calls each way. That is about $12 to $17 at Twilio, plus ElevenLabs, Render, and Claude if AI replies are on.

**Lead times:**

| Step | Who | Lead time |
|---|---|---|
| Upgrade the Twilio account if it is still a trial | You | Minutes |
| Identity bundle for a Polish mobile number (ID + PESEL) | You | Twilio's guide says reviews usually finish within 48 hours; plan for a few days |
| Buy the number | You | Minutes, once the bundle is approved |
| Messaging Service, Verify service, webhooks, fallback | You, from Claude's runbook | Under an hour |
| Deploy the server on Render | You | Under an hour (paid plans) |
| ElevenLabs agent settings | You | Minutes |

There is no US-style registration (A2P 10DLC, toll-free verification) for the Polish number.

**Only you can do these:**
- pay for and upgrade Twilio, and submit your ID and PESEL;
- buy the number;
- create the Messaging Service (Advanced Opt-Out on with Polish replies, Smart Encoding off) and the Verify service;
- set the number's webhooks and the fallback TwiML Bin;
- create the Render resources and type the secrets into Render's dashboard (never into chat or a file);
- change the live ElevenLabs agents (the app and Claude never do);
- approve the new consent wording (a draft is in unit U3);
- run the iPhone checks.

## 4. Flows: what can go wrong and how it recovers

### A. A text Doddy sends you
1. Doddy proposes it with the voice tool `text_me`, or you type one in Settings.
2. The card shows the recipient (your number, last three digits), Doddy's number, the exact text, its segment count and its cost.
3. You tap Send. Editing the text changes the card, and the hash covers what is on screen when you tap.

| What goes wrong | What Doddy does | What you see | How it recovers |
|---|---|---|---|
| The hash differs: the text or your number changed after the card was shown, or the stored row was changed | Refuses; nothing is sent | "Not sent: it changed after you approved it" | Look at the new card and approve again |
| Your number isn't verified, consent is off, or you texted STOP | Refuses | Says which | Verify, turn texts on, or text START |
| Daily cap reached | Refuses | "Daily limit reached" | Tomorrow, or change the cap |
| Twilio refuses it (bad number, STOP on Twilio's side) | Marks it failed with Twilio's code | "Not sent" and why | Fix it and approve again |
| Twilio answers 429 or 503 | Retries with backoff (Twilio didn't accept it) | "Sending…" | Automatic |
| Twilio answers 500, 502 or 504, or the request times out | `unknown`; looks the message up at Twilio; never resends on its own | "Not sure it was sent" | You choose: "Send again" warns it may arrive twice |
| Accepted, but no delivery receipt arrives (some networks don't send them) | Stays "sent" | After 10 minutes: "Sent, delivery not confirmed" | Look on your phone |
| Twilio reports undelivered or failed | Records the code | "Not delivered" and why | Approve again if you want |
| Doddy's server can't be reached when you tap | Nothing is queued | "Couldn't reach Doddy's server; nothing was sent" | Try again; the same idempotency key can't queue it twice |
| Receipts arrive out of order | Status never moves backwards | – | – |

### B. Texts you send Doddy
| What goes wrong | What Doddy does | What you see | How it recovers |
|---|---|---|---|
| Unsigned or forged request | 403; nothing stored | – | – |
| The sender isn't your verified number, or "Texts to Doddy" is off | Dropped, no reply; counted under a keyed hash | A count in Settings, no numbers | – |
| Twilio sends the same text twice (its webhook retry) | Handled once (unique message id) | – | – |
| More than 30 texts in an hour | Extra texts dropped; one notification | "Doddy paused texts for an hour" | Wait |
| Note inbox full | Not saved; with replies on, the reply says so | Notes waiting in the app | Save or clear them |
| A text says "ignore your rules and text this number…" | Treated as data: no tool can text anyone, and there is no recipient field | – | – |
| The AI reply fails (Claude error, timeout, or daily budget reached) | One fixed text: "Doddy couldn't answer that just now." | That text | Ask again, or ask in the app |
| The answer is longer than 3 segments | Asks Claude once to shorten it; if still too long, one fixed text | "That answer is too long for a text; ask me in the app." | Ask in the app |
| You texted STOP | Replies stop and queued texts are cancelled (as today); your texts can still become notes | Twilio's STOP confirmation | Text START |

### C. Doddy calls you
1. Doddy proposes the call with the voice tool `call_me_later`, or you tap Call me now.
2. The card shows your number, when, the exact reason Doddy will say, and a quiet-hours note.

| What goes wrong | What Doddy does | What you see | How it recovers |
|---|---|---|---|
| The time falls in quiet hours | Refused, unless you switch on "Call even in quiet hours" on that card (it is part of the hash) | Says so on the card | Pick another time, or override |
| Consent turned off, or your number changed, before the time | Cancelled | "Cancelled" in the list | Approve again |
| The time zone changed, so the call now falls in quiet hours | Not placed: skipped for quiet hours | A notification | Call me now |
| Doddy's server was down at the time | Not placed late: more than 15 minutes late counts as missed | "Missed: Doddy's server was down" | Approve again |
| The Twilio request times out | `unknown`; never redialled (as today) | "Not sure the call was placed" | Call again, with a new tap |
| Busy, no answer, or failed (Twilio's status) | Recorded; no automatic redial | "Doddy called at 18:00, no answer" | Call again, with a new tap |
| Voicemail answers | The agent's first line (AI, reason) is left on your voicemail | – | Decision 9 |
| You answer, but `register-call` fails | A fixed "Doddy can't talk right now" and hang up | That sentence | Call again |
| Cap reached | Refused when you approve, and again at the time | "Daily limit reached" | Tomorrow, or change the cap |

### D. You call Doddy
| What goes wrong | What Doddy does | What you hear | How it recovers |
|---|---|---|---|
| Not your verified number, number withheld, or calls off | A fixed sentence and hang up; counted under a keyed hash; no AI | "This is Doddy, an AI assistant. This number only works for its owner. Goodbye." (Polish, then English) | – |
| Someone fakes your caller ID | Gets past the caller-ID check, but the PIN is still needed before any memory or note (ADR-154, ADR-175: escalating lockouts, a notification to you) | The PIN question | Change your PIN |
| Voice not configured on the server | A fixed sentence and hang up | "Doddy's voice isn't set up yet." | – |
| `register-call` fails or takes more than 5 seconds | A fixed sentence and hang up; recorded as failed | "Doddy can't talk right now." | Call again |
| The server can't reach its database | Treated as unknown: a fixed sentence and hang up | "Doddy isn't available right now." | Call again later |
| Doddy's server is down | Twilio's fallback TwiML Bin answers | "Doddy isn't available right now." | Call again later |
| Wrong or locked PIN | As today | As today | As today |

## 5. Privacy
Recording stays off. No TwiML or Twilio API call asks Twilio to record, and a test fails if one does. The ElevenLabs phone agent keeps no audio (ADR-158). This milestone adds no way to turn recording on.

| What | Where | How long | Delete or export |
|---|---|---|---|
| Your phone number | Doddy's database (Render, Frankfurt) | Until you delete server data | Settings → delete server data (built) |
| Your phone number | Twilio (Verify, message and call records) | Doddy deletes its message and call records at Twilio after each final status (new). Twilio says deleted records can take up to 14 days to disappear fully, and it keeps billing data. | – |
| Your phone number | ElevenLabs, for the calls you're allowed to make or receive | ElevenLabs conversation records, 30 days | – |
| Texts Doddy sends you | Doddy's outbox, encrypted until sent, then erased (ADR-144); Twilio as above; your Messages app (and your iCloud backup, if it is on) | Your phone: outside Doddy's control | Delete in Messages |
| Texts you send Doddy | Twilio in transit, then deleted as above; a note in the inbox, encrypted (AES-256-GCM, not end to end), until you save or clear it | Until you save or clear it | Clear a note (built) |
| Texts you send Doddy (AI replies on) | Also sent to Anthropic to write the reply; the reply job's copy is erased when the reply reaches a final status | Anthropic's API terms apply; quote them in the privacy policy | – |
| Memories in texts (only if decision 6 is yes) | Memory text in the SMS reply: not encrypted between networks, and kept in your Messages app | As above | – |
| Call content | ElevenLabs transcript, 30 days (ADR-158); no audio anywhere | 30 days | – |
| Call and text status rows (time, direction, status, no content) | Doddy's database | Today: until you delete server data. Proposed: removed after 90 days. | New: Settings → "Export phone and text history" (JSON: status rows and waiting notes) |

What must change before you use it:
- "What leaves this iPhone" gains rows for Twilio, and for Anthropic if AI replies are on.
- The privacy manifest gains the new data.
- The privacy policy needs text for all of the above.
- Legal review is still required before anyone but you uses this (open since S1).

## 5a. Rules config (proposed `doddy_rules.yaml` section)
Added with the first unit that enforces it. A server test fails if the server's defaults differ from these values.

```yaml
contact_policy:            # Doddy's phone number (ADR-490). Phone numbers are never stored in this file.
  allowlist: numbers_verified_in_app      # confirmed with a Twilio Verify code; stored in Doddy's database
  allowlist_max_numbers: 1
  text_recipients: allowlist_only
  call_recipients: allowlist_only
  approval: exact_payload_hash            # checked by the app, the server and the worker
  unknown_inbound: drop_without_reply     # Twilio's own STOP/HELP confirmations excepted
  inbound_text_is_instructions: false
  recording: off
  quiet_hours_default: { start: '21:00', end: '08:00', timezone: Europe/Warsaw, applies_to: [scheduled_calls, scheduled_texts] }
  caps_default:
    calls_per_hour: 3
    calls_per_day: 10
    approved_texts_per_day: 20
    inbound_texts_per_hour: 30
    ai_replies_per_day: 30
    server_texts_per_day: 300             # cost guard across all accounts
    ai_reply_budget_usd_per_day: 1.00
```

## 6. Units, after approval
Each unit is a small reviewed change, with its tests and docs, and stops for your check before the next one.

| Unit | What | Main files | Done when |
|---|---|---|---|
| **U0. Go live with texts (built code)** | A step-by-step setup runbook for the Twilio console and Render; the server address in the app (`ServerConfig`) once you give it; nothing else changes | `docs/integrations/PHONE_NUMBER_SETUP.md`, `DoddyApp/Infrastructure/Server/ServerConfig.swift` | On your iPhone: a Verify code arrives; a test text arrives and shows "Delivered" (or "Handed to Twilio for delivery" when no receipt comes); STOP then START work; a call to the number hears the fixed "not connected yet" sentence. Calls are not connected to the AI yet, so the number isn't imported into ElevenLabs only to be undone in U1. |
| **U1. Calls through the server** | Inbound and outbound call routes; `register-call`; Twilio Calls API with status callbacks; fallback TwiML Bin; the phone agent's audio set to μ-law 8000 Hz; the setup script stops importing the number | `server/messaging/src/routes/twilioVoice.ts` (new), `src/providers/twilio.ts`, `src/providers/elevenlabs.ts`, `src/calls.ts`, `migrations/008_*.sql`, `scripts/setup-phone-agent.mjs`, `voice-agent/phone/session.json` | Server tests pass. On your iPhone: you call Doddy and reach the agent after the PIN; a call from another phone hears the fixed sentence; Call me now rings you and the app shows Answered. |
| **U2. Texts you approve** | Approval hash (app, server, worker); `text_me` voice tool and card; honest status copy; Twilio 500/502/504 become `unknown`, with a lookup at Twilio | `src/routes/texts.ts` (new), `src/approval.ts` (new), `src/outbox.ts`, `contracts/phone/approval-vectors.json`, `Packages/DoddyCore/.../ApprovalHash.swift`, `VoiceTools.swift`, `voice-agent/tools.json`, `instructions.md`, `DoddyApp/Features/Voice`, `Features/Calls`, `doddy_rules.yaml` | Tests pass. The live app agent gets `text_me` (you update it). A text Doddy proposes arrives after your tap, and an edited text needs a new tap. |
| **U3. Texts to Doddy** | Allowlist, unique message ids, rate limit, Polish keywords, notes inbox, deleting records at Twilio, history export; AI replies (if decision 4 is yes, off by default) with Claude and the two tools. Draft consent wording for you to approve: "Texts you send to Doddy's number go to Doddy's server and to Twilio. If you turn on replies, Doddy, an AI, answers by text, and your text goes to Anthropic to write the answer. Text STOP to stop." | `src/routes/twilioWebhooks.ts`, `src/sms.ts`, `src/textReplies.ts` (new), `migrations/009_*.sql`, `Features/Calls` | Tests pass. On your iPhone: a text from you becomes a note, or gets an answer; a text from another phone gets nothing. |
| **U4. Doddy calls you** | Reason and time on the card; `call_me_later` voice tool; scheduled calls in the worker; quiet hours with a time zone; caps from config | `src/routes/calls.ts`, `src/quietHours.ts` (new), `src/config.ts`, `migrations/010_*.sql`, `voice-agent/tools.json`, `voice-agent/phone/instructions.md` (`{{doddy_call_purpose}}`), `Features/Calls` | Tests pass, including the 2026-10-25 change from summer to winter time in Warsaw. On your iPhone: a scheduled call rings at the time with the reason; one inside quiet hours is refused. |

## 7. Tests
**Automated, server** (Node 22 and PostgreSQL 16, both in this container). Twilio and ElevenLabs are stand-ins, labelled **mock server**; Twilio signatures are computed with the official `twilio` library, as S1 did.
- **Signatures:** every new route rejects unsigned and forged requests.
- **Allowlist:** a stranger's call gets the fixed TwiML and the ElevenLabs stand-in is never called; a stranger's text is dropped with no reply and nothing stored.
- **Approval hash:** a mismatch at the server gives 409; a stored row whose text no longer matches its hash is never sent; the shared vectors pass in TypeScript.
- **Status state machine:** only allowed moves; out-of-order receipts don't move a status backwards; `delivered` and `answered` come only from Twilio's callbacks.
- **`unknown` is not success:** a timeout or a 500 gives `unknown`, the worker never resends it, and the API reports it as not confirmed.
- **STOP / START / HELP:** English and Polish keywords; STOP cancels queued texts.
- **Quiet hours:** Europe/Warsaw, including the night of 2026-10-25 (summer to winter time) and a spring-forward night.
- **Caps:** parallel requests can't pass a cap together (per-account lock, as today).
- **Message ids:** a repeated Twilio message id is handled once.
- **Injection:** a fixture text with instructions to text another number leads only to a reply to the sender.
- **Recording:** no `record` parameter anywhere in TwiML or Twilio API calls.
- **Config drift:** the server's default caps and quiet hours equal `doddy_rules.yaml`.

**Optional, labelled "Twilio test credentials", never in CI:** one test sends to Twilio's magic test number and expects 201 with no charge. Test credentials don't call webhooks, so they can't test the rest.

**Swift** (`Packages/DoddyCore`): the approval-hash vectors, argument checks for `text_me` and `call_me_later`, segment counting (GSM-7 and Unicode), and status copy. There is no Swift toolchain in this container, so these run in hosted CI or on your Mac. Here they will be marked **NOT RUN**.

**Voice agent spec:** `voice_agent_spec.py check` for both agents. The new tools change something, so they need a card and a tap; the phone agent must still disclose that it is an AI.

**No automated test sends a real text or places a real call.**

**Manual, on your iPhone** (after each unit):
- real Verify code, real text, STOP and START;
- calling Doddy from your phone, and from another phone;
- Call me now;
- a text Doddy proposes;
- a text you send Doddy;
- a scheduled call, and one in quiet hours;
- what happens with the server switched off.

## 8. Constitution
| Rule | Enforced by (planned) | Test (planned) |
|---|---|---|
| DOD-03 AI identity | The phone agent's first sentence (built) with the reason added; every fixed TwiML sentence says "an AI assistant" | `voice_agent_spec.py check --agent phone`; TwiML snapshot test |
| DOD-07 approval before external writes | Recipient fixed to your verified number; hash checked by app, server and worker; the phone agent has no text or call tool | Hash mismatch tests; phone agent tool list check |
| DOD-08 verified status | "Delivered" and "answered" only from Twilio callbacks | State machine tests |
| DOD-09 no blind retry | `unknown` never resent; 500/502/504 become `unknown` with a lookup; message ids handled once | Retry and duplicate tests |
| DOD-06 memory control | Notes from texts and calls go to the inbox, never straight into memories | No code path from a text to a memory write (test) |
| DOD-10 no manipulation | No unsolicited calls or texts; caps; quiet hours | Cap and quiet-hours tests |
| DOD-11 observable privacy | "What leaves this iPhone" rows; deletion at Twilio; recording off | "No record parameter" test; data-flow row test |
| Content is data, not instructions | Text in a data block; no tool takes a recipient | Injection fixture test |

## 9. Decisions (taken 2026-10-17)
You approved the recommendations below. Decision 7 had no recommendation, so the default applies: Claude Opus 5.5. It is a config value, so switching to Claude Haiku 5.5 later is one setting. Decision 9 keeps the default: Doddy speaks into your voicemail, with no answering-machine detection.

1. **Approve this plan and the unit order** (U0 to U4). Recommendation: yes, and stop after each unit.
2. **Whose name is on the number:** you as a person (ID and PESEL), or a business (KRS, REGON or NIP, and an authorised person). Recommendation: you, for a personal build.
3. **Route calls through Doddy's server** with `register-call`, replacing the ElevenLabs number import in ADR-152. Recommendation: yes.
4. **AI replies to your texts in this milestone,** or texts become inbox notes only. Recommendation: build both, with AI replies behind a switch that is off by default.
5. **AI replies count as conversation,** allowed by that one switch with no tap per reply, but only to your number, one reply per text, and within 10 minutes. Recommendation: yes. Otherwise every reply needs a tap in the app, and texting Doddy stops being useful.
6. **May AI replies use your memories?** That puts saved memory text into an SMS. Recommendation: a separate switch, off by default.
7. **Which Claude model writes the replies:**
   - Claude Opus 5.5, the default for new Claude work: about $0.03 per reply (estimate).
   - Claude Haiku 5.5, which the daily news already uses (ADR-160): under $0.001 per reply (estimate).
8. **Quiet hours 21:00 to 08:00 Warsaw time, and the caps in section 5a.** Recommendation: yes; you can change them later.
9. **When voicemail answers Doddy's call:**
   - default: let the agent speak into your voicemail;
   - or turn on Twilio's answering-machine detection, which costs extra per call and adds a few seconds before Doddy speaks, so Doddy hangs up instead.

## What this plan does not claim
- Nothing here is built, deployed or tested. S1 and S2 have never run against real Twilio or ElevenLabs.
- Prices and Poland rules were read from Twilio's public pages on 2026-10-17. Check them again in the console before buying.
- What `register-call` can do comes from ElevenLabs' documentation and hasn't been tried. The call session's secret variable is expected to work through `register-call` the same way it does through ElevenLabs' outbound-call API (the same `conversation_initiation_client_data` object). The first live call in U1 checks this.
- Claude costs per reply are estimates, not measurements.

## Sources (read 2026-10-17)
- Twilio, Poland SMS guidelines: https://www.twilio.com/en-us/guidelines/pl/sms
- Twilio, Poland regulatory requirements: https://www.twilio.com/en-us/guidelines/pl/regulatory
- Twilio, Poland voice guidelines: https://www.twilio.com/en-us/guidelines/pl/voice
- Twilio, SMS pricing for Poland: https://www.twilio.com/en-us/sms/pricing/pl
- Twilio, voice pricing for Poland: https://www.twilio.com/en-us/voice/pricing/pl
- Twilio, number availability and two-way SMS: https://help.twilio.com/articles/223183068
- Twilio, deleting message and call records (error 20009): https://www.twilio.com/docs/api/errors/20009
- Twilio, message redaction: https://www.twilio.com/docs/messaging/guides/privacy-message-redaction
- ElevenLabs, register Twilio calls: https://elevenlabs.io/docs/eleven-agents/phone-numbers/twilio-integration/register-call
- ElevenLabs, SMS conversations: https://elevenlabs.io/docs/eleven-agents/phone-numbers/twilio-integration/sms-conversations
