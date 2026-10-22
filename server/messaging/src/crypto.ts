import { createCipheriv, createDecipheriv, createHash, createHmac, hkdfSync, randomBytes, scrypt, timingSafeEqual } from "node:crypto";
import { promisify } from "node:util";

export function sha256(value: string): Buffer {
  return createHash("sha256").update(value).digest();
}

const scryptAsync = promisify(scrypt) as (pw: string, salt: Buffer, len: number, opts: object) => Promise<Buffer>;

/**
 * AES-256-GCM for memory text stored on the server. The associated data binds each
 * ciphertext to its account and row, so a row copied to another account fails to decrypt.
 * Layout: 12-byte IV | 16-byte tag | ciphertext.
 */
export class TextCipher {
  readonly keyVersion = 1;

  constructor(private readonly key: Buffer) {
    if (key.length !== 32) throw new Error("MEMORY_ENCRYPTION_KEY must be 32 bytes (base64)");
  }

  static fromBase64(value: string): TextCipher {
    return new TextCipher(Buffer.from(value, "base64"));
  }

  encrypt(plaintext: string, aad: string): Buffer {
    const iv = randomBytes(12);
    const cipher = createCipheriv("aes-256-gcm", this.key, iv);
    cipher.setAAD(Buffer.from(aad));
    const body = Buffer.concat([cipher.update(plaintext, "utf8"), cipher.final()]);
    return Buffer.concat([iv, cipher.getAuthTag(), body]);
  }

  decrypt(blob: Buffer, aad: string): string {
    return this.decryptBytes(blob, aad).toString("utf8");
  }

  /** As `encrypt`, for bytes (Studio's files, ADR-584). Same layout and key. */
  encryptBytes(plaintext: Buffer, aad: string): Buffer {
    const iv = randomBytes(12);
    const cipher = createCipheriv("aes-256-gcm", this.key, iv);
    cipher.setAAD(Buffer.from(aad));
    const body = Buffer.concat([cipher.update(plaintext), cipher.final()]);
    return Buffer.concat([iv, cipher.getAuthTag(), body]);
  }

  decryptBytes(blob: Buffer, aad: string): Buffer {
    const decipher = createDecipheriv("aes-256-gcm", this.key, blob.subarray(0, 12));
    decipher.setAAD(Buffer.from(aad));
    decipher.setAuthTag(blob.subarray(12, 28));
    return Buffer.concat([decipher.update(blob.subarray(28)), decipher.final()]);
  }

  /** A separate 32-byte key for one purpose (HKDF-SHA256), so no key is used for two jobs. */
  derivedKey(purpose: string): Buffer {
    return Buffer.from(hkdfSync("sha256", this.key, Buffer.alloc(0), `doddy:${purpose}`, 32));
  }
}

export function hmacSha256(key: Buffer, value: string | Buffer): Buffer {
  return createHmac("sha256", key).update(value).digest();
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
