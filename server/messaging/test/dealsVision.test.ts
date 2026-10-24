// The page reader: image checks, what the code keeps of the model's read (a price only when the code can parse
// it), and the real Claude client against a local stand-in for the API. Nothing here calls Anthropic.
import assert from "node:assert/strict";
import http from "node:http";
import { describe, test } from "node:test";
import {
  AnthropicDealsModel, inspectImage, parsePrice, parseReadDate, prepareImage, readPage, readProducts, visualTokens,
} from "../src/deals/vision.js";
import { fakeJpeg, fakePng, FakeModel, read } from "./dealsFakes.js";

describe("images", () => {
  test("type from the bytes, size from the header (PNG, JPEG, WebP, GIF)", () => {
    assert.deepEqual(inspectImage(fakePng(1146, 1800, "x")), { mediaType: "image/png", width: 1146, height: 1800 });
    assert.deepEqual(inspectImage(fakeJpeg(1786, 2467, "x")), { mediaType: "image/jpeg", width: 1786, height: 2467 });
    const webp = Buffer.alloc(30);
    webp.write("RIFF", 0, "latin1"); webp.write("WEBP", 8, "latin1"); webp.write("VP8X", 12, "latin1");
    webp.writeUIntLE(1419, 24, 3); webp.writeUIntLE(2399, 27, 3);
    assert.deepEqual(inspectImage(webp), { mediaType: "image/webp", width: 1420, height: 2400 });
    const gif = Buffer.concat([Buffer.from("GIF89a", "latin1"), Buffer.from([0x10, 0x00, 0x20, 0x00]), Buffer.alloc(20)]);
    assert.deepEqual(inspectImage(gif), { mediaType: "image/gif", width: 16, height: 32 });
    assert.equal(inspectImage(Buffer.from("<html>not an image</html>")), undefined);
  });

  test("visual tokens per Claude's high-resolution tier (2,576 px, 4,784 tokens), the API's own downscaling", () => {
    assert.equal(visualTokens(1146, 1800), 41 * 65, "a Biedronka page: not resized");
    assert.equal(visualTokens(1420, 2400), 51 * 86, "a Lidl zoom page: not resized");
    assert.ok(visualTokens(1786, 2467) <= 4784, "a Dino page: downscaled by the API");
    assert.ok(visualTokens(3840, 2160) <= 4784 && visualTokens(3840, 2160) > 4600);
  });

  test("an image the API would refuse isn't sent", () => {
    assert.deepEqual(prepareImage(fakePng(9000, 100, "x")), { error: "too_large" });
    assert.deepEqual(prepareImage(Buffer.from("nope, not an image at all")), { error: "not_an_image" });
    assert.equal((prepareImage(fakePng(1146, 1800, "x")) as { mediaType: string }).mediaType, "image/png");
  });
});

describe("what the code keeps of a read", () => {
  test("prices: only plain printed amounts; anything else is not a price", () => {
    assert.deepEqual(parsePrice("4,99"), { minor: 499, currency: "PLN" });
    assert.deepEqual(parsePrice("3.79 zł"), { minor: 379, currency: "PLN" });
    assert.deepEqual(parsePrice("5"), { minor: 500, currency: "PLN" });
    for (const bad of ["4,9", "ok. 5 zł", "12,99-15,99", "", "0,00", "abc", "4,99 / szt", null]) assert.equal(parsePrice(bad), undefined, String(bad));
    assert.deepEqual(parseReadDate("23.10"), { day: 23, month: 10 });
    assert.deepEqual(parseReadDate("23.10.26"), { day: 23, month: 10, year: 2026 });
    assert.equal(parseReadDate("32.10"), undefined);
  });

  test("a product whose price can't be parsed is dropped; conditions become kinds the code words; doubts are kept", () => {
    const products = readProducts({ products: [
      read({ name: "Masło Extra 82%", size: "200 g", price: "4,99", regularPrice: "6,49", conditions: [
        { kind: "app", quantity: null, text: null }, { kind: "limit", quantity: 4, text: null }, { kind: "min_quantity", quantity: 0, text: null },
        { kind: "multi_buy", quantity: null, text: " 2 + 1 " }, { kind: "other", quantity: null, text: "druga sztuka za 1 zł" },
        { kind: "other", quantity: null, text: "tylko w sobotę" }, { kind: "app", quantity: null, text: null },
      ] }),
      read({ name: "Masło Roślinne", price: "ok. 5 zł" }),
      read({ name: "   ", price: "3,99" }),
      read({ name: "Masło Łaciate", price: "6,99", regularPrice: "chyba 8", confidence: "high" }),
      read({ name: "Masło Mlekovita", price: "5,49", confidence: "low" }),
    ] });
    assert.deepEqual(products.map((p) => p.name), ["Masło Extra 82%", "Masło Łaciate", "Masło Mlekovita"]);
    const [extra, laciate, mlekovita] = products;
    assert.deepEqual(extra!.price, { minor: 499, currency: "PLN" });
    assert.deepEqual(extra!.regularPrice, { minor: 649, currency: "PLN" });
    assert.equal(extra!.sizeText, "200 g");
    assert.deepEqual(extra!.conditions, [
      { kind: "app" }, { kind: "limit", quantity: 4 }, { kind: "multi_buy", text: "2+1" }, { kind: "other", text: "tylko w sobotę" },
    ], "a zero quantity, a money amount in free text and a repeat are dropped; at most four");
    assert.equal(extra!.lowConfidence, false);
    assert.equal(laciate!.regularPrice, undefined);
    assert.equal(laciate!.lowConfidence, true, "a printed figure the code couldn't parse");
    assert.equal(mlekovita!.lowConfidence, true);
  });

  test("readPage passes the chain and the items, and returns the model's refusal as it is", async () => {
    const model = new FakeModel().page("p1", { products: [read({ name: "Masło", price: "4,99" })] }).page("p2", "refuse");
    const image = prepareImage(fakePng(1146, 1800, "p1"));
    assert.ok(!("error" in image));
    const r = await readPage(model, image, { chain: "biedronka", queries: ["masło"], signal: new AbortController().signal });
    assert.equal(r.kind, "ok");
    assert.deepEqual(r.kind === "ok" && r.products.map((p) => [p.name, p.price.minor]), [["Masło", 499]]);
    assert.deepEqual(model.reads[0]!.queries, ["masło"]);
    assert.equal(model.reads[0]!.chain, "biedronka");
    const refused = await readPage(model, prepareImage(fakePng(10, 10, "p2")) as never, { chain: "lidl", queries: ["x"], signal: new AbortController().signal });
    assert.equal(refused.kind, "refused");
  });
});

