import { lookup as dnsLookup, type LookupAddress } from "node:dns";
import { request } from "node:https";
import { isIP } from "node:net";

/**
 * The only network code that talks to a seller. The URL comes from a model that may have read
 * hostile web content, so it is treated as an attack surface: https only, a real public hostname,
 * and the address the connection actually uses is checked inside the socket's own DNS lookup (so a
 * DNS answer that changes between a check and the connection cannot slip through). No redirects, no
 * cookies, a size cap, and the caller's deadline.
 */

export type UrlRefusal = "not_a_url" | "not_https" | "credentials" | "port" | "address_literal" | "internal_name" | "host_not_allowed" | "too_long";

export class UrlRefused extends Error {
  constructor(readonly reason: UrlRefusal) {
    super(reason);
    this.name = "UrlRefused";
  }
}

const INTERNAL_SUFFIXES = [".local", ".localhost", ".internal", ".lan", ".home", ".corp", ".intranet", ".home.arpa"];

/** Normalised https URL (no fragment), or a refusal. `allowedHosts` empty = any public host. */
export function checkSellerUrl(raw: string, allowedHosts: readonly string[] = []): string {
  if (raw.length > 2048) throw new UrlRefused("too_long");
  let url: URL;
  try {
    url = new URL(raw);
  } catch {
    throw new UrlRefused("not_a_url");
  }
  if (url.protocol !== "https:") throw new UrlRefused("not_https");
  if (url.username || url.password) throw new UrlRefused("credentials");
  if (url.port !== "" && url.port !== "443") throw new UrlRefused("port");
  const host = url.hostname.toLowerCase().replace(/\.$/, "");
  if (isIP(host) !== 0 || host.startsWith("[") || /^[0-9.]+$/.test(host) || /^0x[0-9a-f]+$/i.test(host)) throw new UrlRefused("address_literal");
  if (!host.includes(".") || host === "localhost" || INTERNAL_SUFFIXES.some((s) => host.endsWith(s))) throw new UrlRefused("internal_name");
  if (allowedHosts.length > 0 && !allowedHosts.some((a) => host === a || host.endsWith(`.${a}`))) throw new UrlRefused("host_not_allowed");
  url.hash = "";
  return url.href;
}

// ------------------------------------------------------------------ addresses

function ipv4Octets(ip: string): number[] | null {
  const parts = ip.split(".");
  if (parts.length !== 4) return null;
  const octets = parts.map((p) => (/^\d{1,3}$/.test(p) ? Number(p) : NaN));
  return octets.every((o) => o >= 0 && o <= 255) ? octets : null;
}

function isPublicIpv4(o: number[]): boolean {
  const [a, b, c] = o as [number, number, number, number];
  if (a === 0 || a === 10 || a === 127 || a >= 224) return false;
  if (a === 100 && b >= 64 && b <= 127) return false; // carrier-grade NAT
  if (a === 169 && b === 254) return false; // link-local, cloud metadata
  if (a === 172 && b >= 16 && b <= 31) return false;
  if (a === 192 && b === 168) return false;
  if (a === 192 && b === 0 && (c === 0 || c === 2)) return false;
  if (a === 198 && (b === 18 || b === 19)) return false;
  if ((a === 198 && b === 51 && c === 100) || (a === 203 && b === 0 && c === 113)) return false;
  return true;
}

function ipv6Bytes(input: string): number[] | null {
  let ip = input.split("%")[0]!.toLowerCase();
  let tail: number[] = [];
  const dotted = /(\d+\.\d+\.\d+\.\d+)$/.exec(ip);
  if (dotted) {
    const o = ipv4Octets(dotted[1]!);
    if (!o) return null;
    tail = [(o[0]! << 8) | o[1]!, (o[2]! << 8) | o[3]!];
    ip = ip.slice(0, -dotted[1]!.length) + "0:0";
  }
  const halves = ip.split("::");
  if (halves.length > 2) return null;
  const parse = (s: string) => (s === "" ? [] : s.split(":"));
  const head = parse(halves[0]!);
  const rest = halves.length === 2 ? parse(halves[1]!) : [];
  const missing = 8 - head.length - rest.length;
  if (halves.length === 1 ? head.length !== 8 : missing < 1) return null;
  const groups = [...head, ...Array<string>(halves.length === 2 ? missing : 0).fill("0"), ...rest];
  const words = groups.map((g) => (/^[0-9a-f]{1,4}$/.test(g) ? parseInt(g, 16) : NaN));
  if (words.length !== 8 || words.some(Number.isNaN)) return null;
  if (tail.length === 2) {
    words[6] = tail[0]!;
    words[7] = tail[1]!;
  }
  return words.flatMap((w) => [w >> 8, w & 0xff]);
}

