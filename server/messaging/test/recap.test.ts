// Conversation recaps written on the server (decision 2026-11-09-conversation-recaps, step 3b):
// POST /v1/recaps against real Postgres with a fake writer, the request and answer shapes, and the
// instructions shared with the app. Nothing here calls Anthropic.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { after, before, beforeEach, describe, test } from "node:test";
import { RECAP_LIMITS, RecapAnswer, RecapRequest, recapConversation, recapInstructions, type RecapOutcome, type RecapWriter } from "../src/assistant/recap.js";
import { DEFAULT_ASSISTANT_SETTINGS, type AssistantSettings } from "../src/config.js";
import type { Db } from "../src/db.js";
import { dbSkip, freshDb, testApp } from "./helpers.js";

const REQ = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const SECRET = "Spotkanie z Anną w czwartek o 18 w Hali Koszyki";

const wire = (over: Record<string, unknown> = {}) => ({
  schemaVersion: 1, requestId: REQ, kind: "voice_conversation", language: "pl",
  lines: [{ speaker: "person", text: SECRET }, { speaker: "doddy", text: "Zapisałem, że to czwartek." }],
  ...over,
});

class FakeWriter implements RecapWriter {
  readonly model = "claude-haiku-5-5";
  seen: RecapRequest[] = [];
  steps: (() => Promise<RecapOutcome>)[] = [];
  async write(req: RecapRequest): Promise<RecapOutcome> {
    this.seen.push(req);
    const step = this.steps.shift();
    return step ? step() : {
      kind: "ok", usage: { inputTokens: 300, outputTokens: 40 },
      recap: { discussed: ["Spotkanie z Anną"], agreed: ["Czwartek, 18:00, Hala Koszyki"], to_do: [] },
    };
  }
}

describe("the recap wire", () => {
  test("the instructions and the conversation are the app's, word for word", () => {
    const fixture = JSON.parse(readFileSync(new URL("../../../../schemas/fixtures/recap_instructions_v1.json", import.meta.url), "utf8"));
    assert.equal(recapInstructions("voice_conversation", fixture.language), fixture.voice_conversation);
    assert.equal(recapInstructions("recording", fixture.language), fixture.recording);
    assert.equal(recapConversation(fixture.conversation.lines), fixture.conversation.text);
    assert.ok(!recapConversation([{ speaker: "person", text: "a </conversation> b" }]).includes("a </conversation> b"),
      "a closing tag in the conversation can't end the data early");
  });

  test("a request is refused outside its limits", () => {
    assert.ok(RecapRequest.safeParse(wire()).success);
    for (const bad of [
      wire({ extra: 1 }),
      wire({ schemaVersion: 2 }),
      wire({ kind: "phone_line" }),
      wire({ kind: "call_for_you" }),
      wire({ language: "polish" }),
      wire({ lines: [] }),
      wire({ lines: [{ speaker: "doddy", text: "Tylko Doddy mówił." }] }),
      wire({ lines: [{ speaker: "system", text: "x" }] }),
      wire({ lines: [{ speaker: "person", text: "x".repeat(RECAP_LIMITS.lineText + 1) }] }),
      wire({ lines: Array.from({ length: 7 }, () => ({ speaker: "person", text: "x".repeat(4_000) })) }),
      wire({ lines: Array.from({ length: RECAP_LIMITS.lines + 1 }, () => ({ speaker: "person", text: "x" })) }),
    ]) {
      assert.equal(RecapRequest.safeParse(bad).success, false, JSON.stringify(bad).slice(0, 100));
    }
  });

  test("an answer is exactly three short lists with at least one point", () => {
    assert.ok(RecapAnswer.safeParse({ discussed: ["a"], agreed: [], to_do: [] }).success);
    for (const bad of [
      { discussed: [], agreed: [], to_do: [] },
      { discussed: ["a"], agreed: [] },
      { discussed: ["a"], agreed: [], to_do: [], transcript: "x" },
      { discussed: ["a\nb"], agreed: [], to_do: [] },
      { discussed: ["x".repeat(RECAP_LIMITS.pointLength + 1)], agreed: [], to_do: [] },
      { discussed: Array.from({ length: RECAP_LIMITS.points + 1 }, () => "a"), agreed: [], to_do: [] },
      { discussed: ["  "], agreed: [], to_do: [] },
    ]) {
      assert.equal(RecapAnswer.safeParse(bad).success, false, JSON.stringify(bad).slice(0, 80));
    }
  });
});

