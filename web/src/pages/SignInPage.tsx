import { type FormEvent, useEffect, useId, useRef, useState } from "react";
import { ApiError } from "../api/client.js";
import { useSession } from "../auth/session.js";
import { DoddyFigure, Wordmark } from "../components/Brand.js";
import { errorText } from "../components/States.js";
import { useI18n } from "../i18n/i18n.js";
import { LANGUAGE_NAMES, LANGUAGES, type Language } from "../i18n/messages.js";

/** What a person typed, as the canonical code, or null. The server checks it again. */
export function canonicalCode(typed: string): string | null {
  const plain = typed.toUpperCase().replace(/[\s-]/g, "");
  return /^[A-HJKMNP-TV-Z2-9]{8}$/.test(plain) ? `${plain.slice(0, 4)}-${plain.slice(4)}` : null;
}

export function SignInPage() {
  const { t, language, setLanguage } = useI18n();
  const { signIn, state } = useSession();
  const [code, setCode] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const inputId = useId();
  const hintId = useId();
  const errorId = useId();
  const heading = useRef<HTMLHeadingElement>(null);
  const notice = state.status === "signedOut" ? state.notice : null;

  useEffect(() => heading.current?.focus(), []);

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
        <DoddyFigure size={96} />
        <h1 tabIndex={-1} ref={heading}>
          {t("signIn.title")}
        </h1>
        <p className="lead">{t("signIn.lead")}</p>
        {notice === "expired" ? (
          <p className="notice" role="status">
            {t("common.signedOutNotice")}
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
        <p className="fine-print">{t("signIn.safety", { origin: window.location.origin })}</p>
      </div>
    </main>
  );
}
