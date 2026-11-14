// The daily retry of voice conversation deletions (decision 2026-11-12-voice-conversations-per-account).
//
// When an account is deleted, the conversations ElevenLabs didn't confirm gone stay recorded as owed. Vercel calls
// this handler once a day (`vercel.json` crons) and each owed account gets another try. Vercel sends
// `Authorization: Bearer $CRON_SECRET` when the project has a CRON_SECRET; without that setting this does nothing at
// all, so the route can't be used by anyone else to start the work.
//
// Logs and answers are counts only: never an id, a user id or a secret.
import { createHash, timingSafeEqual } from "node:crypto";
import { conversationClientFromEnv, retryOwedConversations } from "./conversations.js";
import { sessionStoreFromEnv, VoiceAuthStoreUnavailable } from "./voice-auth.js";

/**
 * @param {Request} request
 * @param {{ CRON_SECRET?: string }} env
 * @param {{ store?: object, elevenLabsFetch?: typeof fetch, storeFetch?: typeof fetch, now?: () => number,
 *   log?: (entry: object) => void }} [deps]
 */
export async function handleConversationsCron(request, env, deps = {}) {
  const now = deps.now ?? Date.now;
  const log = deps.log ?? ((entry) => console.log(JSON.stringify(entry)));
  const started = now();
  const finish = (status, error, body = { error }, headers = {}, extra = {}) => {
    log({ event: "voice_conversations_cron", status, error: error ?? null, ms: Math.max(0, now() - started), ...extra });
    return new Response(JSON.stringify(body), {
      status, headers: { "content-type": "application/json", "cache-control": "no-store", ...headers },
    });
  };

  if (request.method !== "GET") return finish(405, "method_not_allowed", undefined, { allow: "GET" });
  const secret = typeof env?.CRON_SECRET === "string" ? env.CRON_SECRET.trim() : "";
  if (!secret) return finish(503, "cron_not_configured");
  if (!sameSecret(bearer(request.headers.get("authorization")), secret)) return finish(401, "unauthorized");

  let store;
  try {
    store = deps.store ?? sessionStoreFromEnv(env, { fetch: deps.storeFetch });
  } catch {
    return finish(503, "server_not_configured");
  }
  const client = conversationClientFromEnv(env, deps.elevenLabsFetch ?? fetch);
  if (!client) return finish(503, "server_not_configured");
  try {
    const counts = await retryOwedConversations({ store, client, now });
    return finish(200, null, counts, {}, counts);
  } catch (error) {
    if (error instanceof VoiceAuthStoreUnavailable) return finish(503, "server_not_configured");
    return finish(500, "cron_failed");
  }
}

function bearer(header) {
  const match = /^Bearer (.+)$/.exec(header ?? "");
  return match ? match[1] : null;
}

/** Compares the digests, so the comparison takes the same time whatever the guess shares with the secret. */
function sameSecret(given, secret) {
  if (typeof given !== "string") return false;
  const digest = (value) => createHash("sha256").update(value, "utf8").digest();
  return timingSafeEqual(digest(given), digest(secret));
}
