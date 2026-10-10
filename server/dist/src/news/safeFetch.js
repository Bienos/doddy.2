import { lookup as dnsLookup } from "node:dns";
import http from "node:http";
import https from "node:https";
import { BlockList, isIP } from "node:net";
// Fetches user-supplied URLs (custom feeds) without letting them reach this server's own
// network: every address a hostname resolves to is checked at connect time (so DNS rebinding
// can't swap in a private address), redirects are followed manually and re-checked, and size
// and time are capped.
const blocked = new BlockList();
for (const [net, bits] of [
    ["0.0.0.0", 8], ["10.0.0.0", 8], ["100.64.0.0", 10], ["127.0.0.0", 8], ["169.254.0.0", 16],
    ["172.16.0.0", 12], ["192.0.0.0", 24], ["192.0.2.0", 24], ["192.168.0.0", 16], ["198.18.0.0", 15],
    ["198.51.100.0", 24], ["203.0.113.0", 24], ["224.0.0.0", 4], ["240.0.0.0", 4],
])
    blocked.addSubnet(net, bits, "ipv4");
for (const [net, bits] of [
    // IPv4-mapped addresses (::ffff:a.b.c.d) are unwrapped and checked as IPv4 below; a
    // ::ffff:0:0/96 rule here would make BlockList treat every IPv4 address as blocked.
    ["::", 128], ["::1", 128], ["64:ff9b::", 96], ["100::", 64], ["2001:db8::", 32],
    ["fc00::", 7], ["fe80::", 10], ["ff00::", 8],
])
    blocked.addSubnet(net, bits, "ipv6");
export function isPublicAddress(address) {
    const mapped = /^::ffff:(\d+\.\d+\.\d+\.\d+)$/i.exec(address);
    if (mapped)
        return isPublicAddress(mapped[1]);
    if (/^::ffff:/i.test(address))
        return false;
    const family = isIP(address);
    if (family === 0)
        return false;
    return !blocked.check(address, family === 4 ? "ipv4" : "ipv6");
}
export class UnsafeUrlError extends Error {
}
/** Only http(s) on default ports, no credentials, no bare IPs in private ranges. */
export function checkUrl(raw) {
    let url;
    try {
        url = new URL(raw);
    }
    catch {
        throw new UnsafeUrlError("not a URL");
    }
    if (url.protocol !== "https:" && url.protocol !== "http:")
        throw new UnsafeUrlError("scheme");
    if (url.username || url.password)
        throw new UnsafeUrlError("credentials");
    if (url.port && url.port !== "80" && url.port !== "443")
        throw new UnsafeUrlError("port");
    const host = url.hostname.replace(/^\[|\]$/g, "");
    if (isIP(host) && !isPublicAddress(host))
        throw new UnsafeUrlError("private address");
    if (host === "localhost" || host.endsWith(".localhost") || host.endsWith(".internal") || !host.includes(".") && !isIP(host)) {
        throw new UnsafeUrlError("local host");
    }
    return url;
}
const safeLookup = (hostname, options, callback) => {
    dnsLookup(hostname, { ...options, all: true }, (err, addresses) => {
        if (err)
            return callback(err, "", 0);
        const list = addresses;
        if (list.length === 0 || list.some((a) => !isPublicAddress(a.address))) {
            return callback(new UnsafeUrlError("resolves to a private address"), "", 0);
        }
        if (options.all)
            return callback(null, list);
        callback(null, list[0].address, list[0].family);
    });
};
export async function safeFetchText(raw, opts = {}) {
    const { timeoutMs = 10_000, maxBytes = 2 * 1024 * 1024, maxRedirects = 3 } = opts;
    let url = checkUrl(raw);
    for (let hop = 0;; hop++) {
        const res = await requestOnce(url, timeoutMs, maxBytes, opts.userAgent);
        if (res.status >= 300 && res.status < 400 && res.location) {
            if (hop >= maxRedirects)
                throw new UnsafeUrlError("too many redirects");
            url = checkUrl(new URL(res.location, url).toString());
            continue;
        }
        return { status: res.status, text: res.text, finalUrl: url.toString() };
    }
}
function requestOnce(url, timeoutMs, maxBytes, userAgent) {
    return new Promise((resolve, reject) => {
        const lib = url.protocol === "https:" ? https : http;
        const req = lib.get(url, {
            lookup: safeLookup,
            timeout: timeoutMs,
            headers: {
                "user-agent": userAgent ?? "Mozilla/5.0 (compatible; DoddyNewsBot/0.1)",
                accept: "application/rss+xml, application/atom+xml, application/xml;q=0.9, text/xml;q=0.9, */*;q=0.5",
            },
        }, (res) => {
            const status = res.statusCode ?? 0;
            if (status >= 300 && status < 400) {
                res.resume();
                return resolve({ status, text: "", location: res.headers.location });
            }
            let size = 0;
            const chunks = [];
            res.on("data", (c) => {
                size += c.length;
                if (size > maxBytes) {
                    req.destroy(new UnsafeUrlError("too large"));
                    return;
                }
                chunks.push(c);
            });
            res.on("end", () => resolve({ status, text: Buffer.concat(chunks).toString("utf8") }));
            res.on("error", reject);
        });
        req.on("timeout", () => req.destroy(new Error("timeout")));
        req.on("error", reject);
    });
}
//# sourceMappingURL=safeFetch.js.map