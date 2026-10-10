import assert from 'node:assert/strict';
import test from 'node:test';
import { handleAssist } from '../src/assist.js';
import { costMicros, MemorySpendCap, SharedSpendCap, estimateMicros, secondsUntilNextUtcDay, utcDay } from '../src/budget.js';
import { loadConfig } from '../src/config.js';
import { MESSAGE } from '../src/errors.js';
import { SharedRateLimiter } from '../src/ratelimit.js';
import { handleRegister } from '../src/register.js';
import { createLimits } from '../src/runtime.js';
import { createRestStore, StoreUnavailableError } from '../src/store.js';
import { assistRequest, DEVICE, ENV, fakeProvider, fixture, INVITE, NOW_MS, providerOk, SECRET, token } from './helpers.js';

// No network anywhere in this file: the shared store is an in-process fake of the Upstash REST API.

const STORE_URL = 'https://fake-store.upstash.test';
const STORE_TOKEN = 'store-token-not-real-0000000000';
const SHARED_ENV = { ...ENV, UPSTASH_REDIS_REST_URL: STORE_URL, UPSTASH_REDIS_REST_TOKEN: STORE_TOKEN };
const OTHER_DEVICE = '9a8b7c6d-5e4f-4a3b-9c2d-1e0f9a8b7c6d';

/**
 * Fake of Upstash's POST /multi-exec: [["CMD", ...args], ...] -> [{result}, ...]. Honours TTLs against
 * a controllable clock. `state.down` makes fetch reject (unreachable); `state.status` returns an HTTP error.
 */
function fakeStore(clock = { now: NOW_MS }) {
  /** @type {Map<string, {value: string, expiresAtMs?: number}>} */
  const data = new Map();
  const state = { down: false, status: 200, calls: /** @type {any[]} */ ([]) };
  const live = (k) => {
    const e = data.get(k);
    if (e && e.expiresAtMs !== undefined && e.expiresAtMs <= clock.now) { data.delete(k); return undefined; }
    return e;
  };
  const add = (k, by) => {
    const e = live(k) ?? { value: '0' };
    e.value = String(Number(e.value) + by);
    data.set(k, e);
    return Number(e.value);
  };
  const fetch = async (url, init) => {
    state.calls.push({ url, init, body: JSON.parse(init.body) });
    if (state.down) throw new TypeError('fetch failed');
    if (state.status !== 200) return new Response(JSON.stringify({ error: 'ERR' }), { status: state.status });
    assert.equal(url, `${STORE_URL}/multi-exec`);
    assert.equal(init.headers.authorization, `Bearer ${STORE_TOKEN}`);
    const out = JSON.parse(init.body).map(([cmd, k, arg]) => {
      switch (cmd) {
        case 'INCR': return { result: add(k, 1) };
        case 'INCRBY': return { result: add(k, Number(arg)) };
        case 'DECRBY': return { result: add(k, -Number(arg)) };
        case 'EXPIRE': { const e = live(k); if (!e) return { result: 0 }; e.expiresAtMs = clock.now + Number(arg) * 1000; return { result: 1 }; }
        default: return { error: `ERR unknown command '${cmd}'` };
      }
    });
    return Response.json(out);
  };
  return { fetch, data, state, clock };
}

/** Handler deps backed by the shared adapters, as runtime.js builds them. */
function sharedDeps(store, { env = SHARED_ENV, provider = fakeProvider(providerOk({ answer: 'ok', sources: [] })) } = {}) {
  const logs = [];
  const limits = createLimits(env, { fetch: store.fetch, logSink: (l) => logs.push(l) });
  assert.equal(limits.shared, true);
  return { deps: { env, fetch: provider, now: () => store.clock.now, limiter: limits.limiter, spend: limits.spend, logSink: (l) => logs.push(l) }, logs, provider };
}

const body = () => structuredClone(fixture('assist_request_v1.json'));
const call = async (deps, auth = token()) => { const res = await handleAssist(assistRequest(body(), { auth }), deps); return { res, json: await res.json() }; };
const registerRequest = () => new Request('https://g.test/api/register', {
  method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ inviteCode: INVITE, deviceId: DEVICE }),
});

// ---------- Shared rate limiter ----------

