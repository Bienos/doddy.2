import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { createHmac, hkdfSync } from "node:crypto";
import { once } from "node:events";
import type { Server } from "node:http";
import type { AddressInfo } from "node:net";
import { afterEach, test } from "node:test";
import { inspect } from "node:util";
import { buildApp } from "../src/app.js";
import { issuedAtOf } from "../src/requestCredential.js";
import { RevocableSessionVerifier, sessionTokenIssuedAt, SignedSessionVerifier, TokenFloors } from "../src/auth.js";
import { ConfigError, loadConfig } from "../src/config.js";
import { type DeviceOwnerStore, DeviceSessionIssuer, deviceUserId } from "../src/deviceSession.js";
import { DocumentLinks } from "../src/documents.js";
import { SigningKeys } from "../src/signingKeys.js";
import { listeningLine } from "../src/startLine.js";
import { Store } from "../src/store.js";

/**
 * One signing key per purpose, a key id on everything signed, and a previous key for rotation
 * (decision 2026-11-12-account-and-device-tokens, part b). Every key here is an obviously fake test value.
 */

const fakeKey = (tag: string) => Buffer.from(`not-a-real-key-${tag}`.padEnd(32, "-"));
const K1 = fakeKey("one");
const K2 = fakeKey("two");
const K3 = fakeKey("three");
/** What the live server signed with before this change: a key used directly, no key id. Frozen values below were made by that code. */
const EARLIER = Buffer.from("frozen-fixture-key-not-real-0001");

const SESSION = "doddy/backend/session/v1";
const FILE_LINK = "doddy/backend/file-link/v1";
const NOW = new Date("2026-11-01T12:00:00Z");
const USER = "00000000-0000-4000-8000-0000000000f1";
const DOC = "AAAAAAAAAAAAAAAAAAAAAAAA";

// The same derivation written out again with node:crypto alone, so a change to a label or to the KDF fails here.
const derive = (master: Buffer, label: string) => Buffer.from(hkdfSync("sha256", master, Buffer.alloc(0), label, 32));
const keyId = (master: Buffer, label: string) => Buffer.from(hkdfSync("sha256", master, Buffer.alloc(0), `${label}/key-id`, 6)).toString("base64url");
const mac = (key: Buffer, message: string) => createHmac("sha256", key).update(message).digest("base64url");

const b64 = (key: Buffer) => key.toString("base64");
const every = (key: Buffer) => [key.toString("base64"), key.toString("base64url"), key.toString("hex"), key.toString("latin1")];

/** The earlier session format, written out the way the code before this change wrote it. */
function earlierToken(master: Buffer, userId: string, now: Date, ttlSeconds: number, scope?: "ask"): string {
  const iat = Math.floor(now.getTime() / 1000);
  const claims = { v: 1, sub: userId, iat, exp: iat + ttlSeconds, ...(scope ? { scp: scope } : {}) };
  const payload = Buffer.from(JSON.stringify(claims)).toString("base64url");
  return `ds1.${payload}.${mac(master, `ds1.${payload}`)}`;
}

const bearer = (token: string) => `Bearer ${token}`;
const payloadOf = (token: string) => token.split(".")[1]!;
const signatureOf = (token: string) => token.split(".")[2]!;
const withSignature = (token: string, signature: string) => `ds1.${payloadOf(token)}.${signature}`;
/** The iPhone's row a device token names (its signed `dev` claim). */
const deviceOf = (token: string) => (JSON.parse(Buffer.from(payloadOf(token), "base64url").toString("utf8")) as { dev: string }).dev;

// ------------------------------------------------------------------ derivation

test("each purpose gets its own key from the master with HKDF-SHA256 and a fixed label", () => {
  const keys = new SigningKeys(K1);
  const message = "any message";
  assert.equal(keys.for("session").sign(message), keyId(K1, SESSION) + mac(derive(K1, SESSION), message));
  assert.equal(keys.for("file-link").sign(message), keyId(K1, FILE_LINK) + mac(derive(K1, FILE_LINK), message));
  assert.notEqual(derive(K1, SESSION).toString("hex"), derive(K1, FILE_LINK).toString("hex"));
  assert.notEqual(keys.for("session").sign(message), keys.for("file-link").sign(message));
  for (const purpose of ["session", "file-link"] as const) {
    assert.notEqual(derive(K1, purpose === "session" ? SESSION : FILE_LINK).toString("hex"), K1.toString("hex"), "never the master itself");
  }
});

test("a key id says which key signed, without helping anyone find it", () => {
  const keys = new SigningKeys(K1);
  const id = keys.for("session").keyId;
  assert.match(id, /^[A-Za-z0-9_-]{8}$/);
  assert.equal(id, keyId(K1, SESSION));
  assert.notEqual(id, keys.for("file-link").keyId, "one per purpose");
  assert.notEqual(id, new SigningKeys(K2).for("session").keyId, "one per master key");
  for (const form of every(K1)) assert.ok(!form.includes(id), "not a piece of the master");
  for (const form of every(derive(K1, SESSION))) assert.ok(!form.includes(id), "not a piece of the derived key");
});

