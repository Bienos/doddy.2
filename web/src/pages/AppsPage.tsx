import { api } from "../api/client.js";
import type { ToolkitView } from "../api/schemas.js";
import { useResource } from "../api/useResource.js";
import { PageHeader } from "../components/PageHeader.js";
import { ErrorState, Loading } from "../components/States.js";
import { useI18n } from "../i18n/i18n.js";

/**
 * What Doddy can reach (GET /v1/tools), read-only on the web for now (ADR-600): connecting goes
 * through the iPhone's sign-in sheet, and switching a tool on is the iPhone's ASK-01 flow.
 */
export function AppsPage() {
  const { t } = useI18n();
  const { resource, reload } = useResource(api.catalog);
  return (
    <>
      <PageHeader title={t("apps.title")} lead={t("apps.lead")} />
      {resource.status === "loading" ? <Loading /> : null}
      {resource.status === "error" ? <ErrorState error={resource.error} onRetry={reload} /> : null}
      {resource.data ? (
        <ul className="app-list">
          {orderApps(resource.data.toolkits).map((kit) => (
            <AppItem key={kit.id} kit={kit} />
          ))}
        </ul>
      ) : null}
    </>
  );
}

/** Connected first, then the ones that can be connected, then the ones this server lacks. */
export function orderApps(kits: readonly ToolkitView[]): ToolkitView[] {
  const rank = (k: ToolkitView) => (k.status === "connected" ? 0 : k.status === "unavailable" ? 2 : 1);
  return [...kits].sort((a, b) => rank(a) - rank(b));
}

function AppItem({ kit }: { kit: ToolkitView }) {
  const { t, date } = useI18n();
  return (
    <li className="app">
      <div className="app-head">
        <h2>{kit.title}</h2>
        <p className={`status status-app-${kit.status}`}>{t(`apps.status.${kit.status}`)}</p>
      </div>
      <p className="app-access">{kit.access}</p>
      <p className="document-meta">{kit.needsAccount ? (kit.connectedAt && kit.status === "connected" ? t("apps.since", { date: date(kit.connectedAt) }) : null) : t("apps.noAccount")}</p>
      {kit.remoteCleanup === "pending" ? <p className="notice">{t("apps.cleanupPending")}</p> : null}
      {kit.remoteCleanup === "failed" ? <p className="notice">{t("apps.cleanupFailed")}</p> : null}
      {kit.tools.length > 0 && kit.status !== "unavailable" ? (
        <details className="tools">
          <summary>{t("apps.tools")}</summary>
          <ul>
            {kit.tools.map((tool) => (
              <li key={tool.name} className="tool">
                <span className="tool-title">{tool.title}</span>
                <span className={`tool-switch ${tool.enabled ? "is-on" : ""}`}>{tool.enabled ? t("apps.toolOn") : t("apps.toolOff")}</span>
                <span className="tool-risk">{tool.risk === "read" ? t("apps.reads") : t("apps.changes")}</span>
              </li>
            ))}
          </ul>
        </details>
      ) : null}
    </li>
  );
}
