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

const APPLE_ISSUER = "https://appleid.apple.com";
const APPLE_KEYS_URL = "https://appleid.apple.com/auth/keys";
const APPLE_TOKEN_URL = "https://appleid.apple.com/auth/token";
const APPLE_REVOKE_URL = "https://appleid.apple.com/auth/revoke";
const APPLE_CALL_TIMEOUT_MS = 5_000;
const MAX_AUTHORIZATION_CODE_LENGTH = 1_024;
const MAX_APPLE_TOKEN_LENGTH = 4_096;
const ACCESS_TOKEN_SECONDS = 600;
const REFRESH_TOKEN_SECONDS = 30 * 24 * 60 * 60;
const NONCE_TTL_SECONDS = 600;
const MAX_BODY_BYTES = 24_000;
const STORE_TIMEOUT_MS = 2_000;
const STORE_PREFIX = "doddy:voice:v1:";

let appleKeysCache;

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

    async rotateRefreshSession(oldHash, newHash, prior, ttlSeconds) {
      const script = `
        local old = redis.call('GET', KEYS[1])
        if not old then return false end
        local info = cjson.decode(old)
        local session = redis.call('GET', KEYS[2])
        if not session then redis.call('DEL', KEYS[1]); return false end
        local state = cjson.decode(session)
        if state.userId ~= info.userId or state.sessionId ~= info.sessionId then return false end
        local fresh = redis.call('SET', KEYS[3], cjson.encode(info), 'EX', ARGV[1], 'NX')
        if not fresh then return false end
        state.refreshHash = ARGV[2]
        redis.call('SET', KEYS[2], cjson.encode(state), 'EX', ARGV[1])
        redis.call('DEL', KEYS[1])
        redis.call('EXPIRE', KEYS[4], ARGV[1])
        redis.call('EXPIRE', KEYS[5], ARGV[1])
        return cjson.encode(state)
      `;
      const result = await evalScript(script, [
        key("refresh", oldHash), key("session", prior.sessionId), key("refresh", newHash), key("user-sessions", prior.userId),
        key("apple-token", prior.userId),
      ], [ttlSeconds, newHash]);
      return parseJSON(result);
    },

    async getRefresh(hash) {
      const [value] = await exec([["GET", key("refresh", hash)]]);
      return typeof value === "string" ? parseJSON(value) : null;
    },

    async getSession(sessionId) {
      const [value] = await exec([["GET", key("session", sessionId)]]);
      return typeof value === "string" ? parseJSON(value) : null;
    },

    async hitLimits(userId, perUserLimit, globalLimit, nowMs) {
      const windowSeconds = 3_600;
      const window = Math.floor(nowMs / (windowSeconds * 1_000));
      const ttl = windowSeconds + 60;
      const perUserKey = key("limit-user", `${userId}:${window}`);
      const globalKey = key("limit-global", String(window));
      const script = `
        local per = redis.call('INCR', KEYS[1])
        if per == 1 then redis.call('EXPIRE', KEYS[1], ARGV[1]) end
        local global = redis.call('INCR', KEYS[2])
        if global == 1 then redis.call('EXPIRE', KEYS[2], ARGV[1]) end
        return {per, global}
      `;
      const counts = await evalScript(script, [perUserKey, globalKey], [ttl]);
      if (!Array.isArray(counts) || counts.length !== 2) throw new VoiceAuthStoreUnavailable();
      const [perUserCount, globalCount] = counts;
      const per = Number(perUserCount);
      const global = Number(globalCount);
      if (!Number.isSafeInteger(per) || !Number.isSafeInteger(global)) throw new VoiceAuthStoreUnavailable();
      return { allowed: per <= perUserLimit && global <= globalLimit, perUserCount: per, globalCount: global,
        retryAfterSeconds: Math.max(1, Math.ceil(((window + 1) * windowSeconds * 1_000 - nowMs) / 1_000)) };
    },

    async revokeSession(sessionId, userId) {
      const script = `
        local session = redis.call('GET', KEYS[1])
        if not session then return 0 end
        local state = cjson.decode(session)
        if state.userId ~= ARGV[1] then return 0 end
        redis.call('DEL', KEYS[1])
        redis.call('DEL', KEYS[2] .. state.refreshHash)
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

    async deleteAccount(userId) {
      const script = `
        local sessions = redis.call('SMEMBERS', KEYS[1])
        for _, sid in ipairs(sessions) do
          local sessionKey = ARGV[1] .. sid
          local session = redis.call('GET', sessionKey)
          if session then
            local state = cjson.decode(session)
            redis.call('DEL', ARGV[2] .. state.refreshHash)
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
  if (!["sign-in", "refresh", "sign-out", "delete-account"].includes(action)) return finish(400, "unknown_action");

  let store;
  let signingKey;
  try {
    store = deps.store ?? createVoiceAuthStore({
      url: env.UPSTASH_REDIS_REST_URL, token: env.UPSTASH_REDIS_REST_TOKEN,
      fetch: deps.storeFetch ?? fetch, timeoutMs: deps.storeTimeoutMs,
    });
    signingKey = signingSecret(env.DODDY_SESSION_SIGNING_KEY);
  } catch {
    return finish(503, "server_not_configured");
  }

  try {
    if (action === "sign-in") {
      if (typeof body.identityToken !== "string" || typeof body.rawNonce !== "string"
          || body.identityToken.length > 18_000 || !/^[A-Za-z0-9_-]{40,64}$/.test(body.rawNonce)
          || (body.provider !== "openai" && body.provider !== "elevenlabs")
          || typeof env.APPLE_BUNDLE_ID !== "string" || !env.APPLE_BUNDLE_ID.trim()) {
        return finish(400, "invalid_request");
      }
      if (!voiceProviderConfigured(body.provider, env)) return finish(503, "server_not_configured");
      const claims = await (deps.verifyAppleIdentityToken ?? verifyAppleIdentityToken)(
        body.identityToken, body.rawNonce, env.APPLE_BUNDLE_ID.trim(), { fetch: deps.fetch ?? fetch, now: now() });
      if (!claims) return finish(401, "apple_sign_in_failed");
      const userId = hmac(signingKey, `apple-sub:${claims.sub}`);
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
          if (appleToken) await store.setAppleToken(userId, sealAppleToken(appleToken, signingKey), REFRESH_TOKEN_SECONDS);
        } catch {
          // The account works without it; deleting it later just can't revoke at Apple.
        }
      }
      return finish(200, null, sessionReply(signingKey, userId, sessionId, refreshToken, now()));
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
      if (!rotated) return finish(401, "session_expired");
      return finish(200, null, sessionReply(signingKey, prior.userId, prior.sessionId, nextToken, now()));
    }

    const access = await authenticateVoiceSession(request, env, { store, signingKey, now: now() });
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
      const appleToken = sealed ? openAppleToken(sealed, signingKey) : null;
      apple = !appleToken ? "no_token"
        : await (deps.revokeAppleToken ?? revokeAppleToken)(appleToken, env, { fetch: deps.fetch ?? fetch, now: now() })
          ? "revoked" : "failed";
    }
    await store.deleteAccount(access.userId);
    return finish(200, null, { deleted: true, appleRevoked: apple === "revoked" }, {}, { apple });
  } catch (error) {
    if (error instanceof VoiceAuthStoreUnavailable) return finish(503, "server_not_configured");
    return finish(500, "voice_auth_failed");
  }
}

