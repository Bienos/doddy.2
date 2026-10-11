import assert from 'node:assert/strict';
import test from 'node:test';
import { handleRegister } from '../src/register.js';
import { verifyToken } from '../src/token.js';
import { ENV, INVITE, DEVICE, SECRET, NOW_MS, fixture, makeDeps } from './helpers.js';

const req = (body, headers = {}) => new Request('https://g.test/api/register', {
  method: 'POST', headers: { 'content-type': 'application/json', ...headers }, body: JSON.stringify(body),
});

test('valid invite code returns a token that verifies for that device', async () => {
  const { deps } = makeDeps();
  const res = await handleRegister(req({ inviteCode: INVITE, deviceId: DEVICE }), deps);
  const json = await res.json();
  assert.equal(res.status, 200);
  assert.equal(verifyToken(json.token, SECRET, Math.floor(NOW_MS / 1000))?.deviceId, DEVICE);
  assert.equal(json.expiresAtMs, NOW_MS + 24 * 3600 * 1000);
  assert.equal(json.schemaVersion, 1);
});

test('wrong invite code is 401 and says nothing about which codes exist', async () => {
  const { deps } = makeDeps();
  const res = await handleRegister(req({ inviteCode: 'WRONG-CODE-0000001', deviceId: DEVICE }), deps);
  assert.equal(res.status, 401);
  assert.doesNotMatch(await res.text(), /INVITE/);
});

test('shared register fixture is accepted by the validator shape', async () => {
  const { deps } = makeDeps({ env: { ...ENV, GATEWAY_INVITE_CODES: fixture('register_request_v1.json').inviteCode } });
  assert.equal((await handleRegister(req(fixture('register_request_v1.json')), deps)).status, 200);
});

test('registration is rate limited per client address', async () => {
  const { deps } = makeDeps();
  let last;
  for (let i = 0; i < 21; i++) last = await handleRegister(req({ inviteCode: 'WRONG-CODE-0000001', deviceId: DEVICE }, { 'x-real-ip': '203.0.113.9' }), deps);
  assert.equal(last.status, 429);
});

test('logs never contain the invite code or device id', async () => {
  const { deps, logs } = makeDeps();
  await handleRegister(req({ inviteCode: INVITE, deviceId: DEVICE }), deps);
  await handleRegister(req({ inviteCode: 'WRONG-CODE-0000001', deviceId: DEVICE }), deps);
  const all = logs.join('\n');
  for (const s of [INVITE, 'WRONG-CODE-0000001', DEVICE]) assert.ok(!all.includes(s), s);
});

test('review: IPv6 clients in one /64 share a registration bucket', async () => {
  const { deps } = makeDeps();
  let last;
  for (let i = 0; i < 21; i++) {
    last = await handleRegister(req({ inviteCode: 'WRONG-CODE-0000001', deviceId: DEVICE }, { 'x-real-ip': `2001:db8:1:2:${i.toString(16)}::${i}` }), deps);
  }
  assert.equal(last.status, 429);
});

test('IPv4 clients seen as IPv4-mapped IPv6 keep their own buckets', async () => {
  const { deps } = makeDeps();
  for (let i = 0; i < 20; i++) {
    await handleRegister(req({ inviteCode: 'WRONG-CODE-0000001', deviceId: DEVICE }, { 'x-real-ip': '::ffff:198.51.100.7' }), deps);
  }
  const other = await handleRegister(req({ inviteCode: INVITE, deviceId: DEVICE }, { 'x-real-ip': '::ffff:203.0.113.9' }), deps);
  assert.equal(other.status, 200, 'a different IPv4 client is not blocked by the first one');
  const same = await handleRegister(req({ inviteCode: INVITE, deviceId: DEVICE }, { 'x-real-ip': '198.51.100.7' }), deps);
  assert.equal(same.status, 429, 'mapped and plain forms of one address share a bucket');
});

test('a request without client address headers is logged as such', async () => {
  const { deps, logs } = makeDeps();
  assert.equal((await handleRegister(req({ inviteCode: INVITE, deviceId: DEVICE }), deps)).status, 200);
  assert.equal(JSON.parse(logs.at(-1)).cause, 'noClientAddress');
  await handleRegister(req({ inviteCode: INVITE, deviceId: DEVICE }, { 'x-real-ip': '198.51.100.8' }), deps);
  assert.equal(JSON.parse(logs.at(-1)).cause, undefined);
});

test('review: short invite codes in config fail closed', async () => {
  const { deps } = makeDeps({ env: { ...ENV, GATEWAY_INVITE_CODES: 'short' } });
  const res = await handleRegister(req({ inviteCode: 'short', deviceId: DEVICE }), deps);
  assert.equal(res.status, 503);
});
