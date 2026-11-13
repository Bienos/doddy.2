// analytics.js: Google Analytics loads only after the visitor taps Allow; "No thanks" means it never loads.
// The file runs in a small stand-in for the browser (no jsdom here); a real browser check is in README.md.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import vm from "node:vm";

const SOURCE = readFileSync(new URL("../analytics.js", import.meta.url), "utf8");

function element(tag) {
  const listeners = {};
  const el = {
    tagName: tag.toUpperCase(), children: [], attributes: {}, hidden: false, textContent: "", className: "", focused: false,
    setAttribute(name, value) { this.attributes[name] = String(value); },
    getAttribute(name) { return this.attributes[name] ?? null; },
    appendChild(child) { this.children.push(child); child.parent = this; return child; },
    addEventListener(type, fn) { (listeners[type] ??= []).push(fn); },
    dispatch(type, event = {}) { for (const fn of listeners[type] ?? []) fn({ preventDefault() {}, ...event }); },
    querySelector(selector) { return selector === "button" ? this.all().find((c) => c.tagName === "BUTTON") ?? null : null; },
    all() { return this.children.flatMap((c) => [c, ...c.all()]); },
    focus() { this.focused = true; },
    closest(selector) {
      for (let node = this; node; node = node.parent) if (selector === "[data-consent]" && node.attributes?.["data-consent"]) return node;
      return null;
    },
  };
  return el;
}

// Loads analytics.js in a fresh page. `stored` is what localStorage holds; `cookies` what the page already has.
function visit({ stored = null, cookies = ["_ga=GA1.1.old", "_ga_MRF40685L1=x", "other=1"], storageThrows = false } = {}) {
  const jar = new Map(cookies.map((c) => c.split("=")));
  const storage = new Map(stored ? [["doddy-analytics-consent", stored]] : []);
  const note = element("p"); note.hidden = true;
  const choices = element("button");
  const head = element("head");
  const body = element("body");
  const document = {
    readyState: "complete",
    head, body,
    createElement: element,
    addEventListener() {},
    querySelectorAll(selector) { return selector === "[data-ga-note]" ? [note] : selector === "[data-analytics-choices]" ? [choices] : []; },
    get cookie() { return [...jar].map(([k, v]) => `${k}=${v}`).join("; "); },
    set cookie(value) {
      const [pair, ...attributes] = value.split(";").map((s) => s.trim());
      const [name, v] = pair.split("=");
      if (attributes.includes("Max-Age=0")) jar.delete(name); else jar.set(name, v);
    },
  };
  const localStorage = {
    getItem(key) { if (storageThrows) throw new Error("blocked"); return storage.get(key) ?? null; },
    setItem(key, value) { if (storageThrows) throw new Error("blocked"); storage.set(key, value); },
  };
  const window = { addEventListener() {}, doddyT: (text) => text };
  vm.runInNewContext(SOURCE, { window, document, localStorage, location: { hostname: "www.doddy.lol" }, Date });
  const banner = () => body.children.find((c) => c.className === "consent");
  const button = (value) => banner().all().find((c) => c.attributes["data-consent"] === value);
  return {
    window, note, choices, jar, storage, banner, button,
    scripts: () => head.children.filter((c) => c.tagName === "SCRIPT").map((s) => s.src),
    tap: (value) => banner().dispatch("click", { target: button(value) }),
  };
}

const GTAG = "https://www.googletagmanager.com/gtag/js?id=G-MRF40685L1";
// The page's gtag() calls, as plain data (they were made in the page's own realm). Dates become strings.
const gtagCalls = (page) => JSON.parse(JSON.stringify(page.window.dataLayer.map((args) => Array.from(args))));

test("a first visit shows the choice, loads nothing from Google and removes _ga cookies left from before", () => {
  const page = visit();
  assert.deepEqual(page.scripts(), []);
  assert.equal(page.window.dataLayer, undefined);
  assert.ok(page.banner() && !page.banner().hidden);
  assert.equal(page.banner().getAttribute("aria-label"), "Analytics choice");
  assert.deepEqual(page.banner().all().filter((c) => c.tagName === "BUTTON").map((b) => b.textContent), ["Allow", "No thanks"]);
  assert.equal(page.button("granted").focused, false, "the banner doesn't take focus on its own");
  assert.deepEqual([...page.jar.keys()], ["other"]);
  assert.equal(page.note.hidden, false, "the footer sentence is shown");
});

test("No thanks: nothing loads, the choice is kept, and the next visit neither asks nor loads", () => {
  const page = visit();
  page.tap("denied");
  assert.deepEqual(page.scripts(), []);
  assert.equal(page.banner().hidden, true);
  assert.equal(page.storage.get("doddy-analytics-consent"), "denied");
  const next = visit({ stored: "denied" });
  assert.deepEqual(next.scripts(), []);
  assert.equal(next.banner(), undefined);
  assert.deepEqual([...next.jar.keys()], ["other"]);
});

test("Allow loads Google's tag once, with ads consent denied and signals off; the next visit loads it without asking", () => {
  const page = visit();
  page.tap("granted");
  page.tap("granted");
  assert.deepEqual(page.scripts(), [GTAG]);
  const calls = gtagCalls(page);
  assert.deepEqual(calls[0], ["consent", "default", { analytics_storage: "granted", ad_storage: "denied", ad_user_data: "denied", ad_personalization: "denied" }]);
  assert.deepEqual(calls[2], ["config", "G-MRF40685L1", { allow_google_signals: false, allow_ad_personalization_signals: false }]);
  assert.equal(page.storage.get("doddy-analytics-consent"), "granted");
  const next = visit({ stored: "granted", cookies: ["_ga=GA1.1.kept"] });
  assert.deepEqual(next.scripts(), [GTAG]);
  assert.equal(next.banner(), undefined);
  assert.deepEqual([...next.jar.keys()], ["_ga"], "an allowed visit keeps GA's cookies");
});

test("Analytics choices asks again with focus on Allow; changing to No thanks turns GA off and removes its cookies", () => {
  const page = visit({ stored: "granted" });
  page.choices.dispatch("click");
  assert.equal(page.banner().hidden, false);
  assert.equal(page.button("granted").focused, true);
  page.tap("denied");
  const calls = gtagCalls(page);
  assert.deepEqual(calls.at(-1), ["consent", "update", { analytics_storage: "denied" }]);
  assert.deepEqual([...page.jar.keys()], ["other"]);
  assert.equal(page.storage.get("doddy-analytics-consent"), "denied");
});

test("with storage blocked, the visitor is asked each time and nothing loads until Allow", () => {
  const page = visit({ storageThrows: true });
  assert.deepEqual(page.scripts(), []);
  assert.equal(page.banner().hidden, false);
  page.tap("granted");
  assert.deepEqual(page.scripts(), [GTAG]);
});

test("an unknown stored value counts as no choice", () => {
  const page = visit({ stored: "yes please" });
  assert.deepEqual(page.scripts(), []);
  assert.equal(page.banner().hidden, false);
});
