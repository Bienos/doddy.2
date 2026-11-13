# Calls Doddy makes for the person sound like their assistant; the AI disclosure is one short "wirtualny asystent" and a plain yes when asked

- **Date:** 2026-11-13
- **Decided by:** owner, in part: "trzeba też poprawić tego agenta, żeby nie mówił, że jest AI-em, że zawsze jest bardziej asystentem moim i że dzwonisz w moim imieniu … rozmawiamy, można z tobą rozmawiać jak z człowiekiem … reagujesz też normalnie". The part that keeps a disclosure is the constitution's (DOD-03, ADR-191) and is flagged for the owner below.
- **Status:** applied in #416; the two live call agents got the new prompts on 13 Nov 2026 on the owner's instruction (versions in `voice-agent/README.md`); not heard in a real call yet
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
- **Live agents:** `server/messaging/src/taskCalls/agentSpec.ts` has the new prompt hashes, and `SYNC_PENDING_PROMPTS` still accepts the two earlier prompts of each agent, so a deploy of this server doesn't stop calls before ElevenLabs is synced. The owner had both live prompts replaced on 13 Nov 2026 (versions in `voice-agent/README.md`); the server's own start check then logged "task-call agent matches its spec" for both agents.

## Consequences
- Callers hear a shorter, friendlier opening, and an agent that reacts like a person would, while still being told once, first, that it is a virtual assistant.
- **Open (a lawyer, before outside testers):** whether "wirtualny asystent" alone is enough disclosure under Art. 50 for Polish listeners, or the opening should say "wirtualny asystent AI". The owner chose to keep "wirtualny asystent" on 13 Nov 2026. Not legal advice; `legal_review_required_before_launch` in `docs/trust/config/doddy_rules.yaml` still applies.
- Removing the disclosure altogether, or having the agent claim to be a person, is not offered: it breaks DOD-03 and the CI check, and very likely Art. 50.

## Owner's answer on the wording (13 Nov 2026)
"wirtualny asystent może być, personal asystent, nawet może personalny asystent". "Wirtualny asystent" stays in the opening, because it tells the listener at once that this is not a person; the prompts call Doddy "the personal assistant of a person" for how it behaves, and asked directly it still says it is an AI. "Personalny asystent" alone would not say that it isn't human, so it is not used as the disclosure. Whether the wording meets EU AI Act Art. 50 remains `not legal advice`; a Polish lawyer before outside testers.

## Evidence
- `python3 -I scripts/voice_agent_spec.py check --agent task-call` and `--agent task-call-book`: PASS.
- Messaging server tests: see the pull request (opening line, call-back line, the agents' drift check and a new test that both prompts keep the plain answer).
- Not run: a real call, or the prompts on ElevenLabs.
