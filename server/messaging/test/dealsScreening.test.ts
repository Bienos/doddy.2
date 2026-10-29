// ADR-662: an image-only leaflet (Biedronka's) is screened twenty pages at a time, and only the pages the screen
// flags, with their neighbours, are read in full. Every page screened and not flagged counts as checked; a batch
// that couldn't be screened is read page by page, as before. Nothing here calls Anthropic.
import assert from "node:assert/strict";
import http from "node:http";
import { describe, test } from "node:test";
import { PoliteFetcher } from "../src/deals/fetcher.js";
import { searchDeals } from "../src/deals/service.js";
import { AnthropicDealsModel, prepareImage, readScreen, screenBatches, SCREEN_MAX_IMAGES, visualTokens } from "../src/deals/vision.js";
import { DEFAULT_DEALS_SETTINGS, type DealsResponse, type DealsSettings, type PageImage } from "../src/deals/types.js";
import { chainsWeb, fakePng, fixtureJson, read, ScreeningFakeModel, type FakeWeb } from "./dealsFakes.js";

const NOW = () => new Date("2026-10-24T06:10:00.000Z");
const butter = { products: [read({ name: "Masło Extra 82%", size: "200 g", price: "4,99" })] };

async function biedronka(model: ScreeningFakeModel, settings: Partial<DealsSettings> = {}, web: FakeWeb = chainsWeb()) {
  const { response, stats } = await searchDeals(
    { settings: { ...DEFAULT_DEALS_SETTINGS, ...settings }, fetcher: new PoliteFetcher({ fetch: web.fetch }), model, now: NOW },
    { items: ["masło"], chains: ["biedronka"], language: "pl" },
  );
  return { response, stats, web };
}

const row = (r: DealsResponse) => r.chains[0] as { status: string; leaflet?: unknown; pages?: unknown };
const images = () => fixtureJson<{ images_mobile: { page: number; image: string }[] }>("biedronka_leaflet.json").images_mobile;

describe("screen first, then read what the screen found", () => {
  test("one call screens the five pages; the flagged page and its neighbours are read; every page counts as checked", async () => {
    const model = new ScreeningFakeModel().page("biedronka:3", butter);
    const { response, stats, web } = await biedronka(model);
    assert.deepEqual(model.screens.map((s) => s.markers), [["biedronka:1", "biedronka:2", "biedronka:3", "biedronka:4", "biedronka:5"]]);
    assert.deepEqual(model.screens[0]!.queries, ["masło"]);
    assert.deepEqual(model.reads.map((r) => r.marker), ["biedronka:3", "biedronka:2", "biedronka:4"], "the flagged page first, then its neighbours");
    assert.deepEqual(response.chains, [{ chain: "biedronka", status: "checked", leaflet: row(response).leaflet }], "no `pages`: all five were looked at");
    assert.equal(response.items[0]!.offers[0]!.product, "Masło Extra 82%");
    assert.equal(stats.pagesRead, 5, "every page went to the model once");
    for (const i of images()) assert.equal(web.hits(i.image), 1, "each image is fetched once and held for the full read");
  });

  test("nothing flagged: no full read, and the leaflet was read whole, so it's 'no match'", async () => {
    const model = new ScreeningFakeModel();
    const { response } = await biedronka(model);
    assert.equal(model.reads.length, 0);
    assert.equal(response.chains[0]!.status, "no_match");
  });

  test("a screen that misses a page loses its offer: the recall the eval has to measure", async () => {
    const model = new ScreeningFakeModel().page("biedronka:3", butter);
    model.misses.add("biedronka:3");
    const { response } = await biedronka(model);
    assert.equal(model.reads.length, 0);
    assert.equal(response.chains[0]!.status, "no_match");
  });

  test("a batch that couldn't be screened is read page by page, up to the cap, and says how much was read", async () => {
    for (const step of ["refuse", "unparsed", "throw"] as const) {
      const model = new ScreeningFakeModel().page("biedronka:3", butter);
      model.screenSteps.set(0, step);
      const { response } = await biedronka(model, { maxPages: 3 });
      assert.deepEqual(model.reads.map((r) => r.marker), ["biedronka:1", "biedronka:2", "biedronka:3"], step);
      assert.equal(response.chains[0]!.status, "checked", step);
      assert.deepEqual(row(response).pages, { read: 3, of: 5 }, step);
    }
  });

  test("the screen cap: pages beyond it aren't looked at, and the row says so", async () => {
    const model = new ScreeningFakeModel().page("biedronka:2", butter);
    const { response } = await biedronka(model, { screenPages: 3 });
    assert.deepEqual(model.screens.map((s) => s.markers), [["biedronka:1", "biedronka:2", "biedronka:3"]]);
    assert.deepEqual(model.reads.map((r) => r.marker), ["biedronka:2", "biedronka:1", "biedronka:3"]);
    assert.deepEqual(row(response).pages, { read: 3, of: 5 });
  });

  test("the full-read cap holds after screening: flagged pages before neighbours, and a neighbour left out still counts as checked", async () => {
    const model = new ScreeningFakeModel().page("biedronka:2", butter).page("biedronka:4", butter);
    const { response } = await biedronka(model, { maxPages: 2 });
    assert.deepEqual(model.reads.map((r) => r.marker), ["biedronka:2", "biedronka:4"]);
    assert.equal(row(response).pages, undefined, "1, 3 and 5 were screened and not flagged");
    const nothing = new ScreeningFakeModel().page("biedronka:2", { products: [read({ name: "Ser żółty", price: "5,99" })] });
    const { response: none } = await biedronka(nothing, { maxPages: 1 });
    assert.equal(row(none).status, "no_match", "the flagged page was read; the neighbours the cap left out don't make it 'failed'");
  });

  test("screening off (0), or a model without it: every page read in order, as before", async () => {
    const off = new ScreeningFakeModel().page("biedronka:3", butter);
    await biedronka(off, { screenPages: 0 });
    assert.equal(off.screens.length, 0);
    assert.deepEqual(off.reads.map((r) => r.marker), ["biedronka:1", "biedronka:2", "biedronka:3", "biedronka:4", "biedronka:5"]);
  });

  test("Lidl's pages, chosen by their text, aren't screened", async () => {
    const model = new ScreeningFakeModel();
    const web = chainsWeb();
    await searchDeals(
      { settings: DEFAULT_DEALS_SETTINGS, fetcher: new PoliteFetcher({ fetch: web.fetch }), model, now: NOW },
      { items: ["masło"], chains: ["lidl"], language: "pl" },
    );
    assert.equal(model.screens.length, 0);
    assert.ok(model.reads.length > 0);
  });
});

