import type { Composio } from "@composio/core";
import { ProviderError } from "../errors.js";
import type { ProviderConnectionStatus } from "./types.js";

// Helpers shared by the calendar and the online-accounts Composio adapters, so both read Composio's
// statuses and errors the same way (review 2026-10-11: the two copies had started to differ).

export function mapStatus(status: string, isDisabled: boolean): ProviderConnectionStatus {
  if (isDisabled) return "disabled";
  switch (status) {
    case "ACTIVE":
      return "active";
    case "INITIALIZING":
    case "INITIATED":
      return "pending";
    case "EXPIRED":
      return "expired";
    case "REVOKED":
    case "INACTIVE":
      return "revoked";
    default:
      return "failed";
  }
}

/** Reads only the granted scope list from connection state; returns null when it is not exposed. */
export function extractScopes(state: unknown): string[] | null {
  if (typeof state !== "object" || state === null) return null;
  const val = (state as { val?: unknown }).val;
  if (typeof val !== "object" || val === null) return null;
  const scope = (val as { scope?: unknown }).scope;
  if (typeof scope === "string") {
    const list = scope.split(/[\s,]+/).filter(Boolean);
    return list.length > 0 ? list : null;
  }
  if (Array.isArray(scope) && scope.every((s) => typeof s === "string")) {
    return scope.length > 0 ? [...scope] : null;
  }
  return null;
}

export function errorName(error: unknown): string {
  return error instanceof Error ? error.name : "";
}

export function isCancel(error: unknown): boolean {
  return errorName(error) === "ComposioRequestCancelledError" || errorName(error) === "AbortError" || errorName(error) === "TimeoutError";
}

export function httpStatus(error: unknown): { status: number | null; retryAfter: number | undefined } {
  for (let e: unknown = error, depth = 0; e && depth < 4; e = (e as { cause?: unknown }).cause, depth++) {
    const status = (e as { status?: unknown }).status;
    if (typeof status === "number") {
      const headers = (e as { headers?: unknown }).headers;
      let raw: string | null = null;
      if (headers instanceof Headers) raw = headers.get("retry-after");
      else if (headers && typeof headers === "object") {
        const v = (headers as Record<string, unknown>)["retry-after"];
        raw = typeof v === "string" ? v : null;
      }
      const seconds = raw !== null && /^\d{1,5}$/.test(raw) ? Number(raw) : undefined;
      return { status, retryAfter: seconds };
    }
  }
  return { status: null, retryAfter: undefined };
}

/** Maps SDK/HTTP failures to safe codes. Provider messages are dropped, never logged or returned. */
export function mapProviderError(error: unknown, opts: { execute?: boolean } = {}): ProviderError {
  if (error instanceof ProviderError) return error;
  if (isCancel(error)) return new ProviderError("provider_timeout");
  if (errorName(error) === "ComposioConnectedAccountNotFoundError") return new ProviderError("connection_expired");
  const { status, retryAfter } = httpStatus(error);
  if (status === 429) return new ProviderError("rate_limited", retryAfter);
  // 401/403 from Composio means Doddy's own project key or config is wrong, not the user's grant;
  // a bad key must surface as an error, never as "reconnect" or as demo data.
  // A 404 from running a tool can also mean an unknown slug or version (Doddy's configuration), so
  // only account lookups read it as an expired connection. A missing account on execute is caught
  // above by its own error name.
  if ((status === 404 || status === 410) && !opts.execute) return new ProviderError("connection_expired");
  return new ProviderError("provider_unavailable");
}

export async function guard<T>(fn: () => Promise<T>, opts: { execute?: boolean } = {}): Promise<T> {
  try {
    return await fn();
  } catch (error) {
    throw mapProviderError(error, opts);
  }
}

/**
 * Revokes (where the toolkit supports it) and deletes one Composio connection. A revoke that times
 * out stops here as "failed": the delete would run on the same, already expired, signal.
 */
export async function removeComposioConnection(
  client: Pick<Composio, "connectedAccounts">, connectionId: string, signal: AbortSignal,
): Promise<"removed" | "failed"> {
  try {
    await client.connectedAccounts.revoke(connectionId, { signal });
  } catch (error) {
    // Not supported / not revokable / already gone: still delete the Composio connection below.
    if (isCancel(error)) return "failed";
  }
  try {
    await client.connectedAccounts.delete(connectionId, { signal });
    return "removed";
  } catch (error) {
    return errorName(error) === "ComposioConnectedAccountNotFoundError" ? "removed" : "failed";
  }
}