test("a purpose's key cannot sign or verify another purpose's things, even with the key id rewritten", () => {
  const keys = new SigningKeys(K1);
  const session = keys.for("session");
  const fileLink = keys.for("file-link");
  const signed = session.sign("same message");
  assert.equal(session.verify("same message", signed), true);
  assert.equal(fileLink.verify("same message", signed), false, "a session signature is no file-link signature");
  assert.equal(session.verify("same message", fileLink.sign("same message")), false, "and the other way round");
  const relabelled = fileLink.keyId + signed.slice(fileLink.keyId.length);
  assert.equal(fileLink.verify("same message", relabelled), false, "the id of the other purpose does not make the signature count");
  const borrowed = session.keyId + fileLink.sign("same message").slice(session.keyId.length);
  assert.equal(session.verify("same message", borrowed), false);
});

test("the previous key is for checking only: it never signs", () => {
  const rotated = new SigningKeys(K2, K1);
  const signed = rotated.for("session").sign("m");
  assert.ok(signed.startsWith(keyId(K2, SESSION)), "signed with the new key");
  assert.ok(!signed.startsWith(keyId(K1, SESSION)));
  assert.equal(new SigningKeys(K2).for("session").verify("m", signed), true, "the new key alone checks it");
  assert.equal(new SigningKeys(K1).for("session").verify("m", signed), false, "the old key alone does not");
  // Things signed under the old key still check while it is the previous key, and stop when it is removed.
  const old = new SigningKeys(K1).for("session").sign("m");
  assert.equal(rotated.for("session").verify("m", old), true);
  assert.equal(new SigningKeys(K2).for("session").verify("m", old), false);
  assert.equal(rotated.hasPrevious, true);
  assert.equal(new SigningKeys(K2).hasPrevious, false);
});

test("a signature with an unknown key id, a wrong length or any other shape is refused", () => {
  const rotated = new SigningKeys(K2, K1);
  const session = rotated.for("session");
  const strangers = new SigningKeys(K3).for("session").sign("m");
  assert.equal(session.verify("m", strangers), false, "signed with a key this server does not hold");
  const good = session.sign("m");
  const unknownId = "AAAAAAAA" + good.slice(8);
  assert.equal(session.verify("m", unknownId), false);
  for (const bad of ["", good.slice(1), good + "A", good.slice(0, 43), "!".repeat(good.length), good.replace(/.$/, good.endsWith("A") ? "B" : "A")]) {
    assert.equal(session.verify("m", bad), false, bad);
  }
  assert.equal(session.verify("another message", good), false);
});

test("keys must be strong, and the previous key must be a different key", () => {
  assert.throws(() => new SigningKeys(Buffer.alloc(31, 1)), /too short/);
  assert.throws(() => new SigningKeys(K1, Buffer.alloc(31, 1)), /too short/);
  assert.throws(() => new SigningKeys(K1, Buffer.from(K1)), /differ/);
  assert.equal(new SigningKeys(K1, null).hasPrevious, false);
});

// ------------------------------------------------------------------ sessions

test("a new session token keeps the ds1 shape the app and the cut-off checks read, and carries a key id", () => {
  const keys = new SigningKeys(K1);
  const token = new SignedSessionVerifier(keys).mint(USER, NOW, 3_600);
  const parts = token.split(".");
  assert.equal(parts.length, 3);
  assert.equal(parts[0], "ds1", "the app only accepts a ds1. token");
  assert.ok(token.length <= 2048, "the app refuses a longer one");
  assert.match(token, /^ds1\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/);
  assert.equal(signatureOf(token), keyId(K1, SESSION) + mac(derive(K1, SESSION), `ds1.${payloadOf(token)}`));
  assert.deepEqual(JSON.parse(Buffer.from(payloadOf(token), "base64url").toString("utf8")), {
    v: 1,
    sub: USER,
    iat: Math.floor(NOW.getTime() / 1000),
    exp: Math.floor(NOW.getTime() / 1000) + 3_600,
  });
  assert.deepEqual(new SignedSessionVerifier(keys).verify(bearer(token), NOW), { userId: USER });
  assert.equal(sessionTokenIssuedAt(bearer(token)), Math.floor(NOW.getTime() / 1000), "the ADR-709 cut-off still reads its date");
  assert.equal(issuedAtOf(bearer(token)), Math.floor(NOW.getTime() / 1000));
  const guest = new SignedSessionVerifier(keys).mint(USER, NOW, 3_600, "ask");
  assert.deepEqual(new SignedSessionVerifier(keys).verify(bearer(guest), NOW), { userId: USER, scope: "ask" });
});

