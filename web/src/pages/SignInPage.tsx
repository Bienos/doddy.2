import { type FormEvent, type MouseEvent, useEffect, useId, useRef, useState } from "react";
import { api, ApiError, socialStartUrl } from "../api/client.js";
import type { SocialProvider } from "../api/schemas.js";
import {
  closeSelf,
  insideSignInPopup,
  openChannel,
  openSignInPopup,
  POLL_MS,
  type PopupMessage,
  popupWanted,
  tellOpener,
  WAIT_LIMIT_MS,
} from "../auth/popup.js";
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

interface SignInOutcome {
  result: SignInResult;
  provider: SocialProvider | null;
}

/** Only the server's known results and providers pass; anything else (an address, a message) is nothing. */
function knownOutcome(result: unknown, provider: unknown): SignInOutcome | null {
  if (typeof result !== "string" || !(SIGNIN_RESULTS as readonly string[]).includes(result)) return null;
  return { result: result as SignInResult, provider: provider === "google" || provider === "apple" ? provider : null };
}

export function readSignInResult(search: string): SignInOutcome | null {
  const params = new URLSearchParams(search);
  return knownOutcome(params.get("signin"), params.get("provider"));
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
  const [social, setSocial] = useState(() => readSignInResult(location.search));
  // Apple or Google in a small window (see auth/popup.ts): which one is open, and which one gave up.
  const [waiting, setWaiting] = useState<SocialProvider | null>(null);
  const [timedOut, setTimedOut] = useState<SocialProvider | null>(null);
  const popupRef = useRef<Window | null>(null);
  const inPopup = useState(() => insideSignInPopup())[0];

  useEffect(() => heading.current?.focus(), []);
  useEffect(() => {
    if (social || location.pathname === "/sign-in") navigate("/", { replace: true });
    // Once, on arrival.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);
  // In the small window: hand the server's answer to the page that opened it, and go.
  useEffect(() => {
    if (!inPopup || !social) return;
    tellOpener({ type: "result", result: social.result, provider: social.provider });
    closeSelf();
    // Once, on arrival.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);
  // In the page that opened it: wait for the sign-in by asking the server, which owns the answer.
  useEffect(() => {
    if (!waiting) return;
    let finished = false;
    const closePopup = () => {
      try {
        popupRef.current?.close();
      } catch {
        // Already closed, or no longer ours.
      }
      popupRef.current = null;
    };
    const check = () => {
      api.session().then(
        (session) => {
          if (finished) return;
          finished = true;
          closePopup();
          signedIn(session);
        },
        () => undefined,
      );
    };
    const timer = window.setInterval(check, POLL_MS);
    const limit = window.setTimeout(() => {
      finished = true;
      closePopup();
      setTimedOut(waiting);
      setWaiting(null);
    }, WAIT_LIMIT_MS);
    const channel = openChannel();
    if (channel) {
      channel.onmessage = (event: MessageEvent<PopupMessage>) => {
        const message = event.data;
        if (message?.type === "signedIn") check();
        else if (message?.type === "result") {
          const outcome = knownOutcome(message.result, message.provider);
          if (!outcome || finished) return;
          finished = true;
          closePopup();
          setSocial(outcome);
          setWaiting(null);
        }
      };
    }
    window.addEventListener("focus", check);
    return () => {
      finished = true;
      window.clearInterval(timer);
      window.clearTimeout(limit);
      window.removeEventListener("focus", check);
      channel?.close();
    };
  }, [waiting, signedIn]);
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

  /** "Create my Doddy account" (ADR-818): only after Google or Apple, and only when the person presses it. */
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

  /**
   * A mouse on a wide screen opens Apple or Google in a small window and this page waits; anything
   * else (a phone, a new-tab click, a blocked window) follows the link as a whole-page redirect.
   */
  const startSocial = (event: MouseEvent<HTMLAnchorElement>, provider: SocialProvider) => {
    if (event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
    if (!popupWanted()) return;
    const popup = openSignInPopup(socialStartUrl(provider, "signin"));
    if (!popup) return;
    event.preventDefault();
    popupRef.current = popup;
    setTimedOut(null);
    setSocial(null);
    setWaiting(provider);
  };
  const cancelWaiting = () => {
    try {
      popupRef.current?.close();
    } catch {
      // Already closed.
    }
    popupRef.current = null;
    setWaiting(null);
  };

  const socialButtons =
    providers.length > 0 ? (
      <div className="social-sign-in">
        {providers.map((provider) => (
          <a
            key={provider}
            className={`button button-social button-${provider}`}
            href={socialStartUrl(provider, "signin")}
            aria-busy={waiting === provider ? true : undefined}
            onClick={(event) => startSocial(event, provider)}
          >
            {t(`signIn.with.${provider}` as MessageKey)}
          </a>
        ))}
        {waiting ? (
          <div className="notice waiting" role="status">
            <p>{t("signIn.waiting", { provider: providerName(waiting) })}</p>
            <button type="button" className="button button-quiet button-small" onClick={cancelWaiting}>
              {t("signIn.waitingCancel")}
            </button>
          </div>
        ) : null}
        {timedOut ? (
          <p className="notice" role="status">
            {t("signIn.waitingTimeout", { provider: providerName(timedOut) })}
          </p>
        ) : null}
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

  // The small window only carries the server's answer back to the page that opened it.
  if (inPopup && social) {
    return (
      <main id="main" className="centered popup-done">
        <DoddyFigure size={88} />
        <h1 tabIndex={-1} ref={heading}>
          {t("app.name")}
        </h1>
        <p className="lead">{t("popup.resultBody")}</p>
        <button type="button" className="button" onClick={closeSelf}>
          {t("popup.closeButton")}
        </button>
      </main>
    );
  }

  return (
    <main id="main" className="sign-in">
      <div className="sign-in-card">
        <section className="sign-in-intro">
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
          <div className="sign-in-foot">
            <DoddyFigure size={160} />
            <p className="says">{t("signIn.hand")}</p>
          </div>
        </section>
        <section className="sign-in-panel">
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
        </section>
      </div>
    </main>
  );
}
