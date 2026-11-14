// Deleting a Doddy account also deletes its voice conversations at ElevenLabs (decision
// 2026-11-12-voice-conversations-per-account).
//
// The voice server records which conversations belong to which account when it issues a token
// (`handler.js`), tags each conversation with a keyed user id, deletes both kinds when the account is deleted
// (`voice-auth.js`, action `delete-conversations`) and retries what is still owed once a day (`cron.js`).
//
// A conversation counts as deleted only when ElevenLabs answers 404 on reading it back after the delete (DOD-08).
// Whatever isn't confirmed stays recorded as owed. Nothing here writes an id, a token or a user id to a log:
// callers log counts.
import { identifierHash, keyRingFromEnv } from "./keys.js";

const ELEVENLABS_API = "https://api.elevenlabs.io";
const CALL_TIMEOUT_MS = 4_000;
const LIST_PAGE_SIZE = 100;
const MAX_LIST_PAGES = 10;
const CONCURRENCY = 8;
const ADD_CHUNK = 200;

/** The translator-only agent "Doddy 6 · Tłumacz" (decision 2026-11-12-translator-agent). Its id is public, like the main agent's. */
export const DEFAULT_TRANSLATOR_AGENT_ID = "agent_8901m787fgppedy9kkvg7memny34";

/**
 * Conversation ids kept per account. Recording never expires (the owner chose no retention limit at ElevenLabs, so a
 * record that ran out would leave conversations nobody could delete). The cap only stops one account from growing
 * without end: past it the oldest ids are let go of, and those conversations are still found by the account's user id
 * (or, for older ones, the iPhone's install id) when the account is deleted. At the 150 tokens a day an account may
 * use, 5 000 is more than a month at the limit.
 */
export const MAX_RECORDED_CONVERSATIONS = 5_000;

/** How long and how much one `delete-conversations` request works before it answers with what is left. */
export const REQUEST_BUDGET_MS = 9_000;
export const REQUEST_MAX_IDS = 300;
/** The daily retry: the function may run 60 seconds (`vercel.json`). */
export const CRON_BUDGET_MS = 45_000;
export const CRON_MAX_IDS = 3_000;
export const CRON_MAX_ACCOUNTS = 50;

const CONVERSATION_ID = /^[A-Za-z0-9_-]{1,128}$/;
// The id this iPhone made for itself (`UUID().uuidString`), the only kind of old per-install id there is. Anything
// shorter or plainer ("user", "anonymous") could belong to other people's conversations.
const INSTALL_USER_ID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const ACCOUNT_USER_ID = /^[0-9a-f]{32}$/;
const MAX_FILTERS = 8;

/** The id ElevenLabs gave a conversation, or null when it isn't one (absent, wrong type, or not an id's characters). */
export function validConversationId(value) {
  return typeof value === "string" && CONVERSATION_ID.test(value) ? value : null;
}

/** The iPhone's own per-install id in the shape the app makes it, or null. */
export function validInstallUserId(value) {
  return typeof value === "string" && INSTALL_USER_ID.test(value) ? value : null;
}

/**
 * Keyed hashes of one account, made with the identifier key (`src/keys.js`: `DODDY_IDENTIFIER_KEY`, or the session
 * signing key itself when that is not set, as the Apple subjects are): `recordKey` names its record in the store,
 * `userId` is what the app gives ElevenLabs as the conversation's user. They differ, so neither gives away the other,
 * and neither is the account. They have to stay the same for as long as the account lives, so they do not follow the
 * signing key when it is rotated. Null without a usable key.
 * @param {{ DODDY_SESSION_SIGNING_KEY?: string, DODDY_SESSION_SIGNING_KEY_PREVIOUS?: string, DODDY_IDENTIFIER_KEY?: string }} env
 * @param {string} accountId a Doddy account (`account:<id>`) or an older voice account's pseudonymous id
 */
