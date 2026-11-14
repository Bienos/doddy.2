import {
  createCipheriv,
  createDecipheriv,
  createHash,
  createHmac,
  createPrivateKey,
  createPublicKey,
  randomBytes,
  sign as signWithKey,
  timingSafeEqual,
  verify as verifySignature,
} from "node:crypto";
import { isIP } from "node:net";
import { AccountCheckUnavailable, authenticateDoddyAccount } from "./doddy-account.js";
import {
  conversationClientFromEnv, conversationIdentity, sweepAccountConversations, validInstallUserId,
} from "./conversations.js";
import {
  ACCESS_TOKEN_LABEL, APPLE_TOKEN_SEAL_LABEL, allMasters, asKeyRing, identifierHash, keyRingFromEnv, mastersNamed, purposeKey,
} from "./keys.js";

const APPLE_ISSUER = "https://appleid.apple.com";
const APPLE_KEYS_URL = "https://appleid.apple.com/auth/keys";
const APPLE_TOKEN_URL = "https://appleid.apple.com/auth/token";
const APPLE_REVOKE_URL = "https://appleid.apple.com/auth/revoke";
const APPLE_CALL_TIMEOUT_MS = 5_000;
const MAX_AUTHORIZATION_CODE_LENGTH = 1_024;
const MAX_APPLE_TOKEN_LENGTH = 4_096;
const ACCESS_TOKEN_SECONDS = 600;
const REFRESH_TOKEN_SECONDS = 30 * 24 * 60 * 60;
/**
 * How long Apple's refresh token for a Doddy account is kept, sealed (decision
 * 2026-11-09-apple-revoke-for-doddy-accounts). Longer than a voice session: a Doddy account has no
 * 30-day session, and the token is only useful on the day the account is deleted. Each new sign-in
 * with Apple replaces it with a fresh one, which restarts this clock.
 */
const APPLE_LINK_SECONDS = 400 * 24 * 60 * 60;
const NONCE_TTL_SECONDS = 600;
const MAX_BODY_BYTES = 24_000;
const STORE_TIMEOUT_MS = 2_000;
const STORE_PREFIX = "doddy:voice:v1:";
const HOUR_SECONDS = 3_600;
const DAY_SECONDS = 86_400;
/** Voice tokens per account per UTC day, on top of the hourly limit (ADR-712). */
export const DEFAULT_TOKENS_PER_DAY = 150;

// Sign-ins per caller address (ADR-712). Counted only for sign-ins that carry a valid Apple token,
// so junk can't use up the allowance of a shared address, and only on sign-in, never on refresh.
const DEFAULT_SIGNINS_PER_CLIENT_HOUR = 10;
const DEFAULT_SIGNINS_PER_CLIENT_DAY = 30;
/** With no usable address every caller shares one bucket, so that bucket gets a higher limit. */
const UNKNOWN_CLIENT_LIMIT_FACTOR = 10;

let appleKeysCache;
let appleKeysFetchedAt = -Infinity;
const APPLE_KEYS_TTL_MS = 60 * 60 * 1_000;
/** An unknown key ID fetches Apple's keys again at most this often (the backend's Supabase rule). */
const APPLE_KEYS_REFETCH_MIN_MS = 30_000;

export class VoiceAuthStoreUnavailable extends Error {
  constructor() {
    super("voice auth store unavailable");
    this.name = "VoiceAuthStoreUnavailable";
  }
}

