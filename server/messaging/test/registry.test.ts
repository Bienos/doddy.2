// Company registers (ADR-683): the CEIDG client against a fake CEIDG, and GET /v1/registry/ceidg against real
// Postgres. CEIDG's answer below is the official integrator documentation's example (API v3, v1.0). Nothing
// here reaches CEIDG.
import assert from "node:assert/strict";
import { after, before, describe, test } from "node:test";
import type { Db } from "../src/db.js";
import { CEIDG_DEFAULT_BASE, CeidgClient, isValidNip, trimEntries } from "../src/registry/ceidg.js";
import { dbSkip, freshDb, testApp } from "./helpers.js";

const DOC_EXAMPLE = {
  firma: [{
    id: "31F87519-9395-4FCF-8E19-6D5C0522FA7A", nazwa: "Adam IntegracjaMGMF - Zmiana",
    adresDzialalnosci: { ulica: "ul. Zwierzyniecka", budynek: "1", miasto: "Białystok", wojewodztwo: "PODLASKIE", kraj: "PL", kod: "15-333", terc: "2061011" },
    adresKorespondencyjny: { ulica: "ul. Zwierzyniecka", budynek: "1", miasto: "Białystok", kod: "15-333" },
    wlasciciel: { imie: "Adam", nazwisko: "IntegracjaMGMF - Zmiana", nip: "2367852376", regon: "29883786011481" },
    pkd: [{ kod: "3030Z", nazwa: "x" }], dataRozpoczecia: "2014-07-28", status: "AKTYWNY",
  }],
};

function fakeCeidg(answers: Array<{ status: number; body?: unknown }>) {
  const calls: Array<{ url: string; auth: string | null }> = [];
  const fetchFn = (async (input: string | URL | Request, init?: RequestInit) => {
    calls.push({ url: String(input), auth: new Headers(init?.headers).get("authorization") });
    const next = answers.shift() ?? { status: 500 };
    return new Response(next.body === undefined ? null : JSON.stringify(next.body), { status: next.status });
  }) as typeof fetch;
  return { calls, fetchFn };
}

describe("CEIDG client (no database)", () => {
  test("a NIP is checked by its check digit", () => {
    assert.equal(isValidNip("2367852376"), true);
    assert.equal(isValidNip("5260250995"), true);
    assert.equal(isValidNip("1234567890"), false);
    assert.equal(isValidNip("236785237"), false);
    assert.equal(isValidNip("PL2367852376"), false);
  });

  test("the documentation's entry is cut to name, status and business address", () => {
    assert.deepEqual(trimEntries(DOC_EXAMPLE, "2367852376"), [{
      nazwa: "Adam IntegracjaMGMF - Zmiana", status: "AKTYWNY", wlasciciel: { nip: "2367852376" },
      adresDzialalnosci: { ulica: "ul. Zwierzyniecka", budynek: "1", miasto: "Białystok", kod: "15-333", kraj: "PL" },
    }]);
    assert.deepEqual(trimEntries(DOC_EXAMPLE, "5260250995"), [], "another owner's entry is dropped");
    assert.equal(trimEntries({ nothing: true }, "2367852376"), undefined);
  });

  test("the token goes in the header, only the NIP in the address, and answers are told apart", async () => {
    const web = fakeCeidg([{ status: 200, body: DOC_EXAMPLE }, { status: 204 }, { status: 429 }, { status: 401 }, { status: 200, body: "<html>" }]);
    const client = new CeidgClient({ token: "t".repeat(40), baseUrl: CEIDG_DEFAULT_BASE, fetch: web.fetchFn });
    const found = await client.lookup("2367852376");
    assert.equal(found.kind, "found");
    assert.equal(web.calls[0]!.url, "https://dane.biznes.gov.pl/api/ceidg/v3/firma?nip=2367852376");
    assert.equal(web.calls[0]!.auth, `Bearer ${"t".repeat(40)}`);
    assert.deepEqual(await client.lookup("2367852376"), { kind: "not_found" });
    assert.deepEqual(await client.lookup("2367852376"), { kind: "busy" });
    assert.deepEqual(await client.lookup("2367852376"), { kind: "unavailable", status: 401 });
    assert.deepEqual(await client.lookup("2367852376"), { kind: "unavailable", status: 200 }, "a body that isn't CEIDG's");
  });

  test("the server keeps under CEIDG's pace", async () => {
    let now = 0;
    const web = fakeCeidg(Array.from({ length: 5 }, () => ({ status: 204 })));
    const client = new CeidgClient({ token: "t".repeat(40), baseUrl: CEIDG_DEFAULT_BASE, fetch: web.fetchFn, maxPerWindow: 2, now: () => now });
    assert.equal((await client.lookup("2367852376")).kind, "not_found");
    assert.equal((await client.lookup("2367852376")).kind, "not_found");
    assert.equal((await client.lookup("2367852376")).kind, "busy");
    assert.equal(web.calls.length, 2, "a third request isn't sent");
    now = 180_000;
    assert.equal((await client.lookup("2367852376")).kind, "not_found");
  });

  test("only CEIDG's own hosts are accepted", () => {
    assert.throws(() => new CeidgClient({ token: "t".repeat(40), baseUrl: "https://example.com/api" }));
    assert.throws(() => new CeidgClient({ token: "t".repeat(40), baseUrl: "http://dane.biznes.gov.pl/api/ceidg/v3" }));
    assert.doesNotThrow(() => new CeidgClient({ token: "t".repeat(40), baseUrl: "https://test-dane.biznes.gov.pl/api/ceidg/v3" }));
  });
});

