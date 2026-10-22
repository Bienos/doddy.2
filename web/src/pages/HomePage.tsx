import { Link } from "react-router";
import { api } from "../api/client.js";
import { useResource } from "../api/useResource.js";
import { DoddyFigure } from "../components/Brand.js";
import { DocumentItem } from "../components/DocumentItem.js";
import { PageHeader } from "../components/PageHeader.js";
import { Empty, ErrorState, Loading } from "../components/States.js";
import { useI18n } from "../i18n/i18n.js";
import { ReceiptItem } from "./ActivityPage.js";
import { refreshWhileWorking } from "./DocumentsPage.js";

/**
 * The calm starting point (ADR-545's "I'm here", on a bigger screen). Every card is real data
 * from the server; there is no simulated progress, sample day or chat box that isn't wired up.
 */
export function HomePage() {
  const { t, dateTime } = useI18n();
  const documents = useResource(api.documents, { refreshEveryMs: refreshWhileWorking });
  const catalog = useResource(api.catalog);
  const receipts = useResource(api.receipts);

  const docs = documents.resource.data?.documents ?? [];
  const working = docs.filter((d) => d.status === "working");
  const recent = docs.filter((d) => d.status !== "working").slice(0, 3);
  const connected = (catalog.resource.data?.toolkits ?? []).filter((k) => k.needsAccount && k.status === "connected");

  return (
    <>
      <div className="home-hero">
        <DoddyFigure size={88} />
        <PageHeader title={t("home.greeting")} lead={t("home.lead")} />
      </div>

      {working.length > 0 ? (
        <section className="card card-working" aria-labelledby="making-heading">
          <h2 id="making-heading">
            <span className="cue-dot" aria-hidden="true" />
            {t("home.making")}
          </h2>
          <ul className="plain-list" aria-live="polite">
            {working.map((d) => (
              <li key={d.id}>
                <span className="document-name">{d.name}</span>
                <span className="document-meta"> · {t("home.makingItem", { time: dateTime(d.createdAt) })}</span>
              </li>
            ))}
          </ul>
        </section>
      ) : null}

      <div className="home-grid">
        <section className="card" aria-labelledby="recent-heading">
          <div className="card-head">
            <h2 id="recent-heading">{t("home.recentDocuments")}</h2>
            <Link to="/documents">{t("common.seeAll")}</Link>
          </div>
          {documents.resource.status === "loading" ? <Loading /> : null}
          {documents.resource.status === "error" ? <ErrorState error={documents.resource.error} onRetry={documents.reload} /> : null}
          {documents.resource.data ? (
            recent.length === 0 && working.length === 0 ? (
              <Empty>{t("home.noDocuments")}</Empty>
            ) : (
              <ul className="document-list">
                {recent.map((doc) => (
                  <DocumentItem key={doc.id} doc={doc} compact />
                ))}
              </ul>
            )
          ) : null}
        </section>

        <section className="card" aria-labelledby="apps-heading">
          <div className="card-head">
            <h2 id="apps-heading">{t("home.apps")}</h2>
            <Link to="/apps">{t("common.seeAll")}</Link>
          </div>
          {catalog.resource.status === "loading" ? <Loading /> : null}
          {catalog.resource.status === "error" ? <ErrorState error={catalog.resource.error} onRetry={catalog.reload} /> : null}
          {catalog.resource.data ? <p>{connected.length === 0 ? t("home.appsNone") : t("home.appsSome", { names: connected.map((k) => k.title).join(", ") })}</p> : null}
        </section>

        <section className="card" aria-labelledby="activity-heading">
          <div className="card-head">
            <h2 id="activity-heading">{t("home.activity")}</h2>
            <Link to="/activity">{t("common.seeAll")}</Link>
          </div>
          {receipts.resource.status === "loading" ? <Loading /> : null}
          {receipts.resource.status === "error" ? <ErrorState error={receipts.resource.error} onRetry={receipts.reload} /> : null}
          {receipts.resource.data ? (
            receipts.resource.data.length === 0 ? (
              <Empty>{t("home.activityNone")}</Empty>
            ) : (
              <ul className="receipt-list">
                {receipts.resource.data.slice(0, 3).map((receipt) => (
                  <ReceiptItem key={receipt.operationId} receipt={receipt} />
                ))}
              </ul>
            )
          ) : null}
        </section>

        <section className="card card-quiet" aria-labelledby="later-heading">
          <h2 id="later-heading">{t("home.notYet")}</h2>
          <p>{t("home.notYetBody")}</p>
        </section>
      </div>
    </>
  );
}
