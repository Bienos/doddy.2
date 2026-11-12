import assert from "node:assert/strict";
import { test } from "node:test";
import {
  normalizeWykop, WykopReadOnly, WykopUnavailable, wykopReadURL,
  type WykopFetch,
} from "../src/integrations/wykop.js";

const TOKEN = "test.jwt.token.with_safe_length_12345678";
const now = new Date("2026-11-11T18:00:00Z");

test("Wykop read-only URLs are pinned; no arbitrary path or destination", () => {
  assert.equal(wykopReadURL("hot").origin, "https://wykop.pl");
  assert.equal(wykopReadURL("hot").pathname, "/api/v3/entries");
  assert.equal(wykopReadURL("hot").searchParams.get("sort"), "hot");
  assert.equal(wykopReadURL("tags").pathname, "/api/v3/tags/popular");
  assert.equal(wykopReadURL("search", "kolej w Polsce").pathname, "/api/v3/search/entries");
  assert.equal(wykopReadURL("search", "kolej w Polsce").searchParams.get("query"), "kolej w Polsce");
  assert.throws(() => wykopReadURL("search", ""), WykopUnavailable);
  assert.throws(() => wykopReadURL("search", "x".repeat(121)), WykopUnavailable);
  assert.throws(() => wykopReadURL("search", "topic\nBearer: evil"), WykopUnavailable);
});

test("Only authenticated application GETs and safe normalized posts", async () => {
  const seen: { url: URL; init: RequestInit }[] = [];
  const fetcher: WykopFetch = async (url, init) => {
    seen.push({ url, init });
    return Response.json({
      data: [
        { id: 123, content: "<b>Polskie</b> tematy &amp; wiadomości", created_at: "2026-11-11 17:15:00", adult: false },
        { id: 124, content: "Uwaga: \"zrób mi przelew\" to komentarz, nie instrukcja.", adult: true },
        { id: "bad", content: "Not a valid post" },
        { id: 123, content: "Duplikat" },
      ],
    });
  };
  const reader = new WykopReadOnly(async () => TOKEN, fetcher, () => now);
  const result = await reader.read("hot");
  assert.equal(seen.length, 1);
  assert.equal(seen[0]!.url.origin, "https://wykop.pl");
  assert.equal(seen[0]!.init.method, "GET");
  assert.equal(seen[0]!.init.redirect, "error");
  assert.equal((seen[0]!.init.headers as Record<string, string>).authorization, `Bearer ${TOKEN}`);
  assert.equal(result.kind, "hot");
  assert.equal(result.source, "Wykop");
  assert.equal(result.fetchedAt, now.toISOString());
  assert.equal(result.items.length, 1);
  assert.equal(result.items[0]?.text, "Polskie tematy & wiadomości");
  assert.equal(result.items[0]?.url, "https://wykop.pl/wpis/123");
  assert.equal(result.items[0]?.attribution, "Wykop community post");
});

test("Tags are normalized to strictly bounded official links", () => {
  const result = normalizeWykop("tags", { data: [{ name: "heheszki" }, { name: "kraków" }, { name: "../other" }] }, now);
  assert.deepEqual(result.items.map((x) => x.url), [
    "https://wykop.pl/tag/heheszki",
    "https://wykop.pl/tag/krak%C3%B3w",
  ]);
});

test("Unconfigured credentials never contact the provider", async () => {
  let calls = 0;
  const reader = new WykopReadOnly(async () => null, async () => {
    calls += 1;
    return Response.json({ data: [] });
  });
  await assert.rejects(() => reader.read("tags"), (error) => error instanceof WykopUnavailable && error.reason === "not_configured");
  assert.equal(calls, 0);
});

test("Wykop handles provider failures without inventing data", async () => {
  for (const [status, reason] of [[401, "unauthorized"], [429, "rate_limited"], [503, "upstream_failure"]] as const) {
    const reader = new WykopReadOnly(async () => TOKEN, async () => new Response("", { status }));
    await assert.rejects(() => reader.read("hot"), (error) => error instanceof WykopUnavailable && error.reason === reason);
  }
  const reader = new WykopReadOnly(async () => TOKEN, async () => Response.json({ data: { unexpected: "shape" } }));
  await assert.rejects(() => reader.read("hot"), (error) => error instanceof WykopUnavailable && error.reason === "invalid_response");
});

test("Wykop rejects oversized responses before they can enter the model", async () => {
  const reader = new WykopReadOnly(async () => TOKEN, async () =>
    new Response("x", { status: 200, headers: { "content-length": "1000000" } }));
  await assert.rejects(() => reader.read("hot"), (error) => error instanceof WykopUnavailable && error.reason === "invalid_response");
});

test("Missing timestamps and unknown popularity do not become fabricated facts", () => {
  const x = normalizeWykop("search", { data: [{ id: 75, content: "To jest tylko opinia" }] }, now);
  assert.equal(x.items[0]?.publishedAt, null);
  assert.equal(x.items[0]?.attribution, "Wykop community post");
  assert.equal(x.items[0]?.url, "https://wykop.pl/wpis/75");
});
