import { z } from "zod";
import { ConnectionReason, Mode, ReceiptStatus } from "../contracts.js";
import { TOOLKIT_IDS } from "./catalog.js";
import { WEB_SECTION_ID } from "./websearch.js";

/**
 * Doddy-owned HTTP contract for online-account tools (v1). Request bodies are strict: a user ID,
 * a connection ID, a Composio slug or any unknown field is rejected, not ignored.
 */

export const ToolkitIdSchema = z.enum(TOOLKIT_IDS as [string, ...string[]]);

/** A Settings section: a Composio account, or web search (Monid), which needs no account. */
export const SectionIdSchema = z.enum([WEB_SECTION_ID, ...TOOLKIT_IDS] as [string, ...string[]]);
export const ToolStatus = z.enum(["unavailable", "disconnected", "connecting", "connected", "permission_insufficient", "expired", "error"]);

export const ToolViewSchema = z
  .object({
    name: z.string(),
    title: z.string(),
    blurb: z.string(),
    risk: z.enum(["read", "write"]),
    /** True only if the user switched it on and the account is connected with an acceptable grant. */
    enabled: z.boolean(),
  })
  .strict();

export const ToolkitViewSchema = z
  .object({
    id: SectionIdSchema,
    title: z.string(),
    access: z.string(),
    /** False for web search: there is nothing to connect, only the tool switch. */
    needsAccount: z.boolean(),
    status: ToolStatus,
    reason: ConnectionReason.nullable(),
    connectedAt: z.string().nullable(),
    remoteCleanup: z.enum(["none", "pending", "failed"]),
    tools: z.array(ToolViewSchema),
  })
  .strict();
export type ToolkitView = z.infer<typeof ToolkitViewSchema>;

export const ToolsCatalogSchema = z.object({ mode: Mode, toolkits: z.array(ToolkitViewSchema) }).strict();
export type ToolsCatalog = z.infer<typeof ToolsCatalogSchema>;

export const ToolReceiptSchema = z
  .object({
    operationId: z.string().uuid(),
    operation: z.enum(["connect", "disconnect", "switch", "read", "write"]),
    toolkit: SectionIdSchema,
    tool: z.string().nullable(),
    timestamp: z.string(),
    mode: Mode,
    status: ReceiptStatus,
    summary: z.string().max(200),
    errorCode: z.string().nullable(),
    providerReference: z.string().nullable(),
  })
  .strict();
export type ToolReceipt = z.infer<typeof ToolReceiptSchema>;

export const ToolkitResultSchema = z.object({ toolkit: ToolkitViewSchema, receipt: ToolReceiptSchema }).strict();
export type ToolkitResult = z.infer<typeof ToolkitResultSchema>;

export const SwitchRequestSchema = z.object({ tool: z.string().min(1).max(64), enabled: z.boolean() }).strict();

export const PrepareRequestSchema = z.object({ tool: z.string().min(1).max(64), arguments: z.record(z.unknown()) }).strict();

export const RunRequestSchema = z
  .object({
    tool: z.string().min(1).max(64),
    arguments: z.record(z.unknown()),
    /** IANA zone used to show times; offsets and abbreviations are refused. */
    timeZone: z.string().min(1).max(64),
    approvalId: z.string().uuid().optional(),
  })
  .strict();

export const PrepareResultSchema = z
  .object({
    mode: Mode,
    tool: z.string(),
    preview: z.object({ title: z.string(), lines: z.array(z.string()), confirmLabel: z.string() }).strict(),
    approvalId: z.string().uuid(),
    expiresAt: z.string(),
    /**
     * ADR-303: the same write (same arguments) already ran in the last day. `succeeded`: it went
     * through. `outcome_unknown`: it may have. `found`: it may have, and a look found it there.
     */
    earlier: z.object({ status: z.enum(["succeeded", "outcome_unknown", "found"]), at: z.string() }).strict().optional(),
  })
  .strict();
export type PrepareResult = z.infer<typeof PrepareResultSchema>;

/**
 * One listed email or task, for screens such as the morning brief (ADR-231). Metadata only:
 * never an email preview or body, never task notes.
 */
export const ResultItemSchema = z
  .object({
    kind: z.enum(["email", "task"]),
    /** Email subject or task text. */
    title: z.string(),
    /** Email sender as Gmail gives it; null for tasks. */
    from: z.string().nullable(),
    /** Email received time or task due, in the user's time zone, as text; null when unknown. */
    when: z.string().nullable(),
    /** Todoist priority 1; always false for email. */
    urgent: z.boolean(),
  })
  .strict();
export type ResultItem = z.infer<typeof ResultItemSchema>;

export const RunResultSchema = z
  .object({
    mode: Mode,
    tool: z.string(),
    /** Written for the voice agent: states only what the provider returned. */
    text: z.string(),
    count: z.number().int().min(0),
    truncated: z.boolean(),
    /** check_email and list_todoist_tasks only: the same items as `text`, without previews. */
    items: z.array(ResultItemSchema).optional(),
    /** Writes: the provider's id for the draft or task (ADR-303). */
    externalId: z.string().optional(),
    /** True when this answers a repeated run of an approval that already succeeded: nothing ran again. */
    replayed: z.boolean().optional(),
    receipt: ToolReceiptSchema,
  })
  .strict();
export type RunResult = z.infer<typeof RunResultSchema>;

export const ToolReceiptsSchema = z.object({ receipts: z.array(ToolReceiptSchema) }).strict();
