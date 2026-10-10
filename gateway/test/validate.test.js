import assert from 'node:assert/strict';
import test from 'node:test';
import { LIMITS, validateAssistRequest, validateRegisterRequest } from '../src/validate.js';
import { fixture } from './helpers.js';

const base = () => structuredClone(fixture('assist_request_v1.json'));
const reason = (body) => { const r = validateAssistRequest(body); return r.ok ? 'ok' : r.reason; };

test('the shared contract fixture is a valid request', () => {
  assert.equal(reason(base()), 'ok');
});

test('unknown fields are rejected at every level (nothing rides along)', () => {
  const top = base(); top.extra = 1;
  const turn = base(); turn.turns[0].extra = 1;
  const mem = base(); mem.memories[0].extra = 1;
  assert.equal(reason(top), 'unknown-field');
  assert.equal(reason(turn), 'turn');
  assert.equal(reason(mem), 'memory');
});

test('identifiers, locale, and schema version are checked', () => {
  const a = base(); a.schemaVersion = 2;
  const b = base(); b.requestId = 'nope';
  const c = base(); c.locale = 'English';
  const d = base(); d.memories[0].id = 'x';
  assert.deepEqual([a, b, c, d].map(reason), ['schemaVersion', 'requestId', 'locale', 'memory-id']);
});

test('length limits count Unicode scalars and reject rather than truncate', () => {
  const ok = base(); ok.userText = 'a'.repeat(LIMITS.userText);
  const long = base(); long.userText = 'a'.repeat(LIMITS.userText + 1);
  const empty = base(); empty.userText = '   ';
  assert.equal(reason(ok), 'ok');
  assert.equal(reason(long), 'userText');
  assert.equal(reason(empty), 'userText');
  const emoji = base(); emoji.userText = '👨‍👩‍👧'.repeat(300); // 5 scalars each = 1500
  assert.equal(reason(emoji), 'ok');
});

test('memory count, total size, source and duplicates are limited', () => {
  const many = base();
  many.memories = Array.from({ length: LIMITS.memories + 1 }, (_, i) => ({ ...many.memories[0], id: `00000000-0000-4000-8000-00000000000${i}` }));
  assert.equal(reason(many), 'memories');

  const big = base();
  big.memories = [0, 1, 2].map((i) => ({ ...big.memories[0], id: `00000000-0000-4000-8000-00000000000${i}`, text: 'x'.repeat(LIMITS.memoryText) }));
  assert.equal(reason(big), 'memory-total');

  const fixtureSource = base(); fixtureSource.memories[0].source = 'sample_fixture';
  assert.equal(reason(fixtureSource), 'memory-source', 'sample fixtures must never be sent');

  const dup = base(); dup.memories.push({ ...dup.memories[0] });
  assert.equal(reason(dup), 'memory-duplicate');
});

test('register request shape', () => {
  assert.equal(validateRegisterRequest(fixture('register_request_v1.json')).ok, true);
  assert.equal(validateRegisterRequest({ inviteCode: 'abcd', deviceId: 'x' }).ok, false);
  assert.equal(validateRegisterRequest({ inviteCode: 'abcd', deviceId: fixture('register_request_v1.json').deviceId, extra: 1 }).ok, false);
});
