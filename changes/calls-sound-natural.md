Calls Doddy makes for you sound less stiff (owner, 15 Nov 2026).
- Shorter opening: "Dzień dobry, tu Doddy, wirtualny asystent Anny. Mam jedno krótkie pytanie. …?"
- Short spoken turns with one reaction word first.
- "Jakim tematem?" no longer ends the call as a wrong number.
- The three call agents' prompts are rewritten. Decision `2026-11-15-calls-sound-natural`.
Ran: `npm test` in `server/messaging` with a disposable PostgreSQL 16 (1317 pass, 0 fail, 0 skipped); `voice_agent_spec.py check` for the three call agents (PASS). Not run: a real call.
Deploy `doddy-messaging` first (it still accepts the old prompts), then sync the three live call agents' prompts.
