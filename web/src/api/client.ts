import type { z } from "zod";
import { LogbookDeleted, LogbookView } from "../logbook/schema.js";
import { OwnerAccounts, OwnerFlag, OwnerOverview } from "../owner/schema.js";
import { ChatContext, ChatReply, ConversationDeleted, ConversationDetail, ConversationList, MemoryDeleted, MemoryOverview, NotesList } from "../memory/schema.js";
import { AccountDeleted, AccountKind, CurrentSession, DocumentList, ErrorBody, IdentityList, ReceiptList, ServerInfo, SessionList, SignedOut, SignedUp, SignInOptions, type SocialProvider, ThreadView, ToolsCatalog, Unlinked } from "./schemas.js";

/**
 * Talks to Doddy's server on this page's own origin (ADR-600). The session is a cookie the page
 * can't read; this code never sees or stores it. Every reply is checked against its schema, and a
 * reply that doesn't fit is an error, never half-shown data.
 */

export type ApiErrorCode =
  | "unauthenticated"
  | "rate_limited"
  | "not_found"
  | "invalid_request"
  | "payload_too_large"
  | "capability_disabled"
  | "quota_exceeded"
  | "live_not_configured"
  | "refused"
  | "provider_unavailable"
  | "provider_timeout"
  | "malformed_provider_result"
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

