import assert from "node:assert/strict";
import { test } from "node:test";
import { BOOKING_PLATFORMS, bookingPage, listingBookingPage } from "../src/tools/bookingPages.js";
import { normalizeWebSearch } from "../src/tools/websearch.js";

/** Booking pages Doddy may offer (decision 2026-11-11-salon-booking-pages). Pure functions; nothing is fetched. */

test("each Polish booking platform's https pages count, subdomains included", () => {
  assert.deepEqual(bookingPage("https://booksy.com/pl-pl/1_salon_3_krakow"), { platform: "Booksy", url: "https://booksy.com/pl-pl/1_salon_3_krakow" });
  assert.equal(bookingPage("https://www.fresha.com/pl/a/x")?.platform, "Fresha");
  assert.equal(bookingPage("https://salon-demo.reservio.com/")?.platform, "Reservio");
  assert.equal(bookingPage("https://bookero.pl/salon-demo")?.platform, "Bookero");
  assert.equal(bookingPage("https://www.znanylekarz.pl/jan-demo/dentysta/warszawa")?.platform, "ZnanyLekarz");
  assert.equal(bookingPage("https://BOOKSY.com/x")?.platform, "Booksy", "host case doesn't matter");
  assert.equal(bookingPage("https://booksy.com/x#ref")?.url, "https://booksy.com/x", "the fragment is dropped");
  assert.deepEqual(BOOKING_PLATFORMS.map((p) => p.name), ["Booksy", "Fresha", "Reservio", "Bookero", "ZnanyLekarz"]);
});

test("nothing else passes for a booking page", () => {
  for (const link of [
    "http://booksy.com/x", // not https
    "https://booksy.com.evil.example/x", // lookalike host
    "https://notbooksy.com/x", // a different registrable name
    "https://user:pw@booksy.com/x", // credentials
    "https://booksy.com:8443/x", // a port
    "javascript:alert(1)",
    "booksy.com/x", // not a URL
    `https://booksy.com/${"a".repeat(300)}`, // too long
    42,
    undefined,
  ]) assert.equal(bookingPage(link), null, String(link));
});

test("a listing's booking link is read from the known fields only", () => {
  assert.equal(listingBookingPage({ book_online: "https://booksy.com/a" })?.url, "https://booksy.com/a");
  assert.equal(listingBookingPage({ links: { website: "https://own.example", book_online: "https://fresha.com/b" } })?.platform, "Fresha");
  assert.equal(listingBookingPage({ website: "https://own.example" }), null);
  assert.equal(listingBookingPage({ links: ["https://booksy.com/a"] }), null);
  assert.equal(listingBookingPage({ description: "book at https://booksy.com/a" }), null, "free text never counts");
});

test("web results on a booking platform carry the page and the note; others don't", () => {
  const out = normalizeWebSearch({ results: [
    { title: "Fryzjer Demo – Booksy", link: "https://booksy.com/pl-pl/9_fryzjer-demo_3_gdansk", snippet: "Umów wizytę" },
    { title: "Blog", link: "https://blog.example/fryzjer" },
  ] }, "fryzjer gdańsk booksy");
  assert.match(out.text, /- "Fryzjer Demo – Booksy" \(booksy\.com\): "Umów wizytę", booking page \(Booksy\): https:\/\/booksy\.com\/pl-pl\/9_fryzjer-demo_3_gdansk/);
  assert.match(out.text, /- "Blog" \(blog\.example\)\n/);
  assert.match(out.text, /Doddy has not booked anything/);
  assert.doesNotMatch(normalizeWebSearch({ results: [{ title: "Blog", link: "https://blog.example" }] }, "q").text, /booking page/);
});