test('shared limiter: counts are shared across function instances', async () => {
  const store = fakeStore();
  const rest = createRestStore({ url: STORE_URL, token: STORE_TOKEN, fetch: store.fetch });
  const a = new SharedRateLimiter({ store: rest, keySecret: SECRET });
  const b = new SharedRateLimiter({ store: rest, keySecret: SECRET });
  assert.deepEqual(await a.hit('dev:x', 3, 60, NOW_MS), { allowed: true });
  assert.deepEqual(await b.hit('dev:x', 3, 60, NOW_MS), { allowed: true });
  assert.deepEqual(await a.hit('dev:x', 3, 60, NOW_MS), { allowed: true });
  const denied = await b.hit('dev:x', 3, 60, NOW_MS);
  assert.equal(denied.allowed, false);
  // Window is aligned to the epoch: NOW_MS is 20 s into a minute.
  assert.equal(denied.retryAfterSeconds, 60 - (NOW_MS / 1000) % 60);
  // A different bucket is independent.
  assert.deepEqual(await b.hit('dev:y', 3, 60, NOW_MS), { allowed: true });
});

test('shared limiter: a new window starts with a fresh count and old keys expire', async () => {
  const store = fakeStore();
  const limiter = new SharedRateLimiter({ store: createRestStore({ url: STORE_URL, token: STORE_TOKEN, fetch: store.fetch }), keySecret: SECRET });
  assert.equal((await limiter.hit('k', 1, 60, store.clock.now)).allowed, true);
  assert.equal((await limiter.hit('k', 1, 60, store.clock.now)).allowed, false);
  store.clock.now += 60_000;
  assert.equal((await limiter.hit('k', 1, 60, store.clock.now)).allowed, true);
  // Every key got a TTL that outlives its window, so nothing accumulates in the store.
  store.clock.now += 200_000;
  for (const k of [...store.data.keys()]) assert.equal(store.data.get(k)?.expiresAtMs !== undefined, true);
  assert.equal([...store.data.keys()].filter((k) => store.data.get(k).expiresAtMs > store.clock.now).length, 0);
});

test('shared limiter: one atomic MULTI/EXEC per hit, token only in the header, no raw ids in the store', async () => {
  const store = fakeStore();
  const limiter = new SharedRateLimiter({ store: createRestStore({ url: STORE_URL, token: STORE_TOKEN, fetch: store.fetch }), keySecret: SECRET });
  await limiter.hit(`dev:${DEVICE}`, 5, 60, NOW_MS);
  await limiter.hit('reg-ip:203.0.113.7', 5, 3600, NOW_MS);
  assert.equal(store.state.calls.length, 2);
  const [cmds] = store.state.calls.map((c) => c.body);
  assert.deepEqual(cmds.map((c) => c[0]), ['INCR', 'EXPIRE']);
  assert.equal(cmds[1][2], '120', 'TTL = window + 60 s');
  for (const c of store.state.calls) assert.doesNotMatch(c.init.body, new RegExp(STORE_TOKEN));
  const keys = [...store.data.keys()].join(' ');
  assert.doesNotMatch(keys, new RegExp(DEVICE));
  assert.doesNotMatch(keys, /203\.0\.113\.7/);
});

test('shared store failures all surface as StoreUnavailableError (unreachable, HTTP error, error entry, bad shape, timeout)', async () => {
  const store = fakeStore();
  const rest = createRestStore({ url: STORE_URL, token: STORE_TOKEN, fetch: store.fetch });
  const limiter = new SharedRateLimiter({ store: rest, keySecret: SECRET });

  store.state.down = true;
  await assert.rejects(limiter.hit('k', 5, 60, NOW_MS), StoreUnavailableError);
  store.state.down = false; store.state.status = 500;
  await assert.rejects(limiter.hit('k', 5, 60, NOW_MS), StoreUnavailableError);
  store.state.status = 200;
  await assert.rejects(rest.exec([['NOPE', 'k']]), StoreUnavailableError);

  const odd = createRestStore({ url: STORE_URL, token: STORE_TOKEN, fetch: async () => Response.json({ result: 1 }) });
  await assert.rejects(new SharedRateLimiter({ store: odd, keySecret: SECRET }).hit('k', 5, 60, NOW_MS), StoreUnavailableError);
  const notNumber = createRestStore({ url: STORE_URL, token: STORE_TOKEN, fetch: async () => Response.json([{ result: 'x' }, { result: 1 }]) });
  await assert.rejects(new SharedRateLimiter({ store: notNumber, keySecret: SECRET }).hit('k', 5, 60, NOW_MS), StoreUnavailableError);

  const hung = createRestStore({
    url: STORE_URL, token: STORE_TOKEN, timeoutMs: 20,
    fetch: (_url, init) => new Promise((_, reject) => init.signal.addEventListener('abort', () => reject(Object.assign(new Error('aborted'), { name: 'AbortError' })))),
  });
  await assert.rejects(hung.exec([['INCR', 'k']]), StoreUnavailableError);
});

