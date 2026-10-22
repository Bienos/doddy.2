import { type ReactNode, useEffect, useId, useState } from "react";
import { NavLink, useLocation } from "react-router";
import { useSession } from "../auth/session.js";
import { useI18n } from "../i18n/i18n.js";
import type { MessageKey } from "../i18n/messages.js";
import { Wordmark } from "./Brand.js";

/** Only sections that work today are in the menu (ADR-585). Chat, memory and tasks come later. */
export const SECTIONS: { path: string; label: MessageKey }[] = [
  { path: "/", label: "nav.home" },
  { path: "/documents", label: "nav.documents" },
  { path: "/apps", label: "nav.apps" },
  { path: "/activity", label: "nav.activity" },
  { path: "/settings", label: "nav.settings" },
];

/** Whether the server runs on demo data (mock mode); the page then says so on every screen. */
function useDemoMode(): boolean {
  const [demo, setDemo] = useState(false);
  useEffect(() => {
    const controller = new AbortController();
    fetch("/v1/health", { signal: controller.signal, cache: "no-store" })
      .then((r) => (r.ok ? r.json() : null))
      .then((body: unknown) => {
        if (body && typeof body === "object" && (body as { mode?: unknown }).mode === "mock") setDemo(true);
      })
      .catch(() => {});
    return () => controller.abort();
  }, []);
  return demo;
}

export function AppShell({ children }: { children: ReactNode }) {
  const { t } = useI18n();
  const { signOut } = useSession();
  const demo = useDemoMode();
  const location = useLocation();
  const [open, setOpen] = useState(false);
  const [signingOut, setSigningOut] = useState(false);
  const [signOutFailed, setSignOutFailed] = useState(false);
  const navId = useId();

  // A link closes the small-screen menu.
  useEffect(() => setOpen(false), [location.pathname]);

  const onSignOut = async () => {
    setSigningOut(true);
    setSignOutFailed(false);
    try {
      await signOut();
    } catch {
      setSignOutFailed(true);
      setSigningOut(false);
    }
  };

  return (
    <div className="shell">
      <a className="skip-link" href="#main">
        {t("app.skip")}
      </a>
      {demo ? (
        <p className="demo-banner" role="note">
          {t("app.demoBanner")}
        </p>
      ) : null}
      <header className="topbar">
        <NavLink to="/" className="brand-link" aria-label={t("nav.home")}>
          <Wordmark />
        </NavLink>
        <button
          type="button"
          className="menu-button"
          aria-expanded={open}
          aria-controls={navId}
          onClick={() => setOpen((v) => !v)}
        >
          {open ? t("app.closeMenu") : t("app.menu")}
        </button>
      </header>
      <div className="shell-body">
        <nav id={navId} className={`sidebar ${open ? "is-open" : ""}`} aria-label={t("nav.label")}>
          <div className="sidebar-brand" aria-hidden="true">
            <Wordmark />
          </div>
          <ul>
            {SECTIONS.map((section) => (
              <li key={section.path}>
                <NavLink to={section.path} end={section.path === "/"} className={({ isActive }) => `nav-link ${isActive ? "is-active" : ""}`}>
                  {t(section.label)}
                </NavLink>
              </li>
            ))}
          </ul>
          <div className="sidebar-footer">
            <button type="button" className="button button-quiet" onClick={onSignOut} disabled={signingOut}>
              {signingOut ? t("app.signingOut") : t("app.signOut")}
            </button>
            {signOutFailed ? (
              <p className="field-error" role="alert">
                {t("common.error.network")}
              </p>
            ) : null}
          </div>
        </nav>
        <main id="main" className="content">
          {children}
        </main>
      </div>
    </div>
  );
}
