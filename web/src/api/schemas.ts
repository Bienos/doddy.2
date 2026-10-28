import { z } from "zod";

/**
 * The shapes Doddy's server answers with (ADR-600). They mirror backend/src/web/contracts.ts and
 * backend/src/tools/contracts.ts; test/contracts.test.ts reads contracts/web/*.json and
 * contracts/online-accounts/*.json, which the server writes from its own output, through them.
 * Unknown fields are dropped, so a newer server doesn't break an older page.
 */

export const Browser = z.enum(["chrome", "edge", "firefox", "safari", "opera", "other"]);
export const Os = z.enum(["macos", "windows", "ios", "ipados", "android", "linux", "chromeos", "other"]);

export const WebSessionView = z.object({
  id: z.string().uuid(),
  browser: Browser,
  os: Os,
  createdAt: z.string(),
  lastSeenAt: z.string(),
  expiresAt: z.string(),
  current: z.boolean(),
});
export type WebSessionView = z.infer<typeof WebSessionView>;

export const CurrentSession = z.object({ session: WebSessionView });
export const SessionList = z.object({ sessions: z.array(WebSessionView) });

export const DocumentKind = z.enum(["deck", "doc", "spreadsheet", "pdf", "text", "file"]);
export const DocumentStatus = z.enum(["working", "ready", "failed", "interrupted"]);
export type DocumentStatus = z.infer<typeof DocumentStatus>;

export const DocumentView = z.object({
  id: z.string(),
  name: z.string(),
  kind: DocumentKind,
  status: DocumentStatus,
  createdAt: z.string(),
  deleteAfter: z.string(),
  sizeBytes: z.number().int().nonnegative().nullable(),
});
export type DocumentView = z.infer<typeof DocumentView>;

export const DocumentList = z.object({ documents: z.array(DocumentView), keptDays: z.number().int().positive() });
export type DocumentList = z.infer<typeof DocumentList>;

export const SignedOut = z.object({ signedOut: z.literal(true) });

// ---- Messages from the iPhone (GET /v1/web/messages)

export const ThreadMessage = z.object({
  id: z.string(),
  sender: z.enum(["user", "doddy"]),
  text: z.string(),
  createdAt: z.string(),
  delivery: z.enum(["sending", "sent", "failed"]).optional(),
  hasPhoto: z.boolean().optional(),
  file: z.object({ name: z.string(), kind: z.string() }).optional(),
});
export const ThreadView = z.object({ messages: z.array(ThreadMessage), syncedAt: z.string().nullable() });
export type ThreadView = z.infer<typeof ThreadView>;

// ---- connected apps (GET /v1/tools) and what Doddy did (GET /v1/tools/receipts)

export const ToolStatus = z.enum(["unavailable", "disconnected", "connecting", "connected", "permission_insufficient", "expired", "error"]);
export type ToolStatus = z.infer<typeof ToolStatus>;

export const ToolView = z.object({
  name: z.string(),
  title: z.string(),
  blurb: z.string(),
  risk: z.enum(["read", "write"]),
  enabled: z.boolean(),
});

export const ToolkitView = z.object({
  id: z.string(),
  title: z.string(),
  access: z.string(),
  needsAccount: z.boolean(),
  status: ToolStatus,
  reason: z.string().nullable(),
  connectedAt: z.string().nullable(),
  remoteCleanup: z.enum(["none", "pending", "failed"]),
  tools: z.array(ToolView),
});
export type ToolkitView = z.infer<typeof ToolkitView>;

export const ToolsCatalog = z.object({ mode: z.enum(["mock", "live"]), toolkits: z.array(ToolkitView) });
export type ToolsCatalog = z.infer<typeof ToolsCatalog>;

export const ReceiptStatus = z.enum(["succeeded", "failed", "canceled", "blocked", "outcome_unknown"]);
export type ReceiptStatus = z.infer<typeof ReceiptStatus>;

export const ToolReceipt = z.object({
  operationId: z.string(),
  operation: z.enum(["connect", "disconnect", "switch", "read", "write"]),
  toolkit: z.string(),
  tool: z.string().nullable(),
  timestamp: z.string(),
  mode: z.enum(["mock", "live"]),
  status: ReceiptStatus,
  summary: z.string(),
  errorCode: z.string().nullable(),
});
export type ToolReceipt = z.infer<typeof ToolReceipt>;

export const ReceiptList = z.object({ receipts: z.array(ToolReceipt) });

export const ErrorBody = z.object({
  error: z.object({ code: z.string(), message: z.string(), retryAfterSeconds: z.number().optional() }),
});