describe("registry route against real Postgres", { skip: dbSkip }, () => {
  let db: Db;
  before(async () => { db = await freshDb(); });
  after(async () => { await db?.end(); });

  async function world(answers?: Array<{ status: number; body?: unknown }>) {
    const web = answers ? fakeCeidg(answers) : undefined;
    const base = await testApp(db, {
      ceidg: web ? new CeidgClient({ token: "t".repeat(40), baseUrl: CEIDG_DEFAULT_BASE, fetch: web.fetchFn }) : undefined,
    });
    const r = await base.app.inject({ method: "POST", url: "/v1/accounts" });
    const { deviceToken } = r.json() as { deviceToken: string };
    const ask = (nip: string, h: Record<string, string> = { authorization: `Bearer ${deviceToken}` }) =>
      base.app.inject({ method: "GET", url: `/v1/registry/ceidg?nip=${nip}`, headers: h });
    return { ...base, web, ask };
  }

  test("off without a token, and only for a signed-in device", async () => {
    const w = await world();
    assert.equal((await w.ask("2367852376")).statusCode, 503);
    assert.deepEqual((await w.ask("2367852376")).json(), { error: "registry_disabled" });
    const on = await world([]);
    assert.equal((await on.ask("2367852376", {})).statusCode, 401);
  });

  test("an entry, none, a bad NIP and a busy CEIDG", async () => {
    const w = await world([{ status: 200, body: DOC_EXAMPLE }, { status: 204 }, { status: 429 }]);
    const found = await w.ask("2367852376");
    assert.equal(found.statusCode, 200, found.body);
    assert.equal(found.json().firma[0].nazwa, "Adam IntegracjaMGMF - Zmiana");
    assert.equal(found.json().firma[0].adresDzialalnosci.kod, "15-333");
    assert.equal(found.json().firma[0].wlasciciel.imie, undefined, "only what an invoice needs");
    assert.equal((await w.ask("2367852376")).statusCode, 404);
    assert.equal((await w.ask("1234567890")).statusCode, 400);
    assert.equal(w.web!.calls.length, 2, "a bad NIP never reaches CEIDG");
    assert.equal((await w.ask("2367852376")).statusCode, 429);
  });
});
