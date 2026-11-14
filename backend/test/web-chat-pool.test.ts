import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import { loadConfig, testLimits } from "../src/config.js";
import { MockClaudeProvider } from "../src/tools/claude.js";
import { USER_A, USER_B } from "./helpers.js";
import { startWeb, type WebRig } from "./webRig.js";

/**
 * The browser chat has its own server-wide daily pool (`service:web_chat`, decision
 * 2026-11-12-voice-token-fair-share): its questions no longer draw from Ask Doddy's `service:ask`.
 * One person's daily total (`user:<id>:ask`) is still shared between the iPhone and the browser,
 * so using both doesn't double it. Guests' own pool (`service:ask:guest`, ADR-587) is untouched
 * (see assist.test.ts).
 */

let rig: WebRig | undefined;
afterEach(async () => {
  await rig?.close();
  rig = undefined;
});

const DAY = "day:2026-10-22"; // the rig's clock
const ID_A = "00000000-0000-4000-8000-00000000000a"; // DEV_IDENTITIES[USER_A]
const ID_B = "00000000-0000-4000-8000-00000000000b"; // DEV_IDENTITIES[USER_B]

const chat = (r: WebRig, token = USER_A) => r.call("POST", "/v1/web/chat", { token, body: { message: "Which apps do I have connected?", locale: "en" } });

let requests = 0;
/** Ask Doddy on the iPhone, with a request id of its own each time (a repeated id is answered once). */
const phone = (r: WebRig, token = USER_A) =>
  r.call("POST", "/v1/assist", {
    token,
    body: {
      schemaVersion: 1,
      requestId: `00000000-0000-4000-8000-${String(++requests).padStart(12, "0")}`,
      sessionId: "7c9e6679-7425-40de-944b-e07fc1f90ae7",
      locale: "en-GB",
      userText: "What time is it?",
      turns: [],
      memories: [],
    },
  });

const used = (r: WebRig, counter: string) => r.store.usage(counter, DAY);

test("a web chat question draws from the web chat's pool, not from Ask Doddy's", async () => {
  rig = await startWeb({ assist: new MockClaudeProvider() });
  const res = await chat(rig);
  assert.equal(res.status, 200, res.text);
  assert.equal(await used(rig, "service:web_chat"), 1);
  assert.equal(await used(rig, "service:ask"), 0);
  assert.equal(await used(rig, `user:${ID_A}:ask`), 1, "the person's own daily total is counted");
});

test("Ask Doddy on the iPhone draws from its own pool, not from the web chat's", async () => {
  rig = await startWeb({ assist: new MockClaudeProvider() });
  const res = await phone(rig);
  assert.equal(res.status, 200, res.text);
  assert.equal(await used(rig, "service:ask"), 1);
  assert.equal(await used(rig, "service:web_chat"), 0);
  assert.equal(await used(rig, `user:${ID_A}:ask`), 1);
});

test("one person's daily total is shared between the iPhone and the browser, so using both doesn't double it", async () => {
  rig = await startWeb({ assist: new MockClaudeProvider(), askLimits: { userDailyAsk: 3 } });
  assert.equal((await chat(rig)).status, 200);
  assert.equal((await phone(rig)).status, 200);
  assert.equal((await chat(rig)).status, 200);
  assert.equal(await used(rig, `user:${ID_A}:ask`), 3);
  assert.equal(await used(rig, "service:web_chat"), 2);
  assert.equal(await used(rig, "service:ask"), 1);
  // The total is spent: both doors say so, and neither pool is touched by the refusals.
  const web = await chat(rig);
  assert.equal(web.status, 429, web.text);
  assert.equal(web.body.error.code, "quota_exceeded");
  const iphone = await phone(rig);
  assert.equal(iphone.status, 429, iphone.text);
  assert.equal(iphone.body.error.code, "quota_exceeded");
  assert.equal(await used(rig, "service:web_chat"), 2);
  assert.equal(await used(rig, "service:ask"), 1);
  // Another person has their own total.
  assert.equal((await chat(rig, USER_B)).status, 200);
});

test("when the web chat's pool is spent, the refusal is the usual one and Ask Doddy's pool is not touched", async () => {
  rig = await startWeb({ assist: new MockClaudeProvider(), askLimits: { serviceDailyWebChat: 2, serviceDailyAsk: 5 } });
  assert.equal((await chat(rig, USER_A)).status, 200);
  assert.equal((await chat(rig, USER_A)).status, 200);
  const refused = await chat(rig, USER_B);
  assert.equal(refused.status, 429, refused.text);
  assert.equal(refused.body.error.code, "quota_exceeded");
  assert.equal(refused.body.error.message, "Today's question limit was reached. Try again tomorrow.");
  assert.equal(await used(rig, "service:web_chat"), 2, "the refused question was not counted");
  assert.equal(await used(rig, `user:${ID_B}:ask`), 0, "nor against the person's own total");
  // Ask Doddy on the iPhone still has all of its own pool, for the person who was refused and for the one who was not.
  assert.equal((await phone(rig, USER_B)).status, 200);
  assert.equal((await phone(rig, USER_A)).status, 200);
  assert.equal(await used(rig, "service:ask"), 2);
  assert.equal(await used(rig, "service:web_chat"), 2);
  // A new day opens the pool again.
  rig.clock.advance(86_400_000);
  assert.equal((await chat(rig, USER_B)).status, 200);
});

test("when Ask Doddy's pool is spent, the web chat is not affected", async () => {
  rig = await startWeb({ assist: new MockClaudeProvider(), askLimits: { serviceDailyAsk: 1, serviceDailyWebChat: 5 } });
  assert.equal((await phone(rig, USER_A)).status, 200);
  assert.equal((await phone(rig, USER_B)).status, 429);
  assert.equal((await chat(rig, USER_B)).status, 200);
  assert.equal(await used(rig, "service:web_chat"), 1);
});

test("a question the chat can't answer spends nothing from either counter", async () => {
  rig = await startWeb({ chatClaude: null, askLimits: { userDailyAsk: 1, serviceDailyWebChat: 1 } });
  const res = await chat(rig);
  assert.equal(res.status, 503, res.text);
  assert.equal(await used(rig, "service:web_chat"), 0);
  assert.equal(await used(rig, `user:${ID_A}:ask`), 0);
});

test("the web chat's pool is a setting: 200 a day by default, DODDY_LIMIT_SERVICE_DAILY_WEB_CHAT changes it, nonsense is refused", () => {
  assert.equal(testLimits().serviceDailyWebChat, 200);
  assert.equal(loadConfig({}).limits.serviceDailyWebChat, 200);
  assert.equal(loadConfig({ DODDY_LIMIT_SERVICE_DAILY_WEB_CHAT: "40" }).limits.serviceDailyWebChat, 40);
  assert.equal(loadConfig({ DODDY_LIMIT_SERVICE_DAILY_WEB_CHAT: "40" }).limits.serviceDailyAsk, 500, "Ask Doddy's pool is a separate setting");
  assert.throws(() => loadConfig({ DODDY_LIMIT_SERVICE_DAILY_WEB_CHAT: "0" }), /DODDY_LIMIT_SERVICE_DAILY_WEB_CHAT/);
  assert.throws(() => loadConfig({ DODDY_LIMIT_SERVICE_DAILY_WEB_CHAT: "lots" }), /DODDY_LIMIT_SERVICE_DAILY_WEB_CHAT/);
});
