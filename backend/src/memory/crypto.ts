import { createCipheriv, createDecipheriv, randomBytes } from "node:crypto";

/**
 * AES-256-GCM for the notes and conversations a person chooses to keep on Doddy's server (ADR-595).
 * The key is held by the server, so the server can search what it keeps (for the web page and for
 * chatting with it): this is encryption at rest, not end-to-end. The associated data binds each
 * blob to its user, kind and row, so a row copied to another user or another row fails to decrypt.
 * Layout: 12-byte IV | 16-byte tag | ciphertext. `keyVersion` is stored with every row so a key can
 * be replaced later without guessing which rows it covers.
 */
export class MemoryCipher {
  readonly keyVersion = 1;

  constructor(private readonly key: Buffer) {
    if (key.length !== 32) throw new Error("the memory key must be 32 bytes");
  }

  encrypt(plaintext: string, aad: string): Buffer {
    const iv = randomBytes(12);
    const cipher = createCipheriv("aes-256-gcm", this.key, iv);
    cipher.setAAD(Buffer.from(aad));
    const body = Buffer.concat([cipher.update(plaintext, "utf8"), cipher.final()]);
    return Buffer.concat([iv, cipher.getAuthTag(), body]);
  }

  /** Throws when the blob was altered, belongs to another row or was made with another key. */
  decrypt(blob: Buffer, aad: string): string {
    if (blob.length < 28) throw new Error("ciphertext too short");
    const decipher = createDecipheriv("aes-256-gcm", this.key, blob.subarray(0, 12));
    decipher.setAAD(Buffer.from(aad));
    decipher.setAuthTag(blob.subarray(12, 28));
    return Buffer.concat([decipher.update(blob.subarray(28)), decipher.final()]).toString("utf8");
  }
}
