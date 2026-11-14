import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import { DOCUMENT_KINDS, MockClaudeProvider } from "../src/tools/claude.js";
import { judgeDocumentRequest, needDetailsMessage, wordCount } from "../src/tools/documentDetails.js";
import { DEV_IDENTITIES } from "../src/auth.js";
import { USER_A } from "./helpers.js";
import { type Rig, start } from "./toolsRig.js";

/** make_document asks for details first (decision 2026-11-10-files-ask-for-details): a cautious judge, and a refusal that costs nothing. */

let rig: Rig | undefined;
afterEach(async () => {
  await rig?.tools.settle();
  await rig?.close();
  rig = undefined;
});

const verdict = (title: string, request: string, kind: (typeof DOCUMENT_KINDS)[number] = "deck", material?: string) => judgeDocumentRequest({ kind, title, request, material });

test("a bare topic is refused, with what is missing", () => {
  const v = verdict("Iława", "prezentacja o Iławie");
  assert.equal(v.ok, false);
  if (!v.ok) assert.deepEqual(v.missing, ["audience", "purpose", "length"]);
  assert.equal(verdict("Iława", "Make a presentation about Iława").ok, false);
});

test("a stated audience, purpose or length of detail is accepted", () => {
  assert.equal(verdict("Iława", "prezentacja o Iławie dla klasy 5 na 6 slajdów").ok, true, "audience");
  assert.equal(verdict("Iława", "prezentacja o Iławie żeby zachęcić turystów").ok, true, "purpose (Polish)");
  assert.equal(verdict("Iława", "slides about Iława to persuade the council").ok, true, "purpose (English)");
  assert.equal(verdict("Budget", "A short deck for the board").ok, true, "audience (English)");
  assert.equal(verdict("Iława", "Prezentacja o historii miasta Iława, jego zabytkach, jeziorze Jeziorak i atrakcjach").ok, true, "long and specific");
});

test("a cue only counts as a whole word", () => {
  assert.equal(verdict("Kwiaty", "podlać kwiaty").ok, false, "'dla' inside 'podlać' is not an audience");
  assert.equal(verdict("Stories", "forest stories").ok, false, "'for' inside 'forest' is not an audience");
});

test("material is enough; a few characters of it are not", () => {
  assert.equal(verdict("Iława", "prezentacja", "deck", "Iława leży nad jeziorem Jeziorak, ma około 31 tysięcy mieszkańców.").ok, true);
  assert.equal(verdict("Iława", "prezentacja", "deck", "Iława").ok, false);
});

test("every kind is judged; a spreadsheet is never asked for its length", () => {
  for (const kind of DOCUMENT_KINDS) {
    assert.equal(verdict("Iława", "o Iławie", kind).ok, false, kind);
    assert.equal(verdict("Iława", "o Iławie dla turystów", kind).ok, true, kind);
  }
  const sheet = verdict("Budżet", "arkusz budżetu", "spreadsheet");
  assert.deepEqual(sheet.ok ? [] : sheet.missing, ["audience", "purpose"]);
  const asksLength = verdict("Iława", "krótka prezentacja o Iławie", "deck");
  assert.deepEqual(asksLength.ok ? [] : asksLength.missing, ["audience", "purpose"], "a length given is not asked again");
});

test("word counts and the one-line message", () => {
  assert.equal(wordCount("Zażółć gęślą jaźń, 6 slajdów"), 5);
  assert.equal(needDetailsMessage(["audience", "purpose"]), "Missing details: audience, purpose.");
});

// ------------------------------------------------------------------ at prepare: free of charge

test("a refused request makes no card, no approval, no cap use and no Claude call", async () => {
  const claude = new MockClaudeProvider();
  let calls = 0;
  claude.makeDocument = async () => {
    calls++;
    throw new Error("must not run");
  };
  rig = await start({}, { claude });
  const refused = await rig.call("POST", "/v1/tools/prepare", { token: USER_A, body: { tool: "make_document", arguments: { kind: "deck", title: "Iława", request: "prezentacja o Iławie" } } });
  assert.equal(refused.status, 422, refused.text);
  const body = JSON.parse(refused.text) as { error: { code: string; message: string } };
  assert.equal(body.error.code, "need_details");
  assert.match(body.error.message, /audience, purpose, length/);
  assert.equal(calls, 0);
  assert.equal(await rig.store.usage(`user:${DEV_IDENTITIES[USER_A]!}:claude`, "day:2026-10-10"), 0, "no Claude run was counted");
  assert.equal(await rig.store.usage("service:claude", "day:2026-10-10"), 0);

  // The same request with the answers in it is prepared as usual.
  const ok = await rig.call("POST", "/v1/tools/prepare", {
    token: USER_A,
    body: { tool: "make_document", arguments: { kind: "deck", title: "Iława", request: "prezentacja o Iławie dla klasy 5, 6 slajdów" } },
  });
  assert.equal(ok.status, 200, ok.text);
  assert.ok(JSON.parse(ok.text).approvalId);
});
