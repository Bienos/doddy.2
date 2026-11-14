import { createHmac, hkdfSync, timingSafeEqual } from "node:crypto";

/**
 * One signing key per purpose (decision 2026-11-12-account-and-device-tokens, part b).
 *
 * The server holds one master secret (`DODDY_SESSION_SIGNING_KEY`). It never signs with it directly any more:
 * each job gets its own key, derived from the master with HKDF-SHA256 and a fixed label, so a key made for
 * one job can neither make nor check what another job signed. A purpose is added here, with a label that is
 * never reused. The label's version (`v1`) changes only for a deliberate break: it signs everyone out.
 *
 * What is signed carries a key id: the first 8 characters of its signature. The id is a short one-way
 * fingerprint of the derived key (HKDF again, with its own label), so it says which key signed without helping
 * anyone find that key. Checking looks the id up among the keys this server holds (the current key and, while a
 * rotation is under way, the previous one) and refuses an id it doesn't know; it never tries every key.
 *
 * `DODDY_SESSION_SIGNING_KEY_PREVIOUS` is the previous key. It is accepted for checking and never for signing.
 *
 * What was signed before this change used the master directly, with no key id. Those signatures are 43
 * characters long (a key-id signature is 51), and `verifyEarlier` still accepts them, made with the current or
 * the previous master, so nothing has to be reissued at deploy and nobody is signed out. They die with the
 * tokens' own expiry (30 days for sessions, a day for file links); a later change can then delete `verifyEarlier`.
 *
 * Identifiers (a device's user id, an invite code's counter id) are not signatures and do not come from this
 * module: they are derived from the identifier key (`DODDY_IDENTIFIER_KEY`, `deviceSession.ts`) and stay where
 * they were so stored rows still belong to the same people.
 *
 * Nothing here prints key material: the keys are private fields, the keyring prints as a fixed word, and every
 * error names the problem, never a value.
 */

/** What a key signs. Add a purpose here and give it a label of its own. */
export type KeyPurpose = "session" | "file-link";

const LABELS: Readonly<Record<KeyPurpose, string>> = Object.freeze({
  session: "doddy/backend/session/v1",
  "file-link": "doddy/backend/file-link/v1",
});

/** Fewer bytes is not a key. */
export const MIN_KEY_BYTES = 32;

const KEY_ID_BYTES = 6;
/** Characters of a key id (6 bytes in base64url). */
export const KEY_ID_LENGTH = 8;
/** Characters of an HMAC-SHA256 (32 bytes in base64url). */
const MAC_LENGTH = 43;
/** A signature: the key id, then the MAC. */
export const SIGNATURE_LENGTH = KEY_ID_LENGTH + MAC_LENGTH;
/** A signature from before key ids: the MAC alone. */
export const EARLIER_SIGNATURE_LENGTH = MAC_LENGTH;

const NO_SALT = Buffer.alloc(0);
const SIGNATURE_CHARACTERS = /^[A-Za-z0-9_-]+$/;

const derive = (master: Buffer, info: string, bytes: number): Buffer => Buffer.from(hkdfSync("sha256", master, NO_SALT, info, bytes));

const sameBytes = (a: Buffer, b: Buffer): boolean => a.length === b.length && timingSafeEqual(a, b);

/** The keys for one purpose. Get it from `SigningKeys.for`. */
export class PurposeKeys {
  readonly #masters: readonly Buffer[];
  readonly #keys: ReadonlyMap<string, Buffer>;
  readonly #current: { id: string; key: Buffer };

  constructor(purpose: KeyPurpose, masters: readonly Buffer[]) {
    const label = LABELS[purpose];
    this.#masters = masters;
    const keys = new Map<string, Buffer>();
    for (const master of masters) keys.set(idOf(master, label), derive(master, label, 32));
    this.#keys = keys;
    const id = idOf(masters[0]!, label);
    this.#current = { id, key: keys.get(id)! };
  }

