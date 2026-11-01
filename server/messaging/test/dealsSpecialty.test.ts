// Which shops a leaflet search asks (ADR-667): grocery chains for everything, a specialty shop only for its kind of
// item, E.Leclerc only on request. Nothing here reaches a shop or Anthropic.
import assert from "node:assert/strict";
import { describe, test } from "node:test";
import { PoliteFetcher } from "../src/deals/fetcher.js";
import { searchDeals } from "../src/deals/service.js";
import { chainsToRead, defaultChains, fold, itemKinds } from "../src/deals/specialty.js";
import { DEFAULT_DEALS_SETTINGS, isReadChain, READ_CHAINS, type ChainAdapter, type ReadChain } from "../src/deals/types.js";
import { FakeWeb } from "./dealsFakes.js";

describe("the shops a search asks", () => {
  test("an item's kind, from Polish words in any case and with or without Polish letters", () => {
    assert.equal(fold("Żwirek dla KOTA"), "zwirek dla kota");
    assert.deepEqual([...itemKinds(["karma dla psa"])], ["pets"]);
    assert.deepEqual([...itemKinds(["żwirek"])], ["pets"]);
    assert.deepEqual([...itemKinds(["sneakersy damskie", "Kapcie"])], ["shoes"]);
    assert.deepEqual([...itemKinds(["panele podłogowe"])], ["home"]);
    assert.deepEqual([...itemKinds(["dywan 160x230", "buty zimowe", "przysmaki dla kota"])].sort(), ["home", "pets", "shoes"]);
    for (const grocery of ["masło", "kawa mielona", "karmelki", "butelka wody", "kotlet schabowy", "mleko bez laktozy"]) {
      assert.deepEqual([...itemKinds([grocery])], [], grocery);
    }
  });

  test("the default: every read chain but E.Leclerc; specialty shops only for their kind", () => {
    const defaults = defaultChains(READ_CHAINS);
    assert.ok(!defaults.includes("leclerc"));
    assert.ok(defaults.includes("delikatesy"));
    assert.deepEqual(chainsToRead(defaults, ["masło"], isReadChain), ["biedronka", "lidl", "dino", "rossmann", "aldi", "zabka", "delikatesy"]);
    assert.deepEqual(chainsToRead(defaults, ["masło", "karma dla kota"], isReadChain).filter((c) => !["biedronka", "lidl", "dino", "rossmann", "aldi", "zabka", "delikatesy"].includes(c)), ["maxizoo"]);
    assert.ok(chainsToRead(defaults, ["sneakersy"], isReadChain).includes("ccc"));
    assert.ok(chainsToRead(defaults, ["panele"], isReadChain).includes("komfort"));
  });

  test("asked by name: E.Leclerc is read; a specialty shop asked alone is read whatever the item; with others it still needs its kind", () => {
    assert.deepEqual(chainsToRead(["leclerc", "lidl"], ["masło"], isReadChain), ["leclerc", "lidl"]);
    assert.deepEqual(chainsToRead(["ccc"], ["torebka"], isReadChain), ["ccc"], "the person asked CCC on purpose");
    assert.deepEqual(chainsToRead(["ccc", "maxizoo"], ["smycz"], isReadChain), ["ccc", "maxizoo"], "only specialty shops asked: all kept");
    assert.deepEqual(chainsToRead(["biedronka", "ccc", "netto"], ["masło"], isReadChain), ["biedronka", "netto"], "the link-only row stays");
  });

  test("in a search: shops not asked get no row and no request", async () => {
    const asked: ReadChain[] = [];
    const fake = (chain: ReadChain): ChainAdapter => ({ chain, hosts: [], read: async () => { asked.push(chain); return { kind: "no_leaflet" }; } });
    const adapters = Object.fromEntries(READ_CHAINS.map((c) => [c, fake(c)])) as Record<ReadChain, ChainAdapter>;
    const { response } = await searchDeals(
      { settings: DEFAULT_DEALS_SETTINGS, fetcher: new PoliteFetcher({ fetch: new FakeWeb().fetch }), adapters, now: () => new Date("2026-10-30T08:00:00Z") },
      { items: ["masło"], language: "pl" },
    );
    assert.deepEqual(asked.sort(), ["aldi", "biedronka", "delikatesy", "dino", "lidl", "rossmann", "zabka"]);
    assert.deepEqual(response.chains.map((c) => c.chain), ["biedronka", "lidl", "dino", "rossmann", "aldi", "zabka", "delikatesy"]);
    asked.length = 0;
    await searchDeals(
      { settings: DEFAULT_DEALS_SETTINGS, fetcher: new PoliteFetcher({ fetch: new FakeWeb().fetch }), adapters, now: () => new Date("2026-10-30T08:00:00Z") },
      { items: ["karma dla psa"], language: "pl" },
    );
    assert.ok(asked.includes("maxizoo") && !asked.includes("ccc") && !asked.includes("komfort") && !asked.includes("leclerc"));
  });
});