/** Redis REST adapter. All state is shared across serverless instances; there is no memory fallback. */
export function createVoiceAuthStore({ url, token, fetch: fetchImpl = fetch, timeoutMs = STORE_TIMEOUT_MS }) {
  if (!isHttpsURL(url) || !token) throw new VoiceAuthStoreUnavailable();
  const base = url.replace(/\/+$/, "");

  async function exec(commands) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    try {
      const response = await fetchImpl(`${base}/multi-exec`, {
        method: "POST",
        headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
        body: JSON.stringify(commands.map((command) => command.map(String))),
        signal: controller.signal,
      });
      if (!response.ok) throw new VoiceAuthStoreUnavailable();
      const result = await response.json();
      if (!Array.isArray(result) || result.length !== commands.length) throw new VoiceAuthStoreUnavailable();
      return result.map((entry) => {
        if (!entry || typeof entry !== "object" || "error" in entry || !("result" in entry)) {
          throw new VoiceAuthStoreUnavailable();
        }
        return entry.result;
      });
    } catch {
      throw new VoiceAuthStoreUnavailable();
    } finally {
      clearTimeout(timer);
    }
  }

  async function evalScript(script, keys, args) {
    const [result] = await exec([["EVAL", script, keys.length, ...keys, ...args]]);
    return result;
  }

  const key = (kind, id) => `${STORE_PREFIX}${kind}:${id}`;
  const conversationsKey = (recordKey) => key("conversations", recordKey);
  const owedKey = `${STORE_PREFIX}conversations-owed`;
  return {
    async createSession({ userId, sessionId, refreshHash, nonceHash, ttlSeconds, nowSeconds }) {
      const script = `
        if redis.call('EXISTS', KEYS[1]) == 1 then return 0 end
        local refresh = redis.call('SET', KEYS[2], ARGV[1], 'EX', ARGV[3], 'NX')
        if not refresh then return 0 end
        redis.call('SET', KEYS[3], ARGV[2], 'EX', ARGV[3])
        redis.call('SET', KEYS[1], '1', 'EX', ARGV[4])
        redis.call('SADD', KEYS[4], ARGV[5])
        redis.call('EXPIRE', KEYS[4], ARGV[3])
        return 1
      `;
      const session = JSON.stringify({ userId, sessionId, refreshHash, createdAt: nowSeconds });
      const refresh = JSON.stringify({ userId, sessionId });
      return Number(await evalScript(script, [
        key("nonce", nonceHash), key("refresh", refreshHash), key("session", sessionId), key("user-sessions", userId),
      ], [refresh, session, ttlSeconds, NONCE_TTL_SECONDS, sessionId]));
    },

    /**
     * Swaps the refresh token for a new one. The swapped-out hash stays behind as a marked record,
     * with the same lifetime as the session, so if it is ever presented again the whole session
     * ends (ADR-712): the token was copied, or two devices hold it. Only the latest swapped-out
     * hash is kept; an older one is just unknown. Returns the new session record, `{ reused: true }`
     * when a swapped-out token came back (the session is already revoked), or null.
     */
    async rotateRefreshSession(oldHash, newHash, prior, ttlSeconds) {
      const script = `
        local old = redis.call('GET', KEYS[1])
        if not old then return false end
        local info = cjson.decode(old)
        local session = redis.call('GET', KEYS[2])
        if not session then redis.call('DEL', KEYS[1]); return false end
        local state = cjson.decode(session)
        if state.userId ~= info.userId or state.sessionId ~= info.sessionId then return false end
        if info.used then
          redis.call('DEL', KEYS[2])
          redis.call('DEL', ARGV[3] .. state.refreshHash)
          if state.previousRefreshHash then redis.call('DEL', ARGV[3] .. state.previousRefreshHash) end
          redis.call('SREM', KEYS[4], state.sessionId)
          return 'reused'
        end
        local fresh = redis.call('SET', KEYS[3], cjson.encode(info), 'EX', ARGV[1], 'NX')
        if not fresh then return false end
        if state.previousRefreshHash then redis.call('DEL', ARGV[3] .. state.previousRefreshHash) end
        info.used = true
        redis.call('SET', KEYS[1], cjson.encode(info), 'EX', ARGV[1])
        state.previousRefreshHash = ARGV[4]
        state.refreshHash = ARGV[2]
        redis.call('SET', KEYS[2], cjson.encode(state), 'EX', ARGV[1])
        redis.call('EXPIRE', KEYS[4], ARGV[1])
        redis.call('EXPIRE', KEYS[5], ARGV[1])
        return cjson.encode(state)
      `;
      const result = await evalScript(script, [
        key("refresh", oldHash), key("session", prior.sessionId), key("refresh", newHash), key("user-sessions", prior.userId),
        key("apple-token", prior.userId),
      ], [ttlSeconds, newHash, `${STORE_PREFIX}refresh:`, oldHash]);
      return result === "reused" ? { reused: true } : parseJSON(result);
    },

    async getRefresh(hash) {
      const [value] = await exec([["GET", key("refresh", hash)]]);
      return typeof value === "string" ? parseJSON(value) : null;
    },

    async getSession(sessionId) {
      const [value] = await exec([["GET", key("session", sessionId)]]);
      return typeof value === "string" ? parseJSON(value) : null;
    },

    /**
     * One voice token for `userId`: the account's hourly and daily limits and the service's hourly
     * limit, checked and counted in one step. Only a token that is actually issued is counted, so a
     * refused request never uses up the global budget (an account at its own limit can't starve
     * the others, ADR-671) and a refusal for a full global budget never uses up the account's own
     * allowance (ADR-712). `limit` says which one refused: user_hour, user_day or global.
     */
    async hitLimits(userId, perUserLimit, globalLimit, nowMs, perUserDailyLimit = DEFAULT_TOKENS_PER_DAY) {
      if (!Number.isSafeInteger(perUserDailyLimit) || perUserDailyLimit < 1) throw new VoiceAuthStoreUnavailable();
      const hourWindow = Math.floor(nowMs / (HOUR_SECONDS * 1_000));
      const dayWindow = Math.floor(nowMs / (DAY_SECONDS * 1_000));
      const script = `
        local hour = tonumber(redis.call('GET', KEYS[1]) or '0')
        local day = tonumber(redis.call('GET', KEYS[2]) or '0')
        local global = tonumber(redis.call('GET', KEYS[3]) or '0')
        local refused = 0
        if hour >= tonumber(ARGV[3]) then refused = 1
        elseif day >= tonumber(ARGV[4]) then refused = 2
        elseif global >= tonumber(ARGV[5]) then refused = 3 end
        if refused == 0 then
          hour = redis.call('INCR', KEYS[1])
          if hour == 1 then redis.call('EXPIRE', KEYS[1], ARGV[1]) end
          day = redis.call('INCR', KEYS[2])
          if day == 1 then redis.call('EXPIRE', KEYS[2], ARGV[2]) end
          global = redis.call('INCR', KEYS[3])
          if global == 1 then redis.call('EXPIRE', KEYS[3], ARGV[1]) end
        end
        return {refused, hour, day, global}
      `;
      const counts = await evalScript(script, [
        key("limit-user", `${userId}:${hourWindow}`), key("limit-user-day", `${userId}:${dayWindow}`),
        key("limit-global", String(hourWindow)),
      ], [HOUR_SECONDS + 60, DAY_SECONDS + 3_600, perUserLimit, perUserDailyLimit, globalLimit]);
      if (!Array.isArray(counts) || counts.length !== 4) throw new VoiceAuthStoreUnavailable();
      const [refused, perUserCount, dailyCount, globalCount] = counts.map(Number);
      if (![refused, perUserCount, dailyCount, globalCount].every(Number.isSafeInteger)) throw new VoiceAuthStoreUnavailable();
      const limit = [null, "user_hour", "user_day", "global"][refused];
      if (limit === undefined) throw new VoiceAuthStoreUnavailable();
      return { allowed: refused === 0, limit, perUserCount, dailyCount, globalCount,
        retryAfterSeconds: secondsUntilWindowEnds(nowMs, limit === "user_day" ? DAY_SECONDS : HOUR_SECONDS) };
    },

    /**
     * One sign-in for a caller (`bucket` is a keyed hash of the address, never the address). Checked
     * and counted in one step against the hourly and the daily limit; only a granted sign-in counts.
     */
    async hitSignInLimits(bucket, perHourLimit, perDayLimit, nowMs) {
      const hourWindow = Math.floor(nowMs / (HOUR_SECONDS * 1_000));
      const dayWindow = Math.floor(nowMs / (DAY_SECONDS * 1_000));
      const script = `
        local hour = tonumber(redis.call('GET', KEYS[1]) or '0')
        local day = tonumber(redis.call('GET', KEYS[2]) or '0')
        local refused = 0
        if hour >= tonumber(ARGV[3]) then refused = 1
        elseif day >= tonumber(ARGV[4]) then refused = 2 end
        if refused == 0 then
          hour = redis.call('INCR', KEYS[1])
          if hour == 1 then redis.call('EXPIRE', KEYS[1], ARGV[1]) end
          day = redis.call('INCR', KEYS[2])
          if day == 1 then redis.call('EXPIRE', KEYS[2], ARGV[2]) end
        end
        return {refused, hour, day}
      `;
      const counts = await evalScript(script, [
        key("limit-signin", `${bucket}:${hourWindow}`), key("limit-signin-day", `${bucket}:${dayWindow}`),
      ], [HOUR_SECONDS + 60, DAY_SECONDS + 3_600, perHourLimit, perDayLimit]);
      if (!Array.isArray(counts) || counts.length !== 3) throw new VoiceAuthStoreUnavailable();
      const [refused, hourCount, dayCount] = counts.map(Number);
      if (![refused, hourCount, dayCount].every(Number.isSafeInteger)) throw new VoiceAuthStoreUnavailable();
      const limit = [null, "client_hour", "client_day"][refused];
      if (limit === undefined) throw new VoiceAuthStoreUnavailable();
      return { allowed: refused === 0, limit, hourCount, dayCount,
        retryAfterSeconds: secondsUntilWindowEnds(nowMs, limit === "client_day" ? DAY_SECONDS : HOUR_SECONDS) };
    },

    async revokeSession(sessionId, userId) {
      const script = `
        local session = redis.call('GET', KEYS[1])
        if not session then return 0 end
        local state = cjson.decode(session)
        if state.userId ~= ARGV[1] then return 0 end
        redis.call('DEL', KEYS[1])
        redis.call('DEL', KEYS[2] .. state.refreshHash)
        if state.previousRefreshHash then redis.call('DEL', KEYS[2] .. state.previousRefreshHash) end
        redis.call('SREM', KEYS[3], state.sessionId)
        return 1
      `;
      return Number(await evalScript(script, [key("session", sessionId), `${STORE_PREFIX}refresh:`, key("user-sessions", userId)], [userId]));
    },

    /** The Apple refresh token, sealed with a key derived from the signing key (ADR-524). */
    async setAppleToken(userId, sealed, ttlSeconds) {
      await exec([["SET", key("apple-token", userId), sealed, "EX", ttlSeconds]]);
    },

    async getAppleToken(userId) {
      const [value] = await exec([["GET", key("apple-token", userId)]]);
      return typeof value === "string" ? value : null;
    },

    /** Forgets the sealed Apple token alone (a Doddy account's, once Apple has revoked it). */
    async deleteAppleToken(userId) {
      await exec([["DEL", key("apple-token", userId)]]);
    },

    // ---- Voice conversations at ElevenLabs, per account (decision 2026-11-12-voice-conversations-per-account) ----
    // One sorted set per account, under the keyed hash `recordKey` (never the account itself): the ids of its
    // conversations, scored by when they were issued or found. These keys never expire: the owner chose no retention
    // limit at ElevenLabs, so a record that ran out would leave conversations nobody could delete. Only a confirmed
    // deletion removes an id. `deleteAccount` below leaves them alone on purpose.

    /** Keeps `conversationId`, and lets go of the oldest ids past `maxEntries`. Returns how many it let go of. */
    async recordConversation(recordKey, conversationId, nowMs, maxEntries) {
      const script = `
        redis.call('ZADD', KEYS[1], ARGV[2], ARGV[1])
        local extra = redis.call('ZCARD', KEYS[1]) - tonumber(ARGV[3])
        if extra > 0 then redis.call('ZREMRANGEBYRANK', KEYS[1], 0, extra - 1) else extra = 0 end
        return extra
      `;
      const trimmed = Number(await evalScript(script, [conversationsKey(recordKey)], [conversationId, nowMs, maxEntries]));
      if (!Number.isSafeInteger(trimmed) || trimmed < 0) throw new VoiceAuthStoreUnavailable();
      return trimmed;
    },

    /** At most `limit` recorded ids, oldest first. */
    async listConversations(recordKey, limit) {
      const [ids] = await exec([["ZRANGE", conversationsKey(recordKey), 0, limit - 1]]);
      if (!Array.isArray(ids) || !ids.every((id) => typeof id === "string")) throw new VoiceAuthStoreUnavailable();
      return ids;
    },

    async countConversations(recordKey) {
      const [count] = await exec([["ZCARD", conversationsKey(recordKey)]]);
      if (!Number.isSafeInteger(Number(count))) throw new VoiceAuthStoreUnavailable();
      return Number(count);
    },

    /** Adds ids found at ElevenLabs without touching the ones already recorded. Returns how many were new. */
    async addConversations(recordKey, ids, nowMs) {
      if (ids.length === 0) return 0;
      const [added] = await exec([["ZADD", conversationsKey(recordKey), "NX", ...ids.flatMap((id) => [nowMs, id])]]);
      return Number(added);
    },

    /** Forgets ids ElevenLabs confirmed gone. */
    async removeConversations(recordKey, ids) {
      if (ids.length === 0) return 0;
      const [removed] = await exec([["ZREM", conversationsKey(recordKey), ...ids]]);
      return Number(removed);
    },

    /** The account still owes deletions: what is needed to look again (user ids), until it owes nothing. */
    async markOwed(recordKey, record, nowMs) {
      await exec([["HSET", owedKey, recordKey, JSON.stringify({ ...record, since: nowMs })]]);
    },

    async clearOwed(recordKey) {
      await exec([["HDEL", owedKey, recordKey]]);
    },

    /** Every account that owes deletions: `{ recordKey, record }`. Entries that can't be read are left out. */
    async listOwed() {
      const [all] = await exec([["HGETALL", owedKey]]);
      const pairs = Array.isArray(all)
        ? Array.from({ length: Math.floor(all.length / 2) }, (_, n) => [all[2 * n], all[2 * n + 1]])
        : all && typeof all === "object" ? Object.entries(all) : [];
      return pairs.flatMap(([recordKey, text]) => {
        const record = typeof recordKey === "string" && typeof text === "string" ? parseJSON(text) : null;
        return record && typeof record === "object" ? [{ recordKey, record }] : [];
      });
    },

    async deleteAccount(userId) {
      const script = `
        local sessions = redis.call('SMEMBERS', KEYS[1])
        for _, sid in ipairs(sessions) do
          local sessionKey = ARGV[1] .. sid
          local session = redis.call('GET', sessionKey)
          if session then
            local state = cjson.decode(session)
            redis.call('DEL', ARGV[2] .. state.refreshHash)
            if state.previousRefreshHash then redis.call('DEL', ARGV[2] .. state.previousRefreshHash) end
            redis.call('DEL', sessionKey)
          end
        end
        redis.call('DEL', KEYS[1])
        redis.call('DEL', KEYS[2])
        return #sessions
      `;
      return Number(await evalScript(script, [key("user-sessions", userId), key("apple-token", userId)],
        [`${STORE_PREFIX}session:`, `${STORE_PREFIX}refresh:`]));
    },
  };
}