export function conversationIdentity(env, accountId) {
  const keys = keyRingFromEnv(env);
  if (!keys) return null;
  if (typeof accountId !== "string" || accountId.length === 0) return null;
  const hash = (purpose) => identifierHash(keys, `${purpose}:${accountId}`);
  return { recordKey: hash("voice-conversations"), userId: hash("voice-user").slice(0, 32) };
}

/** Doddy's own agents: the main agent and the translator agent. Nothing is ever listed or deleted in any other. */
export function doddyAgentIds(env) {
  const ids = [env?.ELEVENLABS_AGENT_ID, env?.ELEVENLABS_TRANSLATOR_AGENT_ID || DEFAULT_TRANSLATOR_AGENT_ID]
    .map((id) => (typeof id === "string" ? id.trim() : ""))
    .filter((id) => id.length > 0);
  return [...new Set(ids)];
}

/**
 * ElevenLabs' conversation calls for the voice server: delete one conversation and read it back, and list a
 * user's conversations in Doddy's agents. Never throws: a call that fails is simply not a confirmation.
 */
export function createConversationClient({ apiKey, agentIds, fetch: fetchImpl = fetch, timeoutMs = CALL_TIMEOUT_MS }) {
  const allowed = new Set(agentIds);

  async function call(method, path) {
    try {
      return await fetchImpl(`${ELEVENLABS_API}${path}`, { method, headers: { "xi-api-key": apiKey }, signal: AbortSignal.timeout(timeoutMs) });
    } catch {
      return null;
    }
  }
  async function drain(response) {
    try { await response?.body?.cancel(); } catch { /* nothing to free */ }
  }

  return {
    /** True only when, after the delete, reading the conversation answers 404. */
    async deleteAndConfirm(id) {
      const path = `/v1/convai/conversations/${encodeURIComponent(id)}`;
      await drain(await call("DELETE", path));
      const readBack = await call("GET", path);
      await drain(readBack);
      return readBack?.status === 404;
    },

    /**
     * The ids of `userId`'s conversations in Doddy's agents, one list per agent, followed page by page. `complete`
     * is false when any list failed, was cut short, or had more pages than this reads in one go. An answer's
     * conversation counts only if it names one of Doddy's agents itself, whatever the filter did.
     */
    async listIds(userId, { hasTime = () => true } = {}) {
      const ids = new Set();
      let complete = true;
      for (const agentId of allowed) {
        let cursor = null;
        for (let page = 0; ; page += 1) {
          if (page >= MAX_LIST_PAGES || !hasTime()) { complete = false; break; }
          const query = new URLSearchParams({ agent_id: agentId, user_id: userId, page_size: String(LIST_PAGE_SIZE) });
          if (cursor) query.set("cursor", cursor);
          const response = await call("GET", `/v1/convai/conversations?${query}`);
          if (!response?.ok) { await drain(response); complete = false; break; }
          const body = await response.json().catch(() => null);
          if (!Array.isArray(body?.conversations)) { complete = false; break; }
          for (const conversation of body.conversations) {
            const id = validConversationId(conversation?.conversation_id);
            if (id && allowed.has(conversation?.agent_id)) ids.add(id);
          }
          if (body.has_more !== true) break;
          if (typeof body.next_cursor !== "string" || body.next_cursor === "") { complete = false; break; }
          cursor = body.next_cursor;
        }
      }
      return { ids: [...ids], complete };
    },
  };
}

/** A client for this server's ElevenLabs key and agents, or null when there is no key or no agent to ask about. */
export function conversationClientFromEnv(env, fetchImpl = fetch) {
  const apiKey = typeof env?.ELEVENLABS_API_KEY === "string" ? env.ELEVENLABS_API_KEY.trim() : "";
  const agentIds = doddyAgentIds(env);
  if (!apiKey || agentIds.length === 0) return null;
  return createConversationClient({ apiKey, agentIds, fetch: fetchImpl });
}

