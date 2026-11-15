# Calls Doddy makes for you sound like a relaxed person on the phone

- **Date:** 2026-11-15
- **Decided by:** owner ("ta rozmowa wydała się sztuczna trochę, zrób research jak prowadzić rozmowy, żeby były luźne i brzmiały jak człowiek, i niech Doddy tak robi")
- **Status:** accepted
- **Replaces:** the opening-line wording in `2026-11-13-call-agent-sounds-like-an-assistant` ("Dzień dobry, tu Doddy, wirtualny asystent. Dzwonię w imieniu Anny. Chciałbym zapytać: …"); the rest of that decision stands

## Why
The owner's test call on 15 Nov 2026 (`conv_9401m7fpt860fhfvv9srqsr9ap8y`, "Doddy 3", 29 s):
- Doddy opened with one long formal sentence: "Dzień dobry, tu Doddy, wirtualny asystent. Dzwonię w imieniu Pata. Chciałbym zapytać: Czy zajął się Pan już tym tematem?"
- The callee asked "Jakim tematem? Słyszysz?". Doddy waited about 2.3 s, began "Aha, chodzi mi o sprawę…" and was talked over.
- To "Nie wiesz, jaki temat, a? Halo?" it said "Przepraszam za pomyłkę. Do widzenia." and hung up. Rule 9 of the prompt told it to treat "they don't know the matter" as a wrong number.

What the research says (sources below):
- **Short turns.** ElevenLabs' prompting guide: under three sentences, a personality section, guardrails apart.
- **React before the next point**, with brief acknowledgements and natural fillers.
- **Backchannels:** one at a time, varied, never so long that they become a turn of their own.
- **Interruptions:** stop when talked over and answer what was said.
- **Speed:** answer quickly; people take turns within a few hundred milliseconds.
- **Outbound calls:** the opening must tell an unprepared person enough to take the next turn.
- **Telephone openings** in conversation analysis (Schegloff): summons–answer, identification, greeting, then the reason. Plain identification and a short reason work better than a formula.

## Decision
- **Opening line** (`server/messaging/src/taskCalls/opening.ts`): "Dzień dobry, tu Doddy, wirtualny asystent Anny. [recording notice] Mam jedno krótkie pytanie. …?"
  - The AI disclosure is still the first thing said, word for word, and is never phrased by the model.
  - It applies to cards drafted after the deploy. A card drafted before keeps the line it was approved with.
- **"How you sound"** in the three call-agent prompts (`voice-agent/task-call*/instructions.md`):
  - One or two short sentences per turn, then stop.
  - One varied reaction word first.
  - Spoken Polish, still Pan or Pani.
  - No office phrases.
  - "Halo?" is answered at once.
  - "O co chodzi? / Jakim tematem?" is a normal question: say what the call is about from the card. If there is nothing more, say so and use the call-back line instead of hanging up as a wrong number.
  - When talked over, stop and answer.
  - Times and numbers as people say them.
  - At most one apology.
- **The wrong-number rule** now covers only a wrong number or someone who doesn't know the person or place.
- Every rule about money, data, bookings, the AI answer and the confirmation sentences is unchanged.
- **Drift check** (`agentSpec.ts`): the new prompt hashes. Each agent's prompt from before stays accepted (`SYNC_PENDING_PROMPTS`) until its live agent has the new one, so a deploy never stops calls.

## Consequences
- The opening is shorter: about 4 s less before the question.
- The model gets more freedom of wording in replies. The fixed sentences (opening, callback line, booking and order confirmations) stay word for word, and the result writer still audits every Doddy line against the card.
- Not done here: the phone voice model (`eleven_flash_v2_5`) and turn settings. A more expressive voice model should be tried on one test call first, since a wrong setting on a phone agent stops calls (error 3000).

## Sources
- ElevenLabs, [Prompting guide](https://elevenlabs.io/docs/eleven-agents/best-practices/prompting-guide)
- Retell AI, [How to build a good voice agent](https://www.retellai.com/blog/how-to-build-a-good-voice-agent)
- Cekura, [Backchanneling](https://www.cekura.ai/blogs/backchanneling)
- Structurely, [AI voice agent greetings: inbound and outbound](https://www.structurely.com/news/insights/ai-voice-agent-greetings-what-works-for-inbound-and-outbound-calls)
- ElevenLabs, [Conversation flow (turn eagerness)](https://elevenlabs.io/docs/eleven-agents/customization/conversation-flow)
- E. A. Schegloff, [Sequencing in conversational openings](https://conversationanalysis.org/mp-files/sequencing-in-conversational-openings.pdf)

## Evidence
- `npm test` in `server/messaging` with a disposable PostgreSQL 16: 1317 pass, 0 fail, 0 skipped.
- `python3 -I scripts/voice_agent_spec.py check --agent task-call`, `task-call-book` and `task-call-order`: PASS.
- Not run: a real call with the new prompt (after the live sync).
