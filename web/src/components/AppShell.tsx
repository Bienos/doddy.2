import { type ReactNode, useEffect, useId, useState } from "react";
import { NavLink, useLocation } from "react-router";
import { useSession } from "../auth/session.js";
import { useI18n } from "../i18n/i18n.js";
import { IPHONE_SENDS_LOGBOOK, LOGBOOK_ENABLED } from "../logbook/config.js";
import { IPHONE_SYNCS_MEMORY, MEMORY_ENABLED } from "../memory/config.js";
import type { MessageKey } from "../i18n/messages.js";
import { Wordmark } from "./Brand.js";

/**
 * Only sections that work today are in the menu (ADR-600). Chat, memory and tasks come later.
 * Logbook is there too (ADR-602), marked Example until the iPhone can send it; Memory and Ask Doddy (ADR-603)
 * are marked Soon until the iPhone can send notes and conversations.
 */
export const SECTIONS: { path: string; label: MessageKey; example?: boolean; soon?: boolean }[] = [
  { path: "/", label: "nav.home" },
  { path: "/documents", label: "nav.documents" },
  { path: "/apps", label: "nav.apps" },
  { path: "/activity", label: "nav.activity" },
  ...(LOGBOOK_ENABLED ? [{ path: "/logbook", label: "nav.logbook" as MessageKey, example: !IPHONE_SENDS_LOGBOOK }] : []),
  ...(MEMORY_ENABLED
    ? [
        { path: "/memory", label: "nav.memory" as MessageKey, soon: !IPHONE_SYNCS_MEMORY },
        { path: "/ask", label: "nav.ask" as MessageKey, soon: !IPHONE_SYNCS_MEMORY },
      ]
    : []),
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

/** The website's header: the wordmark, the sections in one row, Sign out; a Menu sheet on small screens. */
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
  // Escape closes it too.
  useEffect(() => {
    if (!open) return;
    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Escape") setOpen(false);
    };
    document.addEventListener("keydown", onKey);
    return () => document.removeEventListener("keydown", onKey);
  }, [open]);

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

  const wide = location.pathname.startsWith("/logbook");

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
      <header className="nav">
        <div className="nav-inner">
          <NavLink to="/" className="brand-link" aria-label={t("nav.home")}>
            <Wordmark />
          </NavLink>
          <nav id={navId} className={`nav-menu ${open ? "is-open" : ""}`} aria-label={t("nav.label")}>
            <ul className="nav-links">
              {SECTIONS.map((section) => (
                <li key={section.path}>
                  <NavLink to={section.path} end={section.path === "/"} className={({ isActive }) => `nav-link ${isActive ? "is-active" : ""}`}>
                    {t(section.label)}
                    {section.example || section.soon ? (
                      <>
                        {" "}
                        <span className="pill" title={t(section.example ? "common.example" : "common.soon")}>
                          {t(section.example ? "common.example" : "common.soon")}
                        </span>
                      </>
                    ) : null}
                  </NavLink>
                </li>
              ))}
            </ul>
            <div className="nav-actions">
              <button type="button" className="button button-quiet button-small" onClick={onSignOut} disabled={signingOut}>
                {signingOut ? t("app.signingOut") : t("app.signOut")}
              </button>
              {signOutFailed ? (
                <p className="field-error" role="alert">
                  {t("common.error.network")}
                </p>
              ) : null}
            </div>
          </nav>
          <button type="button" className="menu-button" aria-expanded={open} aria-controls={navId} onClick={() => setOpen((v) => !v)}>
            {open ? t("app.closeMenu") : t("app.menu")}
          </button>
        </div>
      </header>
      <main id="main" className={`content ${wide ? "is-wide" : ""}`}>
        {children}
      </main>
    </div>
  );
}