test('handler: the global daily brake holds across two instances sharing the store', async () => {
  const store = fakeStore();
  const env = { ...SHARED_ENV, GATEWAY_GLOBAL_PER_DAY: '2' };
  const one = sharedDeps(store, { env });
  const two = sharedDeps(store, { env });
  assert.equal((await call(one.deps)).res.status, 200);
  assert.equal((await call(two.deps, token({ deviceId: OTHER_DEVICE }))).res.status, 200);
  const third = await call(one.deps, token({ deviceId: '11111111-2222-4333-8444-555555555555' }));
  assert.equal(third.res.status, 429);
  assert.equal(third.json.error.code, 'rateLimited');
  assert.equal(one.provider.calls.length + two.provider.calls.length, 2);
});

test('handler: store down -> assist and register refuse with 503 (fail closed) and never call the provider', async () => {
  const store = fakeStore();
  const { deps, logs, provider } = sharedDeps(store);
  store.state.down = true;
  const { res, json } = await call(deps);
  assert.equal(res.status, 503);
  assert.equal(json.error.code, 'providerUnavailable');
  assert.equal(json.requestId, undefined, 'refused at the rate-limit step, before the body is read');
  assert.equal(provider.calls.length, 0);
  assert.match(logs.at(-1), /"cause":"limitStore"/);
  assert.doesNotMatch(logs.join('\n'), new RegExp(STORE_TOKEN));

  const reg = await handleRegister(registerRequest(), deps);
  assert.equal(reg.status, 503);
  assert.equal((await reg.json()).error.code, 'providerUnavailable');
  assert.match(logs.at(-1), /"evt":"register".*"cause":"limitStore"/);
});

test('handler: store goes down between rate limits and budget -> 503, provider not called', async () => {
  const store = fakeStore();
  const { deps, provider } = sharedDeps(store);
  const hit = deps.limiter.hit.bind(deps.limiter);
  let hits = 0;
  deps.limiter = { hit: async (...a) => { const d = await hit(...a); if (++hits === 4) store.state.down = true; return d; } };
  const { res, json } = await call(deps);
  assert.equal(res.status, 503);
  assert.equal(json.error.code, 'providerUnavailable');
  assert.equal(json.requestId, body().requestId);
  assert.equal(provider.calls.length, 0);
});

// ---------- Daily spend cap ----------

test('budget: a request that would exceed DAILY_BUDGET_USD is refused before the provider is called', async () => {
  const store = fakeStore();
  const { deps, provider } = sharedDeps(store, { env: { ...SHARED_ENV, DAILY_BUDGET_USD: '0.001' } });
  const { res, json } = await call(deps);
  assert.equal(res.status, 429);
  assert.equal(json.error.code, 'dailyLimitReached');
  assert.equal(json.error.message, "Doddy's daily limit is reached; try again tomorrow.");
  assert.equal(json.error.retryAfterSeconds, secondsUntilNextUtcDay(NOW_MS));
  assert.equal(res.headers.get('retry-after'), String(secondsUntilNextUtcDay(NOW_MS)));
  assert.equal(json.requestId, body().requestId);
  assert.equal(provider.calls.length, 0);
  // The refused reservation was rolled back on every scope.
  const spend = new SharedSpendCap({ store: createRestStore({ url: STORE_URL, token: STORE_TOKEN, fetch: store.fetch }), keySecret: SECRET });
  assert.equal(store.data.get(spend.key('all', utcDay(NOW_MS)))?.value, '0');
  assert.equal(store.data.get(spend.key(`dev:${DEVICE}`, utcDay(NOW_MS)))?.value, '0');
});

