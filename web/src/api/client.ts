import type { z } from "zod";
import { CurrentSession, DocumentList, ErrorBody, ReceiptList, SessionList, SignedOut, ToolsCatalog } from "./schemas.js";

/**
 * Talks to Doddy's server on this page's own origin (ADR-585). The session is a cookie the page
 * can't read; this code never sees or stores it. Every reply is checked against its schema, and a
 * reply that doesn't fit is an error, never half-shown data.
 */

export type ApiErrorCode =
  | "unauthenticated"
  | "rate_limited"
  | "not_found"
  | "invalid_request"
  | "payload_too_large"
  | "network"
  | "unreadable"
  | "server";

export class ApiError extends Error {
  constructor(
    readonly code: ApiErrorCode,
    /** The server's own wording (English). The page shows its own translated text for the code. */
    message: string,
    readonly status: number,
    readonly retryAfterSeconds?: number,
  ) {
    super(message);
    this.name = "ApiError";
  }
}

const KNOWN: ReadonlySet<string> = new Set(["unauthenticated", "rate_limited", "not_found", "invalid_request", "payload_too_large"]);

interface Options {
  method?: "GET" | "POST" | "DELETE";
  body?: unknown;
  signal?: AbortSignal | undefined;
}

async function send(path: string, { method = "GET", body, signal }: Options = {}): Promise<Response> {
  // The header (with the browser's own Origin) is what the server checks on a request that changes
  // something. A page on another site can't add it without a CORS preflight, which the server never allows.
  const headers: Record<string, string> = { accept: "application/json", "x-doddy-web": "1" };
  if (body !== undefined) headers["content-type"] = "application/json";
  let response: Response;
  try {
    response = await fetch(path, {
      method,
      headers,
      credentials: "same-origin",
      redirect: "error",
      cache: "no-store",
      referrerPolicy: "no-referrer",
      ...(body !== undefined ? { body: JSON.stringify(body) } : {}),
      ...(signal ? { signal } : {}),
    });
  } catch (error) {
    if (error instanceof DOMException && error.name === "AbortError") throw error;
    throw new ApiError("network", "Doddy's server couldn't be reached.", 0);
  }
  if (response.ok) return response;
  let parsed: z.infer<typeof ErrorBody> | null = null;
  try {
    const result = ErrorBody.safeParse(await response.json());
    parsed = result.success ? result.data : null;
  } catch {
    parsed = null;
  }
  const code = parsed && KNOWN.has(parsed.error.code) ? (parsed.error.code as ApiErrorCode) : "server";
  throw new ApiError(code, parsed?.error.message ?? `HTTP ${response.status}`, response.status, parsed?.error.retryAfterSeconds);
}

async function json<S extends z.ZodTypeAny>(schema: S, path: string, options?: Options): Promise<z.infer<S>> {
  const response = await send(path, options);
  let raw: unknown;
  try {
    raw = await response.json();
  } catch {
    throw new ApiError("unreadable", "The reply wasn't JSON.", response.status);
  }
  const parsed = schema.safeParse(raw);
  if (!parsed.success) throw new ApiError("unreadable", "The reply didn't match what the page expects.", response.status);
  return parsed.data;
}

export const api = {
  /** The signed-in browser session, or an `unauthenticated` error. */
  session: (signal?: AbortSignal) => json(CurrentSession, "/v1/web/session", { signal }).then((r) => r.session),
  signIn: (code: string) => json(CurrentSession, "/v1/web/session", { method: "POST", body: { code } }).then((r) => r.session),
  signOut: () => json(SignedOut, "/v1/web/session", { method: "DELETE" }),
  sessions: (signal?: AbortSignal) => json(SessionList, "/v1/web/sessions", { signal }).then((r) => r.sessions),
  revokeSession: (id: string) => json(SignedOut, `/v1/web/sessions/${encodeURIComponent(id)}`, { method: "DELETE" }),
  documents: (signal?: AbortSignal) => json(DocumentList, "/v1/web/documents", { signal }),
  catalog: (signal?: AbortSignal) => json(ToolsCatalog, "/v1/tools", { signal }),
  receipts: (signal?: AbortSignal) => json(ReceiptList, "/v1/tools/receipts", { signal }).then((r) => r.receipts),
  /** The document's file as a blob. Not shown in the page: it is saved through a download. */
  async documentFile(id: string): Promise<Blob> {
    const response = await send(`/v1/web/documents/${encodeURIComponent(id)}/file`);
    return response.blob();
  },
};
