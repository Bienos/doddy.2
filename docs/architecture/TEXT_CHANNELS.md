# Text channels: asking Doddy about your notes by message (iMessage, SMS, WhatsApp)

**Status (23 Oct 2026): design only. Nothing here is built, nothing sends or receives a message, and no account with Apple, Meta or a messaging provider has been opened for it.** It answers the owner's request of 22 Oct: "the iMessage thing where people could be connected to the information of Doddy and talk with it". It follows ADR-595 (`docs/product/CLOUD_MEMORY.md`): the answer is `MemoryChat.answer(userId, …)`, which knows nothing about the web, so a message channel is a new door onto the same function. The hard part is not the door; it is knowing which person is texting.

## What exists today

| Piece | State |
|---|---|
| `MemoryChat.answer(userId, question, history)` (`backend/src/memory/chat.ts`) | Built and tested. Claude Haiku 5.5, notes and conversations as data, no tools, shared daily caps (50 per person, 500 for everyone). Not deployed. |
| Twilio inbound webhook `POST /webhooks/twilio/sms` (`server/messaging`) | Built, signature-checked. Handles only STOP and START today; any other text is ignored. Not yet run with real Twilio. |
| Verified phone numbers (`phone_numbers`, Twilio Verify) | In the **messaging server's** database, tied to its anonymous account, not to the backend user that owns the kept notes. |
| Outbox for outgoing texts, consent per wording version, STOP honoured | Built in `server/messaging` (S1). |
| Apple Messages for Business | Owner decided to apply (10 Oct); **not submitted**. See below. |
| WhatsApp Business Platform | Not chosen (`docs/architecture/INTEGRATIONS_AND_CHANNELS.md`). |

## The channels

| Channel | How it would work | Blockers |
|---|---|---|
| **iMessage** (blue bubble) | Only as a *business chat* through **Apple Messages for Business** and an Apple-approved messaging service provider (MSP). The person must message Doddy first. Relaying real iMessage from a Mac is against Apple's terms and is rejected. | Apple's requirement of live human agents in business hours and bot-to-agent handoff; an AI-only Doddy may be refused (`docs/implementation/APPLE_MESSAGES_FOR_BUSINESS_APPLICATION.md`). Needs an MSP with EU data residency. Only the owner can register at register.apple.com. **A human handoff is a staffing decision, not code.** |
| **SMS** | Person texts Doddy's number; the Twilio webhook calls the chat; the answer goes back through the outbox. | Weakest identity (sender numbers can be spoofed on some routes; SIM swap; recycled numbers). Plain text across carriers. Poland-only subaccount or sender rules to confirm. Costs per segment. |
| **WhatsApp** | Business Platform webhook, same shape. Replies inside the 24-hour window the person opened need no template. | Meta business verification (slow); per-conversation fees; the content passes through Meta's infrastructure. |

## The identity problem (the real design work)

A text arrives from a number. Doddy must decide *whose notes* it may read. Today no record joins a phone number to the backend user that owns kept memory:

