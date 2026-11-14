import { createCipheriv, createDecipheriv, createHash, createHmac, hkdfSync, randomBytes, scrypt, timingSafeEqual } from "node:crypto";
import { promisify } from "node:util";

export function sha256(value: string): Buffer {
  return createHash("sha256").update(value).digest();
}

const scryptAsync = promisify(scrypt) as (pw: string, salt: Buffer, len: number, opts: object) => Promise<Buffer>;

const IV_BYTES = 12;
/** The tag is always 16 bytes (ADR-706): Node would otherwise accept a tag of 4, 8 or 12 bytes, which is far easier to forge. */
const TAG_BYTES = 16;

/** Key versions are stored in smallint columns next to each ciphertext. */
export const MAX_KEY_VERSION = 32767;

const checkVersion = (version: number) => {
  if (!Number.isInteger(version) || version < 1 || version > MAX_KEY_VERSION) {
    throw new Error(`key versions must be whole numbers from 1 to ${MAX_KEY_VERSION}`);
  }
};

function seal(key: Buffer, plaintext: Buffer, aad: string): Buffer {
  const iv = randomBytes(IV_BYTES);
  const cipher = createCipheriv("aes-256-gcm", key, iv, { authTagLength: TAG_BYTES });
  cipher.setAAD(Buffer.from(aad));
  const body = Buffer.concat([cipher.update(plaintext), cipher.final()]);
  return Buffer.concat([iv, cipher.getAuthTag(), body]);
}

function open(key: Buffer, blob: Buffer, aad: string): Buffer {
  const decipher = createDecipheriv("aes-256-gcm", key, blob.subarray(0, IV_BYTES), { authTagLength: TAG_BYTES });
  decipher.setAAD(Buffer.from(aad));
  decipher.setAuthTag(blob.subarray(IV_BYTES, IV_BYTES + TAG_BYTES));
  return Buffer.concat([decipher.update(blob.subarray(IV_BYTES + TAG_BYTES)), decipher.final()]);
}

/**
 * AES-256-GCM for memory text stored on the server. The associated data binds each
 * ciphertext to its account and row, so a row copied to another account fails to decrypt.
 * Layout: 12-byte IV | 16-byte tag | ciphertext (unchanged by key versions).
 *
 * Key versions (for a rotation): every write uses the current key and stores its version (`keyVersion`) next to the
 * ciphertext. During a rotation the previous key is kept too (MEMORY_ENCRYPTION_KEY_PREVIOUS), until
 * scripts/reencrypt.mjs has rewritten every row to the current version; it picks rows by their stored version and
 * opens each with exactly that version's key. A read that names no version (the server's own reads) tries the current
 * key, then the previous one: AES-GCM refuses a wrong key, so it opens a row with the key its stored version names,
 * also in the one table that stores no version (file_watches). One key alone is version 1, the version of every row
 * written before versions could be set.
 */
export class TextCipher {
  /** The version of the current key: every write stores it. */
  readonly keyVersion: number;
  private readonly previous?: { key: Buffer; version: number };

  constructor(private readonly key: Buffer, version = 1, previous?: { key: Buffer; version: number }) {
    if (key.length !== 32) throw new Error("MEMORY_ENCRYPTION_KEY must be 32 bytes (base64)");
    checkVersion(version);
    if (previous) {
      if (previous.key.length !== 32) throw new Error("MEMORY_ENCRYPTION_KEY_PREVIOUS must be 32 bytes (base64)");
      checkVersion(previous.version);
      if (previous.version === version) throw new Error("MEMORY_ENCRYPTION_KEY_PREVIOUS_VERSION must differ from MEMORY_ENCRYPTION_KEY_VERSION");
      if (previous.key.equals(key)) throw new Error("MEMORY_ENCRYPTION_KEY_PREVIOUS is the same key as MEMORY_ENCRYPTION_KEY");
      this.previous = { key: Buffer.from(previous.key), version: previous.version };
    }
    this.keyVersion = version;
  }

  static fromBase64(value: string, version = 1, previous?: { key: string; version: number }): TextCipher {
    return new TextCipher(Buffer.from(value, "base64"), version,
      previous && { key: Buffer.from(previous.key, "base64"), version: previous.version });
  }

  /** The versions this cipher can read, the current one first. */
  get versions(): number[] {
    return this.previous ? [this.keyVersion, this.previous.version] : [this.keyVersion];
  }

  private keyFor(version: number): Buffer | undefined {
    if (version === this.keyVersion) return this.key;
    return this.previous?.version === version ? this.previous.key : undefined;
  }

  encrypt(plaintext: string, aad: string): Buffer {
    return seal(this.key, Buffer.from(plaintext, "utf8"), aad);
  }

  /** `keyVersion`: the version stored on the row; without it, the current key and then the previous one. */
  decrypt(blob: Buffer, aad: string, keyVersion?: number | null): string {
    return this.decryptBytes(blob, aad, keyVersion).toString("utf8");
  }

