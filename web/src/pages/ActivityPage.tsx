import { api } from "../api/client.js";
import type { ToolReceipt } from "../api/schemas.js";
import { useResource } from "../api/useResource.js";
import { PageHeader } from "../components/PageHeader.js";
import { Empty, ErrorState, Loading } from "../components/States.js";
import { useI18n } from "../i18n/i18n.js";

/** Receipts the server wrote (GET /v1/tools/receipts). An unknown outcome is never shown as done. */
export function ActivityPage() {
  const { t } = useI18n();
  const { resource, reload } = useResource(api.receipts);
  return (
    <>
      <PageHeader
        title={t("activity.title")}
        lead={t("activity.lead")}
        actions={
          <button type="button" className="button button-quiet" onClick={reload}>
            {t("common.refresh")}
          </button>
        }
      />
      {resource.status === "loading" ? <Loading /> : null}
      {resource.status === "error" ? <ErrorState error={resource.error} onRetry={reload} /> : null}
      {resource.data ? (
        resource.data.length === 0 ? (
          <Empty>{t("activity.empty")}</Empty>
        ) : (
          <ul className="receipt-list">
            {resource.data.map((receipt) => (
              <ReceiptItem key={receipt.operationId} receipt={receipt} />
            ))}
          </ul>
        )
      ) : null}
    </>
  );
}

export function ReceiptItem({ receipt }: { receipt: ToolReceipt }) {
  const { t, dateTime } = useI18n();
  return (
    <li className="receipt">
      <p className={`status status-receipt-${receipt.status}`}>{t(`activity.status.${receipt.status}`)}</p>
      <p className="receipt-summary">{receipt.summary}</p>
      <p className="document-meta">
        <time dateTime={receipt.timestamp}>{dateTime(receipt.timestamp)}</time>
      </p>
    </li>
  );
}
