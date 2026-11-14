// MEMORY_ENCRYPTION_KEY on a deployed server, and key versions for a rotation. No database: the start-up rule, the
// settings, the keyring and the outbox's own refusal.
import assert from "node:assert/strict";
import { test } from "node:test";
import { loadConfig } from "../src/config.js";
import { cipherFrom, TextCipher } from "../src/crypto.js";
import { deployedBecause, isDeployed } from "../src/deployment.js";
import type { Db } from "../src/db.js";
import { EncryptionNotConfigured, enqueue } from "../src/outbox.js";

const BASE = { DATABASE_URL: "postgres://x/y" };
const KEY_1 = Buffer.alloc(32, 1).toString("base64");
const KEY_2 = Buffer.alloc(32, 2).toString("base64");

test("a server counts as deployed with NODE_ENV=production, on Render, or with a public PUBLIC_BASE_URL", () => {
  assert.equal(deployedBecause({}), undefined);
  assert.equal(deployedBecause({ NODE_ENV: "development" }), undefined);
  assert.equal(deployedBecause({ NODE_ENV: "production" }), "NODE_ENV");
  assert.equal(deployedBecause({ RENDER: "true" }), "RENDER");
  assert.equal(deployedBecause({ RENDER: "" }), undefined, "an empty value is unset");
  for (const url of ["https://doddy-messaging-zw1n.onrender.com", "https://api.doddy.app/", "http://203.0.113.9:8787", "https://abc123.ngrok.app"]) {
    assert.equal(deployedBecause({ PUBLIC_BASE_URL: url }), "PUBLIC_BASE_URL", url);
  }
  for (const url of ["http://localhost:8787", "https://localhost", "http://127.0.0.1:3000", "http://[::1]:8787", "http://0.0.0.0:8787",
    "https://doddy.example.test", "https://doddy.localhost", "https://doddy.example", "https://x.invalid", "not a url"]) {
    assert.equal(deployedBecause({ PUBLIC_BASE_URL: url }), undefined, url);
  }
  assert.equal(isDeployed({ RENDER: "true" }), true);
  assert.equal(isDeployed({}), false);
});

test("a deployed server refuses to start without MEMORY_ENCRYPTION_KEY; local runs and tests still start", () => {
  for (const env of [{ NODE_ENV: "production" }, { RENDER: "true" }, { PUBLIC_BASE_URL: "https://doddy-messaging-zw1n.onrender.com" }]) {
    assert.throws(() => loadConfig({ ...BASE, ...env }), (err: Error) => {
      assert.match(err.message, /MEMORY_ENCRYPTION_KEY is required/);
      assert.ok(!err.message.includes("onrender.com"), "the address is not repeated");
      return true;
    }, JSON.stringify(env));
    assert.equal(loadConfig({ ...BASE, ...env, MEMORY_ENCRYPTION_KEY: KEY_1 }).memoryEncryptionKey, KEY_1);
  }
  // An empty value is unset, as everywhere in loadConfig.
  assert.throws(() => loadConfig({ ...BASE, RENDER: "true", MEMORY_ENCRYPTION_KEY: "" }), /MEMORY_ENCRYPTION_KEY is required/);
  assert.equal(loadConfig(BASE).memoryEncryptionKey, undefined);
  assert.equal(loadConfig({ ...BASE, PUBLIC_BASE_URL: "http://localhost:8787" }).memoryEncryptionKey, undefined);
});

test("key versions: the current one (default 1) and an optional previous one, each named explicitly", () => {
  const plain = loadConfig({ ...BASE, MEMORY_ENCRYPTION_KEY: KEY_1 });
  assert.equal(plain.memoryEncryptionKeyVersion, 1);
  assert.equal(plain.memoryEncryptionKeyPrevious, undefined);
  const rotating = loadConfig({
    ...BASE, MEMORY_ENCRYPTION_KEY: KEY_2, MEMORY_ENCRYPTION_KEY_VERSION: "2",
    MEMORY_ENCRYPTION_KEY_PREVIOUS: KEY_1, MEMORY_ENCRYPTION_KEY_PREVIOUS_VERSION: "1",
  });
  assert.equal(rotating.memoryEncryptionKeyVersion, 2);
  assert.deepEqual(rotating.memoryEncryptionKeyPrevious, { key: KEY_1, version: 1 });
  const refused: [Record<string, string>, RegExp][] = [
    [{ MEMORY_ENCRYPTION_KEY: KEY_2, MEMORY_ENCRYPTION_KEY_PREVIOUS: KEY_1 }, /MEMORY_ENCRYPTION_KEY_PREVIOUS_VERSION/],
    [{ MEMORY_ENCRYPTION_KEY: KEY_2, MEMORY_ENCRYPTION_KEY_PREVIOUS: KEY_1, MEMORY_ENCRYPTION_KEY_PREVIOUS_VERSION: "1" }, /must differ/],
    [{ MEMORY_ENCRYPTION_KEY_PREVIOUS: KEY_1, MEMORY_ENCRYPTION_KEY_PREVIOUS_VERSION: "1", MEMORY_ENCRYPTION_KEY_VERSION: "2" }, /without MEMORY_ENCRYPTION_KEY/],
  ];
  for (const [env, why] of refused) assert.throws(() => loadConfig({ ...BASE, ...env }), why, JSON.stringify(Object.keys(env)));
  // A version left behind after the previous key was removed is harmless: it never stops a start.
  assert.equal(loadConfig({ ...BASE, MEMORY_ENCRYPTION_KEY: KEY_2, MEMORY_ENCRYPTION_KEY_VERSION: "2", MEMORY_ENCRYPTION_KEY_PREVIOUS_VERSION: "1" })
    .memoryEncryptionKeyPrevious, undefined);
  for (const bad of ["0", "-1", "1.5", "40000", "two"]) {
    assert.throws(() => loadConfig({ ...BASE, MEMORY_ENCRYPTION_KEY: KEY_1, MEMORY_ENCRYPTION_KEY_VERSION: bad }), bad);
  }
  // Errors never carry a key.
  try {
    loadConfig({ ...BASE, MEMORY_ENCRYPTION_KEY: KEY_2, MEMORY_ENCRYPTION_KEY_PREVIOUS: KEY_1, MEMORY_ENCRYPTION_KEY_PREVIOUS_VERSION: "1" });
  } catch (err) {
    assert.ok(!String((err as Error).message).includes(KEY_1) && !String((err as Error).message).includes(KEY_2));
  }
});

