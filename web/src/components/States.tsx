import type { ReactNode } from "react";
import type { ApiError } from "../api/client.js";
import { useI18n } from "../i18n/i18n.js";
import type { MessageKey } from "../i18n/messages.js";

export function errorKey(error: ApiError): MessageKey {
  switch (error.code) {
    case "network":
      return "common.error.network";
    case "unreadable":
      return "common.error.unreadable";
    case "rate_limited":
      return "common.error.rateLimited";
    case "not_found":
      return "common.error.notFound";
    case "quota_exceeded":
      return "common.error.quota";
    case "provider_timeout":
      return "common.error.slow";
    case "provider_unavailable":
    case "malformed_provider_result":
      return "common.error.assistant";
    case "live_not_configured":
      return "common.error.notSetUp";
    case "capability_disabled":
      return "common.error.off";
    case "refused":
      return "common.error.refused";
    default:
      return "common.error.server";
  }
}

export function errorText(error: ApiError, t: ReturnType<typeof useI18n>["t"]): string {
  return t(errorKey(error), { minutes: Math.max(1, Math.ceil((error.retryAfterSeconds ?? 60) / 60)) });
}

export function Loading() {
  const { t } = useI18n();
  return (
    <p className="state state-loading" role="status">
      <span className="spinner" aria-hidden="true" />
      {t("common.loading")}
    </p>
  );
}

export function ErrorState({ error, onRetry }: { error: ApiError; onRetry?: () => void }) {
  const { t } = useI18n();
  return (
    <div className="state state-error" role="alert">
      <p>{errorText(error, t)}</p>
      {onRetry ? (
        <button type="button" className="button button-quiet" onClick={onRetry}>
          {t("common.tryAgain")}
        </button>
      ) : null}
    </div>
  );
}

export function Empty({ children }: { children: ReactNode }) {
  return <p className="state state-empty">{children}</p>;
}