/**
 * POST actions: sign-in (Apple identity token + raw nonce), refresh (opaque refresh token),
 * sign-out (bearer access token), delete-account (bearer access token).
 *
 * Two more are for a Doddy account (a Supabase user, decision 2026-11-09-apple-revoke-for-doddy-accounts)
 * and take its access token, not a voice session: `apple-link` (right after Sign in with Apple, keeps
 * Apple's refresh token sealed) and `apple-revoke` (before the account is deleted, tells Apple to end
 * the link). Neither touches the voice account.
 *
 * `delete-conversations` also takes a Doddy account's access token (decision
 * 2026-11-12-voice-conversations-per-account): the account's voice conversations at ElevenLabs are deleted and read
 * back, and the answer is counts only, `{ deleted, pending }`. `delete-account` does the same for an older Apple
 * voice account's conversations and adds the counts to its answer.
 */
export async function handleVoiceAuthRequest(request, env, deps = {}) {
  const now = deps.now ?? Date.now;
  const log = deps.log ?? ((entry) => console.log(JSON.stringify(entry)));
  const started = now();
  let action = "unknown";
  const finish = (status, error, body = { error }, headers = {}, extra = {}) => {
    log({ event: "voice_auth", action, status, error: error ?? null, ms: Math.max(0, now() - started), ...extra });
    return json(status, body, headers);
  };

  if (request.method !== "POST") return finish(405, "method_not_allowed", undefined, { allow: "POST" });
  const body = await readBody(request);
  if (!body) return finish(400, "invalid_request");
  action = body.action;
  if (!["sign-in", "refresh", "sign-out", "delete-account", "apple-link", "apple-revoke", "delete-conversations"].includes(action)) return finish(400, "unknown_action");

  let store;
  let keys;
  try {
    store = deps.store ?? createVoiceAuthStore({
      url: env.UPSTASH_REDIS_REST_URL, token: env.UPSTASH_REDIS_REST_TOKEN,
      fetch: deps.storeFetch ?? fetch, timeoutMs: deps.storeTimeoutMs,
    });
    keys = voiceKeys(env);
  } catch {
    return finish(503, "server_not_configured");
  }

  try {
    if (action === "sign-in") {
      if (typeof body.identityToken !== "string" || typeof body.rawNonce !== "string"
          || body.identityToken.length > 18_000 || !/^[A-Za-z0-9_-]{40,64}$/.test(body.rawNonce)
          || body.provider !== "elevenlabs"
          || typeof env.APPLE_BUNDLE_ID !== "string" || !env.APPLE_BUNDLE_ID.trim()) {
        return finish(400, "invalid_request");
      }
      if (!voiceProviderConfigured(body.provider, env)) return finish(503, "server_not_configured");
      // A bad setting stops new sign-ins only; refresh and sign-out don't read it.
      const signIns = signInLimits(env);
      if (!signIns || typeof store.hitSignInLimits !== "function") return finish(503, "server_not_configured");
      const claims = await (deps.verifyAppleIdentityToken ?? verifyAppleIdentityToken)(
        body.identityToken, body.rawNonce, env.APPLE_BUNDLE_ID.trim(), { fetch: deps.fetch ?? fetch, now: now() });
      if (!claims) return finish(401, "apple_sign_in_failed");
      // One Apple ID makes one account, so what bounds how many accounts one caller can make is a
      // limit per caller address (ADR-712). Counted here, after Apple has vouched for the token and
      // before anything is created, so unverified requests never use up a shared address's allowance.
      const address = clientAddress(request, env);
      const unknownCaller = address === "unknown";
      const callerFlag = unknownCaller ? { noClientAddress: true } : {};
      const factor = unknownCaller ? UNKNOWN_CLIENT_LIMIT_FACTOR : 1;
      const turn = await store.hitSignInLimits(identifierHash(keys, `client:${address}`),
        signIns.perHour * factor, signIns.perDay * factor, now());
      if (!turn.allowed) {
        return finish(429, "rate_limited", undefined, { "retry-after": String(turn.retryAfterSeconds) },
          { limit: turn.limit, ...callerFlag });
      }
      // The pseudonym is a keyed hash of Apple's subject made with the identifier key, which is what it has always been
      // made with: it is the person's account, so it never changes when the signing key does (src/keys.js).
      const userId = identifierHash(keys, `apple-sub:${claims.sub}`);
      const sessionId = randomBytes(24).toString("base64url");
      const refreshToken = randomBytes(32).toString("base64url");
      const refreshHash = sha256(refreshToken);
      const nonceHash = sha256(claims.nonce);
      const created = await store.createSession({
        userId, sessionId, refreshHash, nonceHash, ttlSeconds: REFRESH_TOKEN_SECONDS,
        nowSeconds: Math.floor(now() / 1_000),
      });
      if (created !== 1) return finish(401, "apple_sign_in_failed");
      // Best effort: keep Apple's refresh token so deleting the account can revoke Sign in with
      // Apple (ADR-524). A failure here never stops the sign-in.
      if (appleRevocationConfigured(env) && typeof body.authorizationCode === "string"
          && body.authorizationCode.length > 0 && body.authorizationCode.length <= MAX_AUTHORIZATION_CODE_LENGTH) {
        try {
          const appleToken = await (deps.exchangeAppleAuthorizationCode ?? exchangeAppleAuthorizationCode)(
            body.authorizationCode, env, { fetch: deps.fetch ?? fetch, now: now(), expectedSub: claims.sub });
          if (appleToken) await store.setAppleToken(userId, sealAppleToken(appleToken, keys), REFRESH_TOKEN_SECONDS);
        } catch {
          // The account works without it; deleting it later just can't revoke at Apple.
        }
      }
      return finish(200, null, sessionReply(keys, userId, sessionId, refreshToken, now()), {}, callerFlag);
    }

    if (action === "refresh") {
      if (typeof body.refreshToken !== "string" || body.refreshToken.length < 40 || body.refreshToken.length > 128) {
        return finish(401, "session_expired");
      }
      const oldHash = sha256(body.refreshToken);
      const prior = await store.getRefresh(oldHash);
      if (!validSessionRecord(prior)) return finish(401, "session_expired");
      const existing = await store.getSession(prior.sessionId);
      if (!validStoredSession(existing, prior)) return finish(401, "session_expired");
      const nextToken = randomBytes(32).toString("base64url");
      const nextHash = sha256(nextToken);
      const rotated = await store.rotateRefreshSession(oldHash, nextHash, prior, REFRESH_TOKEN_SECONDS);
      // A token that was already swapped for a newer one came back: the store has ended the whole
      // session (ADR-712). The caller sees the same answer as for any other dead token; only the
      // content-free log line says why.
      if (rotated?.reused) return finish(401, "session_expired", undefined, {}, { reuse: true });
      if (!rotated) return finish(401, "session_expired");
      return finish(200, null, sessionReply(keys, prior.userId, prior.sessionId, nextToken, now()));
    }

    if (action === "delete-conversations") {
      let account;
      try {
        account = await (deps.authenticateDoddyAccount ?? authenticateDoddyAccount)(
          request, env, { ...(deps.accountFetch ? { fetch: deps.accountFetch } : {}), now: now() });
      } catch (error) {
        // The project's keys couldn't be read: "try again", never "signed out".
        if (error instanceof AccountCheckUnavailable) return finish(503, "account_check_unavailable");
        throw error;
      }
      if (!account) return finish(401, "session_expired");
      // The iPhone's old per-install id (what it gave ElevenLabs before the account's own user id): one more
      // user id to look for. Only the shape the app makes it in; anything else could be someone else's.
      const installUserId = body.installUserId === undefined || body.installUserId === null ? null : validInstallUserId(body.installUserId);
      if (body.installUserId !== undefined && body.installUserId !== null && !installUserId) return finish(400, "invalid_request");
      const identity = conversationIdentity(env, account.userId);
      if (!identity) return finish(503, "server_not_configured");
      // Each call can reach ElevenLabs many times, so it counts against the same per-caller limits as a sign-in.
      const signIns = signInLimits(env);
      if (!signIns || typeof store.hitSignInLimits !== "function") return finish(503, "server_not_configured");
      const turn = await store.hitSignInLimits(identifierHash(keys, `delete-conversations:${account.userId}`),
        signIns.perHour, signIns.perDay, now());
      if (!turn.allowed) {
        return finish(429, "rate_limited", undefined, { "retry-after": String(turn.retryAfterSeconds) }, { limit: turn.limit });
      }
      const counts = await sweepAccountConversations({
        store, client: conversationClientFromEnv(env, deps.elevenLabsFetch ?? fetch), recordKey: identity.recordKey,
        filters: [identity.userId, ...(installUserId ? [installUserId] : [])], now,
      });
      // Counts only: never an id, in the answer or the log.
      return finish(200, null, counts, {}, counts);
    }

    if (action === "apple-link" || action === "apple-revoke") {
      let account;
      try {
        account = await (deps.authenticateDoddyAccount ?? authenticateDoddyAccount)(
          request, env, { ...(deps.accountFetch ? { fetch: deps.accountFetch } : {}), now: now() });
      } catch (error) {
        // The project's keys couldn't be read: "try again", never "signed out".
        if (error instanceof AccountCheckUnavailable) return finish(503, "account_check_unavailable");
        throw error;
      }
      if (!account) return finish(401, "session_expired");
      // Without the owner's Sign in with Apple key there is nothing to keep or revoke (ADR-524).
      if (!appleRevocationConfigured(env)) {
        return finish(200, null, action === "apple-link" ? { linked: false } : { appleRevoked: false, apple: "not_configured" },
          {}, { apple: "not_configured" });
      }
      if (action === "apple-link") {
        if (typeof body.identityToken !== "string" || typeof body.rawNonce !== "string"
            || typeof body.authorizationCode !== "string"
            || body.identityToken.length > 18_000 || !/^[A-Za-z0-9_-]{40,64}$/.test(body.rawNonce)
            || body.authorizationCode.length < 1 || body.authorizationCode.length > MAX_AUTHORIZATION_CODE_LENGTH) {
          return finish(400, "invalid_request");
        }
        // Each call can reach Apple, so it counts against the same per-caller limits as a sign-in.
        const signIns = signInLimits(env);
        if (!signIns || typeof store.hitSignInLimits !== "function") return finish(503, "server_not_configured");
        const turn = await store.hitSignInLimits(identifierHash(keys, `apple-link:${account.userId}`),
          signIns.perHour, signIns.perDay, now());
        if (!turn.allowed) {
          return finish(429, "rate_limited", undefined, { "retry-after": String(turn.retryAfterSeconds) }, { limit: turn.limit });
        }
        // The code must belong to the same Apple person as the identity token the app just used, so
        // a code from another Apple account is never kept (the same rule as the voice sign-in).
        const claims = await (deps.verifyAppleIdentityToken ?? verifyAppleIdentityToken)(
          body.identityToken, body.rawNonce, env.APPLE_BUNDLE_ID.trim(), { fetch: deps.fetch ?? fetch, now: now() });
        if (!claims) return finish(401, "apple_sign_in_failed");
        const appleToken = await (deps.exchangeAppleAuthorizationCode ?? exchangeAppleAuthorizationCode)(
          body.authorizationCode, env, { fetch: deps.fetch ?? fetch, now: now(), expectedSub: claims.sub });
        // The account works without it; deleting it later just can't revoke at Apple.
        if (!appleToken) return finish(200, null, { linked: false }, {}, { apple: "not_linked" });
        await store.setAppleToken(account.userId, sealAppleToken(appleToken, keys), APPLE_LINK_SECONDS);
        return finish(200, null, { linked: true }, {}, { apple: "linked" });
      }
      // apple-revoke: Apple first, then forget the token. A failed revoke keeps it, so asking again can work.
      const sealed = await store.getAppleToken(account.userId);
      const appleToken = sealed ? openAppleToken(sealed, keys) : null;
      const apple = !appleToken ? "no_token"
        : await (deps.revokeAppleToken ?? revokeAppleToken)(appleToken, env, { fetch: deps.fetch ?? fetch, now: now() })
          ? "revoked" : "failed";
      if (apple !== "failed" && sealed) await store.deleteAppleToken(account.userId);
      return finish(200, null, { appleRevoked: apple === "revoked", apple }, {}, { apple });
    }

    const access = await authenticateVoiceSession(request, env, { store, keys, now: now() });
    if (!access) return finish(401, "session_expired");
    if (action === "sign-out") {
      await store.revokeSession(access.sessionId, access.userId);
      return finish(200, null, { signedOut: true });
    }
    // Revoke Sign in with Apple first (ADR-524), then delete everything. Apple failing never
    // keeps the account: the reply says whether the Apple link was revoked.
    let apple = "not_configured";
    if (appleRevocationConfigured(env)) {
      const sealed = await store.getAppleToken(access.userId);
      const appleToken = sealed ? openAppleToken(sealed, keys) : null;
      apple = !appleToken ? "no_token"
        : await (deps.revokeAppleToken ?? revokeAppleToken)(appleToken, env, { fetch: deps.fetch ?? fetch, now: now() })
          ? "revoked" : "failed";
    }
    // The account's voice conversations at ElevenLabs too (decision 2026-11-12-voice-conversations-per-account),
    // before the session goes. ElevenLabs failing never keeps the account: what isn't confirmed gone stays recorded
    // as owed and is retried by the daily job, and the answer says how many (`pending`). The store being down does
    // stop it (503), so nothing is forgotten.
    const identity = conversationIdentity(env, access.userId);
    const conversations = identity
      ? await sweepAccountConversations({
        store, client: conversationClientFromEnv(env, deps.elevenLabsFetch ?? fetch), recordKey: identity.recordKey,
        filters: [identity.userId], now,
      })
      : { deleted: 0, pending: 0 };
    await store.deleteAccount(access.userId);
    return finish(200, null, { deleted: true, appleRevoked: apple === "revoked", conversations }, {}, { apple, ...conversations });
  } catch (error) {
    if (error instanceof VoiceAuthStoreUnavailable) return finish(503, "server_not_configured");
    return finish(500, "voice_auth_failed");
  }
}