test("the keyring writes with the current version and reads each row with the version stored on it", () => {
  const v1 = new TextCipher(Buffer.alloc(32, 1));
  assert.equal(v1.keyVersion, 1, "one key alone is version 1, as every row written so far");
  const old = v1.encrypt("written before the rotation", "acct:note:1");
  const oldBytes = v1.encryptBytes(Buffer.from([0, 1, 2, 255]), "acct:studio-file:1:a.png");

  const ring = cipherFrom({
    memoryEncryptionKey: KEY_2, memoryEncryptionKeyVersion: 2, memoryEncryptionKeyPrevious: { key: KEY_1, version: 1 },
  })!;
  assert.equal(ring.keyVersion, 2);
  assert.deepEqual(ring.versions, [2, 1]);
  // Rows of version 1 still read, by their version and without one (AES-GCM refuses the wrong key).
  assert.equal(ring.decrypt(old, "acct:note:1", 1), "written before the rotation");
  assert.equal(ring.decrypt(old, "acct:note:1"), "written before the rotation");
  assert.deepEqual(ring.decryptBytes(oldBytes, "acct:studio-file:1:a.png", 1), Buffer.from([0, 1, 2, 255]));
  // A row named with the wrong version, or a version no key is set for, is refused.
  assert.throws(() => ring.decrypt(old, "acct:note:1", 2));
  assert.throws(() => ring.decrypt(old, "acct:note:1", 3), /no key for version 3/);
  // New rows are version 2 and need the new key.
  const fresh = ring.encrypt("written after", "acct:note:2");
  assert.equal(ring.decrypt(fresh, "acct:note:2", 2), "written after");
  assert.throws(() => v1.decrypt(fresh, "acct:note:2"));
  // The AAD still binds a row to its account and id.
  assert.throws(() => ring.decrypt(fresh, "acct:note:3"));
  // Keys derived for hashes come from the current key (a rotation starts them afresh).
  assert.deepEqual(ring.derivedKey("client-address"), new TextCipher(Buffer.alloc(32, 2), 2).derivedKey("client-address"));
  assert.notDeepEqual(ring.derivedKey("client-address"), v1.derivedKey("client-address"));

  assert.equal(cipherFrom({ memoryEncryptionKeyVersion: 1 }), undefined, "no key, no cipher");
  assert.throws(() => new TextCipher(Buffer.alloc(32, 2), 2, { key: Buffer.alloc(32, 2), version: 1 }), /same key/);
  assert.throws(() => new TextCipher(Buffer.alloc(32, 2), 2, { key: Buffer.alloc(16, 1), version: 1 }), /MEMORY_ENCRYPTION_KEY_PREVIOUS must be 32 bytes/);
  assert.throws(() => new TextCipher(Buffer.alloc(32, 2), 1, { key: Buffer.alloc(32, 1), version: 1 }), /must differ/);
  assert.throws(() => new TextCipher(Buffer.alloc(32, 2), 0), /1 to 32767/);
});

test("the servers build the keyring from the settings", async () => {
  const { providersFrom } = await import("../src/providers/index.js");
  const cipher = providersFrom(loadConfig({
    ...BASE, MEMORY_ENCRYPTION_KEY: KEY_2, MEMORY_ENCRYPTION_KEY_VERSION: "2",
    MEMORY_ENCRYPTION_KEY_PREVIOUS: KEY_1, MEMORY_ENCRYPTION_KEY_PREVIOUS_VERSION: "1",
  })).cipher!;
  assert.equal(cipher.keyVersion, 2);
  assert.equal(cipher.decrypt(new TextCipher(Buffer.alloc(32, 1)).encrypt("old", "a"), "a", 1), "old");
});

test("a deployed server never queues a readable text, whichever rule marks it deployed", async () => {
  const noDb = { query: async () => { throw new Error("the database must not be reached"); } } as unknown as Db;
  for (const [name, value] of [["RENDER", "true"], ["NODE_ENV", "production"], ["PUBLIC_BASE_URL", "https://doddy-messaging-zw1n.onrender.com"]] as const) {
    const was = process.env[name];
    process.env[name] = value;
    try {
      await assert.rejects(enqueue(noDb, "acct", ["sms"], "hello", new Date(), "k1"), EncryptionNotConfigured, name);
    } finally {
      if (was === undefined) delete process.env[name]; else process.env[name] = was;
    }
  }
});