test('budget: the estimate is replaced by real usage x configured price, and the day total then refuses', async () => {
  const store = fakeStore();
  const prices = { OPENAI_PRICE_INPUT_PER_MTOK_USD: '1', OPENAI_PRICE_OUTPUT_PER_MTOK_USD: '2' };
  // Real usage of 1,000,000 input + 20 output tokens at $1/$2 per 1M = $1.00004.
  const provider = fakeProvider(providerOk({ answer: 'ok', sources: [] }, { input_tokens: 1_000_000, output_tokens: 20 }));
  const env = { ...SHARED_ENV, ...prices, DAILY_BUDGET_USD: '1.003', DAILY_BUDGET_PER_INSTALL_USD: '5' };
  const { deps, logs } = sharedDeps(store, { env, provider });

  const first = await call(deps);
  assert.equal(first.res.status, 200);
  const spend = new SharedSpendCap({ store: createRestStore({ url: STORE_URL, token: STORE_TOKEN, fetch: store.fetch }), keySecret: SECRET });
  assert.equal(store.data.get(spend.key('all', utcDay(NOW_MS)))?.value, '1000040');
  assert.equal(store.data.get(spend.key(`dev:${DEVICE}`, utcDay(NOW_MS)))?.value, '1000040');
  assert.match(logs.at(-1), /"costMicros":1000040/);

  const second = await call(deps, token({ deviceId: OTHER_DEVICE }));
  assert.equal(second.res.status, 429);
  assert.equal(second.json.error.code, 'dailyLimitReached');
  assert.equal(provider.calls.length, 1);

  // Next UTC day: fresh budget.
  store.clock.now = (Math.floor(NOW_MS / 86_400_000) + 1) * 86_400_000 + 5_000;
  assert.equal((await call(deps, token({ deviceId: OTHER_DEVICE, ageSeconds: -86_000 }))).res.status, 200);
});

test('budget: the per-install cap stops one install without stopping others', async () => {
  const store = fakeStore();
  const env = { ...SHARED_ENV, OPENAI_PRICE_INPUT_PER_MTOK_USD: '1', OPENAI_PRICE_OUTPUT_PER_MTOK_USD: '1', DAILY_BUDGET_PER_INSTALL_USD: '0.01' };
  const provider = fakeProvider(providerOk({ answer: 'ok', sources: [] }, { input_tokens: 9_000, output_tokens: 0 }));
  const { deps } = sharedDeps(store, { env, provider });
  assert.equal((await call(deps)).res.status, 200);
  const again = await call(deps);
  assert.equal(again.res.status, 429);
  assert.equal(again.json.error.code, 'dailyLimitReached');
  assert.equal((await call(deps, token({ deviceId: OTHER_DEVICE }))).res.status, 200);
});

test('budget: a 4xx provider rejection releases the reservation; a timeout or 5xx keeps the estimate booked', async () => {
  const prices = { inputPerMTok: 10, outputPerMTok: 40 };
  for (const [reply, expectZero] of [[new Response('{}', { status: 401 }), true], [new Response('{}', { status: 500 }), false]]) {
    const spend = new MemorySpendCap();
    const { deps } = { deps: { env: ENV, fetch: fakeProvider(reply), now: () => NOW_MS, limiter: { hit: async () => ({ allowed: true }) }, spend, logSink: () => {} } };
    const { res } = await call(deps);
    assert.notEqual(res.status, 200);
    const total = spend.total('all', NOW_MS);
    if (expectZero) assert.equal(total, 0);
    else assert.ok(total >= estimateMicros(1, 800, prices) && total > 0, `estimate stays booked (${total})`);
  }
});

test('budget: concurrent reservations never jointly exceed the cap', async () => {
  const store = fakeStore();
  const spend = new SharedSpendCap({ store: createRestStore({ url: STORE_URL, token: STORE_TOKEN, fetch: store.fetch }), keySecret: SECRET });
  const results = await Promise.all(Array.from({ length: 7 }, () => spend.reserve([{ scope: 'all', capMicros: 250 }], 100, NOW_MS)));
  assert.equal(results.filter((r) => r.ok).length, 2);
  assert.equal(store.data.get(spend.key('all', utcDay(NOW_MS)))?.value, '200');
});

test('budget: if the store fails after the answer is paid for, the answer is still returned and the failure logged', async () => {
  const store = fakeStore();
  const provider = fakeProvider(async () => { store.state.down = true; return providerOk({ answer: 'ok', sources: [] }); });
  const { deps, logs } = sharedDeps(store, { provider });
  const { res } = await call(deps);
  assert.equal(res.status, 200);
  assert.ok(logs.some((l) => /"cause":"settleFailed"/.test(l)));
});

test('budget maths: micro-dollars, rounded up; the estimate is an upper bound on a normal call', () => {
  assert.equal(costMicros({ inputTokens: 1_000_000, outputTokens: 0 }, { inputPerMTok: 0.15, outputPerMTok: 0.6 }), 150_000);
  assert.equal(costMicros({ inputTokens: 1, outputTokens: 1 }, { inputPerMTok: 0.15, outputPerMTok: 0.6 }), 1);
  const prices = { inputPerMTok: 2, outputPerMTok: 8 };
  assert.ok(estimateMicros(4_000, 800, prices) >= costMicros({ inputTokens: 4_000, outputTokens: 800 }, prices));
  assert.equal(secondsUntilNextUtcDay(Date.UTC(2026, 9, 10, 23, 59, 30)), 30);
  assert.equal(utcDay(Date.UTC(2026, 9, 10, 23, 59, 59)), '2026-10-10');
});