export async function authenticateVoiceSession(request, env, deps = {}) {
  const store = deps.store;
  // `deps.keys` (or the older `deps.signingKey`) is a key set, or the signing secret itself; otherwise the environment's.
  const keys = deps.keys !== undefined || deps.signingKey !== undefined
    ? asKeyRing(deps.keys ?? deps.signingKey) : keyRingFromEnv(env);
  if (!store || !keys) throw new VoiceAuthStoreUnavailable();
  const token = bearer(request.headers.get("authorization"));
  if (!token) return null;
  const claims = verifyAccessToken(token, keys, deps.now ?? Date.now());
  if (!claims) return null;
  const session = await store.getSession(claims.sid);
  if (!session || session.userId !== claims.sub || session.sessionId !== claims.sid) return null;
  return { userId: claims.sub, sessionId: claims.sid };
}

export function sessionStoreFromEnv(env, deps = {}) {
  return createVoiceAuthStore({
    url: env.UPSTASH_REDIS_REST_URL, token: env.UPSTASH_REDIS_REST_TOKEN,
    fetch: deps.fetch ?? fetch, timeoutMs: deps.storeTimeoutMs,
  });
}

/**
 * A 10-minute access token: an HS256 JWT signed with the access-token key derived from the current signing key, and
 * naming that key in its `kid` header. `keys` is a key set (`src/keys.js`) or the signing secret itself. The previous
 * key never signs.
 */
