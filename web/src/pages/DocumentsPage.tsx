import { api } from "../api/client.js";
import type { DocumentList } from "../api/schemas.js";
import { useResource } from "../api/useResource.js";
import { DocumentItem } from "../components/DocumentItem.js";
import { PageHeader } from "../components/PageHeader.js";
import { Empty, ErrorState, Loading } from "../components/States.js";
import { useI18n } from "../i18n/i18n.js";

/** While Doddy is making something, the list asks the server again every ten seconds. */
export const DOCUMENT_REFRESH_MS = 10_000;
export const refreshWhileWorking = (list: DocumentList) => (list.documents.some((d) => d.status === "working") ? DOCUMENT_REFRESH_MS : null);

export function DocumentsPage() {
  const { t } = useI18n();
  const { resource, reload } = useResource(api.documents, { refreshEveryMs: refreshWhileWorking });
  const list = resource.data;
  return (
    <>
      <PageHeader
        title={t("documents.title")}
        lead={t("documents.lead", { days: list?.keptDays ?? 7 })}
        actions={
          <button type="button" className="button button-quiet" onClick={reload}>
            {t("common.refresh")}
          </button>
        }
      />
      {resource.status === "loading" ? <Loading /> : null}
      {resource.status === "error" ? <ErrorState error={resource.error} onRetry={reload} /> : null}
      {list ? (
        list.documents.length === 0 ? (
          <Empty>{t("documents.empty")}</Empty>
        ) : (
          <>
            {refreshWhileWorking(list) !== null ? <p className="fine-print">{t("documents.autoRefresh")}</p> : null}
            <ul className="document-list" aria-live="polite">
              {list.documents.map((doc) => (
                <DocumentItem key={doc.id} doc={doc} />
              ))}
            </ul>
          </>
        )
      ) : null}
    </>
  );
}
