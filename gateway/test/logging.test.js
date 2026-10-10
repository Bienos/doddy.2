import assert from 'node:assert/strict';
import test from 'node:test';
import { sanitize } from '../src/logging.js';

test('sanitize drops unknown keys, long strings, objects and arrays except configMissing names', () => {
  const out = sanitize({
    evt: 'assist', userText: 'secret', text: 'secret', token: 'abc', status: 200, ms: 5,
    code: 'x'.repeat(65), nested: { a: 1 }, deviceTag: 'abcd1234', configMissing: ['OPENAI_API_KEY', 'sk-leak value'],
  });
  assert.deepEqual(out, { evt: 'assist', status: 200, ms: 5, deviceTag: 'abcd1234', configMissing: ['OPENAI_API_KEY'] });
});

test('allowed keys still reject free text and odd numbers', () => {
  const out = sanitize({
    evt: 'assist', deviceTag: 'my secret question', requestId: '6f1c1f5e-3b0a-4c55-9d0e-0a1b2c3d4e51',
    code: 'where did I park', status: -1, ms: 1.5, inputTokens: '120', memoryCount: 2,
  });
  assert.deepEqual(out, { evt: 'assist', memoryCount: 2 });
});