export function signAccessToken(payload, keys, nowMs = Date.now()) {
  const ring = asKeyRing(keys);
  if (!ring) throw new Error("voice keys are not configured");
  const nowSeconds = Math.floor(nowMs / 1_000);
  const header = base64urlJSON({ alg: "HS256", typ: "JWT", kid: ring.current.kid });
  const claims = base64urlJSON({ iss: "doddy-voice", aud: "voice", sub: payload.userId, sid: payload.sessionId,
    iat: nowSeconds, exp: nowSeconds + ACCESS_TOKEN_SECONDS });
  const input = `${header}.${claims}`;
  return `${input}.${createHmac("sha256", purposeKey(ring.current.master, ACCESS_TOKEN_LABEL)).update(input).digest("base64url")}`;
}

/**
 * The claims of a valid access token, or null. A token naming a key id is checked with the access-token key of the
 * current or the previous signing key, whichever the id names; an unknown id is refused. A token with no key id is
 * the format from before key ids, signed with the signing key itself: it is checked with the current key and the
 * previous one, until it expires (10 minutes), so a deploy or a rotation signs nobody out.
 */
export function verifyAccessToken(token, keys, nowMs = Date.now()) {
  try {
    const ring = asKeyRing(keys);
    if (!ring || typeof token !== "string" || token.length > 4_096) return null;
    const [headerPart, claimsPart, signaturePart, ...extra] = token.split(".");
    if (!headerPart || !claimsPart || !signaturePart || extra.length) return null;
    const header = parseJSON(Buffer.from(headerPart, "base64url").toString("utf8"));
    if (header?.alg !== "HS256") return null;
    const input = `${headerPart}.${claimsPart}`;
    const actual = Buffer.from(signaturePart, "base64url");
    const candidates = header.kid === undefined
      ? allMasters(ring)
      : mastersNamed(ring, header.kid).map((master) => purposeKey(master, ACCESS_TOKEN_LABEL));
    const signed = candidates.some((key) => {
      const expected = createHmac("sha256", key).update(input).digest();
      return actual.length === expected.length && timingSafeEqual(actual, expected);
    });
    if (!signed) return null;
    const claims = parseJSON(Buffer.from(claimsPart, "base64url").toString("utf8"));
    if (claims?.iss !== "doddy-voice" || claims?.aud !== "voice"
        || typeof claims.sub !== "string" || typeof claims.sid !== "string"
        || !Number.isSafeInteger(claims.exp) || claims.exp <= Math.floor(nowMs / 1_000)) return null;
    return claims;
  } catch {
    return null;
  }
}