export async function authenticateVoiceSession(request, env, deps = {}) {
  const store = deps.store;
  const signingKey = deps.signingKey ?? signingSecret(env.DODDY_SESSION_SIGNING_KEY);
  if (!store || !signingKey) throw new VoiceAuthStoreUnavailable();
  const token = bearer(request.headers.get("authorization"));
  if (!token) return null;
  const claims = verifyAccessToken(token, signingKey, deps.now ?? Date.now());
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

export function signAccessToken(payload, secret, nowMs = Date.now()) {
  const nowSeconds = Math.floor(nowMs / 1_000);
  const header = base64urlJSON({ alg: "HS256", typ: "JWT" });
  const claims = base64urlJSON({ iss: "doddy-voice", aud: "voice", sub: payload.userId, sid: payload.sessionId,
    iat: nowSeconds, exp: nowSeconds + ACCESS_TOKEN_SECONDS });
  const input = `${header}.${claims}`;
  return `${input}.${createHmac("sha256", secret).update(input).digest("base64url")}`;
}

export function verifyAccessToken(token, secret, nowMs = Date.now()) {
  try {
    if (typeof token !== "string" || token.length > 4_096) return null;
    const [headerPart, claimsPart, signaturePart, ...extra] = token.split(".");
    if (!headerPart || !claimsPart || !signaturePart || extra.length) return null;
    const input = `${headerPart}.${claimsPart}`;
    const expected = createHmac("sha256", secret).update(input).digest();
    const actual = Buffer.from(signaturePart, "base64url");
    if (actual.length !== expected.length || !timingSafeEqual(actual, expected)) return null;
    const header = parseJSON(Buffer.from(headerPart, "base64url").toString("utf8"));
    const claims = parseJSON(Buffer.from(claimsPart, "base64url").toString("utf8"));
    if (header?.alg !== "HS256" || claims?.iss !== "doddy-voice" || claims?.aud !== "voice"
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
  const keys = await appleSigningKeys(fetchImpl, header.kid);
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

function appleTokenKey(signingKey) {
  return createHmac("sha256", signingKey).update("apple-refresh-token:v1").digest();
}

export function sealAppleToken(token, signingKey) {
  const iv = randomBytes(12);
  const cipher = createCipheriv("aes-256-gcm", appleTokenKey(signingKey), iv);
  const sealed = Buffer.concat([cipher.update(token, "utf8"), cipher.final()]);
  return Buffer.concat([iv, sealed, cipher.getAuthTag()]).toString("base64url");
}

export function openAppleToken(value, signingKey) {
  try {
    const raw = Buffer.from(value, "base64url");
    if (raw.length < 12 + 16 + 1) return null;
    const decipher = createDecipheriv("aes-256-gcm", appleTokenKey(signingKey), raw.subarray(0, 12));
    decipher.setAuthTag(raw.subarray(raw.length - 16));
    return Buffer.concat([decipher.update(raw.subarray(12, raw.length - 16)), decipher.final()]).toString("utf8");
  } catch {
    return null;
  }
}

async function appleSigningKeys(fetchImpl, requiredKid) {
  const now = Date.now();
  if (appleKeysCache && appleKeysCache.expiresAt > now
      && appleKeysCache.keys.some((item) => item.kid === requiredKid)) return appleKeysCache.keys;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 5_000);
  try {
    const response = await fetchImpl(APPLE_KEYS_URL, { signal: controller.signal });
    if (!response.ok) return [];
    const body = await response.json();
    if (!Array.isArray(body?.keys)) return [];
    appleKeysCache = { keys: body.keys, expiresAt: now + 60 * 60 * 1_000 };
    return body.keys;
  } catch {
    return [];
  } finally {
    clearTimeout(timer);
  }
}

function sessionReply(signingKey, userId, sessionId, refreshToken, nowMs) {
  return { accessToken: signAccessToken({ userId, sessionId }, signingKey, nowMs), refreshToken,
    expiresIn: ACCESS_TOKEN_SECONDS };
}

function signingSecret(value) {
  if (typeof value !== "string" || Buffer.byteLength(value, "utf8") < 32) throw new VoiceAuthStoreUnavailable();
  return value;
}

function validSessionRecord(value) {
  return value && typeof value.userId === "string" && typeof value.sessionId === "string";
}

function validStoredSession(value, record) {
  return value && value.userId === record.userId && value.sessionId === record.sessionId
    && typeof value.refreshHash === "string";
}

function voiceProviderConfigured(provider, env) {
  return provider === "openai"
    ? typeof env.OPENAI_API_KEY === "string" && env.OPENAI_API_KEY.trim().length > 0
    : typeof env.ELEVENLABS_API_KEY === "string" && env.ELEVENLABS_API_KEY.trim().length > 0
      && typeof env.ELEVENLABS_AGENT_ID === "string" && env.ELEVENLABS_AGENT_ID.trim().length > 0;
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
function hmac(secret, value) { return createHmac("sha256", secret).update(value).digest("hex"); }
function isHttpsURL(value) {
  try {
    const url = new URL(value);
    return url.protocol === "https:" && !url.username && !url.password;
  } catch { return false; }
}
function json(status, body, headers = {}) {
  return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json", "cache-control": "no-store", ...headers } });
}
