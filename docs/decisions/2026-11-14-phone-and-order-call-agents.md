# The phone agent opens with the server's sentence in the caller's language, and the order agent sounds like the person's assistant

- **Date:** 2026-11-14
- **Decided by:** owner: "Dawaj rób wszystko i wybierz best options", in answer to three proposals about the live call agents (record the phone agent's 11 Nov prompt change in the repository; give the phone agent the server's first sentence; give the order agent the style of the ask and booking agents). The choices below are the session's "best options".
- **Status:** accepted; the repository part is in this pull request, the live ElevenLabs agents are changed after `doddy-messaging` is deployed with it (recorded in `voice-agent/README.md`)
- **Replaces:** `docs/OWNER_QUEUE.md` 82 point 3 (the phone agent's first sentence, language and maximum length)

## Why
Read on 14 Nov 2026 (read only): the phone agent "Doddy 2" (`agent_4801m5q2sq5xft6ab6k0mnyda04v`, version `agtvrsn_3201m76g8vdfep2th1kry8gz5rfm`, saved 11 Nov 23:49 UTC by someone this repository doesn't record) differs from `voice-agent/phone/` both ways:
- **The live agent is ahead:** its prompt says Doddy speaks Polish and English only, Polish by default; the repository's said only "if the caller speaks Polish, answer in Polish".
- **The repository is ahead:** the live prompt has no `{{doddy_call_reason}}` and no rule about a scheduled call's reason (ADR-754), and its first message is the fixed "Cześć, tu Doddy, asystent AI. W czym mogę pomóc?" instead of `{{doddy_call_opening}}`. So a call the person booked with "call me later" never says why Doddy is calling.
- **A trap in the server:** without a scheduled call, `callOpening` always returned the English "Hi, this is Doddy, an AI assistant. How can I help?". Switching the live first message to the variable would have greeted every Polish caller in English.

The order agent "Doddy 7" was made on 14 Nov from `voice-agent/task-call-order/instructions.md`, which was written before the 13 Nov decision `2026-11-13-call-agent-sounds-like-an-assistant` and still read like a script: fixed goodbye, a bare "Jestem asystentem AI.", and a line saying its first message called it an "AI assistant" when the server's opening says "wirtualny asystent".

## Decision
- **Phone agent's first sentence:** the server's `{{doddy_call_opening}}`. Without a scheduled call's own language, the person's own number picks it: Polish for +48, English for any other (`numberLanguage` in `server/messaging/src/calls.ts`). The Polish sentence without a reason is exactly the live fixed one, so Polish callers hear no change; a booked call now says its reason.
- **Phone agent's prompt:** `voice-agent/phone/instructions.md` keeps rule 6 and `{{doddy_call_reason}}`, and takes the live language rule word for word. The live agent gets this whole text.
- **Language `pl` and 600 s**, as live: Polish is the default in the prompt and for almost every caller; the 600 s limit has been live without trouble, a cut-off in mid-sentence is worse than a longer call, and the daily caps per account and per server (`2026-11-12-call-back-limits`) already bound the cost.
- **Order agent:** the "How you sound" section and the plain DOD-03 answer of the ask and booking agents ("Tak, jestem asystentem AI, wirtualnym asystentem …"), a goodbye in its own words, and its first message described as the server says it. Every rule that keeps it safe is unchanged word for word: only the card's order, the fixed confirmation and refusal sentences, never pay, never a link, one clarifying question at most.
- **The server accepts the order agent's first prompt** (`SYNC_PENDING_PROMPTS`) until the live agent has the new one, so the deploy doesn't stop order calls.

## Consequences
- A call the person booked opens with its reason; English numbers hear English first.
- The order agent sounds like the other two call agents and its prompt no longer contradicts its opening line.
- Not changed: the phone agent's call-start webhook switch (`enable_conversation_initiation_client_data_from_webhook` is on live, off in `phone/session.json`) and its text-only override; whether either matters needs its own look.
- The `SYNC_PENDING_PROMPTS` entry for the order agent can go in a later pull request once the live agent is read back with the new prompt.

## Evidence
- Messaging server tests with a local Postgres: 1,302 pass, 0 skipped (new: a call to Doddy's number opens in the language of the caller's number; changed: "Call me now" opens in Polish for a Polish number; the order agent's first prompt is accepted and the new one keeps the plain answer).
- `python3 -I scripts/voice_agent_spec.py check --agent phone` and `--agent task-call-order`: PASS.
- Not run: a real phone call, a real order call, the prompts in an ElevenLabs conversation.
