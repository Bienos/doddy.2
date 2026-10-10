import { createHash, randomBytes, randomUUID, timingSafeEqual } from "node:crypto";
export const SESSION_HOURS = 2;
export const PIN_MAX_ATTEMPTS = 5;
export const PIN_LOCK_MINUTES = 15;
export const OUTBOUND_DAILY_LIMIT = 10;
export const MAX_PENDING_NOTES = 20;
export function variablesFor(caller, direction) {
    return { secret__doddy_session: "none", doddy_caller: caller, doddy_memory: "off", doddy_pin: "not_set", doddy_direction: direction };
}
export function sha256(value) {
    return createHash("sha256").update(value).digest();
}
export function sameSecret(expected, given) {
    if (!given)
        return false;
    const a = sha256(expected);
    const b = sha256(given);
    return timingSafeEqual(a, b);
}
/** Creates the per-call capability and returns the variables for a recognised caller. */
export async function openSession(db, accountId, callId, direction) {
    const token = randomBytes(32).toString("base64url");
    await db.query(`INSERT INTO call_sessions (id, account_id, token_hash, call_id, expires_at)
     VALUES ($1, $2, $3, $4, now() + make_interval(hours => $5))`, [randomUUID(), accountId, sha256(token), callId, SESSION_HOURS]);
    const { rows } = await db.query(`SELECT pin_hash IS NOT NULL AS pin_set, memory_copy_enabled_at IS NOT NULL AS memory_on
     FROM call_settings WHERE account_id = $1`, [accountId]);
    return {
        secret__doddy_session: token,
        doddy_caller: "known",
        doddy_memory: rows[0]?.memory_on ? "on" : "off",
        doddy_pin: rows[0]?.pin_set ? "set" : "not_set",
        doddy_direction: direction,
    };
}
export async function findSession(db, token) {
    if (!token || token === "none" || token.length > 100)
        return undefined;
    const { rows } = await db.query(`SELECT id, account_id, pin_verified_at IS NOT NULL AS pin_verified
     FROM call_sessions WHERE token_hash = $1 AND expires_at > now()`, [sha256(token)]);
    const r = rows[0];
    return r && { id: r.id, accountId: r.account_id, pinVerified: r.pin_verified };
}
export async function purgeExpiredSessions(db) {
    const r = await db.query("DELETE FROM call_sessions WHERE expires_at < now()");
    return r.rowCount ?? 0;
}
/** Wording shown next to the "Doddy may call me" switch; stored with its version. */
export const OUTBOUND_CONSENT_VERSIONS = new Set(["calls-v1"]);
//# sourceMappingURL=calls.js.map