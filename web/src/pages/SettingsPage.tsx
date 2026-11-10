import { useEffect, useState } from "react";
import { useLocation, useNavigate } from "react-router";
import { api, ApiError, socialStartUrl } from "../api/client.js";
import type { LinkedIdentity, SocialProvider, WebSessionView } from "../api/schemas.js";
import { useResource } from "../api/useResource.js";
import { useSession } from "../auth/session.js";
import { PageHeader } from "../components/PageHeader.js";
import { ErrorState, errorText, Loading } from "../components/States.js";
import { useI18n } from "../i18n/i18n.js";
import { LANGUAGE_NAMES, LANGUAGES, type Language, type MessageKey } from "../i18n/messages.js";

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
      <OnYourIphone />
      <SignInMethods />
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
      <DeleteAccount />
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

/** What the server said after linking (`/settings?link=…`), read once (ADR-818). */
const LINK_RESULTS = ["linked", "already", "taken", "canceled", "failed", "busy", "signed_out", "reauth"] as const;
type LinkResult = (typeof LINK_RESULTS)[number];

export function readLinkResult(search: string): { result: LinkResult; provider: SocialProvider | null } | null {
  const params = new URLSearchParams(search);
  const result = params.get("link");
  if (!result || !(LINK_RESULTS as readonly string[]).includes(result)) return null;
  const provider = params.get("provider");
  return { result: result as LinkResult, provider: provider === "google" || provider === "apple" ? provider : null };
}

/**
 * Apple and Google linked to this account (ADR-818). Shown only when the server offers them.
 * "Link" is a whole-page trip to Apple or Google and back; the server says how it went.
 */