export async function verifyAppleIdentityToken(token, rawNonce, audience, { fetch: fetchImpl, now }) {
  const parts = token.split(".");
  if (parts.length !== 3 || token.length > 18_000) return null;
  const [headerText, claimsText, signatureText] = parts;
  const header = parseJSON(Buffer.from(headerText, "base64url").toString("utf8"));
  const claims = parseJSON(Buffer.from(claimsText, "base64url").toString("utf8"));
  if (header?.alg !== "RS256" || typeof header.kid !== "string" || !claims) return null;
  const keys = await appleSigningKeys(fetchImpl, header.kid, now);
  const jwk = keys.find((item) => item.kid === header.kid && item.kty === "RSA" && item.use === "sig");
  if (!jwk) return null;
  const key = createPublicKey({ key: jwk, format: "jwk" });
  const signature = Buffer.from(signatureText, "base64url");
  if (!verifySignature("RSA-SHA256", Buffer.from(`${headerText}.${claimsText}`), key, signature)) return null;
  const aud = Array.isArray(claims.aud) ? claims.aud : [claims.aud];
  const nonceHash = createHash("sha256").update(rawNonce, "utf8").digest("hex");
  const nowSeconds = Math.floor(now / 1_000);
  if (claims.iss !== APPLE_ISSUER || !aud.includes(audience) || !Number.isSafeInteger(claims.exp)
      || !Number.isSafeInteger(claims.iat) || claims.exp <= nowSeconds || claims.iat > nowSeconds + 60
      || claims.nonce !== nonceHash || typeof claims.sub !== "string"
      || claims.sub.length < 1 || claims.sub.length > 255) return null;
  return { sub: claims.sub, nonce: rawNonce };
}

