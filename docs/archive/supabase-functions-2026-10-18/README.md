# Old Supabase Edge Functions (saved 2026-10-18 before removal)

These two functions ran in the Supabase project `doddy-gateway` (ref `sliondswemhneuzehpoq`, eu-central-1). Their source was never in this repository. The owner chose to save the code and then delete them (`docs/research/1PASSWORD_SECRETS_2026-10.md`, decision 2). Nothing in the app calls them: the app's voice server is the Vercel project `doddy-voice-token`.

This is an archive. Don't deploy it, and don't treat it as current code.

| Function | Version | Last updated | What it is | Use seen in logs |
|---|---|---|---|---|
| `voice-token` | 1 | 2026-10-13 | The voice token server on Deno. `handler.js` is **identical** to `server/voice-token/src/handler.js` at commit `d6ece5d` (checked with `diff`). It still uses the retired `DODDY_ACCESS_CODES` sign-in | 14 Oct: 3 POSTs, all answered 500. None on 15, 16, 17 or 18 Oct |
| `assistant` | 4 | 2026-10-08 | An early M2 typed-assistant gateway (`/register`, `/chat`) using Postgres functions `register_device` and `consume_quota` in the same project. Replaced by `gateway/`. `index.ts` was copied from Supabase's API response; there is no git copy to compare it with | None from 14 to 18 Oct |

Logs were read through the Supabase log query (24-hour windows). Days before 14 October weren't checked.

## Secrets these functions read (names only)
- `voice-token`: `ELEVENLABS_API_KEY`, `ELEVENLABS_AGENT_ID`, `DODDY_ACCESS_CODES`, `DODDY_TOKENS_PER_HOUR`, `OPENAI_API_KEY`, `OPENAI_REALTIME_MODEL`, `OPENAI_REALTIME_VOICE`, `PICOVOICE_ACCESS_KEY`.
- `assistant`: `OPENAI_API_KEY`, `OPENAI_MODEL`, `DEVICE_DAILY_LIMIT`, `GLOBAL_DAILY_LIMIT`, `MAX_REGISTRATIONS_PER_DAY`, plus Supabase's own `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY`.

## Removing them (owner, in the Supabase dashboard)
The tools available to Claude in this session can't delete a function, so the owner does this:
1. Supabase → project `doddy-gateway` → Edge Functions → `voice-token` → delete. Same for `assistant`.
2. Edge Functions → Secrets: delete the secrets listed above. Deleting a function doesn't remove the project's secrets.
3. Optional: if the provider keys stored there (OpenAI, ElevenLabs, Picovoice) are the same keys the live Vercel servers use, they don't need rotating just because the functions are gone. If they are separate keys made only for Supabase, revoke them at the provider.
4. Optional, later: the `register_device` / `consume_quota` Postgres functions and their tables can stay or go. Nothing else uses them as far as this repository shows.
