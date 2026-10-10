import assert from 'node:assert/strict';
import test from 'node:test';
import { handleAssist } from '../src/assist.js';
import { errorResponse } from '../src/http.js';
import { handleRegister } from '../src/register.js';
import { assistRequest, fakeProvider, fixture, makeDeps, providerOk, DEVICE, INVITE } from './helpers.js';

// The Swift tests decode these same files (schemas/fixtures). Pinning them to real handler output means
// "Swift decodes the fixture" really implies "Swift decodes what the gateway sends".

test('assist_response_v1.json is exactly what the gateway returns for assist_request_v1.json', async () => {
  const expected = fixture('assist_response_v1.json');
  const provider = fakeProvider(providerOk(
    { answer: expected.text, sources: ['n1'] },
    { input_tokens: expected.usage.inputTokens, output_tokens: expected.usage.outputTokens },
  ));
  const { deps } = makeDeps({ fetch: provider });
  const res = await handleAssist(assistRequest(fixture('assist_request_v1.json')), deps);
  assert.equal(res.status, 200);
  assert.deepEqual(await res.json(), expected);
});

test('assist_error_v1.json is exactly what the gateway returns for a rate limit', async () => {
  const expected = fixture('assist_error_v1.json');
  const res = errorResponse('rateLimited', { requestId: expected.requestId, retryAfterSeconds: expected.error.retryAfterSeconds });
  assert.equal(res.status, 429);
  assert.deepEqual(await res.json(), expected);
});

test('register_response_v1.json has the same shape the gateway returns', async () => {
  const { deps } = makeDeps();
  const res = await handleRegister(new Request('https://g.test/api/register', {
    method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ inviteCode: INVITE, deviceId: DEVICE }),
  }), deps);
  const actual = await res.json();
  const expected = fixture('register_response_v1.json');
  assert.deepEqual(Object.keys(actual).sort(), Object.keys(expected).sort());
  assert.equal(typeof actual.token, 'string');
  assert.equal(Number.isInteger(actual.expiresAtMs), true);
  assert.equal(actual.schemaVersion, expected.schemaVersion);
});
