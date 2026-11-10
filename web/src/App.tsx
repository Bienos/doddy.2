import { lazy, Suspense } from "react";
import { Navigate, Route, Routes, useLocation } from "react-router";
import { insideSignInPopup } from "./auth/popup.js";
import { useSession } from "./auth/session.js";
import { AppShell } from "./components/AppShell.js";
import { DoddyFigure } from "./components/Brand.js";
import { PopupDone } from "./components/PopupDone.js";
import { ErrorState, Loading } from "./components/States.js";
import { useI18n } from "./i18n/i18n.js";
import { ActivityPage } from "./pages/ActivityPage.js";
import { AppsPage } from "./pages/AppsPage.js";
import { DocumentsPage } from "./pages/DocumentsPage.js";
import { HomePage } from "./pages/HomePage.js";
import { MessagesPage } from "./pages/MessagesPage.js";
import { LOGBOOK_ENABLED } from "./logbook/config.js";
import { MEMORY_ENABLED } from "./memory/config.js";
import { CHAT_ENABLED } from "./chat/suggestions.js";
import { ChatPage } from "./pages/ChatPage.js";
import { LogbookPage } from "./pages/LogbookPage.js";
import { MemoryPage } from "./pages/MemoryPage.js";
import { NotFoundPage } from "./pages/NotFoundPage.js";
import { SettingsPage } from "./pages/SettingsPage.js";
import { SignInPage } from "./pages/SignInPage.js";

/** The admin dashboard is its own chunk, fetched only when /admin is opened (decision 2026-11-09-usage-counts-on-by-default). */
const AdminPage = lazy(() => import("./pages/AdminPage.js"));

/** Every page needs a session; without one, the sign-in page shows at whatever address was opened. */
export function App() {
  const { state, recheck } = useSession();
  const { t } = useI18n();
  const location = useLocation();

  if (state.status === "checking") {
    return (
      <main id="main" className="centered">
        <DoddyFigure size={72} />
        <Loading />
      </main>
    );
  }
  if (state.status === "unreachable") {
    return (
      <main id="main" className="centered">
        <DoddyFigure size={72} />
        <h1 className="visually-hidden">{t("app.name")}</h1>
        <ErrorState error={state.error} onRetry={recheck} />
      </main>
    );
  }
  if (state.status === "signedOut") return <SignInPage />;
  // The small sign-in window (auth/popup.ts) has done its job: the page that opened it takes over.
  if (insideSignInPopup()) return <PopupDone />;
  // Outside the workspace menu and shell: its own page, for the owner's accounts only.
  if (location.pathname === "/admin") {
    return (
      <Suspense
        fallback={
          <main id="main" className="centered">
            <Loading />
          </main>
        }
      >
        <AdminPage />
      </Suspense>
    );
  }

  return (
    <AppShell>
      <Routes>
        <Route path="/" element={<HomePage />} />
        <Route path="/messages" element={<MessagesPage />} />
        <Route path="/documents" element={<DocumentsPage />} />
        <Route path="/apps" element={<AppsPage />} />
        <Route path="/activity" element={<ActivityPage />} />
        {LOGBOOK_ENABLED ? <Route path="/logbook" element={<LogbookPage />} /> : null}
        {MEMORY_ENABLED ? <Route path="/memory" element={<MemoryPage />} /> : null}
        {CHAT_ENABLED ? <Route path="/chat" element={<ChatPage />} /> : null}
        {/* Ask Doddy became the chat (ADR-604); old links still land there. */}
        {CHAT_ENABLED ? <Route path="/ask" element={<Navigate to="/chat" replace />} /> : null}
        <Route path="/settings" element={<SettingsPage />} />
        <Route path="*" element={<NotFoundPage />} />
      </Routes>
    </AppShell>
  );
}