/** True only for addresses on the public internet. Unknown or odd forms are refused. */
export function isPublicIp(ip: string): boolean {
  const kind = isIP(ip);
  if (kind === 4) return isPublicIpv4(ipv4Octets(ip)!);
  if (kind !== 6) return false;
  const b = ipv6Bytes(ip);
  if (!b) return false;
  const mappedV4 = b.slice(0, 10).every((x) => x === 0) && b[10] === 0xff && b[11] === 0xff;
  if (mappedV4) return isPublicIpv4(b.slice(12));
  if ((b[0]! & 0xe0) !== 0x20) return false; // only global unicast 2000::/3
  if (b[0] === 0x20 && b[1] === 0x01 && b[2] === 0x0d && b[3] === 0xb8) return false; // documentation
  if (b[0] === 0x20 && b[1] === 0x01 && b[2] === 0 && b[3] === 0) return false; // Teredo
  if (b[0] === 0x20 && b[1] === 0x02) return false; // 6to4
  return true;
}

// ------------------------------------------------------------------ the one HTTP call

export interface HttpResult {
  status: number;
  /** Lower-cased names; repeated headers joined with ", ". */
  headers: Record<string, string>;
  body: string;
  truncated: boolean;
}

export type HttpFailureKind = "timeout" | "network" | "blocked_address";

export class HttpFailure extends Error {
  constructor(readonly kind: HttpFailureKind) {
    super(kind);
    this.name = "HttpFailure";
  }
}

export interface SellerHttp {
  get(url: string, options: { headers?: Record<string, string>; signal: AbortSignal }): Promise<HttpResult>;
}

export const MAX_BODY_BYTES = 256 * 1024;

type LookupCallback = (err: NodeJS.ErrnoException | null, address: string | LookupAddress[], family?: number) => void;

/** DNS lookup used by the socket itself: refuses the connection when any answer is not a public address. */
export function guardedLookup(hostname: string, options: { all?: boolean }, callback: LookupCallback): void {
  dnsLookup(hostname, { all: true, verbatim: true }, (error, addresses) => {
    if (error) return callback(error, "");
    if (addresses.length === 0 || addresses.some((a) => !isPublicIp(a.address))) {
      return callback(Object.assign(new Error("blocked_address"), { code: "EBLOCKED" }) as NodeJS.ErrnoException, "");
    }
    if (options.all) return callback(null, addresses);
    callback(null, addresses[0]!.address, addresses[0]!.family);
  });
}

export class PublicHttps implements SellerHttp {
  get(rawUrl: string, options: { headers?: Record<string, string>; signal: AbortSignal }): Promise<HttpResult> {
    return new Promise((resolve, reject) => {
      let url: URL;
      try {
        url = new URL(checkSellerUrl(rawUrl));
      } catch {
        return reject(new HttpFailure("blocked_address"));
      }
      const req = request(
        {
          protocol: "https:",
          hostname: url.hostname,
          port: 443,
          path: `${url.pathname}${url.search}`,
          method: "GET",
          headers: { accept: "application/json, text/plain;q=0.9, */*;q=0.1", "user-agent": "Doddy/1", ...(options.headers ?? {}) },
          lookup: guardedLookup as never,
          signal: options.signal,
        },
        (res) => {
          const chunks: Buffer[] = [];
          let size = 0;
          let truncated = false;
          res.on("data", (chunk: Buffer) => {
            if (truncated) return;
            size += chunk.length;
            if (size > MAX_BODY_BYTES) {
              truncated = true;
              res.destroy();
              return;
            }
            chunks.push(chunk);
          });
          const finish = () => {
            const headers: Record<string, string> = {};
            for (const [name, value] of Object.entries(res.headers)) {
              if (value !== undefined) headers[name.toLowerCase()] = Array.isArray(value) ? value.join(", ") : value;
            }
            resolve({ status: res.statusCode ?? 0, headers, body: Buffer.concat(chunks).toString("utf8"), truncated });
          };
          res.on("end", finish);
          res.on("close", () => {
            if (truncated) finish();
          });
          res.on("error", () => (truncated ? finish() : reject(new HttpFailure("network"))));
        },
      );
      req.on("error", (error: NodeJS.ErrnoException) => {
        if (error.code === "EBLOCKED") return reject(new HttpFailure("blocked_address"));
        if (error.name === "AbortError" || error.code === "ABORT_ERR") return reject(new HttpFailure("timeout"));
        reject(new HttpFailure("network"));
      });
      req.end();
    });
  }
}