test("a session token made for the file links, or any other purpose, is not a session", () => {
  const keys = new SigningKeys(K1);
  const verifier = new SignedSessionVerifier(keys);
  const token = verifier.mint(USER, NOW, 3_600);
  // The signature of a file link put on a session payload.
  const link = new DocumentLinks(keys, "https://api.doddy.test").link(DOC, USER, NOW);
  const linkSignature = new URL(link).searchParams.get("sig")!;
  assert.equal(verifier.verify(bearer(withSignature(token, linkSignature)), NOW), null);
  // And the session's signature on a file link.
  const links = new DocumentLinks(keys, "https://api.doddy.test");
  const claim = links.claim(new URL(link))!;
  assert.equal(links.check({ ...claim, sig: signatureOf(token) }, USER, NOW), "invalid");
  // A signature of a session payload made with the master or the file-link key is no session either.
  const payload = payloadOf(token);
  assert.equal(verifier.verify(bearer(withSignature(token, keyId(K1, SESSION) + mac(derive(K1, FILE_LINK), `ds1.${payload}`))), NOW), null);
  assert.equal(verifier.verify(bearer(withSignature(token, keyId(K1, SESSION) + mac(K1, `ds1.${payload}`))), NOW), null);
});

test("a session token signed the earlier way, with today's key directly and no key id, keeps verifying", () => {
  const verifier = new SignedSessionVerifier(new SigningKeys(EARLIER));
  // Made by the code before this change, with the fake key above, and kept as it was written.
  const frozen =
    "ds1.eyJ2IjoxLCJzdWIiOiIwMDAwMDAwMC0wMDAwLTQwMDAtODAwMC0wMDAwMDAwMDAwZjEiLCJpYXQiOjE3OTM0OTEyMDAsImV4cCI6MTc5NjA4MzIwMH0.9b1-2L_8OXubdeUzNs_JUTCCwr2TYV_TM1Tt_NqxidE";
  const frozenAsk =
    "ds1.eyJ2IjoxLCJzdWIiOiIwMDAwMDAwMC0wMDAwLTQwMDAtODAwMC0wMDAwMDAwMDAwZjIiLCJpYXQiOjE3OTM0OTEyMDAsImV4cCI6MTc5NjA4MzIwMCwic2NwIjoiYXNrIn0.-FuIZzW8fC4oiyhQqCyA324rgQAXoXJefgp_T_X23ZA";
  assert.deepEqual(verifier.verify(bearer(frozen), NOW), { userId: USER });
  assert.deepEqual(verifier.verify(bearer(frozenAsk), NOW), { userId: "00000000-0000-4000-8000-0000000000f2", scope: "ask" });
  assert.equal(earlierToken(EARLIER, USER, new Date("2026-11-01T00:00:00Z"), 30 * 86_400), frozen, "the helper writes the earlier format exactly");
  // Still a token like any other: it expires, it can't be edited, and another key does not make it.
  assert.equal(verifier.verify(bearer(frozen), new Date("2026-12-01T00:00:01Z")), null, "expired");
  assert.equal(verifier.verify(bearer(frozen.replace(/.$/, "A")), NOW), null, "edited signature");
  const edited = withSignature(frozen, signatureOf(frozen)).replace(payloadOf(frozen), Buffer.from(JSON.stringify({ v: 1, sub: USER, iat: 1, exp: 9e9 })).toString("base64url"));
  assert.equal(verifier.verify(bearer(edited), NOW), null, "edited payload");
  assert.equal(new SignedSessionVerifier(new SigningKeys(K1)).verify(bearer(frozen), NOW), null, "another key");
  // The cut-off after an account is erased still reads the date of an earlier-format token.
  assert.equal(sessionTokenIssuedAt(bearer(frozen)), 1_793_491_200);
});

