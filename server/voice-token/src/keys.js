// One key per job (decision 2026-11-12-account-and-device-tokens, part b).
//
// The voice server has one master secret, `DODDY_SESSION_SIGNING_KEY`. It used to be used as it was for every job.
// Now each job that signs or seals something gets its own key, derived from the master with HKDF-SHA256 and a fixed
// label, so a key that leaks or is replaced for one job says nothing about another:
//
//   access tokens            ACCESS_TOKEN_LABEL       the HS256 signature of the 10-minute access token
//   Apple's refresh token    APPLE_TOKEN_SEAL_LABEL   the AES-256-GCM key it is kept under (sealed)
//
// Every signed or sealed value names the key it was made with, by a key id (`keyId`): a short fingerprint of the
// master, made with HKDF as well, so it needs no setting and shows nothing of the key. A second master,
// `DODDY_SESSION_SIGNING_KEY_PREVIOUS`, is accepted for checking and opening only. It never signs or seals.
//
// Identifiers are not a signing job. The Apple pseudonyms, the keys under which each account's voice conversations
// are recorded, the user id given to ElevenLabs and the rate-limit buckets are keyed hashes that must stay the same
// for as long as the person does (a new one would be a new person, and the old conversations could not be found
// again). They use the identifier key: `DODDY_IDENTIFIER_KEY` when it is set, otherwise the master itself, which is
// exactly what they have always used, so nothing changes at deploy. Before the master is rotated the identifier key
// is set to the master's value, so the rotation can't move them; a previous key without it is refused.
//
// Nothing here logs, and nothing here puts a key, or any part of one, in an error.
import { createHmac, hkdfSync } from "node:crypto";

export const ACCESS_TOKEN_LABEL = "doddy/voice/access-token/v1";
export const APPLE_TOKEN_SEAL_LABEL = "doddy/voice/apple-token-seal/v1";
const KEY_ID_LABEL = "doddy/voice/key-id/v1";
const KEY_BYTES = 32;
const KEY_ID_BYTES = 6;
const MIN_SECRET_BYTES = 32;
// RFC 5869: no salt is the same as a salt of zero bytes. The label is what tells the jobs apart.
const NO_SALT = Buffer.alloc(0);

/**
 * @typedef {{ kid: string, master: string }} MasterKey a secret and its key id
 * @typedef {{ current: MasterKey, previous: MasterKey | null, identifier: string }} KeyRing
 *   `current` signs and seals; `previous` (if any) only checks and opens; `identifier` is the key of the keyed hashes
 */

/** The key for one job: HKDF-SHA256 over the master, the label as `info`, 32 bytes. */
export function purposeKey(master, label) {
  return Buffer.from(hkdfSync("sha256", Buffer.from(master, "utf8"), NO_SALT, Buffer.from(label, "utf8"), KEY_BYTES));
}

/** Eight characters naming a master without giving it away: HKDF output, so nothing can be worked back from it. */
export function keyId(master) {
  return Buffer.from(hkdfSync("sha256", Buffer.from(master, "utf8"), NO_SALT, Buffer.from(KEY_ID_LABEL, "utf8"), KEY_ID_BYTES))
    .toString("base64url");
}

/** The masters that may have made a value naming `kid`: the current one, the previous one, or neither. */
export function mastersNamed(ring, kid) {
  if (typeof kid !== "string") return [];
  return [ring.current, ring.previous].filter((master) => master && master.kid === kid).map((master) => master.master);
}

/** Every master, current first: what the formats from before key ids could have been made with. */
export function allMasters(ring) {
  return [ring.current, ring.previous].filter(Boolean).map((master) => master.master);
}

/**
 * The key set from the environment, or null when it can't be used (and the caller fails closed): no usable signing key,
 * an unusable previous or identifier key, or a previous key with no identifier key (see the top of this file).
 * @param {Record<string, string | undefined>} env
 * @returns {KeyRing | null}
 */
export function keyRingFromEnv(env) {
  const current = env?.DODDY_SESSION_SIGNING_KEY;
  if (!usable(current)) return null;
  const previous = setting(env.DODDY_SESSION_SIGNING_KEY_PREVIOUS);
  const identifier = setting(env.DODDY_IDENTIFIER_KEY);
  if ((previous !== undefined && !usable(previous)) || (identifier !== undefined && !usable(identifier))) return null;
  // The same key twice is no rotation.
  const older = previous !== undefined && previous !== current ? previous : undefined;
  if (older !== undefined && identifier === undefined) return null;
  return {
    current: { kid: keyId(current), master: current },
    previous: older === undefined ? null : { kid: keyId(older), master: older },
    identifier: identifier ?? current,
  };
}

/** A key set from a master alone, for callers that hand the secret itself over. Null when it is not usable. */
export function keyRingFromSecret(secret) {
  return usable(secret) ? { current: { kid: keyId(secret), master: secret }, previous: null, identifier: secret } : null;
}

/** A key set from either form: the secret itself, or a key set already made. Null when it is neither. */
export function asKeyRing(value) {
  if (typeof value === "string") return keyRingFromSecret(value);
  return value && typeof value === "object" && value.current && typeof value.current.master === "string" ? value : null;
}

/** A keyed hash (hex) of `message`, with the identifier key. */
export function identifierHash(ring, message) {
  return createHmac("sha256", ring.identifier).update(message).digest("hex");
}

function usable(value) {
  return typeof value === "string" && Buffer.byteLength(value, "utf8") >= MIN_SECRET_BYTES;
}

/** A setting that is set: blank, or not set at all, is the same thing. */
function setting(value) {
  return typeof value === "string" && value.trim() !== "" ? value : undefined;
}
