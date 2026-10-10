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
  })
  .strict();
export type PrepareResult = z.infer<typeof PrepareResultSchema>;

export const RunResultSchema = z
  .object({
    mode: Mode,
    tool: z.string(),
    /** Written for the voice agent: states only what the provider returned. */
    text: z.string(),
    count: z.number().int().min(0),
    truncated: z.boolean(),
    receipt: ToolReceiptSchema,
  })
  .strict();
export type RunResult = z.infer<typeof RunResultSchema>;

export const ToolReceiptsSchema = z.object({ receipts: z.array(ToolReceiptSchema) }).strict();