/**
 * Deletes one account's conversations as far as the budget allows and brings the record up to date:
 * 1. the ids already recorded, and the ids found by listing `filters` (user ids: the account's own, and the iPhone's
 *    old install id) in Doddy's agents, which are added to the record so they are owed from then on;
 * 2. each is deleted and read back; only a 404 removes it from the record.
 * `pending` is what is not confirmed gone: the ids still recorded, plus one when a list could not be read to the
 * end (or there is no ElevenLabs key), because what is there is then unknown. While pending is above 0 the account
 * stays in the owed list with its filters, for the daily retry; when it is 0 it leaves it.
 * The store throws (VoiceAuthStoreUnavailable) when it is unreachable, and then nothing is claimed.
 * @returns {Promise<{deleted: number, pending: number}>} counts only
 */
export async function sweepAccountConversations({
  store, client, recordKey, filters, now = Date.now, budgetMs = REQUEST_BUDGET_MS, maxIds = REQUEST_MAX_IDS,
}) {
  const startedAt = now();
  const hasTime = () => now() - startedAt < budgetMs;
  // The store first: if it is down, nothing is looked up or deleted.
  const recorded = await store.listConversations(recordKey, maxIds);

  let listingComplete = client !== null && client !== undefined;
  const found = [];
  if (client) {
    for (const userId of filters) {
      const result = await client.listIds(userId, { hasTime });
      if (!result.complete) listingComplete = false;
      found.push(...result.ids);
    }
    const known = new Set(recorded);
    const fresh = [...new Set(found)].filter((id) => !known.has(id));
    for (let at = 0; at < fresh.length; at += ADD_CHUNK) await store.addConversations(recordKey, fresh.slice(at, at + ADD_CHUNK), now());
    recorded.push(...fresh);
  }

  let deleted = 0;
  if (client) {
    const ids = recorded.slice(0, maxIds);
    for (let at = 0; at < ids.length && hasTime(); at += CONCURRENCY) {
      const batch = ids.slice(at, at + CONCURRENCY);
      const confirmed = await Promise.all(batch.map((id) => client.deleteAndConfirm(id)));
      const gone = batch.filter((_, index) => confirmed[index]);
      if (gone.length > 0) {
        await store.removeConversations(recordKey, gone);
        deleted += gone.length;
      }
    }
  }

  const pending = (await store.countConversations(recordKey)) + (listingComplete ? 0 : 1);
  if (pending > 0) await store.markOwed(recordKey, { filters }, now());
  else await store.clearOwed(recordKey);
  return { deleted, pending };
}

/**
 * The daily retry: every account that still owes deletions, in turn, until the budget is used. Counts only.
 * @returns {Promise<{accounts: number, deleted: number, pending: number}>}
 */
export async function retryOwedConversations({
  store, client, now = Date.now, budgetMs = CRON_BUDGET_MS, maxIds = CRON_MAX_IDS, maxAccounts = CRON_MAX_ACCOUNTS,
}) {
  const startedAt = now();
  const owed = (await store.listOwed()).slice(0, maxAccounts);
  let accounts = 0;
  let deleted = 0;
  let pending = 0;
  for (const { recordKey, record } of owed) {
    const left = budgetMs - (now() - startedAt);
    if (left <= 0) break;
    const result = await sweepAccountConversations({
      store, client, recordKey, filters: cleanFilters(record?.filters), now, budgetMs: left, maxIds,
    });
    accounts += 1;
    deleted += result.deleted;
    pending += result.pending;
  }
  return { accounts, deleted, pending };
}

/** The user ids to look for again, as this server wrote them: the account's own and an iPhone's install id. */
function cleanFilters(value) {
  if (!Array.isArray(value)) return [];
  return [...new Set(value.filter((id) => typeof id === "string" && (ACCOUNT_USER_ID.test(id) || INSTALL_USER_ID.test(id))))].slice(0, MAX_FILTERS);
}
