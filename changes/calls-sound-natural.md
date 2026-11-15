Calls Doddy makes for you sound less stiff (owner, 15 Nov 2026).
- Shorter opening: "Dzień dobry, tu Doddy, wirtualny asystent Anny. Mam jedno krótkie pytanie. …?"
- Short spoken turns with one reaction word first.
- "Jakim tematem?" no longer ends the call as a wrong number.
- The three call agents' prompts are rewritten. Decision `2026-11-15-calls-sound-natural`.
Ran: `npm test` in `server/messaging` with a disposable PostgreSQL 16 (1317 pass, 0 fail, 0 skipped); `voice_agent_spec.py check` for the three call agents (PASS). Not run: a real call.
Deploy `doddy-messaging` first (it still accepts the old prompts), then sync the three live call agents' prompts.
Live (15 Nov 2026, about 14:07 UTC): `doddy-messaging` deployed with #522, then the three call agents' prompts synced (versions and rollbacks in `voice-agent/README.md`).
Later the same day (decision `2026-11-15-call-opening-asks-for-a-moment`):
- The opening asks "Dzwonię z krótkim pytaniem, czy mogę zająć chwilkę?" and the question follows a yes.
- "Are you a robot?" gets a light "Tak, ale bardzo kulturalnym. Jestem asystentem Anny…"; "are you a human?" always gets "Nie, jestem wirtualnym asystentem Anny…".
- The spec check's honesty lines replace the required words "jestem asystentem AI".
Live (15 Nov 2026, about 15:00 UTC): `doddy-messaging` deployed with #523, then the three call agents' prompts synced again (versions and rollbacks in `voice-agent/README.md`).
Then: "nie mam czasu" gets one quick try ("Jasne, nie ma problemu. To dosłownie jedno szybkie pytanie, zanim się rozłączę: …"), and a second no gets a polite goodbye.
Live (15 Nov 2026, about 16:25 UTC): `doddy-messaging` deployed with #527, then the three call agents synced with the "no time" retry (versions in `voice-agent/README.md`).