function SignInMethods() {
  const { t, date } = useI18n();
  const location = useLocation();
  const navigate = useNavigate();
  const [outcome] = useState(() => readLinkResult(location.search));
  const [providers, setProviders] = useState<SocialProvider[] | null>(null);
  const { resource, reload } = useResource(api.identities);

  useEffect(() => {
    if (outcome) navigate("/settings", { replace: true });
    // Once, on arrival.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);
  useEffect(() => {
    const controller = new AbortController();
    api.signInOptions(controller.signal).then(setProviders, () => setProviders([]));
    return () => controller.abort();
  }, []);

  if (!providers || providers.length === 0) return null;
  const name = (p: SocialProvider | null) => (p ? t(`provider.${p}` as MessageKey) : "");
  const linked = resource.data ?? [];
  const unlinked = providers.filter((p) => !linked.some((identity) => identity.provider === p));

  return (
    <section className="card" aria-labelledby="methods-heading">
      <h2 id="methods-heading">{t("settings.methods")}</h2>
      <p className="lead">{t("settings.methodsLead")}</p>
      {outcome ? (
        <p className="notice" role={outcome.result === "linked" || outcome.result === "already" ? "status" : "alert"}>
          {t(`settings.link.${outcome.result}` as MessageKey, { provider: name(outcome.provider) })}
        </p>
      ) : null}
      {resource.status === "loading" ? <Loading /> : null}
      {resource.status === "error" ? <ErrorState error={resource.error} onRetry={reload} /> : null}
      {resource.data ? (
        <>
          {linked.length === 0 ? <p>{t("settings.methodsNone")}</p> : null}
          <ul className="session-list">
            {linked.map((identity) => (
              <IdentityItem key={identity.id} identity={identity} label={name(identity.provider)} linkedOn={t("settings.linkedOn", { date: date(identity.linkedAt) })} onChanged={reload} />
            ))}
          </ul>
          {unlinked.length > 0 ? (
            <p className="button-row">
              {unlinked.map((provider) => (
                <a key={provider} className={`button button-social button-${provider}`} href={socialStartUrl(provider, "link")}>
                  {t("settings.link", { provider: name(provider) })}
                </a>
              ))}
            </p>
          ) : null}
        </>
      ) : null}
    </section>
  );
}

function IdentityItem({ identity, label, linkedOn, onChanged }: { identity: LinkedIdentity; label: string; linkedOn: string; onChanged: () => void }) {
  const { t } = useI18n();
  const { expired } = useSession();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const unlink = async () => {
    setBusy(true);
    setError(null);
    try {
      await api.unlinkIdentity(identity.id);
      onChanged();
    } catch (caught) {
      if (caught instanceof ApiError && caught.code === "unauthenticated") {
        expired();
        return;
      }
      if (caught instanceof ApiError && caught.code === "not_found") {
        onChanged();
        return;
      }
      // ADR-818: a browser changes sign-in methods only soon after signing in with a code.
      if (caught instanceof ApiError && caught.code === "refused") {
        setError(t("settings.link.reauth"));
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
        <p className="session-name">{label}</p>
        <p className="document-meta">{linkedOn}</p>
      </div>
      <button type="button" className="button button-quiet" onClick={unlink} disabled={busy} aria-label={`${t("settings.unlink")}: ${label}`}>
        {busy ? t("settings.unlinking") : t("settings.unlink")}
      </button>
      {error ? (
        <p className="field-error" role="alert">
          {error}
        </p>
      ) : null}
    </li>
  );
}

/**
 * Delete account (ADR-818): an account made on the web has no iPhone to delete it from. Two steps;
 * the server deletes everything it keeps for this account and signs every browser out. It needs a
 * sign-in from the last 15 minutes, and says so instead.
 */
function DeleteAccount() {
  const { t } = useI18n();
  const { deleted, expired } = useSession();
  const { resource } = useResource(api.account);
  const [asking, setAsking] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const remove = async () => {
    setBusy(true);
    setError(null);
    try {
      const receipt = await api.deleteAccount();
      deleted(receipt.complete);
    } catch (caught) {
      if (caught instanceof ApiError && caught.code === "unauthenticated") {
        expired();
        return;
      }
      if (caught instanceof ApiError && caught.code === "refused") setError(t("settings.delete.reauth"));
      else setError(errorText(caught instanceof ApiError ? caught : new ApiError("network", String(caught), 0), t));
      setBusy(false);
    }
  };

  if (resource.status === "loading") return null;
  if (resource.status === "error" || !resource.data.madeOnWeb) {
    // An iPhone's account (or not known): deleted on the iPhone, as before (ADR-674).
    return (
      <section className="card" aria-labelledby="delete-heading">
        <h2 id="delete-heading">{t("settings.delete")}</h2>
        <p>{t("settings.delete.iphone")}</p>
      </section>
    );
  }

  return (
    <section className="card" aria-labelledby="delete-heading">
      <h2 id="delete-heading">{t("settings.delete")}</h2>
      <p>{t("settings.delete.body")}</p>
      {error ? (
        <p className="field-error" role="alert">
          {error}
        </p>
      ) : null}
      {asking ? (
        <div className="button-row">
          <p className="notice" role="alert">
            {t("settings.delete.confirm")}
          </p>
          <button type="button" className="button" onClick={remove} disabled={busy}>
            {busy ? t("settings.delete.deleting") : t("settings.delete.yes")}
          </button>
          <button type="button" className="button button-quiet" onClick={() => setAsking(false)} disabled={busy}>
            {t("settings.delete.no")}
          </button>
        </div>
      ) : (
        <button type="button" className="button button-quiet" onClick={() => setAsking(true)}>
          {t("settings.delete.start")}
        </button>
      )}
    </section>
  );
}

/** ADR-819: an account made on the web can be used on the iPhone too. Shown only for those accounts. */
function OnYourIphone() {
  const { t } = useI18n();
  const { resource } = useResource(api.account);
  if (resource.status !== "ready" || !resource.data.madeOnWeb) return null;
  return (
    <section className="card" aria-labelledby="iphone-heading">
      <h2 id="iphone-heading">{t("settings.iphone")}</h2>
      <p>{t("settings.iphoneBody")}</p>
    </section>
  );
}

