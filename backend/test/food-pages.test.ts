import assert from "node:assert/strict";
import { test } from "node:test";
import { FOOD_PLATFORMS, foodPage, listingFoodPage } from "../src/tools/foodPages.js";
import { normalizeWebSearch } from "../src/tools/websearch.js";

/** Order pages Doddy may offer to open (decision 2026-11-12-food-restaurant-pages). Pure functions; nothing is fetched. */

test("a restaurant's https page on each delivery app counts, subdomains included, without query or fragment", () => {
  assert.deepEqual(foodPage("https://wolt.com/pl/pol/warsaw/restaurant/sushi-kushi"), { platform: "Wolt", url: "https://wolt.com/pl/pol/warsaw/restaurant/sushi-kushi" });
  assert.equal(foodPage("https://glovoapp.com/pl/pl/warszawa/stores/pizza-demo")?.platform, "Glovo");
  assert.equal(foodPage("https://www.pyszne.pl/menu/demo")?.platform, "Pyszne.pl");
  assert.equal(foodPage("https://www.ubereats.com/pl/store/demo/abc")?.platform, "Uber Eats");
  assert.equal(foodPage("https://food.bolt.eu/pl-pl/1-warsaw/p/demo")?.platform, "Bolt Food");
  assert.equal(foodPage("https://WOLT.com/pl/x")?.platform, "Wolt", "host case doesn't matter");
  assert.equal(foodPage("https://wolt.com/pl/x?utm_source=a&session=b#top")?.url, "https://wolt.com/pl/x", "query and fragment are dropped");
  assert.deepEqual(FOOD_PLATFORMS.map((p) => p.name), ["Uber Eats", "Wolt", "Glovo", "Bolt Food", "Pyszne.pl"]);
});

test("nothing else passes for an order page, and a front page is not a restaurant", () => {
  for (const link of [
    "http://wolt.com/pl/x", // not https
    "https://wolt.com.evil.example/x", // lookalike host
    "https://notwolt.com/x", // a different registrable name
    "https://wolt.com@evil.example/x", // credentials trick
    "https://user:pw@wolt.com/x", // credentials
    "https://wolt.com:8443/x", // a port
    "https://bolt.eu/pl-pl/food/", // not Bolt Food's own host
    "https://wolt.com", // front page
    "https://wolt.com/", // front page
    "javascript:alert(1)",
    "wolt.com/x", // not a URL
    `https://wolt.com/${"a".repeat(300)}`, // too long
    42,
    undefined,
  ]) assert.equal(foodPage(link), null, String(link));
});

test("a listing's order link is read from the known fields only", () => {
  assert.equal(listingFoodPage({ order_online: "https://wolt.com/pl/x" })?.platform, "Wolt");
  assert.equal(listingFoodPage({ links: { website: "https://own.example", delivery: "https://glovoapp.com/pl/s/x" } })?.platform, "Glovo");
  assert.equal(listingFoodPage({ website: "https://own.example" }), null);
  assert.equal(listingFoodPage({ links: ["https://wolt.com/pl/x"] }), null);
  assert.equal(listingFoodPage({ description: "order at https://wolt.com/pl/x" }), null, "free text never counts");
});

test("web results on a delivery app carry the page and the note; others don't", () => {
  const out = normalizeWebSearch({ results: [
    { title: "Sushi Kushi – Wolt", link: "https://wolt.com/pl/pol/warsaw/restaurant/sushi-kushi?ref=x", snippet: "Zamów online" },
    { title: "Blog", link: "https://blog.example/sushi" },
  ] }, "sushi kushi wolt");
  assert.match(out.text, /- "Sushi Kushi – Wolt" \(wolt\.com\): "Zamów online", order page \(Wolt\): https:\/\/wolt\.com\/pl\/pol\/warsaw\/restaurant\/sushi-kushi\n/);
  assert.match(out.text, /- "Blog" \(blog\.example\)\n/);
  assert.match(out.text, /Doddy has ordered nothing/);
  assert.doesNotMatch(normalizeWebSearch({ results: [{ title: "Blog", link: "https://blog.example" }] }, "q").text, /order page/);
});

test("the platforms are exactly the apps open_food_app can name (voice-agent/tools.json)", async () => {
  const { readFile } = await import("node:fs/promises");
  const spec = JSON.parse(await readFile(new URL("../../../voice-agent/tools.json", import.meta.url), "utf8")) as {
    tools: { name: string; parameters: { properties: { app: { enum: string[] }; page: { type: string } } } }[];
  };
  const tool = spec.tools.find((t) => t.name === "open_food_app");
  assert.ok(tool, "open_food_app is in tools.json");
  assert.deepEqual([...tool.parameters.properties.app.enum].sort(), FOOD_PLATFORMS.map((p) => p.name).sort());
  assert.equal(tool.parameters.properties.page.type, "string");
});
