import { api } from "../api/client.js";
import { useResource } from "../api/useResource.js";
import { PageHeader } from "../components/PageHeader.js";
import { Empty, ErrorState, Loading } from "../components/States.js";
import { useI18n } from "../i18n/i18n.js";

/**
 * Messages from the iPhone, read only (owner, 28 Oct 2026). The iPhone sends its thread to Doddy's server whenever
 * it changes; this page shows that copy. Writing and deleting happen on the iPhone: a message deleted there is gone
 * here at its next send. A photo is never sent here, only that a message had one.
 */
export function MessagesPage() {
  const { t, dateTime } = useI18n();
  const { resource, reload } = useResource(api.messages);
  const thread = resource.data;
  return (
    <>
      <PageHeader
        title={t("messages.title")}
        lead={t("messages.lead")}
        actions={
          <button type="button" className="button button-quiet" onClick={reload}>
            {t("common.refresh")}
          </button>
        }
      />
      {resource.status === "loading" ? <Loading /> : null}
      {resource.status === "error" ? <ErrorState error={resource.error} onRetry={reload} /> : null}
      {thread ? (
        thread.messages.length === 0 ? (
          <Empty>{t("messages.empty")}</Empty>
        ) : (
          <>
            {thread.syncedAt ? <p className="fine-print">{t("messages.synced", { time: dateTime(thread.syncedAt) })}</p> : null}
            <ol className="thread" aria-label={t("messages.title")}>
              {thread.messages.map((m) => (
                <li key={m.id} className={`thread-message ${m.sender === "user" ? "from-you" : "from-doddy"}`}>
                  <span className="visually-hidden">{m.sender === "user" ? t("messages.you") : t("messages.doddy")}: </span>
                  {m.hasPhoto ? <span className="thread-note">{t("messages.photo")}</span> : null}
                  {m.file ? <span className="thread-note">{t("messages.file", { name: m.file.name })}</span> : null}
                  {m.file ? null : <p className="thread-text">{m.text}</p>}
                  <time className="thread-time" dateTime={m.createdAt}>{dateTime(m.createdAt)}</time>
                  {m.sender === "user" && m.delivery === "failed" ? <span className="thread-note">{t("messages.notDelivered")}</span> : null}
                </li>
              ))}
            </ol>
          </>
        )
      ) : null}
    </>
  );
}