test("rotation: the old key as the previous key keeps every earlier token alive, and removing it ends them", () => {
  const before = new SignedSessionVerifier(new SigningKeys(K1));
  const newFormat = before.mint(USER, NOW, 86_400);
  const earlier = earlierToken(K1, USER, NOW, 86_400);

  const rotated = new SignedSessionVerifier(new SigningKeys(K2, K1));
  assert.deepEqual(rotated.verify(bearer(newFormat), NOW), { userId: USER }, "signed with the old key by the new format");
  assert.deepEqual(rotated.verify(bearer(earlier), NOW), { userId: USER }, "signed with the old key by the earlier format");
  const fresh = rotated.mint(USER, NOW, 86_400);
  assert.ok(signatureOf(fresh).startsWith(keyId(K2, SESSION)), "new tokens carry the new key's id");
  assert.deepEqual(rotated.verify(bearer(fresh), NOW), { userId: USER });

  const finished = new SignedSessionVerifier(new SigningKeys(K2));
  assert.deepEqual(finished.verify(bearer(fresh), NOW), { userId: USER }, "the new key alone checks what it signed");
  assert.equal(finished.verify(bearer(newFormat), NOW), null, "previous key removed: the old new-format token stops");
  assert.equal(finished.verify(bearer(earlier), NOW), null, "previous key removed: the earlier-format token stops");
  assert.equal(before.verify(bearer(fresh), NOW), null, "a server still holding only the old key does not take the new tokens");

  // A token signed with a key this server holds neither as current nor as previous is refused.
  const stranger = new SignedSessionVerifier(new SigningKeys(K3)).mint(USER, NOW, 86_400);
  assert.equal(rotated.verify(bearer(stranger), NOW), null);
  assert.equal(rotated.verify(bearer(earlierToken(K3, USER, NOW, 86_400)), NOW), null);
});

test("the cut-off after an account is erased applies to the new format too", async () => {
  const keys = new SigningKeys(K1);
  const issuedAt = new Date("2026-11-01T12:00:00Z");
  const floor = Math.floor(issuedAt.getTime() / 1000) + 10;
  const verifier = new RevocableSessionVerifier(new SignedSessionVerifier(keys), new TokenFloors({ tokenFloor: async () => floor }));
  const token = new SignedSessionVerifier(keys).mint(USER, issuedAt, 86_400);
  assert.equal(await verifier.verify(bearer(token), issuedAt), null, "dated before the cut-off");
  const later = new SignedSessionVerifier(keys).mint(USER, new Date(issuedAt.getTime() + 20_000), 86_400);
  assert.deepEqual(await verifier.verify(bearer(later), new Date(issuedAt.getTime() + 20_000)), { userId: USER });
});

// ------------------------------------------------------------------ file links

test("a new file link keeps exactly the two parameters the messaging server rebuilds a link from", () => {
  const links = new DocumentLinks(new SigningKeys(K1), "https://api.doddy.test");
  const url = new URL(links.link(DOC, USER, NOW));
  assert.deepEqual([...url.searchParams.keys()].sort(), ["exp", "sig"], "server/messaging/src/fileWatches.ts drops any other parameter");
  const sig = url.searchParams.get("sig")!;
  assert.match(sig, /^[A-Za-z0-9_-]{20,64}$/, "the shape that server accepts");
  const exp = Number(url.searchParams.get("exp"));
  assert.equal(sig, keyId(K1, FILE_LINK) + mac(derive(K1, FILE_LINK), `doddy-document:v3:${DOC}:${USER}:${exp}`));
  assert.equal(links.check(links.claim(url)!, USER, NOW), "ok");
});

test("a file link signed the earlier way keeps working until it expires, and one signed the oldest way only reads as expired", () => {
  const links = new DocumentLinks(new SigningKeys(EARLIER), "https://api.doddy.test");
  // Made by the code before this change: key and `v2` message, no key id, a day's expiry from 1 Nov 2026 00:00 UTC.
  const frozen = new URL(`https://api.doddy.test/v1/documents/${DOC}?exp=1793577600&sig=opQXMcoUY8FfSxMkzfcxhmSrvmyyoqbCJ-emRJE-Opg`);
  const claim = links.claim(frozen)!;
  assert.equal(links.check(claim, USER, NOW), "ok");
  assert.equal(links.check(claim, USER, new Date("2026-11-02T00:00:00Z")), "ok", "to the second");
  assert.equal(links.check(claim, USER, new Date("2026-11-02T00:00:01Z")), "expired");
  assert.equal(links.check(claim, "someone-else", NOW), "invalid", "still bound to one account");
  assert.equal(links.check({ ...claim, exp: claim.exp + 3_600 }, USER, NOW), "invalid", "the expiry can't be moved");
  assert.equal(new DocumentLinks(new SigningKeys(K1), "https://api.doddy.test").check(claim, USER, NOW), "invalid", "another key");
  const v1 = { id: DOC, exp: 1_793_534_400, sig: "qD753ho1koNBhp4ORZmckuN7TBNn1mq_AanNTi6Ezww" };
  assert.equal(links.check(v1, USER, NOW), "expired");
});