describe("AnthropicDealsModel against a local stand-in for the API", () => {
  async function standIn(reply: () => object) {
    const seen: { path?: string; headers: http.IncomingHttpHeaders; body: Record<string, unknown> }[] = [];
    const server = http.createServer((req, res) => {
      let raw = "";
      req.on("data", (c) => { raw += c; });
      req.on("end", () => {
        seen.push({ path: req.url, headers: req.headers, body: JSON.parse(raw) });
        res.writeHead(200, { "content-type": "application/json" }).end(JSON.stringify(reply()));
      });
    });
    await new Promise<void>((r) => server.listen(0, "127.0.0.1", r));
    return { seen, baseURL: `http://127.0.0.1:${(server.address() as { port: number }).port}`, close: () => server.close() };
  }
  const message = (text: string, stop = "end_turn") => ({
    id: "msg_1", type: "message", role: "assistant", model: "claude-haiku-5-5", stop_reason: stop, stop_sequence: null,
    content: text ? [{ type: "text", text }] : [], usage: { input_tokens: 2665, output_tokens: 140 },
  });

  test("one base64 image, the items as data, structured output, Haiku at low effort, no tools", async () => {
    const out = { products: [read({ name: "Masło Extra 82%", price: "4,99" })] };
    const api = await standIn(() => message(JSON.stringify(out)));
    try {
      const model = new AnthropicDealsModel("test-key", { baseURL: api.baseURL });
      const img = prepareImage(fakePng(1146, 1800, "page"));
      assert.ok(!("error" in img));
      const r = await model.readPage({ image: img, chain: "biedronka", queries: ["masło"] }, new AbortController().signal);
      assert.deepEqual(r, { kind: "ok", output: out, usage: { inputTokens: 2665, outputTokens: 140 } });
      const sent = api.seen[0]!;
      assert.equal(sent.path, "/v1/messages?beta=true");
      assert.equal(sent.body.model, "claude-haiku-5-5");
      assert.deepEqual((sent.body.output_config as { effort: string }).effort, "low");
      assert.equal((sent.body.output_config as { format: { type: string } }).format.type, "json_schema");
      assert.equal(sent.body.tools, undefined);
      for (const banned of ["temperature", "top_p", "top_k", "thinking"]) assert.equal(sent.body[banned], undefined, banned);
      const content = (sent.body.messages as { content: { type: string; source?: { type: string; media_type: string; data: string }; text?: string }[] }[])[0]!.content;
      assert.equal(content[0]!.type, "image");
      assert.equal(content[0]!.source!.type, "base64");
      assert.equal(content[0]!.source!.media_type, "image/png");
      assert.equal(Buffer.from(content[0]!.source!.data, "base64").equals(img.data), true);
      assert.deepEqual(JSON.parse(content[1]!.text!), { chain: "Biedronka", items: ["masło"] });
      assert.match(sent.body.system as string, /Never guess/);
    } finally {
      api.close();
    }
  });

  test("a refusal and a reply that isn't the schema are not reads", async () => {
    let next = message("", "refusal");
    const api = await standIn(() => next);
    try {
      const model = new AnthropicDealsModel("test-key", { baseURL: api.baseURL, model: "claude-haiku-5-5" });
      const img = prepareImage(fakePng(100, 100, "p")) as never;
      assert.equal((await model.readPage({ image: img, chain: "lidl", queries: ["x"] }, new AbortController().signal)).kind, "refused");
      next = message("this is not json");
      assert.equal((await model.readPage({ image: img, chain: "lidl", queries: ["x"] }, new AbortController().signal)).kind, "unparsed");
      next = message(JSON.stringify({ matches: [{ item: 0, ids: ["c1"] }] }));
      const pick = await model.pick({ queries: ["masło"], candidates: [[{ id: "c1", chain: "Dino", name: "Masło" }]] }, new AbortController().signal);
      assert.deepEqual(pick.kind === "ok" && pick.output, { matches: [{ item: 0, ids: ["c1"] }] });
      const sent = api.seen.at(-1)!.body;
      assert.deepEqual(JSON.parse((sent.messages as { content: { text: string }[] }[])[0]!.content[0]!.text), {
        items: [{ item: 0, words: "masło", candidates: [{ id: "c1", chain: "Dino", name: "Masło" }] }],
      });
    } finally {
      api.close();
    }
  });
});