// ---------- Configuration ----------

test('config: nothing configured -> per-instance memory adapters with startup warnings (local dev keeps working)', async () => {
  const logs = [];
  const limits = createLimits(ENV, { fetch: async () => { throw new Error('no network in tests'); }, logSink: (l) => logs.push(l) });
  assert.equal(limits.shared, false);
  assert.ok(logs.includes('{"evt":"startup","code":"limitsPerInstance"}'));
  assert.ok(logs.includes('{"evt":"startup","code":"placeholderPrices"}'));
  const loaded = loadConfig(ENV);
  assert.equal(loaded.ok, true);
  assert.equal(loaded.ok && loaded.config.sharedStore, null);
  assert.equal(loaded.ok && loaded.config.dailyBudgetMicros, 1_000_000);
});

test('config: REQUIRE_SHARED_LIMITS=1 without a store -> every endpoint answers 503 notConfigured', async () => {
  const env = { ...ENV, REQUIRE_SHARED_LIMITS: '1' };
  const logs = [];
  const limits = createLimits(env, { fetch: async () => { throw new Error('unused'); }, logSink: (l) => logs.push(l) });
  const deps = { env, fetch: fakeProvider(providerOk({ answer: 'x' })), now: () => NOW_MS, limiter: limits.limiter, spend: limits.spend, logSink: (l) => logs.push(l) };
  const { res, json } = await call(deps);
  assert.equal(res.status, 503);
  assert.equal(json.error.code, 'notConfigured');
  assert.equal(deps.fetch.calls.length, 0);
  assert.match(logs.at(-1), /"configMissing":\["UPSTASH_REDIS_REST_URL","UPSTASH_REDIS_REST_TOKEN"\]/);
  assert.equal((await handleRegister(registerRequest(), deps)).status, 503);
});

test('config: half a store configuration, a non-https URL or a bad budget is refused, never a silent fallback', () => {
  const cases = [
    [{ UPSTASH_REDIS_REST_URL: STORE_URL }, ['UPSTASH_REDIS_REST_TOKEN']],
    [{ UPSTASH_REDIS_REST_TOKEN: STORE_TOKEN }, ['UPSTASH_REDIS_REST_URL']],
    [{ UPSTASH_REDIS_REST_URL: 'http://plain.example', UPSTASH_REDIS_REST_TOKEN: STORE_TOKEN }, ['UPSTASH_REDIS_REST_URL']],
    [{ DAILY_BUDGET_USD: 'abc' }, ['DAILY_BUDGET_USD']],
    [{ DAILY_BUDGET_USD: '0' }, ['DAILY_BUDGET_USD']],
    [{ DAILY_BUDGET_PER_INSTALL_USD: '-1' }, ['DAILY_BUDGET_PER_INSTALL_USD']],
    [{ OPENAI_PRICE_OUTPUT_PER_MTOK_USD: 'free' }, ['OPENAI_PRICE_OUTPUT_PER_MTOK_USD']],
  ];
  for (const [extra, missing] of cases) {
    const loaded = loadConfig({ ...ENV, ...extra });
    assert.equal(loaded.ok, false, JSON.stringify(extra));
    assert.deepEqual(!loaded.ok && loaded.missing, missing);
  }
});

test('config: Vercel KV variable names are accepted as the shared store', () => {
  const env = { ...ENV, KV_REST_API_URL: STORE_URL, KV_REST_API_TOKEN: STORE_TOKEN, REQUIRE_SHARED_LIMITS: '1' };
  const loaded = loadConfig(env);
  assert.equal(loaded.ok, true);
  assert.deepEqual(loaded.ok && loaded.config.sharedStore, { url: STORE_URL, token: STORE_TOKEN });
  assert.equal(createLimits(env, { fetch: fakeStore().fetch, logSink: () => {} }).shared, true);
});

test('wire: dailyLimitReached is a new code with a fixed message; other codes are unchanged', () => {
  assert.equal(MESSAGE.dailyLimitReached, "Doddy's daily limit is reached; try again tomorrow.");
  assert.equal(MESSAGE.rateLimited, 'Too many requests. Try again shortly.');
});
