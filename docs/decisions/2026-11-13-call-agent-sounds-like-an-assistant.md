# Calls Doddy makes for the person sound like their assistant; the AI disclosure is one short "wirtualny asystent" and a plain yes when asked

- **Date:** 2026-11-13
- **Decided by:** owner, in part: "trzeba też poprawić tego agenta, żeby nie mówił, że jest AI-em, że zawsze jest bardziej asystentem moim i że dzwonisz w moim imieniu … rozmawiamy, można z tobą rozmawiać jak z człowiekiem … reagujesz też normalnie". The part that keeps a disclosure is the constitution's (DOD-03, ADR-191) and is flagged for the owner below.
- **Status:** proposed in this branch; the live ElevenLabs agents are not changed (only the owner syncs them)
- **Replaces:** the opening line "Dzień dobry, mówi Doddy, asystent AI, dzwonię w imieniu …" (ADR-502) and the prompts' fixed answer "Jestem asystentem AI."

## Why
The owner hears the call agent as a robot reading a script: it opens with "asystent AI", answers in fixed sentences and doesn't react to what people say. They want it to sound like a capable personal assistant calling on their behalf.

Two things limit how far that goes:
- **DOD-03** (`docs/trust/01_THE_DODDY_CONSTITUTION.md`) and ADR-191: Doddy never implies being human, and asked whether it is a person or an AI it says so plainly. `scripts/voice_agent_spec.py` enforces this in CI for both call agents.
- **EU AI Act Art. 50(1)**, in force from 2 Aug 2026: people talking with an AI system must be told so unless it is obvious. The people Doddy calls (a restaurant, a service desk) can't tell otherwise.

## Decision
- **Opening line** (server-built, spoken word for word, `server/messaging/src/taskCalls/opening.ts`): "Dzień dobry, tu Doddy, wirtualny asystent. Dzwonię w imieniu {imienia}." The word "AI" is gone from the opening; "wirtualny asystent" still tells the listener at once that this is not a person. The technical apology and the call-back hand-over line say "wirtualny asystent" too (`TECHNICAL_APOLOGY`, `server/messaging/src/callbacks.ts`). Calls Doddy makes to the person themselves (`calls.ts`) are unchanged.
- **Prompts** (`voice-agent/task-call/instructions.md`, `voice-agent/task-call-book/instructions.md`): a "How you sound" section: natural, warm, everyday Polish; short sentences; react before going on, with varied acknowledgements; adapt to someone busy or friendly; re-say things in simpler words instead of repeating them; never pad sentences with "jako asystent AI"; never pretend to have feelings, a body or a life. The goodbye is the agent's own short words instead of one fixed sentence (the booking confirmation sentence and the call-back line stay fixed, as safety requires).
- **Asked directly** whether it is a robot, a computer, an AI or a person, the agent never denies or dodges: "Tak, jestem asystentem AI, wirtualnym asystentem {imienia}. Wszystko przekażę." Then it carries on if they are happy to. This is the DOD-03 line and stays.
- **Nothing else changes:** the agent still only asks (or books exactly the card's booking), never agrees, pays or gives data beyond the ticked facts, and the server's checks, caps and transcripts are as before.
- **Live agents:** `server/messaging/src/taskCalls/agentSpec.ts` has the new prompt hashes, and `SYNC_PENDING_PROMPTS` still accepts the two earlier prompts of each agent, so a deploy of this server doesn't stop calls before the owner syncs ElevenLabs (owner queue 61).

## Consequences
- Callers hear a shorter, friendlier opening, and an agent that reacts like a person would, while still being told once, first, that it is a virtual assistant.
- **Owner decision (owner queue 62):** whether "wirtualny asystent" alone is enough disclosure under Art. 50 for Polish listeners, or the opening should say "wirtualny asystent AI". Not legal advice; `legal_review_required_before_launch` in `docs/trust/config/doddy_rules.yaml` still applies.
- Removing the disclosure altogether, or having the agent claim to be a person, is not offered: it breaks DOD-03 and the CI check, and very likely Art. 50.

## Evidence
- `python3 -I scripts/voice_agent_spec.py check --agent task-call` and `--agent task-call-book`: PASS.
- Messaging server tests: see the pull request (opening line, call-back line, the agents' drift check and a new test that both prompts keep the plain answer).
- Not run: a real call, or the prompts on ElevenLabs.
