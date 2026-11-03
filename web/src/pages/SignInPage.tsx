import { type FormEvent, useEffect, useId, useRef, useState } from "react";
import { api, ApiError, socialStartUrl } from "../api/client.js";
import type { SocialProvider } from "../api/schemas.js";
import { useSession } from "../auth/session.js";
import { DoddyFigure, Wordmark } from "../components/Brand.js";
import { errorText } from "../components/States.js";
import { useLocation, useNavigate } from "react-router";
import { useI18n } from "../i18n/i18n.js";
import type { MessageKey } from "../i18n/messages.js";
import { LANGUAGE_NAMES, LANGUAGES, type Language } from "../i18n/messages.js";

/** What a person typed, as the canonical code, or null. The server checks it again. */
export function canonicalCode(typed: string): string | null {
  const plain = typed.toUpperCase().replace(/[\s-]/g, "");
  return /^[A-HJKMNP-TV-Z2-9]{8}$/.test(plain) ? `${plain.slice(0, 4)}-${plain.slice(4)}` : null;
}

/** What the server said about an Apple or Google sign-in (`/sign-in?signin=…`), read once. */
const SIGNIN_RESULTS = ["not_linked", "new_account", "canceled", "failed", "busy"] as const;
type SignInResult = (typeof SIGNIN_RESULTS)[number];

export function readSignInResult(search: string): { result: SignInResult; provider: SocialProvider | null } | null {
  const params = new URLSearchParams(search);
  const result = params.get("signin");
  if (!result || !(SIGNIN_RESULTS as readonly string[]).includes(result)) return null;
  const provider = params.get("provider");
  return { result: result as SignInResult, provider: provider === "google" || provider === "apple" ? provider : null };
}

