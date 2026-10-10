import assert from 'node:assert/strict';
import test from 'node:test';
import { deviceTag, inviteTag, issueToken, verifyToken } from '../src/token.js';
import { SECRET } from './helpers.js';

const now = 1_790_000_000;

test('issued token verifies and carries the device and invite tag only', () => {
  const { token, expiresAtMs } = issueToken({ deviceId: 'd1', inviteTag: 'i1' }, SECRET, now, 60);
  assert.equal(expiresAtMs, (now + 60) * 1000);
  assert.deepEqual(verifyToken(token, SECRET, now + 1), { deviceId: 'd1', inviteTag: 'i1', exp: now + 60 });
});

test('expired, tampered, wrong-secret and malformed tokens are rejected', () => {
  const { token } = issueToken({ deviceId: 'd1', inviteTag: 'i1' }, SECRET, now, 60);
  assert.equal(verifyToken(token, SECRET, now + 60), null, 'expires exactly at exp');
  assert.equal(verifyToken(token, SECRET + 'x', now + 1), null);
  const [v, payload, sig] = token.split('.');
  const forged = Buffer.from(JSON.stringify({ did: 'other', inv: 'i1', iat: now, exp: now + 9999 })).toString('base64url');
  assert.equal(verifyToken([v, forged, sig].join('.'), SECRET, now + 1), null);
  assert.equal(verifyToken([v, payload, sig.slice(0, -2) + 'AA'].join('.'), SECRET, now + 1), null);
  for (const junk of ['', 'a.b', 'v2.a.b', 'v1..', 'v1.a.b.c']) assert.equal(verifyToken(junk, SECRET, now), null, junk);
});

test('tags do not reveal the invite code or device id, and invite tags depend on the server secret', () => {
  assert.doesNotMatch(inviteTag('SECRET-CODE-000001', SECRET), /SECRET/);
  assert.notEqual(inviteTag('SECRET-CODE-000001', SECRET), inviteTag('SECRET-CODE-000001', SECRET + 'x'), 'offline guessing needs the secret');
  assert.equal(deviceTag('3f2b8a10-6c4d-4e7f-b1a2-c3d4e5f60718').length, 8);
});