test("file links follow the same rotation: the previous key checks, the new key signs, a stranger is refused", () => {
  const before = new DocumentLinks(new SigningKeys(K1), "https://api.doddy.test");
  const old = new URL(before.link(DOC, USER, NOW));
  const rotated = new DocumentLinks(new SigningKeys(K2, K1), "https://api.doddy.test");
  assert.equal(rotated.check(rotated.claim(old)!, USER, NOW), "ok", "made before the rotation");
  const fresh = new URL(rotated.link(DOC, USER, NOW));
  assert.ok(fresh.searchParams.get("sig")!.startsWith(keyId(K2, FILE_LINK)));
  assert.equal(rotated.check(rotated.claim(fresh)!, USER, NOW), "ok");
  const finished = new DocumentLinks(new SigningKeys(K2), "https://api.doddy.test");
  assert.equal(finished.check(finished.claim(fresh)!, USER, NOW), "ok");
  assert.equal(finished.check(finished.claim(old)!, USER, NOW), "invalid", "previous key removed");
  assert.equal(before.check(before.claim(fresh)!, USER, NOW), "invalid", "a server holding only the old key");
  const stranger = new URL(new DocumentLinks(new SigningKeys(K3), "https://api.doddy.test").link(DOC, USER, NOW));
  assert.equal(rotated.check(rotated.claim(stranger)!, USER, NOW), "invalid");
  // A link made under the earlier format with the old master still opens while that master is the previous key.
  const earlierLink = new URL(new DocumentLinks(EARLIER, "https://api.doddy.test").link(DOC, USER, NOW));
  assert.equal(new DocumentLinks(new SigningKeys(K2, EARLIER), "https://api.doddy.test").check(rotated.claim(earlierLink)!, USER, NOW), "ok");
  assert.equal(finished.check(finished.claim(earlierLink)!, USER, NOW), "invalid");
});

// ------------------------------------------------------------------ identifiers stay where they were

const PHONE = "11111111-1111-4111-8111-111111111111";
/** Made by the code before this change from EARLIER and PHONE; stored rows (owner, device joins, links, usage) hold ids like these. */
const STORED_DEVICE_USER = "a2f96479-8a17-4124-b0ff-b536fc32748e";
const STORED_INVITE_CODE_ID = "wFiVCl2hoUXvrDFflpuWal";

function fakeStore(seen: { codeIds: string[]; users: string[] }): DeviceOwnerStore {
  return {
    claimDeviceOwner: async (userId) => {
      seen.users.push(userId);
      return userId;
    },
    reserveUsage: async () => true,
    tokenFloor: async () => 0,
    useInviteCode: async (input) => {
      seen.codeIds.push(input.codeId);
      seen.users.push(input.userId);
      return "ok";
    },
  };
}

test("a stored device user id and invite code id still resolve to the same values", async () => {
  assert.equal(deviceUserId(EARLIER, PHONE), STORED_DEVICE_USER);
  const seen = { codeIds: [] as string[], users: [] as string[] };
  const issuer = new DeviceSessionIssuer(EARLIER, { signup: "off", inviteCodes: ["frozen-invite-code"], store: fakeStore(seen) });
  await issuer.issue({ deviceId: PHONE, inviteCode: "frozen-invite-code" }, NOW);
  assert.deepEqual(seen, { codeIds: [STORED_INVITE_CODE_ID], users: [STORED_DEVICE_USER] });
  assert.equal(issuer.userIdFor(PHONE), STORED_DEVICE_USER);
});

test("rotating the signing keys does not move a person's identifiers: they follow the identifier key", async () => {
  const seen = { codeIds: [] as string[], users: [] as string[] };
  const keys = new SigningKeys(K2, EARLIER);
  const issuer = new DeviceSessionIssuer(keys, { signup: "off", inviteCodes: ["frozen-invite-code"], store: fakeStore(seen), identifierKey: EARLIER });
  const signedIn = await issuer.issue({ deviceId: PHONE, inviteCode: "frozen-invite-code" }, NOW);
  assert.deepEqual(seen, { codeIds: [STORED_INVITE_CODE_ID], users: [STORED_DEVICE_USER] }, "the same person, the same counters");
  assert.equal(issuer.userIdFor(PHONE), STORED_DEVICE_USER);
  assert.deepEqual(new SignedSessionVerifier(keys).verify(bearer(signedIn.token), NOW), { userId: STORED_DEVICE_USER });
  assert.ok(signatureOf(signedIn.token).startsWith(keyId(K2, SESSION)), "signed with the new key");
  // Without an identifier key the signing keys cannot stand in for it: a rotation would have moved everyone.
  assert.throws(() => new DeviceSessionIssuer(keys, { signup: "off", inviteCodes: ["frozen-invite-code"], store: fakeStore(seen) }), /identifier key/);
});

// ------------------------------------------------------------------ settings

const KEY_B64 = b64(K1);
const base = { DODDY_MODE: "mock", DODDY_AUTH_MODE: "signed", DODDY_SESSION_SIGNING_KEY: KEY_B64 };
const problemsOf = (env: Record<string, string>): string[] => {
  try {
    loadConfig(env);
    return [];
  } catch (error) {
    assert.ok(error instanceof ConfigError);
    return error.problems;
  }
};