export function SignInPage() {
  const { t, language, setLanguage } = useI18n();
  const { signIn, signedIn, state } = useSession();
  const [code, setCode] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const inputId = useId();
  const hintId = useId();
  const errorId = useId();
  const heading = useRef<HTMLHeadingElement>(null);
  const notice = state.status === "signedOut" ? state.notice : null;
  const [providers, setProviders] = useState<SocialProvider[]>([]);
  const [signupOpen, setSignupOpen] = useState(false);
  const [creating, setCreating] = useState(false);
  const [createError, setCreateError] = useState<string | null>(null);
  // Read once, then the address is tidied, so a reload or a later sign-in doesn't show it again.
  const location = useLocation();
  const navigate = useNavigate();
  const [social] = useState(() => readSignInResult(location.search));

  useEffect(() => heading.current?.focus(), []);
  useEffect(() => {
    if (social || location.pathname === "/sign-in") navigate("/", { replace: true });
    // Once, on arrival.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);
  useEffect(() => {
    const controller = new AbortController();
    // Without the list (an older server, or offline) the page simply offers the code.
    api.signInSetup(controller.signal).then(
      (setup) => {
        setProviders(setup.providers);
        setSignupOpen(setup.signup);
      },
      () => setProviders([]),
    );
    return () => controller.abort();
  }, []);
  const providerName = (p: SocialProvider | null) => (p ? t(`provider.${p}` as MessageKey) : "Google");

  /** "Create my Doddy account" (ADR-700): only after Google or Apple, and only when the person presses it. */
  const createAccount = async () => {
    setCreating(true);
    setCreateError(null);
    try {
      const done = await api.signUp();
      signedIn(done.session);
    } catch (caught) {
      const apiError = caught instanceof ApiError ? caught : new ApiError("network", String(caught), 0);
      setCreateError(apiError.code === "not_found" ? t("signUp.expired") : errorText(apiError, t));
      setCreating(false);
    }
  };

  const socialButtons =
    providers.length > 0 ? (
      <div className="social-sign-in">
        {providers.map((provider) => (
          <a key={provider} className={`button button-social button-${provider}`} href={socialStartUrl(provider, "signin")}>
            {t(`signIn.with.${provider}` as MessageKey)}
          </a>
        ))}
        <p className="field-hint">{signupOpen ? t("signIn.socialHintOpen") : t("signIn.socialHint")}</p>
      </div>
    ) : null;
  const newAccount = social?.result === "new_account";

  const submit = async (event: FormEvent) => {
    event.preventDefault();
    const canonical = canonicalCode(code);
    if (!canonical) {
      setError(t("signIn.malformed"));
      return;
    }
    setBusy(true);
    setError(null);
    try {
      await signIn(canonical);
    } catch (caught) {
      const apiError = caught instanceof ApiError ? caught : new ApiError("network", String(caught), 0);
      setError(apiError.code === "unauthenticated" ? t("signIn.badCode") : errorText(apiError, t));
      setBusy(false);
    }
  };

  return (
    <main id="main" className="sign-in">
      <div className="sign-in-card">
        <div className="sign-in-top">
          <Wordmark className="wordmark-large" />
          <label className="language-picker">
            <span className="visually-hidden">{t("settings.languageLabel")}</span>
            <select value={language} onChange={(e) => setLanguage(e.target.value as Language)}>
              {LANGUAGES.map((l) => (
                <option key={l} value={l} lang={l}>
                  {LANGUAGE_NAMES[l]}
                </option>
              ))}
            </select>
          </label>
        </div>
        <h1 tabIndex={-1} ref={heading}>
          {t("signIn.title")}
        </h1>
        <p className="lead">{signupOpen && providers.length > 0 ? t("signIn.leadOpen") : t("signIn.lead")}</p>
        {newAccount ? (
          <section className="notice new-account" aria-labelledby="new-account-heading">
            <h2 id="new-account-heading">{t("signUp.title", { provider: providerName(social!.provider) })}</h2>
            <p>{t("signUp.body", { provider: providerName(social!.provider) })}</p>
            <p className="field-hint">{t("signUp.kept", { provider: providerName(social!.provider) })}</p>
            {createError ? (
              <p className="field-error" role="alert">
                {createError}
              </p>
            ) : null}
            <button type="button" className="button button-primary" onClick={createAccount} disabled={creating}>
              {creating ? t("signUp.creating") : t("signUp.create")}
            </button>
            <p className="field-hint">{t("signUp.haveIphone", { provider: providerName(social!.provider) })}</p>
          </section>
        ) : null}
        {social && !newAccount ? (
          <p className="notice" role={social.result === "not_linked" || social.result === "failed" ? "alert" : "status"}>
            {t(`signIn.result.${social.result}` as MessageKey, { provider: providerName(social.provider) })}
          </p>
        ) : null}
        {notice === "expired" ? (
          <p className="notice" role="status">
            {t("common.signedOutNotice")}
          </p>
        ) : null}
        {notice === "deleted" || notice === "deletedPending" ? (
          <p className="notice" role="status">
            {t(notice === "deleted" ? "signIn.deletedNotice" : "signIn.deletedPendingNotice")}
          </p>
        ) : null}
        {/* With sign-up open, Google and Apple come first; the iPhone's code is the other way in. */}
        {signupOpen && !newAccount ? socialButtons : null}
        {signupOpen && providers.length > 0 ? (
          <p className="divider">
            <span>{t("signIn.orCode")}</span>
          </p>
        ) : null}
        <ol className="steps">
          <li>{t("signIn.step1")}</li>
          <li>{t("signIn.step2")}</li>
          <li>{t("signIn.step3")}</li>
        </ol>
        <form onSubmit={submit} noValidate>
          <label htmlFor={inputId} className="field-label">
            {t("signIn.codeLabel")}
          </label>
          <input
            id={inputId}
            className="code-input"
            name="code"
            value={code}
            onChange={(e) => setCode(e.target.value)}
            autoComplete="one-time-code"
            autoCapitalize="characters"
            autoCorrect="off"
            spellCheck={false}
            inputMode="text"
            maxLength={12}
            placeholder="ABCD-EFGH"
            aria-describedby={`${hintId}${error ? ` ${errorId}` : ""}`}
            aria-invalid={error ? true : undefined}
            disabled={busy}
          />
          <p id={hintId} className="field-hint">
            {t("signIn.codeHint")}
          </p>
          {error ? (
            <p id={errorId} className="field-error" role="alert">
              {error}
            </p>
          ) : null}
          <button type="submit" className="button button-primary" disabled={busy}>
            {busy ? t("signIn.submitting") : t("signIn.submit")}
          </button>
        </form>
        {!signupOpen && providers.length > 0 ? (
          <>
            <p className="divider">
              <span>{t("signIn.or")}</span>
            </p>
            {socialButtons}
          </>
        ) : null}
        <p className="fine-print">{t("signIn.safety", { origin: window.location.origin })}</p>
        <div className="sign-in-foot">
          <p className="says">{t("signIn.hand")}</p>
          <DoddyFigure size={88} />
        </div>
      </div>
    </main>
  );
}