/** Revoking needs a Sign in with Apple key from the Apple Developer account (ADR-524). */
export function appleRevocationConfigured(env) {
  return [env.APPLE_BUNDLE_ID, env.APPLE_TEAM_ID, env.APPLE_SIGN_IN_KEY_ID, env.APPLE_SIGN_IN_PRIVATE_KEY]
    .every((value) => typeof value === "string" && value.trim().length > 0);
}

/** The ES256 client secret Apple's token and revoke endpoints ask for; valid for 5 minutes. */
export function appleClientSecret(env, nowMs = Date.now()) {
  const iat = Math.floor(nowMs / 1_000);
  const header = base64urlJSON({ alg: "ES256", kid: env.APPLE_SIGN_IN_KEY_ID.trim() });
  const claims = base64urlJSON({
    iss: env.APPLE_TEAM_ID.trim(), iat, exp: iat + 300, aud: APPLE_ISSUER, sub: env.APPLE_BUNDLE_ID.trim(),
  });
  const input = `${header}.${claims}`;
  // Hosts often store a multi-line .p8 key with literal "\n".
  const key = createPrivateKey(env.APPLE_SIGN_IN_PRIVATE_KEY.trim().replace(/\\n/g, "\n"));
  const signature = signWithKey("sha256", Buffer.from(input), { key, dsaEncoding: "ieee-p1363" });
  return `${input}.${signature.toString("base64url")}`;
}

/**
 * Swaps the one-time authorization code from sign-in for Apple's refresh token, or null. The
 * id_token in Apple's reply (straight from Apple over TLS) must name `expectedSub`, the person
 * whose identity token was verified, so a code from another Apple account is never kept.
 */
export async function exchangeAppleAuthorizationCode(code, env, { fetch: fetchImpl = fetch, now = Date.now(), expectedSub } = {}) {
  try {
    if (typeof expectedSub !== "string" || !expectedSub) return null;
    const response = await postAppleForm(APPLE_TOKEN_URL, {
      client_id: env.APPLE_BUNDLE_ID.trim(), client_secret: appleClientSecret(env, now),
      code, grant_type: "authorization_code",
    }, fetchImpl);
    if (!response.ok) return null;
    const body = await response.json();
    const idClaims = typeof body?.id_token === "string" ? JSON.parse(Buffer.from(body.id_token.split(".")[1] ?? "", "base64url")) : null;
    if (idClaims?.sub !== expectedSub) return null;
    const token = body?.refresh_token;
    return typeof token === "string" && token.length > 0 && token.length <= MAX_APPLE_TOKEN_LENGTH ? token : null;
  } catch {
    return null;
  }
}

/** Tells Apple to end the app's Sign in with Apple link for this person. True only on a 200. */
export async function revokeAppleToken(token, env, { fetch: fetchImpl = fetch, now = Date.now() } = {}) {
  try {
    const response = await postAppleForm(APPLE_REVOKE_URL, {
      client_id: env.APPLE_BUNDLE_ID.trim(), client_secret: appleClientSecret(env, now),
      token, token_type_hint: "refresh_token",
    }, fetchImpl);
    return response.status === 200;
  } catch {
    return false;
  }
}

async function postAppleForm(url, fields, fetchImpl) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), APPLE_CALL_TIMEOUT_MS);
  try {
    return await fetchImpl(url, {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams(fields).toString(),
      signal: controller.signal,
    });
  } finally {
    clearTimeout(timer);
  }
}

/**
 * The key Apple's refresh token was sealed with before key ids: an HMAC of a fixed word under the signing key itself.
 * Kept only to open what was sealed then (it lasts up to 400 days, `APPLE_LINK_SECONDS`); nothing is sealed with it now.
 */
function formerAppleTokenKey(master) {
  return createHmac("sha256", master).update("apple-refresh-token:v1").digest();
}

/** The layout of a sealed value, `v2.<key id>.<base64url of iv, ciphertext, tag>`: the dots tell it from the format before. */
const SEAL_VERSION = "v2";

/**
 * Apple's refresh token, sealed (AES-256-GCM, a fresh nonce each time) with the Apple-token key derived from the current
 * signing key: `v2.<key id>.<iv, ciphertext and tag>`. `keys` is a key set (`src/keys.js`) or the signing secret itself.
 * The previous key never seals.
 */
export function sealAppleToken(token, keys) {
  const ring = asKeyRing(keys);
  if (!ring) throw new Error("voice keys are not configured");
  const iv = randomBytes(12);
  const cipher = createCipheriv("aes-256-gcm", purposeKey(ring.current.master, APPLE_TOKEN_SEAL_LABEL), iv);
  const sealed = Buffer.concat([cipher.update(token, "utf8"), cipher.final()]);
  return `${SEAL_VERSION}.${ring.current.kid}.${Buffer.concat([iv, sealed, cipher.getAuthTag()]).toString("base64url")}`;
}

/**
 * The token inside a sealed value, or null (untouched values only, made with a key this server has). A `v2` value
 * names its key: the current or the previous signing key's Apple-token key. A value with no dots is the format from
 * before key ids, made with the key derived from the signing key itself: it opens with the current key or the previous
 * one, for as long as it lives.
 */
export function openAppleToken(value, keys) {
  try {
    const ring = asKeyRing(keys);
    if (!ring || typeof value !== "string") return null;
    const parts = value.split(".");
    if (parts.length === 1) {
      for (const master of allMasters(ring)) {
        const token = openSealed(value, formerAppleTokenKey(master));
        if (token !== null) return token;
      }
      return null;
    }
    if (parts.length !== 3 || parts[0] !== SEAL_VERSION) return null;
    for (const master of mastersNamed(ring, parts[1])) {
      const token = openSealed(parts[2], purposeKey(master, APPLE_TOKEN_SEAL_LABEL));
      if (token !== null) return token;
    }
    return null;
  } catch {
    return null;
  }
}