test("DODDY_SESSION_SIGNING_KEY_PREVIOUS is optional and, when set, is a second key for checking", () => {
  assert.equal(loadConfig(base).signingKeys?.hasPrevious, false, "nothing has to be set at deploy");
  const rotated = loadConfig({ ...base, DODDY_SESSION_SIGNING_KEY: b64(K2), DODDY_SESSION_SIGNING_KEY_PREVIOUS: KEY_B64, DODDY_IDENTIFIER_KEY: KEY_B64 });
  assert.equal(rotated.signingKeys?.hasPrevious, true);
  const old = new SignedSessionVerifier(new SigningKeys(K1)).mint(USER, NOW, 3_600);
  assert.deepEqual(new SignedSessionVerifier(rotated.signingKeys!).verify(bearer(old), NOW), { userId: USER });
  assert.equal(loadConfig({ ...base, DODDY_SESSION_SIGNING_KEY_PREVIOUS: "" }).signingKeys?.hasPrevious, false, "an empty value is no value");
});

test("a wrong previous key stops the start and names the setting, never its value", () => {
  // Too short, too few bytes, and the same key as the current one (a copy made in place of a rotation).
  for (const value of ["short", Buffer.alloc(8, 9).toString("base64"), b64(K2)]) {
    const problems = problemsOf({ ...base, DODDY_SESSION_SIGNING_KEY: b64(K2), DODDY_SESSION_SIGNING_KEY_PREVIOUS: value, DODDY_IDENTIFIER_KEY: KEY_B64 });
    assert.ok(problems.some((p) => p.includes("DODDY_SESSION_SIGNING_KEY_PREVIOUS")), value);
    assert.ok(!problems.some((p) => p.includes("DODDY_IDENTIFIER_KEY")), "the identifier key is set, so only the previous key is at fault");
    for (const p of problems) assert.ok(!p.includes(value), "the value is never repeated");
  }
  // Without the current key a previous key means nothing.
  const only = problemsOf({ DODDY_MODE: "mock", DODDY_AUTH_MODE: "signed", DODDY_SESSION_SIGNING_KEY_PREVIOUS: KEY_B64 });
  assert.ok(only.some((p) => p.includes("DODDY_SESSION_SIGNING_KEY")));
  assert.ok(!only.join(" ").includes(KEY_B64));
});

test("a previous key without an identifier key is refused at start, so a rotation can't move identifiers by mistake", () => {
  // The same rule as the voice token server: pin the identifier key first, then rotate.
  const rotating = { ...base, DODDY_SESSION_SIGNING_KEY: b64(K2), DODDY_SESSION_SIGNING_KEY_PREVIOUS: KEY_B64 };
  const refused = problemsOf(rotating);
  assert.ok(refused.some((p) => p.includes("DODDY_SESSION_SIGNING_KEY_PREVIOUS") && p.includes("DODDY_IDENTIFIER_KEY")), refused.join("; "));
  assert.ok(!refused.join(" ").includes(KEY_B64) && !refused.join(" ").includes(b64(K2)), "names the settings, never a value");
  assert.ok(problemsOf({ ...rotating, DODDY_IDENTIFIER_KEY: "  " }).length > 0, "an empty value is no value");
  assert.deepEqual(problemsOf({ ...rotating, DODDY_IDENTIFIER_KEY: KEY_B64 }), []);
  // Neither alone is a problem: an unset previous key changes nothing, and an identifier key may be pinned ahead of time.
  assert.deepEqual(problemsOf(base), []);
  assert.deepEqual(problemsOf({ ...base, DODDY_IDENTIFIER_KEY: KEY_B64 }), []);
});

test("DODDY_IDENTIFIER_KEY is optional: unset, identifiers follow the signing key exactly as before", () => {
  const plain = loadConfig(base);
  assert.deepEqual(plain.identifierKey, K1);
  const pinned = loadConfig({ ...base, DODDY_SESSION_SIGNING_KEY: b64(K2), DODDY_IDENTIFIER_KEY: KEY_B64 });
  assert.deepEqual(pinned.identifierKey, K1);
  assert.deepEqual(loadConfig({ DODDY_MODE: "mock" }).identifierKey, null);
  const problems = problemsOf({ ...base, DODDY_IDENTIFIER_KEY: "short" });
  assert.ok(problems.some((p) => p.includes("DODDY_IDENTIFIER_KEY")));
  assert.ok(!problems.join(" ").includes("short"), "the value is never repeated");
});