const KNOWN: ReadonlySet<string> = new Set([
  "unauthenticated",
  "rate_limited",
  "not_found",
  "invalid_request",
  "payload_too_large",
  "capability_disabled",
  "quota_exceeded",
  "live_not_configured",
  "refused",
  "provider_unavailable",
  "provider_timeout",
  "malformed_provider_result",
]);

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
  /** Which Apple or Google buttons the sign-in page shows (ADR-818). An older server has none. */
  signInOptions: (signal?: AbortSignal) => api.signInSetup(signal).then((r) => r.providers),
  /** The buttons, and whether a new account can be made with one. */
  signInSetup: (signal?: AbortSignal): Promise<{ providers: SocialProvider[]; signup: boolean }> =>
    json(SignInOptions, "/v1/web/sign-in-options", { signal }).catch((error: unknown) => {
      if (error instanceof ApiError && error.code === "not_found") return { providers: [] as SocialProvider[], signup: false };
      throw error;
    }),
  /** "Create my Doddy account" after Google or Apple sent the person back without one. */
  signUp: () => json(SignedUp, "/v1/web/signup", { method: "POST", body: {} }),
  /** Whether this account was made on the web. A server without the route: no. */
  account: (signal?: AbortSignal) =>
    json(AccountKind, "/v1/web/account", { signal }).catch((error: unknown) => {
      if (error instanceof ApiError && error.code === "not_found") return { madeOnWeb: false };
      throw error;
    }),
  /** Deletes the whole account and everything Doddy's server keeps for it, then this browser is signed out. */
  deleteAccount: () => json(AccountDeleted, "/v1/web/account/delete", { method: "POST", body: { confirm: "delete" } }),
  /** Apple and Google sign-ins linked to this account. */
  identities: (signal?: AbortSignal) => json(IdentityList, "/v1/web/identities", { signal }).then((r) => r.identities),
  unlinkIdentity: (id: string) => json(Unlinked, `/v1/web/identities/${encodeURIComponent(id)}`, { method: "DELETE" }),
  revokeSession: (id: string) => json(SignedOut, `/v1/web/sessions/${encodeURIComponent(id)}`, { method: "DELETE" }),
  documents: (signal?: AbortSignal) => json(DocumentList, "/v1/web/documents", { signal }),
  /** The iPhone's Messages thread, as it last sent it. Read only. */
  messages: (signal?: AbortSignal) => json(ThreadView, "/v1/web/messages", { signal }),
  catalog: (signal?: AbortSignal) => json(ToolsCatalog, "/v1/tools", { signal }),
  /** Whether the server runs on demo data, for the "Demo server" banner. */
  server: (signal?: AbortSignal) => json(ServerInfo, "/v1/server", { signal }),
  receipts: (signal?: AbortSignal) => json(ReceiptList, "/v1/tools/receipts", { signal }).then((r) => r.receipts),
  /** The days the iPhone has sent for Logbook (ADR-602), and whether it is on. */
  logbook: (signal?: AbortSignal) => json(LogbookView, "/v1/web/logbook", { signal }),
  /**
   * Whether this account sees the owner panel (decision 2026-11-09-usage-counts-on-by-default). The
   * server says "not found" to everyone else, and to a server without the panel; both read as no.
   */
  isOwner: (signal?: AbortSignal) =>
    json(OwnerFlag, "/v1/web/owner", { signal })
      .then(() => true)
      .catch((error: unknown) => {
        if (error instanceof ApiError && error.code === "not_found") return false;
        throw error;
      }),
  /** Totals across every account over the last `days` days. Owner only. */
  ownerOverview: (days: number, signal?: AbortSignal) => json(OwnerOverview, `/v1/web/owner/overview?days=${days}`, { signal }),
  /** Every account with its sign-in details and its counts over the last `days` days. Owner only. */
  ownerAccounts: (days: number, signal?: AbortSignal) => json(OwnerAccounts, `/v1/web/owner/accounts?days=${days}`, { signal }),
  /** One account's own Logbook days, as that person's page reads them. Owner only. */
  ownerAccountLogbook: (userId: string, signal?: AbortSignal) =>
    json(LogbookView, `/v1/web/owner/accounts/${encodeURIComponent(userId)}/logbook`, { signal }),
  /** Deletes every stored Logbook day. Logbook stays as it was (on or off). */
  deleteLogbook: () => json(LogbookDeleted, "/v1/web/logbook", { method: "DELETE" }),
  /** Everything stored for Logbook, as the server's JSON file. Saved through a download. */
  async logbookFile(): Promise<Blob> {
    const response = await send("/v1/web/logbook/export");
    return response.blob();
  },
  /** What Doddy's server keeps of your notes and conversations, and whether each kind is on (ADR-603). */
  memory: (signal?: AbortSignal) => json(MemoryOverview, "/v1/web/memory", { signal }),
  memoryNotes: (o: { limit: number; offset: number }, signal?: AbortSignal) => json(NotesList, `/v1/web/memory/notes?limit=${o.limit}&offset=${o.offset}`, { signal }),
  /** What you search for goes in the body, never in the address. */
  searchMemoryNotes: (o: { q: string; limit: number; offset: number }, signal?: AbortSignal) =>
    json(NotesList, "/v1/web/memory/notes/search", { method: "POST", body: o, signal }),
  memoryConversations: (o: { limit: number; offset: number }, signal?: AbortSignal) =>
    json(ConversationList, `/v1/web/memory/conversations?limit=${o.limit}&offset=${o.offset}`, { signal }),
  memoryConversation: (id: string, signal?: AbortSignal) => json(ConversationDetail, `/v1/web/memory/conversations/${encodeURIComponent(id)}`, { signal }),
  deleteMemoryConversation: (id: string) => json(ConversationDeleted, `/v1/web/memory/conversations/${encodeURIComponent(id)}`, { method: "DELETE" }),
  /** Deletes every kept note and conversation and switches both kinds off. */
  deleteMemory: () => json(MemoryDeleted, "/v1/web/memory", { method: "DELETE" }),
  /** Everything kept, as the server's JSON file. Saved through a download. */
  async memoryFile(): Promise<Blob> {
    const response = await send("/v1/web/memory/export");
    return response.blob();
  },
  /**
   * A message to Doddy's chat (ADR-603, ADR-604): Claude answers from your kept notes and
   * conversations and your account (Logbook, apps, documents, activity). Nothing is stored on the server.
   */
  chat: (body: { message: string; history: { role: "user" | "assistant"; text: string }[]; locale: string; timeZone?: string }, signal?: AbortSignal) =>
    json(ChatReply, "/v1/web/chat", { method: "POST", body, signal }),
  /** Which parts of the account the chat can read now, and whether it is set up on this server. */
  chatContext: (signal?: AbortSignal) => json(ChatContext, "/v1/web/chat/context", { signal }),
  /** The document's file as a blob. Not shown in the page: it is saved through a download. */
  async documentFile(id: string): Promise<Blob> {
    const response = await send(`/v1/web/documents/${encodeURIComponent(id)}/file`);
    return response.blob();
  },
};

/**
 * Where the browser goes to sign in with Apple or Google, or to link one to this account (ADR-818).
 * A whole-page navigation: the server sends it on to Supabase, then Apple or Google, and back.
 */
export function socialStartUrl(provider: SocialProvider, intent: "signin" | "link"): string {
  return `/v1/web/oauth/start?${new URLSearchParams({ provider, ...(intent === "link" ? { intent } : {}) })}`;
}