- the number is known to the messaging server (an anonymous account there);
- the kept notes belong to a backend user (the iPhone's device session);
- the phone holds both sessions, but neither server knows the other's user.

**Recommended link (nothing else may read memory by text):**

1. In the app, **Settings › Doddy on the web › Texting Doddy** (a third switch, off by default, set only by the iPhone like the other two). Turning it on shows what is sent where and asks for the number.
2. The backend creates a **one-time link code** (single use, about 10 minutes, bound to the user). The app shows: "Text `LINK 483920` to Doddy's number from the number you want to use."
3. The inbound webhook (signature-checked) sees the code from the sender number, proves the person controls it by *sending from it*, and calls the backend **service-to-service** (HMAC over the raw body with a shared secret, no user cookie) to complete the link. The backend stores a **peppered hash of the number**, the channel and the user id. It does not store the number in plain text; the messaging server already holds it for its own purposes.
4. Later texts from that number are answered for that user only. Unknown numbers get a fixed reply that reveals nothing ("I don't know this number. Link it in the Doddy app.") and spend no model call.
5. Unlinking is in the app and by texting STOP; deleting everything on the server (ADR-595) removes the links too; a link expires after 90 days unless the person re-confirms in the app.

**What this does not defend against, and the mitigations that shrink it:**

| Risk | Mitigation |
|---|---|
| SIM swap, stolen phone, recycled number: whoever holds the number can ask about your notes | Off by default. Optional **PIN** asked at the start of each hour of texting (the messaging server already has a call PIN, `PUT /v1/calls/pin`). A **push notification** to the iPhone on a new link and on the first text of a day. Answers quote at most short excerpts and never offer an export. Re-confirm in the app every 90 days. |
| Spoofed sender on SMS | Prefer WhatsApp or Messages for Business (identity is an account, not a number). Require the PIN on SMS. Ignore messages whose Twilio signature fails (already done). |
| A text that says "ignore your instructions" | Same as the web: it is the question, passed as data; no tools; the answer schema cites only aliases; the channel cannot write, send or delete anything (tested for the web). |
| Cost abuse | Same daily caps as Ask Doddy, plus a per-number limit; nothing is sent to unlinked numbers. |
| The carrier or provider reads the message | Said in the consent: Twilio / Meta / the MSP and the carriers carry the question *and the answer, which can quote your notes*. This is a new recipient of the text of your notes, beyond Doddy's server and Anthropic. |

## Hard rules for any channel (from the constitution and ADR-595)

- Doddy answers only a message the person sent. It does not start conversations, send reminders about notes, or send an answer to a number that has not linked itself. Outbound updates stay a separate, already-consented feature (SMS updates, S1).
- A channel can read and answer. It cannot switch keeping on, change what is kept, or delete. Those stay in the app.
- Doddy never says a note was saved, changed or forgotten over text: the channel has no write path (the person does that in the app).
- Doddy is an AI character here too: the first reply after a link says so in one line; no claimed feelings; no jokes in sensitive moments.
- Logs hold counts and timings only, never the text of a message or an answer (the web chat is already tested for this; the channel needs the same planted-string test).
- A reply that is too long is shortened and ends with "More on the web: <link>" instead of being split into many messages.

## Plan, in order (each step ends at a decision, none starts without approval)

| # | Step | What it needs |
|---|---|---|
| T0 | **Owner decisions** (below). Privacy text for texting added to `docs/legal/PRIVACY_POLICY_DRAFT.md`. | Owner |
| T1 | Backend: `memory_channels` table (user, channel, peppered number hash, linked-at, last-seen), one-time link codes, an internal `POST /internal/channels/answer` guarded by HMAC and a replay window, tests with a fake messaging server and two users (isolation). Not deployed. | T0 |
| T2 | `server/messaging`: inbound handler for non-STOP texts that calls T1 and replies through the outbox; PIN step; fake-Twilio tests. Not connected to a real number. | T1 |
| T3 | iPhone: the third switch, consent screen, link screen, unlink (DoddyCore tests on Linux; app layer needs the hosted Mac build). | T1 |
| T4 | Owner-only trial on the owner's own number, with a real Twilio number, watching the logs. | T2, T3, deployment |
| T5 | Apple Messages for Business adapter once Apple and an MSP approve; WhatsApp if chosen. | Owner registrations |

## Decisions needed from the owner

1. **Which channel first?** Recommendation: the SMS path first, for the owner's own number only, because the signature-checked webhook, the outbox, STOP handling and verified numbers already exist; decide public SMS only after a PIN and the trial. WhatsApp second. iMessage waits on Apple (human agents).
2. **Staffing for Messages for Business:** who answers as the live agent, in which hours, or whether to skip iMessage.
3. **PIN by default on SMS?** Recommendation: yes.
4. **One account or two:** keep the messaging server and the backend separate with a service-to-service link (this plan), or move texting into the backend (architecture phase 2, more work, one less shared secret).
5. **Cost ceiling:** monthly limit for message fees and model calls, so the caps can be set.
6. **Region:** which provider regions are acceptable for message content (EU preferred).

## Not claimed

No channel is implemented, tested or privacy-reviewed. Nothing in the app, the website or the store listing may say that Doddy can be reached by iMessage, SMS or WhatsApp until a channel has run end to end with a real number and the privacy text has been reviewed.