test("the start line says whether a previous key is in use, and nothing else about the keys", () => {
  const config = { host: "0.0.0.0", port: 10000, mode: "live", authMode: "signed", env: "development", web: null, ownerClaim: "closed" } as const;
  assert.equal(JSON.parse(listeningLine({ ...config, signingKeys: new SigningKeys(K2, K1) }, "postgres", {})).signingKeyPrevious, true);
  assert.equal(JSON.parse(listeningLine({ ...config, signingKeys: new SigningKeys(K2) }, "postgres", {})).signingKeyPrevious, false);
  assert.equal(JSON.parse(listeningLine({ ...config, signingKeys: null }, "postgres", {})).signingKeyPrevious, false);
  const line = listeningLine({ ...config, signingKeys: new SigningKeys(K2, K1) }, "postgres", {});
  for (const key of [K1, K2, derive(K2, SESSION), derive(K1, SESSION)]) for (const form of every(key)) assert.ok(!line.includes(form));
});

// ------------------------------------------------------------------ no key material in any output

test("no key material in an error, a config problem, a log line, a token, a link or a printed keyring", async () => {
  const keys = new SigningKeys(K2, K1);
  const secrets = [K1, K2, K3, EARLIER, derive(K1, SESSION), derive(K2, SESSION), derive(K1, FILE_LINK), derive(K2, FILE_LINK)];
  const output: string[] = [];
  // What a keyring prints, however it is printed.
  output.push(JSON.stringify(keys), String(keys), inspect(keys, { depth: 6, showHidden: true }), inspect({ nested: { keys } }, { depth: 8 }));
  output.push(JSON.stringify({ signingKeys: loadConfig({ ...base, DODDY_SESSION_SIGNING_KEY: b64(K2), DODDY_SESSION_SIGNING_KEY_PREVIOUS: KEY_B64, DODDY_IDENTIFIER_KEY: KEY_B64 }).signingKeys }));
  // The refusal to rotate without an identifier key prints no key either.
  output.push(...problemsOf({ ...base, DODDY_SESSION_SIGNING_KEY: b64(K2), DODDY_SESSION_SIGNING_KEY_PREVIOUS: KEY_B64 }));
  // Errors from every way the keys can be wrong.
  for (const make of [
    () => new SigningKeys(Buffer.concat([K1.subarray(0, 20)])),
    () => new SigningKeys(K1, Buffer.concat([K2.subarray(0, 20)])),
    () => new SigningKeys(K1, Buffer.from(K1)),
    () => new DeviceSessionIssuer(keys, { signup: "off", inviteCodes: ["frozen-invite-code"], store: fakeStore({ codeIds: [], users: [] }) }),
  ]) {
    try {
      make();
    } catch (error) {
      output.push(String((error as Error).message), String((error as Error).stack));
    }
  }
  output.push(...problemsOf({ ...base, DODDY_SESSION_SIGNING_KEY: b64(K2), DODDY_SESSION_SIGNING_KEY_PREVIOUS: b64(K3).slice(0, 20) }));
  output.push(...problemsOf({ ...base, DODDY_SESSION_SIGNING_KEY: b64(K2), DODDY_SESSION_SIGNING_KEY_PREVIOUS: b64(K2) }));
  // What a sign-in logs and returns, and what refusals look like.
  const logs: Record<string, unknown>[] = [];
  const issuer = new DeviceSessionIssuer(keys, {
    signup: "first-device",
    inviteCodes: [],
    store: { ...fakeStore({ codeIds: [], users: [] }), claimDeviceOwner: async () => null },
    ownerClaim: "closed",
    identifierKey: EARLIER,
    log: (line) => logs.push(line),
  });
  await assert.rejects(issuer.issue({ deviceId: PHONE }, NOW), (error: Error) => {
    output.push(error.message);
    return true;
  });
  output.push(JSON.stringify(logs));
  const token = new SignedSessionVerifier(keys).mint(USER, NOW, 3_600);
  const link = new DocumentLinks(keys, "https://api.doddy.test").link(DOC, USER, NOW);
  output.push(token, link);
  const text = output.join("\n");
  for (const secret of secrets) {
    for (const form of every(secret)) assert.ok(!text.includes(form), `no copy of a key (${form.slice(0, 4)}…) in what was printed`);
  }
  assert.ok(!text.includes(b64(K3).slice(0, 20)), "not even a piece of the value that was refused");
  assert.ok(text.includes("DODDY_SESSION_SIGNING_KEY_PREVIOUS"), "the setting is named");
});

// ------------------------------------------------------------------ the real server and the minting tool

let servers: Server[] = [];
let closers: (() => Promise<void>)[] = [];
afterEach(async () => {
  for (const server of servers) server.close();
  for (const close of closers) await close();
  servers = [];
  closers = [];
});

const LIVE = {
  DODDY_MODE: "live",
  DODDY_ENV: "development",
  DODDY_AUTH_MODE: "signed",
  DODDY_PUBLIC_BASE_URL: "https://doddy.onrender.com",
  DODDY_DB_PATH: ":memory:",
  MONID_API_KEY: "monid_live_abcdefgh123",
  DODDY_DEVICE_SIGNUP: "first-device",
  DODDY_OWNER_CLAIM: "open",
};

