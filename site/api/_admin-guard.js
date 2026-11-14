// Limits sign-in attempts on the waitlist admin routes, per client address, in the waitlist's own Vercel
// Blob store (the site has no other shared store). Files starting with "_" in api/ are not routes.
//
// Every request that brings credentials takes a slot BEFORE its password is compared: the slot is a
// timestamp written with a conditional put (ifMatch on the etag), so requests sent in parallel from one
// address can't all be checked before the count catches up. MAX_TRIES slots in WINDOW_MS lock the address
// out for LOCKOUT_MS; while locked, nothing is compared. The right password removes the address's record.
//
// The record's name is an HMAC of the address keyed with the admin password, so the store holds no address
// and no hash anyone without the password could reverse; the body holds timestamps only. Records older
// than WINDOW_MS + LOCKOUT_MS are deleted by the next signed-in admin list (sweepGuardRecords).
import { createHmac } from "node:crypto";
import { isIP } from "node:net";
import { BlobNotFoundError, BlobPreconditionFailedError, del, get, list, put } from "@vercel/blob";

export const PREFIX = "admin-guard/";
export const MAX_TRIES = 5;
export const WINDOW_MS = 15 * 60 * 1000;
export const LOCKOUT_MS = 15 * 60 * 1000;
// Without a usable address everyone shares one bucket, so it gets a higher limit (as ADR-712 does).
export const UNKNOWN_FACTOR = 10;
// Conditional writes that lose to another request from the same address are retried this many times.
const ATTEMPTS = 3;

export class GuardUnavailable extends Error {
  constructor() {
    super("admin guard store unavailable");
    this.name = "GuardUnavailable";
  }
}

/**
 * The caller's address, from the header Vercel sets itself and only on Vercel; anywhere else that header
 * is whatever the caller sends, so the answer is "unknown". An IPv4 address seen through IPv6 is that IPv4
 * address; any other IPv6 address counts as its /64. Same rule as server/voice-token (ADR-712).
 */
export function clientAddress(request, env = process.env) {
  if (typeof env.VERCEL !== "string" || env.VERCEL.trim() === "") return "unknown";
  const first = (request.headers.get("x-vercel-forwarded-for") ?? "").split(",")[0].trim();
  const family = isIP(first);
  if (family === 0) return "unknown";
  if (family === 4) return first;
  const mapped = /^::ffff:(\d{1,3}(?:\.\d{1,3}){3})$/i.exec(first);
  return mapped ? mapped[1] : ipv6Prefix64(first);
}

function ipv6Prefix64(address) {
  const [head, tail = ""] = address.toLowerCase().split("::");
  const first = head ? head.split(":") : [];
  const rest = tail ? tail.split(":") : [];
  const groups = address.includes("::") ? [...first, ...Array(Math.max(0, 8 - first.length - rest.length)).fill("0"), ...rest] : first;
  return `${groups.slice(0, 4).map((group) => group.replace(/^0+(?=.)/, "") || "0").join(":")}::/64`;
}

export const recordName = (password, address) =>
  `${PREFIX}${createHmac("sha256", password).update(`waitlist-admin-guard\0${address}`).digest("hex")}.json`;

const secondsUntil = (ms, now) => Math.max(1, Math.ceil((ms - now) / 1000));

async function read(pathname) {
  let result;
  try {
    // No CDN cache: a cached copy would carry an old count and an old etag.
    result = await get(pathname, { access: "private", useCache: false });
  } catch {
    throw new GuardUnavailable();
  }
  if (!result) return { state: { tries: [], lockedUntil: 0 }, etag: null };
  if (result.statusCode !== 200 || !result.blob?.etag) throw new GuardUnavailable();
  let state;
  try {
    state = JSON.parse(await new Response(result.stream).text());
  } catch {
    state = null;  // unreadable: start again, still overwriting only the version read here
  }
  const tries = Array.isArray(state?.tries) ? state.tries.filter(Number.isFinite) : [];
  const lockedUntil = Number.isFinite(state?.lockedUntil) ? state.lockedUntil : 0;
  return { state: { tries, lockedUntil }, etag: result.blob.etag };
}

async function exists(pathname) {
  try {
    return (await get(pathname, { access: "private", useCache: false })) !== null;
  } catch {
    throw new GuardUnavailable();
  }
}

/**
 * Takes one attempt for this address. Returns {locked: true, retryAfter} when the address may not try now
 * (nothing may be compared), or {locked: false, lockedNow, release}: lockedNow means this attempt was the
 * last one allowed, and release() removes the record (call it after the right password). Throws
 * GuardUnavailable when the store can't be read or written; the caller then compares nothing.
 */
export async function takeAttempt(password, address, now = () => Date.now()) {
  const pathname = recordName(password, address);
  const limit = address === "unknown" ? MAX_TRIES * UNKNOWN_FACTOR : MAX_TRIES;
  for (let attempt = 0; attempt < ATTEMPTS; attempt++) {
    const { state, etag } = await read(pathname);
    const at = now();
    if (state.lockedUntil > at) return { locked: true, retryAfter: secondsUntil(state.lockedUntil, at) };
    const tries = state.tries.filter((t) => t > at - WINDOW_MS && t <= at);
    if (tries.length >= limit) return { locked: true, retryAfter: secondsUntil(Math.min(...tries) + WINDOW_MS, at) };
    tries.push(at);
    const lockedNow = tries.length >= limit;
    const body = JSON.stringify({ tries, lockedUntil: lockedNow ? at + LOCKOUT_MS : 0 });
    const options = { access: "private", addRandomSuffix: false, contentType: "application/json" };
    try {
      await put(pathname, body, etag ? { ...options, allowOverwrite: true, ifMatch: etag } : { ...options, allowOverwrite: false });
    } catch (err) {
      // Another request from this address wrote first (or released the record): read again.
      if (err instanceof BlobPreconditionFailedError || err instanceof BlobNotFoundError) continue;
      if (!etag && (await exists(pathname))) continue;
      throw new GuardUnavailable();
    }
    return {
      locked: false,
      lockedNow,
      retryAfter: lockedNow ? LOCKOUT_MS / 1000 : 0,
      release: () => del(pathname).catch((err) => {
        console.warn(JSON.stringify({ event: "waitlist_admin_guard_release_failed", error: err?.name ?? "unknown" }));
      }),
    };
  }
  // Still losing to parallel requests from the same address: treat it as too many at once.
  return { locked: true, retryAfter: 5 };
}

/** Deletes guard records nobody has written to for WINDOW_MS + LOCKOUT_MS. Never throws. */
export async function sweepGuardRecords(now = Date.now()) {
  try {
    const page = await list({ prefix: PREFIX, limit: 1000 });
    const stale = page.blobs
      .filter((b) => now - new Date(b.uploadedAt).getTime() > WINDOW_MS + LOCKOUT_MS)
      .map((b) => b.pathname);
    if (stale.length) await del(stale);
  } catch (err) {
    console.warn(JSON.stringify({ event: "waitlist_admin_guard_sweep_failed", error: err?.name ?? "unknown" }));
  }
}
