import { readFileSync } from "node:fs";
import { join } from "node:path";
import { vi } from "vitest";

/** Reads a fixture the server wrote from its own output (contracts/…). */
export function fixture(path: string): unknown {
  // Vitest runs from web/; the contracts folder is next to it.
  return JSON.parse(readFileSync(join(process.cwd(), "..", "contracts", `${path}.json`), "utf8"));
}

export interface Seen {
  method: string;
  path: string;
  headers: Record<string, string>;
  body: unknown;
  credentials: RequestCredentials | undefined;
}

type Answer = { status?: number; body?: unknown; raw?: string; blob?: Blob } | Error;

/**
 * A stand-in for Doddy's server: `routes["GET /v1/web/session"] = …`. A function answer is called
 * per request, so a test can change what the server says over time.
 */
export function fakeServer(routes: Record<string, Answer | (() => Answer)>) {
  const seen: Seen[] = [];
  const fetchMock = vi.fn(async (input: RequestInfo | URL, init: RequestInit = {}) => {
    const url = new URL(String(input), "https://app.doddy.test");
    const method = init.method ?? "GET";
    const headers = Object.fromEntries(Object.entries((init.headers as Record<string, string>) ?? {}).map(([k, v]) => [k.toLowerCase(), v]));
    seen.push({ method, path: url.pathname, headers, body: init.body ? JSON.parse(String(init.body)) : undefined, credentials: init.credentials });
    const entry = routes[`${method} ${url.pathname}`];
    const answer = typeof entry === "function" ? entry() : entry;
    if (answer === undefined) return new Response(JSON.stringify({ error: { code: "not_found", message: "Not found." } }), { status: 404 });
    if (answer instanceof Error) throw answer;
    if (answer.blob) return new Response(answer.blob, { status: answer.status ?? 200 });
    return new Response(answer.raw ?? JSON.stringify(answer.body ?? {}), { status: answer.status ?? 200, headers: { "content-type": "application/json" } });
  });
  vi.stubGlobal("fetch", fetchMock);
  return { seen, fetchMock };
}

export const signedOut = { status: 401, body: fixture("web/error-signed-out") };
