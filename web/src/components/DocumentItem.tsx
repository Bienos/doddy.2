import { useState } from "react";
import { api, ApiError } from "../api/client.js";
import type { DocumentView } from "../api/schemas.js";
import { useSession } from "../auth/session.js";
import { useI18n } from "../i18n/i18n.js";
import { errorText } from "./States.js";

/**
 * Saves the file through a download. The file is never opened inside the page: it comes from the
 * server as an attachment, and the page only hands the browser a temporary blob link to save.
 */
export async function saveFile(blob: Blob, name: string): Promise<void> {
  const url = URL.createObjectURL(blob);
  try {
    const link = document.createElement("a");
    link.href = url;
    link.download = name;
    link.rel = "noopener";
    document.body.append(link);
    link.click();
    link.remove();
  } finally {
    // Give the browser a moment to start the download before the link goes.
    setTimeout(() => URL.revokeObjectURL(url), 30_000);
  }
}

export function DocumentItem({ doc, compact = false }: { doc: DocumentView; compact?: boolean }) {
  const { t, dateTime, date, bytes } = useI18n();
  const { expired } = useSession();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const download = async () => {
    setBusy(true);
    setError(null);
    try {
      await saveFile(await api.documentFile(doc.id), doc.name);
    } catch (caught) {
      if (caught instanceof ApiError && caught.code === "unauthenticated") {
        expired();
        return;
      }
      const apiError = caught instanceof ApiError ? caught : new ApiError("network", String(caught), 0);
      setError(t("documents.downloadFailed", { name: doc.name, reason: errorText(apiError, t) }));
    } finally {
      setBusy(false);
    }
  };

  return (
    <li className={`document ${compact ? "document-compact" : ""}`}>
      <div className="document-main">
        <span className={`kind-badge kind-${doc.kind}`} aria-hidden="true">
          {doc.kind === "spreadsheet" ? "xls" : doc.kind === "deck" ? "ppt" : doc.kind === "doc" ? "doc" : doc.kind === "pdf" ? "pdf" : doc.kind === "text" ? "md" : "file"}
        </span>
        <div className="document-text">
          <p className="document-name">{doc.name}</p>
          <p className="document-meta">
            {t(`documents.kind.${doc.kind}`)}
            {doc.sizeBytes !== null ? ` · ${bytes(doc.sizeBytes)}` : ""}
            {" · "}
            {t("documents.made", { date: dateTime(doc.createdAt) })}
          </p>
          {!compact ? <p className="document-meta">{t("documents.deletedAfter", { date: date(doc.deleteAfter) })}</p> : null}
          <p className={`status status-${doc.status}`}>{t(`documents.status.${doc.status}`)}</p>
        </div>
      </div>
      {doc.status === "ready" ? (
        <button type="button" className="button button-quiet" onClick={download} disabled={busy} aria-label={`${t("documents.download")}: ${doc.name}`}>
          {busy ? t("documents.downloading") : t("documents.download")}
        </button>
      ) : null}
      {error ? (
        <p className="field-error" role="alert">
          {error}
        </p>
      ) : null}
    </li>
  );
}
