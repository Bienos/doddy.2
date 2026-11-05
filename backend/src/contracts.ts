import { z } from "zod";

/**
 * Doddy-owned HTTP contract (v1). These are product contracts designed here, not Composio
 * endpoints. Request schemas are strict: unknown fields (a userId, a connection ID, a tool slug)
 * are rejected rather than ignored. Swift mirrors these in DoddyCore/ConnectedApps and both sides
 * decode the fixtures in contracts/connected-apps/.
 */

export const Mode = z.enum(["mock", "live"]);

export const EventsRequestSchema = z
  .object({
    /** Local calendar date the user asked about (the app sends tomorrow's date). */
    date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
    /** Explicit IANA time zone; offsets and abbreviations are refused. */
    timeZone: z.string().min(1).max(64),
  })
  .strict();
export type EventsRequest = z.infer<typeof EventsRequestSchema>;

export const ConnectRequestSchema = z.object({}).strict();

const opaque = z.string().min(1).max(256).regex(/^[A-Za-z0-9_\-.:]+$/);

export const CompleteRequestSchema = z
  .object({
    attemptId: z.string().uuid(),
    nonce: z.string().regex(/^[A-Za-z0-9_-]{43}$/),
    result: z.discriminatedUnion("kind", [
      z
        .object({
          kind: z.literal("callback"),
          status: z.enum(["success", "failed"]),
          connectedAccountId: opaque.optional(),
        })
        .strict(),
      z.object({ kind: z.literal("verifier"), sessionUri: z.string().min(8).max(2048) }).strict(),
      z.object({ kind: z.literal("canceled") }).strict(),
      z.object({ kind: z.literal("mock"), outcome: z.enum(["approve", "deny"]) }).strict(),
    ]),
  })
  .strict();
export type CompleteRequest = z.infer<typeof CompleteRequestSchema>;

export const EmptyRequestSchema = z.object({}).strict();

export const MockScenario = z.enum([
  "events",
  "empty",
  "many",
  "malformed",
  "provider_error",
  "rate_limited",
  "timeout",
  "expired",
  "insufficient_scope",
  "broad_scope",
]);
export type MockScenario = z.infer<typeof MockScenario>;

// ---------------------------------------------------------------- responses

export const ReceiptStatus = z.enum(["succeeded", "failed", "canceled", "blocked", "outcome_unknown"]);
export type ReceiptStatus = z.infer<typeof ReceiptStatus>;

export const ReceiptSchema = z
  .object({
    operationId: z.string().uuid(),
    operation: z.enum(["connect", "disconnect", "read"]),
    capability: z.string(),
    provider: z.literal("google_calendar"),
    accountLabel: z.string().nullable(),
    timestamp: z.string(),
    mode: Mode,
    status: ReceiptStatus,
    summary: z.string().max(200),
    errorCode: z.string().nullable(),
    /** Only a reference the provider actually returned; never invented. */
    providerReference: z.string().nullable(),
  })
  .strict();
export type Receipt = z.infer<typeof ReceiptSchema>;

export const ConnectionStatus = z.enum([
  "disconnected",
  "connecting",
  "connected",
  "permission_insufficient",
  "expired",
  "error",
]);
export type ConnectionStatus = z.infer<typeof ConnectionStatus>;

export const ConnectionReason = z.enum([
  "missing_read_scope",
  "grant_not_read_only",
  "grant_unverifiable",
  "grant_too_broad",
  "revoked_or_expired",
  "provider_unavailable",
]);
export type ConnectionReason = z.infer<typeof ConnectionReason>;

export const ConnectionViewSchema = z
  .object({
    provider: z.literal("google_calendar"),
    mode: Mode,
    status: ConnectionStatus,
    reason: ConnectionReason.nullable(),
    /** Masked calendar name as reported by Google Calendar, or null. Not a verified identity. */
    accountLabel: z.string().nullable(),
    connectedAt: z.string().nullable(),
    lastCheckedAt: z.string().nullable(),
    /** State of revoking/deleting the remote connection after the user disconnected. */
    remoteCleanup: z.enum(["none", "pending", "failed"]),
    access: z
      .object({
        summary: z.string(),
        canWrite: z.literal(false),
        requestedScopes: z.array(z.string()),
      })
      .strict(),
  })
  .strict();
export type ConnectionView = z.infer<typeof ConnectionViewSchema>;

export const ConnectResponseSchema = z
  .object({
    mode: Mode,
    attemptId: z.string().uuid(),
    nonce: z.string(),
    /** System-browser URL for live mode; null in mock mode (no fake Google sign-in is ever shown). */
    authorizationUrl: z.string().url().nullable(),
    callbackScheme: z.string(),
    expiresAt: z.string(),
  })
  .strict();
export type ConnectResponse = z.infer<typeof ConnectResponseSchema>;

export const ConnectionResultSchema = z
  .object({ connection: ConnectionViewSchema, receipt: ReceiptSchema })
  .strict();
export type ConnectionResult = z.infer<typeof ConnectionResultSchema>;

export const CalendarEventSchema = z
  .object({
    title: z.string(),
    allDay: z.boolean(),
    /** RFC 3339 instant for timed events; YYYY-MM-DD for all-day events. */
    start: z.string(),
    /** Exclusive end, same format as start. */
    end: z.string(),
    isRecurring: z.boolean(),
  })
  .strict();
export type CalendarEvent = z.infer<typeof CalendarEventSchema>;

export const EventsResultSchema = z
  .object({
    mode: Mode,
    source: z.object({ provider: z.literal("google_calendar"), calendar: z.literal("primary"), label: z.string().nullable() }).strict(),
    window: z.object({ date: z.string(), timeZone: z.string(), start: z.string(), end: z.string() }).strict(),
    events: z.array(CalendarEventSchema),
    cancelledHidden: z.number().int().min(0),
    truncated: z.boolean(),
    retrievedAt: z.string(),
    /** Transient context: the app discards these results after this time or on disconnect. */
    expiresAt: z.string(),
    receipt: ReceiptSchema,
  })
  .strict();
export type EventsResult = z.infer<typeof EventsResultSchema>;

export const ErrorCode = z.enum([
  "unauthenticated",
  "invalid_request",
  "not_found",
  "payload_too_large",
  "not_connected",
  "permission_insufficient",
  "connection_expired",
  "capability_disabled",
  "attempt_invalid",
  "rate_limited",
  "quota_exceeded",
  "busy",
  "provider_unavailable",
  "provider_timeout",
  "malformed_provider_result",
  "live_not_configured",
  /** The model declined to answer (Ask Doddy, ADR-587). Not retried. */
  "refused",
  "internal",
]);
export type ErrorCode = z.infer<typeof ErrorCode>;

export const ErrorResponseSchema = z
  .object({
    error: z
      .object({
        code: ErrorCode,
        message: z.string(),
        correlationId: z.string(),
        retryAfterSeconds: z.number().int().positive().optional(),
        receipt: ReceiptSchema.optional(),
      })
      .strict(),
  })
  .strict();
export type ErrorResponse = z.infer<typeof ErrorResponseSchema>;

export const HealthSchema = z
  .object({ status: z.literal("ok"), mode: Mode, api: z.literal("v1"), capabilities: z.array(z.string()) })
  .strict();