  /** As `encrypt`, for bytes (Studio's files). Same layout, key and 16-byte tag. */
  encryptBytes(plaintext: Buffer, aad: string): Buffer {
    return seal(this.key, plaintext, aad);
  }

  decryptBytes(blob: Buffer, aad: string, keyVersion?: number | null): Buffer {
    // A blob too short to hold the IV and the whole tag is refused before any key is used (ADR-706).
    if (blob.length < IV_BYTES + TAG_BYTES) throw new Error("ciphertext too short");
    if (keyVersion !== undefined && keyVersion !== null) {
      const key = this.keyFor(keyVersion);
      if (!key) throw new Error(`no key for version ${keyVersion}`);
      return open(key, blob, aad);
    }
    try {
      return open(this.key, blob, aad);
    } catch (err) {
      if (!this.previous) throw err;
      return open(this.previous.key, blob, aad);
    }
  }

  /**
   * A separate 32-byte key for one purpose (HKDF-SHA256), so no key is used for two jobs. Always from the current
   * key: after a rotation the keyed hashes start afresh (README, "Rotating MEMORY_ENCRYPTION_KEY").
   */
  derivedKey(purpose: string): Buffer {
    return Buffer.from(hkdfSync("sha256", this.key, Buffer.alloc(0), `doddy:${purpose}`, 32));
  }

  /**
   * `derivedKey` under every key this cipher holds, the current one first. For the one keyed hash that must survive a
   * rotation, a contact's STOP (src/contactTexts.ts): while both keys are set a lookup tries both, and
   * scripts/reencrypt.mjs re-hashes those rows under the new key.
   */
  derivedKeys(purpose: string): Buffer[] {
    return [this.key, ...(this.previous ? [this.previous.key] : [])]
      .map((k) => Buffer.from(hkdfSync("sha256", k, Buffer.alloc(0), `doddy:${purpose}`, 32)));
  }
}

/** The settings `cipherFrom` reads (Config's names). */
export interface KeySettings {
  memoryEncryptionKey?: string;
  memoryEncryptionKeyVersion?: number;
  memoryEncryptionKeyPrevious?: { key: string; version: number };
}

/** The server's cipher from its settings, or undefined without MEMORY_ENCRYPTION_KEY (local runs and tests only). */
export function cipherFrom(s: KeySettings): TextCipher | undefined {
  if (!s.memoryEncryptionKey) return undefined;
  return TextCipher.fromBase64(s.memoryEncryptionKey, s.memoryEncryptionKeyVersion ?? 1, s.memoryEncryptionKeyPrevious);
}

export function hmacSha256(key: Buffer, value: string | Buffer): Buffer {
  return createHmac("sha256", key).update(value).digest();
}

/**
 * HMAC-SHA256 under a server secret when there is one, else a plain SHA-256 (ADR-705). Used for values kept only to
 * be counted (a phone number, a client address): an IPv4 address or a phone number has too few possible values for
 * a bare hash to protect it, so the secret matters. A deployed server can't start without MEMORY_ENCRYPTION_KEY
 * (deployment.ts), so the bare hash is only ever used by local runs and tests.
 */
export function keyedDigest(secret: Buffer | undefined, value: string): Buffer {
  return secret ? hmacSha256(secret, value) : sha256(value);
}

/** Constant-time comparison of two byte strings of any length. */
export function sameBytes(a: Buffer, b: Buffer): boolean {
  return a.length === b.length && timingSafeEqual(a, b);
}

const SCRYPT = { N: 16384, r: 8, p: 1 };

export async function hashPin(pin: string): Promise<string> {
  const salt = randomBytes(16);
  const hash = await scryptAsync(pin, salt, 32, SCRYPT);
  return `scrypt$${SCRYPT.N}$${SCRYPT.r}$${SCRYPT.p}$${salt.toString("base64")}$${hash.toString("base64")}`;
}

export async function verifyPin(pin: string, stored: string): Promise<boolean> {
  const [scheme, n, r, p, salt, hash] = stored.split("$");
  if (scheme !== "scrypt" || !salt || !hash) return false;
  const expected = Buffer.from(hash, "base64");
  const actual = await scryptAsync(pin, Buffer.from(salt, "base64"), expected.length,
    { N: Number(n), r: Number(r), p: Number(p) });
  return timingSafeEqual(actual, expected);
}

/** 6–8 digits (ADR-175), not all the same digit and not a straight run like 123456 or 987654. */
export function isAcceptablePin(pin: string): boolean {
  if (!/^[0-9]{6,8}$/.test(pin)) return false;
  const d = [...pin].map(Number);
  const allSame = d.every((x) => x === d[0]);
  const up = d.every((x, i) => i === 0 || x === (d[i - 1]! + 1) % 10);
  const down = d.every((x, i) => i === 0 || x === (d[i - 1]! + 9) % 10);
  return !(allSame || up || down);
}
