import { z } from "zod";
import { EventsRequestSchema } from "./contracts.js";

/**
 * Doddy-owned capability registry. IDs are provider-neutral Doddy names, NOT Composio tool slugs;
 * the adapter alone knows which provider tool implements an entry. Only `enabled` entries can run,
 * and nothing outside this registry is reachable (there is no generic tool or proxy route).
 */
export type Risk = "read" | "write";
export type ConfirmationPolicy = "none" | "fresh_per_execution";
export type ImplementationStatus = "implemented" | "planned";

export interface CapabilityDefinition {
  id: string;
  version: number;
  provider: "google_calendar" | "synthetic";
  input: z.ZodTypeAny;
  /** Granted scopes must include at least one of these, and nothing outside `allowedGrants`. */
  requiredAnyGrant: readonly string[];
  risk: Risk;
  confirmation: ConfirmationPolicy;
  enabledModes: readonly ("mock" | "live")[];
  timeoutMs: number;
  resultBounds: { maxEvents: number; maxPages: number; maxTitleLength: number };
  /** Safe reads may retry with capped backoff; writes never retry automatically. */
  retry: { maxRetries: number; baseDelayMs: number; maxDelayMs: number };
  /** Allowance units reserved before the call; each page and each retry costs one more. */
  costClass: "provider_call";
  receipt: "always";
  status: ImplementationStatus;
  evidence: string;
}

export const GOOGLE_CALENDAR_READ_SCOPES = [
  "https://www.googleapis.com/auth/calendar.events.readonly",
  "https://www.googleapis.com/auth/calendar.readonly",
  "https://www.googleapis.com/auth/calendar.events.owned.readonly",
] as const;

/** The narrow scope Doddy asks for. Configure the auth config with exactly this (see docs). */
export const GOOGLE_CALENDAR_REQUESTED_SCOPE = "https://www.googleapis.com/auth/calendar.events.readonly";

/** Identity scopes a hosted OAuth app may add. They cannot change calendar data. */
const IDENTITY_SCOPES = [
  "openid",
  "email",
  "profile",
  "https://www.googleapis.com/auth/userinfo.email",
  "https://www.googleapis.com/auth/userinfo.profile",
] as const;

export const GOOGLE_CALENDAR_ALLOWED_GRANTS: ReadonlySet<string> = new Set([
  ...GOOGLE_CALENDAR_READ_SCOPES,
  ...IDENTITY_SCOPES,
]);

export type GrantVerdict = "read_only" | "missing_read_scope" | "not_read_only" | "unverifiable";

/** Read-only must be proven from the granted scope list; hiding write buttons is not enough. */
export function evaluateGrant(grantedScopes: readonly string[] | null): GrantVerdict {
  if (grantedScopes === null) return "unverifiable";
  if (grantedScopes.some((s) => !GOOGLE_CALENDAR_ALLOWED_GRANTS.has(s))) return "not_read_only";
  if (!grantedScopes.some((s) => (GOOGLE_CALENDAR_READ_SCOPES as readonly string[]).includes(s))) {
    return "missing_read_scope";
  }
  return "read_only";
}

export const CALENDAR_LIST_EVENTS: CapabilityDefinition = {
  id: "calendar.listEvents",
  version: 1,
  provider: "google_calendar",
  input: EventsRequestSchema,
  requiredAnyGrant: GOOGLE_CALENDAR_READ_SCOPES,
  risk: "read",
  confirmation: "none",
  enabledModes: ["mock", "live"],
  timeoutMs: 10_000,
  resultBounds: { maxEvents: 100, maxPages: 3, maxTitleLength: 200 },
  retry: { maxRetries: 2, baseDelayMs: 250, maxDelayMs: 2_000 },
  costClass: "provider_call",
  receipt: "always",
  status: "implemented",
  evidence: "docs/integrations/PROVIDER_CAPABILITY_MATRIX.md#google-calendar",
};

/** Listed so the policy is visible; disabled in every mode and has no handler. */
export const CALENDAR_CREATE_EVENT: CapabilityDefinition = {
  id: "calendar.createEvent",
  version: 0,
  provider: "google_calendar",
  input: z.never(),
  requiredAnyGrant: [],
  risk: "write",
  confirmation: "fresh_per_execution",
  enabledModes: [],
  timeoutMs: 10_000,
  resultBounds: { maxEvents: 0, maxPages: 0, maxTitleLength: 0 },
  retry: { maxRetries: 0, baseDelayMs: 0, maxDelayMs: 0 },
  costClass: "provider_call",
  receipt: "always",
  status: "planned",
  evidence: "not built: writes are out of scope for this milestone",
};

export class CapabilityRegistry {
  private readonly entries = new Map<string, CapabilityDefinition>();

  constructor(definitions: readonly CapabilityDefinition[]) {
    for (const d of definitions) {
      if (this.entries.has(d.id)) throw new Error(`duplicate capability ${d.id}`);
      if (d.risk === "write" && d.confirmation === "none") throw new Error(`${d.id}: writes need confirmation`);
      if (d.risk === "write" && d.retry.maxRetries > 0) throw new Error(`${d.id}: writes never auto-retry`);
      this.entries.set(d.id, d);
    }
  }

  get(id: string): CapabilityDefinition | undefined {
    return this.entries.get(id);
  }

  isEnabled(id: string, mode: "mock" | "live"): boolean {
    return this.entries.get(id)?.enabledModes.includes(mode) ?? false;
  }

  all(): CapabilityDefinition[] {
    return [...this.entries.values()];
  }
}

export const defaultRegistry = () => new CapabilityRegistry([CALENDAR_LIST_EVENTS, CALENDAR_CREATE_EVENT]);