/** AES-256-GCM: iv (12 bytes), ciphertext, tag (16 bytes), all base64url. Null when anything does not check out. */
function openSealed(base64, key) {
  try {
    const raw = Buffer.from(base64, "base64url");
    if (raw.length < 12 + 16 + 1) return null;
    const decipher = createDecipheriv("aes-256-gcm", key, raw.subarray(0, 12));
    decipher.setAuthTag(raw.subarray(raw.length - 16));
    return Buffer.concat([decipher.update(raw.subarray(12, raw.length - 16)), decipher.final()]).toString("utf8");
  } catch {
    return null;
  }
}

async function appleSigningKeys(fetchImpl, requiredKid, now) {
  const cached = appleKeysCache && appleKeysCache.expiresAt > now ? appleKeysCache.keys : null;
  if (cached?.some((item) => item.kid === requiredKid)) return cached;
  // Junk tokens with made-up key IDs must not make this unauthenticated route call Apple every time.
  if (now >= appleKeysFetchedAt && now - appleKeysFetchedAt < APPLE_KEYS_REFETCH_MIN_MS) return cached ?? [];
  appleKeysFetchedAt = now;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 5_000);
  try {
    const response = await fetchImpl(APPLE_KEYS_URL, { signal: controller.signal });
    if (!response.ok) return [];
    const body = await response.json();
    if (!Array.isArray(body?.keys)) return [];
    appleKeysCache = { keys: body.keys, expiresAt: now + APPLE_KEYS_TTL_MS };
    return body.keys;
  } catch {
    return [];
  } finally {
    clearTimeout(timer);
  }
}

function sessionReply(keys, userId, sessionId, refreshToken, nowMs) {
  return { accessToken: signAccessToken({ userId, sessionId }, keys, nowMs), refreshToken,
    expiresIn: ACCESS_TOKEN_SECONDS };
}

/** The key set from the environment (`src/keys.js`); a missing or unusable setting is "not configured". */
function voiceKeys(env) {
  const keys = keyRingFromEnv(env);
  if (!keys) throw new VoiceAuthStoreUnavailable();
  return keys;
}

function validSessionRecord(value) {
  return value && typeof value.userId === "string" && typeof value.sessionId === "string";
}

function validStoredSession(value, record) {
  return value && value.userId === record.userId && value.sessionId === record.sessionId
    && typeof value.refreshHash === "string";
}

function voiceProviderConfigured(provider, env) {
  // ElevenLabs is the only voice (9 Nov 2026), so `provider` is always "elevenlabs" by the time it gets here.
  return provider === "elevenlabs"
    && typeof env.ELEVENLABS_API_KEY === "string" && env.ELEVENLABS_API_KEY.trim().length > 0
    && typeof env.ELEVENLABS_AGENT_ID === "string" && env.ELEVENLABS_AGENT_ID.trim().length > 0;
}

/**
 * A limit from the environment: the fallback when unset, a whole number from 1 to 10 000 when set,
 * and null when set to anything else (so a typo fails closed instead of leaving a default in force).
 */
export function limitSetting(raw, fallback) {
  if (raw === undefined || raw === null || String(raw).trim() === "") return fallback;
  const text = String(raw).trim();
  return /^[1-9][0-9]*$/.test(text) && Number(text) <= 10_000 ? Number(text) : null;
}

/** The sign-in limits per caller address, or null when a setting is invalid. */
function signInLimits(env) {
  const perHour = limitSetting(env.DODDY_SIGNINS_PER_CLIENT_HOUR, DEFAULT_SIGNINS_PER_CLIENT_HOUR);
  const perDay = limitSetting(env.DODDY_SIGNINS_PER_CLIENT_DAY, DEFAULT_SIGNINS_PER_CLIENT_DAY);
  return perHour === null || perDay === null ? null : { perHour, perDay };
}

/**
 * The caller's address, taken only from the header Vercel sets itself (ADR-712). On any other host
 * that header is whatever the caller sends, so there (or when it is missing or not an address) the
 * answer is "unknown": one bucket shared by everyone, with a higher limit. An IPv4 address behind
 * IPv6 (::ffff:a.b.c.d) is that IPv4 address; any other IPv6 address counts as its /64, because one
 * network hands out 2^64 of them.
 */
export function clientAddress(request, env) {
  if (typeof env?.VERCEL !== "string" || env.VERCEL.trim() === "") return "unknown";
  const first = (request.headers.get("x-vercel-forwarded-for") ?? "").split(",")[0].trim();
  const family = isIP(first);
  if (family === 0) return "unknown";
  if (family === 4) return first;
  const mapped = /^::ffff:(\d{1,3}(?:\.\d{1,3}){3})$/i.exec(first);
  return mapped ? mapped[1] : ipv6Prefix64(first);
}

function ipv6Prefix64(address) {
  const [head, tail = ""] = address.toLowerCase().split("::");
  const first = head ? head.split(":") : [];
  const rest = tail ? tail.split(":") : [];
  const groups = address.includes("::") ? [...first, ...Array(Math.max(0, 8 - first.length - rest.length)).fill("0"), ...rest] : first;
  return `${groups.slice(0, 4).map((group) => group.replace(/^0+(?=.)/, "") || "0").join(":")}::/64`;
}

/** Whole seconds until the fixed window of this length (aligned to the epoch) ends; at least 1. */
function secondsUntilWindowEnds(nowMs, windowSeconds) {
  const windowMs = windowSeconds * 1_000;
  return Math.max(1, Math.ceil((windowMs - (nowMs % windowMs)) / 1_000));
}

function bearer(header) {
  const match = /^Bearer\s+(.+)$/i.exec(header ?? "");
  return match ? match[1].trim() : null;
}

function readBody(request) {
  const contentLength = Number(request.headers.get("content-length"));
  if (Number.isFinite(contentLength) && contentLength > MAX_BODY_BYTES) return Promise.resolve(null);
  return request.text().then((text) => {
    if (Buffer.byteLength(text, "utf8") > MAX_BODY_BYTES) return null;
    return parseJSON(text);
  }).catch(() => null);
}

function parseJSON(text) {
  try { return JSON.parse(text); } catch { return null; }
}

function base64urlJSON(value) { return Buffer.from(JSON.stringify(value)).toString("base64url"); }
function sha256(value) { return createHash("sha256").update(value).digest("hex"); }
function isHttpsURL(value) {
  try {
    const url = new URL(value);
    return url.protocol === "https:" && !url.username && !url.password;
  } catch { return false; }
}
function json(status, body, headers = {}) {
  return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json", "cache-control": "no-store", ...headers } });
}
