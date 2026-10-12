import assert from "node:assert/strict";
import { test } from "node:test";
import { checkSellerUrl, guardedLookup, HttpFailure, isPublicIp, PublicHttps, UrlRefused } from "../src/payments/net.js";

const refusal = (url: string, allowed: string[] = []) => {
  try {
    checkSellerUrl(url, allowed);
    return "ok";
  } catch (error) {
    return error instanceof UrlRefused ? error.reason : "other";
  }
};

test("only plain public https pages are accepted, and the fragment is dropped", () => {
  assert.equal(checkSellerUrl("https://Shop.Example/a/b?x=1#frag"), "https://shop.example/a/b?x=1");
  assert.equal(checkSellerUrl("https://shop.example:443/x"), "https://shop.example/x");
  assert.equal(refusal("not a url"), "not_a_url");
  assert.equal(refusal("http://shop.example/"), "not_https");
  assert.equal(refusal("ftp://shop.example/"), "not_https");
  assert.equal(refusal("file:///etc/passwd"), "not_https");
  assert.equal(refusal("https://user:pw@shop.example/"), "credentials");
  assert.equal(refusal("https://shop.example:8443/"), "port");
  assert.equal(refusal(`https://shop.example/${"a".repeat(2100)}`), "too_long");
});

test("address literals and internal names are refused in every spelling", () => {
  for (const url of [
    "https://127.0.0.1/", "https://10.0.0.5/", "https://169.254.169.254/latest/meta-data", "https://[::1]/", "https://[fd00::1]/",
    "https://2130706433/", "https://0x7f000001/", "https://0177.0.0.1/", "https://8.8.8.8/",
  ]) {
    assert.equal(refusal(url), "address_literal", url);
  }
  for (const url of ["https://localhost/", "https://intranet/", "https://printer.local/", "https://db.internal/", "https://nas.lan/", "https://x.home.arpa/", "https://localhost./"]) {
    assert.equal(refusal(url), "internal_name", url);
  }
});

test("an allow-list limits payments to named sites and their subdomains", () => {
  assert.equal(refusal("https://shop.example/", ["shop.example"]), "ok");
  assert.equal(refusal("https://api.shop.example/", ["shop.example"]), "ok");
  assert.equal(refusal("https://evilshop.example/", ["shop.example"]), "host_not_allowed");
  assert.equal(refusal("https://shop.example.evil.test/", ["shop.example"]), "host_not_allowed");
});

test("public and private addresses are told apart, including IPv6 and mapped forms", () => {
  for (const ip of ["8.8.8.8", "1.1.1.1", "93.184.216.34", "2606:4700:4700::1111", "2001:4860:4860::8888"]) assert.equal(isPublicIp(ip), true, ip);
  for (const ip of [
    "0.0.0.0", "10.1.2.3", "100.64.0.1", "127.0.0.1", "169.254.169.254", "172.16.0.1", "172.31.255.255", "192.168.1.1", "192.0.2.1",
    "198.18.0.1", "198.51.100.7", "203.0.113.9", "224.0.0.1", "240.0.0.1", "255.255.255.255",
    "::", "::1", "fe80::1", "fc00::1", "fd12:3456::1", "ff02::1", "2001:db8::1", "2002:7f00:1::", "2001:0:4136:e378::1", "64:ff9b::7f00:1",
    "::ffff:127.0.0.1", "::ffff:10.0.0.1", "::ffff:7f00:1", "not an ip", "",
  ]) {
    assert.equal(isPublicIp(ip), false, ip);
  }
  // 172.15 and 172.32 sit just outside the private /12.
  assert.equal(isPublicIp("172.15.0.1"), true);
  assert.equal(isPublicIp("172.32.0.1"), true);
  assert.equal(isPublicIp("::ffff:8.8.8.8"), true);
});

test("the socket's own DNS lookup refuses a name that resolves to a private address", async () => {
  // "localhost" resolves offline, to loopback: the connection must be refused before any socket opens.
  const outcome = await new Promise<{ error: NodeJS.ErrnoException | null }>((resolve) =>
    guardedLookup("localhost", { all: true }, (error) => resolve({ error })),
  );
  assert.equal(outcome.error?.code, "EBLOCKED");
});

test("the real client refuses a blocked address without opening a connection", async () => {
  const http = new PublicHttps();
  for (const url of ["https://127.0.0.1/", "https://localhost/", "http://shop.example/", "https://[::1]/"]) {
    await assert.rejects(http.get(url, { signal: AbortSignal.timeout(2_000) }), (error: unknown) => error instanceof HttpFailure && error.kind === "blocked_address", url);
  }
});