  /** The id carried by what the current key signs. Not secret. */
  get keyId(): string {
    return this.#current.id;
  }

  /** The key id, then the MAC, made with the current key. The previous key never signs. */
  sign(message: string): string {
    return this.#current.id + createHmac("sha256", this.#current.key).update(message).digest("base64url");
  }

  /** True for a signature made by this purpose's current or previous key. False for an unknown key id, any other shape, or a wrong MAC. */
  verify(message: string, signature: string): boolean {
    if (signature.length !== SIGNATURE_LENGTH || !SIGNATURE_CHARACTERS.test(signature)) return false;
    const key = this.#keys.get(signature.slice(0, KEY_ID_LENGTH));
    if (!key) return false;
    const expected = createHmac("sha256", key).update(message).digest("base64url");
    return sameBytes(Buffer.from(expected), Buffer.from(signature.slice(KEY_ID_LENGTH)));
  }

  /**
   * True for a signature in the format from before key ids: the master itself (the current or the previous one)
   * as the HMAC key. Only for tokens that were already out when keys per purpose arrived; nothing is signed this way any more.
   */
  verifyEarlier(message: string, signature: string): boolean {
    if (signature.length !== EARLIER_SIGNATURE_LENGTH || !SIGNATURE_CHARACTERS.test(signature)) return false;
    const given = Buffer.from(signature);
    let matched = false;
    for (const master of this.#masters) {
      // Every master is compared, so how long this takes doesn't say which one signed.
      if (sameBytes(Buffer.from(createHmac("sha256", master).update(message).digest("base64url")), given)) matched = true;
    }
    return matched;
  }

  /** What the signature's shape says it is: made with a key id, made the earlier way, or neither. */
  static shapeOf(signature: string): "keyed" | "earlier" | "invalid" {
    if (!SIGNATURE_CHARACTERS.test(signature)) return "invalid";
    if (signature.length === SIGNATURE_LENGTH) return "keyed";
    return signature.length === EARLIER_SIGNATURE_LENGTH ? "earlier" : "invalid";
  }
}

function idOf(master: Buffer, label: string): string {
  return derive(master, `${label}/key-id`, KEY_ID_BYTES).toString("base64url");
}

/**
 * The master key and, during a rotation, the previous master key. Hands out the per-purpose keys.
 * A `Buffer` anywhere a `SigningKeys` is accepted stands for a master key with no previous one.
 */
export class SigningKeys {
  readonly #masters: readonly Buffer[];
  readonly #purposes = new Map<KeyPurpose, PurposeKeys>();

  constructor(current: Buffer, previous: Buffer | null = null) {
    if (current.length < MIN_KEY_BYTES) throw new Error("signing key too short");
    if (previous && previous.length < MIN_KEY_BYTES) throw new Error("previous signing key too short");
    if (previous && sameBytes(current, previous)) throw new Error("the previous signing key must differ from the current one");
    this.#masters = Object.freeze(previous ? [Buffer.from(current), Buffer.from(previous)] : [Buffer.from(current)]);
  }

  /** True while a rotation is under way: the previous key is held for checking. */
  get hasPrevious(): boolean {
    return this.#masters.length > 1;
  }

  /** The keys for one purpose. */
  for(purpose: KeyPurpose): PurposeKeys {
    let keys = this.#purposes.get(purpose);
    if (!keys) {
      keys = new PurposeKeys(purpose, this.#masters);
      this.#purposes.set(purpose, keys);
    }
    return keys;
  }

  /** Whatever the keyring is printed with (JSON, a log line, a string), no key comes out. */
  toJSON(): string {
    return "[signing keys]";
  }

  toString(): string {
    return "[signing keys]";
  }

  [Symbol.for("nodejs.util.inspect.custom")](): string {
    return "[signing keys]";
  }
}

/** A keyring, or a master key alone (tests and tools that build one by hand). */
export function keyringOf(keys: SigningKeys | Buffer): SigningKeys {
  return keys instanceof SigningKeys ? keys : new SigningKeys(keys);
}
