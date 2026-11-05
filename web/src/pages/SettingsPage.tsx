import { useState } from "react";
import { api, ApiError } from "../api/client.js";
import type { WebSessionView } from "../api/schemas.js";
import { useResource } from "../api/useResource.js";
import { useSession } from "../auth/session.js";
import { PageHeader } from "../components/PageHeader.js";
import { ErrorState, errorText, Loading } from "../components/States.js";
import { useI18n } from "../i18n/i18n.js";
import { LANGUAGE_NAMES, LANGUAGES, type Language } from "../i18n/messages.js";

export function SettingsPage() {
  const { t, language, setLanguage } = useI18n();
  const { resource, reload } = useResource(api.sessions);
  return (
    <>
      <PageHeader title={t("settings.title")} />
      <section className="card" aria-labelledby="browsers-heading">
        <h2 id="browsers-heading">{t("settings.browsers")}</h2>
        <p className="lead">{t("settings.browsersLead")}</p>
        {resource.status === "loading" ? <Loading /> : null}
        {resource.status === "error" ? <ErrorState error={resource.error} onRetry={reload} /> : null}
        {resource.data ? (
          <ul className="session-list">
            {resource.data.map((session) => (
              <SessionItem key={session.id} session={session} onChanged={reload} />
            ))}
          </ul>
        ) : null}
      </section>
      <section className="card" aria-labelledby="language-heading">
        <h2 id="language-heading">{t("settings.language")}</h2>
        <label className="field-label" htmlFor="language-select">
          {t("settings.languageLabel")}
        </label>
        <select id="language-select" className="select" value={language} onChange={(e) => setLanguage(e.target.value as Language)}>
          {LANGUAGES.map((l) => (
            <option key={l} value={l} lang={l}>
              {LANGUAGE_NAMES[l]}
            </option>
          ))}
        </select>
      </section>
      <section className="card" aria-labelledby="data-heading">
        <h2 id="data-heading">{t("settings.data")}</h2>
        <p>{t("settings.dataBody")}</p>
      </section>
    </>
  );
}

function SessionItem({ session, onChanged }: { session: WebSessionView; onChanged: () => void }) {
  const { t, dateTime, date } = useI18n();
  const { expired, signOut } = useSession();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const label = t("browserOn", { browser: t(`browser.${session.browser}`), os: t(`os.${session.os}`) });

  const revoke = async () => {
    setBusy(true);
    setError(null);
    try {
      if (session.current) {
        await signOut();
        return;
      }
      await api.revokeSession(session.id);
      onChanged();
    } catch (caught) {
      if (caught instanceof ApiError && caught.code === "unauthenticated") {
        expired();
        return;
      }
      // Already signed out elsewhere: the list just catches up.
      if (caught instanceof ApiError && caught.code === "not_found") {
        onChanged();
        return;
      }
      const apiError = caught instanceof ApiError ? caught : new ApiError("network", String(caught), 0);
      setError(errorText(apiError, t));
    } finally {
      setBusy(false);
    }
  };

  return (
    <li className="session">
      <div>
        <p className="session-name">
          {label}
          {session.current ? <span className="pill">{t("settings.thisBrowser")}</span> : null}
        </p>
        <p className="document-meta">{t("settings.signedIn", { date: dateTime(session.createdAt) })}</p>
        <p className="document-meta">{t("settings.lastUsed", { date: dateTime(session.lastSeenAt) })}</p>
        <p className="document-meta">{t("settings.ends", { date: date(session.expiresAt) })}</p>
      </div>
      <button type="button" className="button button-quiet" onClick={revoke} disabled={busy} aria-label={`${session.current ? t("settings.signOutThis") : t("settings.signOutOther")}: ${label}`}>
        {busy ? t("settings.signingOut") : session.current ? t("settings.signOutThis") : t("settings.signOutOther")}
      </button>
      {error ? (
        <p className="field-error" role="alert">
          {error}
        </p>
      ) : null}
    </li>
  );
}