describe("batches and what the code keeps of a screen", () => {
  const page = (w: number, h: number, i: number) => ({ image: prepareImage(fakePng(w, h, `p${i}`)) as PageImage, i });

  test("at most twenty images and 90,000 visual tokens a call, in order", () => {
    const small = Array.from({ length: 45 }, (_, i) => page(1146, 1800, i));
    assert.deepEqual(screenBatches(small).map((b) => b.length), [20, 20, 5]);
    assert.equal(visualTokens(4000, 6000), 4704);
    const big = Array.from({ length: 40 }, (_, i) => page(4000, 6000, i));
    assert.deepEqual(screenBatches(big).map((b) => b.length), [19, 19, 2], "19 × 4,704 = 89,376 tokens");
    assert.deepEqual(screenBatches(small).flat().map((p) => p.i), small.map((p) => p.i));
    assert.equal(SCREEN_MAX_IMAGES, 20);
  });

  test("image numbers outside the batch and item numbers outside the request are dropped", () => {
    const flagged = readScreen({ images: [
      { image: 2, items: [0, 3, 0] }, { image: 0, items: [0] }, { image: 6, items: [1] }, { image: 4, items: [] }, { image: 2, items: [1] },
    ] }, 5, 2);
    assert.deepEqual([...flagged], [[1, [0, 1]], [3, []]], "image 2 (index 1) for items 0 and 1; image 4 listed with no valid item is still flagged");
  });

  test("the real client: each image after its label, the items numbered, the system prompt cached", async () => {
    const seen: Record<string, unknown>[] = [];
    const server = http.createServer((req, res) => {
      let raw = "";
      req.on("data", (c) => { raw += c; });
      req.on("end", () => {
        seen.push(JSON.parse(raw));
        res.writeHead(200, { "content-type": "application/json" }).end(JSON.stringify({
          id: "msg_1", type: "message", role: "assistant", model: "claude-haiku-5-5", stop_reason: "end_turn", stop_sequence: null,
          content: [{ type: "text", text: JSON.stringify({ images: [{ image: 2, items: [0] }] }) }], usage: { input_tokens: 5400, output_tokens: 20 },
        }));
      });
    });
    await new Promise<void>((r) => server.listen(0, "127.0.0.1", r));
    try {
      const model = new AnthropicDealsModel("test-key", { baseURL: `http://127.0.0.1:${(server.address() as { port: number }).port}` });
      const imgs = [prepareImage(fakePng(1146, 1800, "a")), prepareImage(fakePng(1146, 1800, "b"))] as PageImage[];
      const r = await model.screenPages({ images: imgs, chain: "biedronka", queries: ["masło", "kawa"] }, new AbortController().signal);
      assert.deepEqual(r, { kind: "ok", output: { images: [{ image: 2, items: [0] }] }, usage: { inputTokens: 5400, outputTokens: 20 } });
      const body = seen[0]!;
      const content = (body.messages as { content: { type: string; text?: string }[] }[])[0]!.content;
      assert.deepEqual(content.map((c) => c.type), ["text", "image", "text", "image", "text"]);
      assert.equal(content[0]!.text, "Image 1");
      assert.equal(content[2]!.text, "Image 2");
      assert.deepEqual(JSON.parse(content[4]!.text!), { chain: "Biedronka", items: [{ item: 0, words: "masło" }, { item: 1, words: "kawa" }] });
      const system = body.system as { text: string; cache_control?: unknown }[];
      assert.match(system[0]!.text, /Don't read prices/);
      assert.deepEqual(system[0]!.cache_control, { type: "ephemeral" });
      assert.equal(body.tools, undefined);
    } finally {
      server.close();
    }
  });
});