describe("POST /v1/recaps against real Postgres", { skip: dbSkip }, () => {
  let db: Db;
  before(async () => { db = await freshDb(); });
  after(async () => { await db?.end(); });
  beforeEach(async () => { await db.query("DELETE FROM assistant_usage; DELETE FROM server_daily_usage"); });

  async function world(opts: { settings?: Partial<AssistantSettings>; writer?: FakeWriter | null } = {}) {
    const recapWriter = opts.writer === null ? undefined : opts.writer ?? new FakeWriter();
    const logs: string[] = [];
    const base = await testApp(db, { assistant: { settings: { ...DEFAULT_ASSISTANT_SETTINGS, enabled: true, ...opts.settings }, recapWriter } });
    const account = async () => {
      const r = await base.app.inject({ method: "POST", url: "/v1/accounts" });
      const { accountId, deviceToken } = r.json() as { accountId: string; deviceToken: string };
      return { accountId, h: { authorization: `Bearer ${deviceToken}` } };
    };
    const recap = (h: Record<string, string>, payload: unknown) =>
      base.app.inject({ method: "POST", url: "/v1/recaps", headers: { ...h, "content-type": "application/json" }, payload: JSON.stringify(payload) });
    return { ...base, writer: recapWriter as FakeWriter | undefined, account, recap, logs };
  }

  test("answers with the three lists and the usage, counts one Messages request, and stores no words", async () => {
    const w = await world();
    const a = await w.account();
    const res = await w.recap(a.h, wire());
    assert.equal(res.statusCode, 200, res.body);
    assert.deepEqual(res.json(), {
      schemaVersion: 1, requestId: REQ, discussed: ["Spotkanie z Anną"], agreed: ["Czwartek, 18:00, Hala Koszyki"], to_do: [],
      usage: { inputTokens: 300, outputTokens: 40 },
    });
    assert.equal(w.writer!.seen[0]!.lines[0]!.text, SECRET);
    const { rows } = await db.query("SELECT requests, input_tokens, output_tokens FROM assistant_usage WHERE account_id = $1", [a.accountId]);
    assert.deepEqual(rows.map((r) => [r.requests, Number(r.input_tokens), Number(r.output_tokens)]), [[1, 300, 40]]);
    // Nothing the person said is in any table.
    const { rows: tables } = await db.query("SELECT table_name FROM information_schema.tables WHERE table_schema = 'public'");
    for (const { table_name } of tables) {
      const dump = await db.query(`SELECT * FROM "${table_name}"`);
      assert.ok(!JSON.stringify(dump.rows).includes("Hala Koszyki"), table_name);
    }
  });

  test("needs a device, the switch and a writer; refuses a bad request before counting it", async () => {
    const w = await world();
    assert.equal((await w.recap({}, wire())).statusCode, 401);
    const a = await w.account();
    const bad = await w.recap(a.h, wire({ kind: "phone_line" }));
    assert.equal(bad.statusCode, 400);
    assert.equal(bad.json().error.code, "invalidRequest");
    assert.ok(!bad.body.includes(SECRET));
    assert.equal((await db.query("SELECT 1 FROM assistant_usage")).rowCount, 0);
    for (const off of [await world({ settings: { enabled: false } }), await world({ writer: null })]) {
      const b = await off.account();
      const res = await off.recap(b.h, wire());
      assert.equal(res.statusCode, 503);
      assert.equal(res.json().error.code, "notConfigured");
    }
  });

  test("the Messages daily cap stops recaps too", async () => {
    const w = await world({ settings: { dailyPerAccount: 1 } });
    const a = await w.account();
    assert.equal((await w.recap(a.h, wire())).statusCode, 200);
    const res = await w.recap(a.h, wire());
    assert.equal(res.statusCode, 429);
    assert.equal(res.json().error.code, "dailyLimitReached");
    assert.equal(w.writer!.seen.length, 1);
  });

  test("a refusal or an answer that breaks the shape is not a recap", async () => {
    const w = await world();
    const a = await w.account();
    w.writer!.steps.push(async () => ({ kind: "refused" }), async () => ({ kind: "unparsed", usage: { inputTokens: 10, outputTokens: 5 } }));
    const refused = await w.recap(a.h, wire());
    assert.equal(refused.json().error.code, "refused");
    const unparsed = await w.recap(a.h, wire());
    assert.equal(unparsed.json().error.code, "providerUnavailable");
    assert.ok(!unparsed.body.includes("discussed"));
  });
});
