// Supabase Edge Function entry for the Doddy voice token server (server/voice-token).
// The same handler as the Vercel entry (api/voice-token.js): it uses only web-standard
// Request/Response/fetch, so it runs here unchanged. The app sends its own access code as the
// Bearer token, so Supabase's JWT check is off for this function; handler.js checks the code.
// Secrets live in the Supabase project (Edge Functions > Secrets), never in the app or the repo.
import { handleTokenRequest } from "./handler.js";

const KEYS = [
  "ELEVENLABS_API_KEY",
  "ELEVENLABS_AGENT_ID",
  "DODDY_ACCESS_CODES",
  "DODDY_TOKENS_PER_HOUR",
  "OPENAI_API_KEY",
  "OPENAI_REALTIME_MODEL",
  "OPENAI_REALTIME_VOICE",
  "PICOVOICE_ACCESS_KEY",
];

Deno.serve((request) => {
  // Only the handler's own settings; the project's Supabase keys are never passed in.
  const env = Object.fromEntries(KEYS.map((key) => [key, Deno.env.get(key)]));
  return handleTokenRequest(request, env);
});
