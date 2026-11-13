# Calls Doddy makes for you sound like your own assistant, with the AI said once

- **Date:** 2026-11-13
- **Decided by:** owner: "trzeba też poprawić tego agenta, żeby nie mówił, że jest AI-em, że zawsze jest bardziej asystentem moim i że dzwonisz w moim imieniu … można z tobą rozmawiać jak z człowiekiem i jesteś normalnie zachowujący się i reagujesz też normalnie". The "never say it's an AI" part was not applied (see Why).
- **Status:** accepted in the repository; **not on the live agents** (owner step below)
- **Replaces:** the opening wording of ADR-502 (`DECISIONS.md`) and rule 6/7 ("say clearly: Jestem asystentem AI") of both task-call prompts

## Why
The owner heard the task-call agents (`voice-agent/task-call/`, `voice-agent/task-call-book/`) as robotic: they opened with "mówi Doddy, asystent AI", were told "You are an AI, not a person" up front, and had to answer "Jestem asystentem AI." word for word. The owner wants a natural assistant calling on his behalf.

Dropping the AI disclosure entirely was not done:
- EU AI Act art. 50(1), in force for this since 2 August 2026, requires that a person talking to an AI system is told so, at the latest at the first interaction. The people Doddy calls are in Poland.
- The constitution (`docs/trust/config/doddy_rules.yaml`: `identity: ai_character_not_human`, DOD-03) forbids presenting Doddy as a human, and `scripts/voice_agent_spec.py` fails CI without it.
- Doddy calls in the owner's name: a business finding out later that "the assistant" was a bot it was told was a person is a risk to the owner, not only to Doddy.

## Decision
- **Opening (fixed, `server/messaging/src/taskCalls/opening.ts`):** "Dzień dobry, tu Doddy, asystent AI <imię w dopełniaczu>.[ <notice>] Chciałbym zapytać: <pytanie>" — he is the person's own assistant; the AI is said once, in four words, by the server, never phrased by the model.
- **Prompts:** a "How you sound" section: a warm, relaxed personal assistant on the phone; reacts to what is said ("Aha, rozumiem", "Super, dziękuję"), varies its words, short spoken sentences, asks again the way people do, repeats an hour or a number back once, waits when put on hold, matches the other side's tone. Asked whether it is a robot, it answers honestly in its own words ("Tak, jestem asystentem AI Anny…") and carries on; it never says or suggests it is a person, and doesn't keep bringing it up.
- **Unchanged:** every safety rule (no agreeing, no paying, only ticked facts, the fixed call-back line, the booking-confirm line said at most once, voicemail, automated menus, prompt injection, time limit).

## Consequences
- Both prompts changed, so their hashes in `server/messaging/src/taskCalls/agentSpec.ts` changed. Until the owner syncs the live agents, the server's drift check (ADR-503) still accepts the prompts that may be live: main's before 12 Nov and main's of 12 Nov (`SYNC_PENDING_PROMPTS`, texts in `server/messaging/test/fixtures/task-call-prompts/`). So deploying `doddy-messaging` doesn't stop calls; the calls just sound like the old prompt until the sync. Remove those entries once the live agents hold these prompts.
- Legal wording ("asystent AI <imię>") is still not reviewed by a lawyer (`calls.md`, open question 3).

## Evidence
- `python3 -I scripts/voice_agent_spec.py check --agent task-call` and `--agent task-call-book`: PASS.
- After merging main (13 Nov): `cd server/messaging && npm ci && npx tsc -p tsconfig.json && TEST_DATABASE_URL=<disposable Postgres> node --test --test-concurrency=1 dist/test/*.test.js`: 1129 tests, 1129 pass.
- Not run: a real call; the live ElevenLabs agents were not read or changed.

## Owner step
Update both live agents' prompts to these files (`node server/messaging/scripts/setup-task-call-agent.mjs --dry-run`, and `--agent book --dry-run`, print exactly what each agent should hold; the live ask agent and the booking agent `agent_9401m76my4d4fwbvvjf7b3b6tgrd` then get that prompt) then delete the two `SYNC_PENDING_PROMPTS` entries in `agentSpec.ts`. The server deploy and the sync can happen in either order.
