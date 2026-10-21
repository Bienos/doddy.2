import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import { ProviderError } from "../src/errors.js";
import { MONID_TOOLS, monidRequest, normalizeMonidTool } from "../src/tools/websearch.js";
import { on, type Rig, runRaw, start } from "./toolsRig.js";

/** News and places through fixed Monid endpoints (ADR-489): the price is on the card, ASK-01 first. Mock only. */

let rig: Rig;
afterEach(async () => rig?.close());

const prepare = (r: Rig, tool: string, args: Record<string, unknown>) => r.call("POST", "/v1/tools/prepare", { body: { tool, arguments: args } });

test("each tool is one fixed endpoint; nothing the model says picks another", () => {
  assert.deepEqual(monidRequest("news_search", { query: "tram", recent: "week" }), { provider: "search1api", endpoint: "/news", input: { query: "tram", max_results: 5, time_range: "week" } });
  assert.deepEqual(monidRequest("find_places", { query: "cafe", near: "Warsaw" }), { provider: "litescrape", endpoint: "/google/local", input: { queryParams: { q: "cafe", location: "Warsaw" } } });
  assert.deepEqual(Object.keys(MONID_TOOLS).sort(), ["find_places", "news_search"]);
});

test("the card shows the words and what Doddy pays; the yes runs exactly that once", async () => {
  rig = await start();
  await on(rig, "find_places");
  const card = await prepare(rig, "find_places", { query: "cafe", near: "Warsaw" });
  assert.equal(card.status, 200, card.text);
  assert.deepEqual(card.body.preview.lines.slice(0, 2), ["Looking for: cafe", "Near: Warsaw"]);
  assert.match(card.body.preview.lines[2], /Doddy pays about \$0\.0002 per search/);
  assert.deepEqual(rig.webSearch!.queries, [], "asking runs nothing");
  const done = await runRaw(rig, "find_places", { query: "cafe", near: "Warsaw" }, { approvalId: card.body.approvalId });
  assert.equal(done.status, 200, done.text);
  assert.match(done.body.text, /"Demo Café", rated 4\.6 \(212 reviews\)/);
  assert.deepEqual(rig.webSearch!.queries, ["find_places:cafe"]);
  assert.equal((await runRaw(rig, "find_places", { query: "cafe", near: "Krakow" }, { approvalId: card.body.approvalId })).status, 403);
  assert.equal((await prepare(rig, "find_places", { query: "cafe", near: "Warsaw", provider: "x", endpoint: "/v1/run" })).status, 400);
});

test("news: on by default (ADR-562); the user's off is refused; on, the articles come with their sites and dates", async () => {
  rig = await start();
  await rig.call("PUT", "/v1/tools/switch", { body: { tool: "news_search", enabled: false } });
  assert.equal((await prepare(rig, "news_search", { query: "tram" })).status, 403);
  await on(rig, "news_search");
  const card = await prepare(rig, "news_search", { query: "tram", recent: "day" });
  assert.match(card.body.preview.lines[0], /^News about: tram \(last day\)$/);
  const done = await runRaw(rig, "news_search", { query: "tram", recent: "day" }, { approvalId: card.body.approvalId });
  assert.equal(done.status, 200, done.text);
  assert.match(done.body.text, /"Demo: city opens new tram line" \(news\.demo\.example, 2026-10-17\)/);
});

test("answers Doddy can't read are errors, never invented places or news", () => {
  assert.throws(() => normalizeMonidTool("news_search", { results: 5 }, { query: "q" }), (e: unknown) => e instanceof ProviderError);
  assert.throws(() => normalizeMonidTool("find_places", "nope", { query: "q", near: "x" }), (e: unknown) => e instanceof ProviderError);
  assert.equal(normalizeMonidTool("find_places", {}, { query: "q", near: "x" }).count, 0);
  const odd = normalizeMonidTool("find_places", { local_results: [{ title: "A", rating: 99 }, { rating: 5 }] }, { query: "q", near: "x" });
  assert.equal(odd.count, 1);
  assert.doesNotMatch(odd.text, /rated 99/);
});
