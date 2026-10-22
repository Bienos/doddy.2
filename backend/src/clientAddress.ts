import type { IncomingMessage } from "node:http";

/**
 * Who a per-client limit counts against (web sign-in, ADR-579; guest iPhones, ADR-581).
 * `trustProxy`: behind exactly one proxy that appends the client to X-Forwarded-For (Render), so
 * its last entry is the one address nobody but the proxy wrote. Otherwise the socket's address.
 */
export function clientAddress(req: IncomingMessage, trustProxy: boolean): string {
  if (trustProxy) {
    const raw = req.headers["x-forwarded-for"];
    const forwarded = Array.isArray(raw) ? raw.join(",") : raw;
    const last = forwarded?.split(",").map((part) => part.trim()).filter(Boolean).at(-1);
    if (last) return last;
  }
  return req.socket.remoteAddress ?? "unknown";
}

/**
 * The address a limit counts against: an IPv4 address as it is, an IPv6 address by its /64 (one
 * home or phone network usually has a whole /64, so counting single addresses would let one device
 * rotate through them). An IPv4-mapped IPv6 address counts as its IPv4 address.
 */
export function clientKey(address: string): string {
  const mapped = /^::ffff:(\d{1,3}(?:\.\d{1,3}){3})$/i.exec(address);
  if (mapped) return mapped[1]!;
  if (!address.includes(":")) return address;
  const [head = "", tail = ""] = address.split("%")[0]!.toLowerCase().split("::");
  const left = head === "" ? [] : head.split(":");
  const right = address.includes("::") ? (tail === "" ? [] : tail.split(":")) : [];
  const groups = address.includes("::") ? [...left, ...Array(Math.max(0, 8 - left.length - right.length)).fill("0"), ...right] : left;
  return `${groups.slice(0, 4).map((g) => g.replace(/^0+(?=.)/, "")).join(":")}::/64`;
}