/** `shared`: the database of an earlier start. A restart of the same server keeps its database, and with iPhones stored a device token names a row in it. */
async function app(env: Record<string, string>, shared?: Store) {
  const { server, store } = await buildApp(loadConfig({ ...LIVE, ...env }), { webSearch: null, ...(shared ? { store: shared } : {}) });
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  servers.push(server);
  if (!shared) closers.push(() => store.close());
  const origin = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
  return {
    signIn: async (deviceId: string) => {
      const res = await fetch(`${origin}/v1/session/device`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ deviceId }) });
      return { status: res.status, body: (await res.json()) as { token: string; access: string } };
    },
    /** An authenticated route; 200 means the token was accepted. */
    status: async (token: string) => (await fetch(`${origin}/v1/tools`, { headers: { authorization: bearer(token) } })).status,
  };
}

test("the real server, rotated: new tokens, earlier tokens and old-key tokens all work, identifiers do not move, and removing the previous key ends the old ones", async () => {
  const now = new Date();
  const earlier = earlierToken(EARLIER, STORED_DEVICE_USER, now, 3_600);
  const newFormatBefore = new SignedSessionVerifier(new SigningKeys(EARLIER)).mint(STORED_DEVICE_USER, now, 3_600);

  // Before anything is set: today's key alone, as the live server runs it.
  const database = await Store.memoryForTests();
  closers.push(() => database.close());
  const today = await app({ DODDY_SESSION_SIGNING_KEY: b64(EARLIER) }, database);
  assert.equal(await today.status(earlier), 200, "a token from before this change");
  const first = await today.signIn(PHONE);
  assert.equal(first.status, 200);
  assert.equal(signatureOf(first.body.token).length, 51, "new tokens carry a key id");
  assert.equal(await today.status(first.body.token), 200);
  // The server now stores iPhones, so its device tokens also name the iPhone's row (a signed claim); the person is the same.
  assert.deepEqual(
    new SignedSessionVerifier(new SigningKeys(EARLIER)).verify(bearer(first.body.token), now),
    { userId: STORED_DEVICE_USER, deviceId: deviceOf(first.body.token) },
    "the same person as before",
  );
  assert.match(deviceOf(first.body.token), /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);

  // Rotation: the old key becomes the previous key, a new key is set, and identifiers stay where they were.
  const rotated = await app({ DODDY_SESSION_SIGNING_KEY: b64(K2), DODDY_SESSION_SIGNING_KEY_PREVIOUS: b64(EARLIER), DODDY_IDENTIFIER_KEY: b64(EARLIER) }, database);
  assert.equal(await rotated.status(earlier), 200, "earlier-format token, signed with the previous key");
  assert.equal(await rotated.status(first.body.token), 200, "a token this server's old key signed");
  assert.equal(await rotated.status(newFormatBefore), 200);
  const second = await rotated.signIn(PHONE);
  assert.equal(second.status, 200);
  assert.ok(signatureOf(second.body.token).startsWith(keyId(K2, SESSION)), "signed with the new key, never the previous one");
  assert.deepEqual(
    new SignedSessionVerifier(new SigningKeys(K2)).verify(bearer(second.body.token), now),
    { userId: STORED_DEVICE_USER, deviceId: deviceOf(first.body.token) },
    "still the same person, and the same iPhone's row: a new key doesn't make a new iPhone",
  );

  // Thirty days later the previous key is removed.
  const finished = await app({ DODDY_SESSION_SIGNING_KEY: b64(K2), DODDY_IDENTIFIER_KEY: b64(EARLIER) }, database);
  assert.equal(await finished.status(second.body.token), 200, "what the new key signed");
  assert.equal(await finished.status(earlier), 401);
  assert.equal(await finished.status(first.body.token), 401);
  assert.equal(await finished.status(withSignature(second.body.token, "AAAAAAAA" + signatureOf(second.body.token).slice(8))), 401, "an unknown key id");
});

test("the minting tool signs with the session key and prints a token and the user, nothing else", () => {
  const script = new URL("../src/mintSession.js", import.meta.url).pathname;
  const out = execFileSync(process.execPath, [script, USER, "2"], { env: { PATH: process.env.PATH ?? "", DODDY_SESSION_SIGNING_KEY: b64(K1) }, encoding: "utf8" });
  const token = out.trim().split("\n")[1]!;
  assert.equal(out.trim().split("\n")[0], `user ${USER}`);
  assert.deepEqual(new SignedSessionVerifier(new SigningKeys(K1)).verify(bearer(token), new Date()), { userId: USER });
  assert.ok(signatureOf(token).startsWith(keyId(K1, SESSION)));
  for (const form of [...every(K1), ...every(derive(K1, SESSION))]) assert.ok(!out.includes(form));
});
